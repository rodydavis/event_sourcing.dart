You're looking to build a powerful local-first application using **event sourcing** with **SQLite** for persistence, primarily written in **pure C** (potentially as a VSCode extension), with a **Go backend** for synchronization. This robust setup involves two SQLite databases: one for an immutable **event log** and another for **materialized views**. Synchronization will be handled via **WebSockets** (or potentially SSE/WebRTC), with **Hybrid Logical Clocks (HLCs)** ensuring distributed ordering, and a **Git-like pull-before-push** mechanism for conflict resolution. The materialized views will support **easy schema evolution** by replaying events.

Let's break down how to implement this system, along with a runnable example and testing strategy.

---

## Architectural Overview

At the heart of this system are three main components:

1.  **C Client (Local-First Application):** This component, built in pure C and compiled to **WebAssembly (Wasm)**, runs in the client's environment (e.g., a web browser, a VSCode webview). It interacts with two local SQLite databases:
    * **Event Log DB:** An append-only store for immutable events. This is the single source of truth for the client.
    * **Materialized View DB:** A derived, query-optimized database reflecting the current state, built by projecting events from the event log.
2.  **Go Backend (Sync Server & Web Server):** This Go application serves the web client and handles all synchronization logic. It also maintains its own SQLite event log, acting as the authoritative server-side event store.
3.  **Synchronization Layer:** Responsible for reliably exchanging events between the client and the server, ensuring causal consistency using HLCs and managing conflicts.

```
+---------------------+         +---------------------+
|                     |         |                     |
|  C Client (Wasm)    |         |   Go Backend        |
|  (e.g., VSCode Ext.)|         |   (Sync Server)     |
|                     |         |                     |
| +-----------------+ |         | +-----------------+ |
| | Event Log DB    | |         | | Event Log DB    | |
| | (Local SQLite)  |<-----------| | (Server SQLite) | |
| +-----------------+ |  WebSocket/ | +-----------------+ |
|          |          |  HTTP/SSE   |          ^          |
|          v          |             |          |          |
| +-----------------+ |             | +-----------------+ |
| | Materialized    | |             | | Materialized    | |
| | View DB         | |             | | View DB         | |
| | (Local SQLite)  | |             | | (Server SQLite) | |
| +-----------------+ |             | +-----------------+ |
+---------------------+             +---------------------+
      Local Projection                      Server Projection
```

---

## Event Sourcing with SQLite

Event sourcing fundamentally changes how you store application state. Instead of saving the current state directly, you record every *event* that led to that state.

### Event Log Database Schema

Your event log will be a simple, append-only table. The crucial aspect is that rows are never updated or deleted.

```sql
CREATE TABLE events (
    event_id        TEXT PRIMARY KEY, -- Unique ID for each event (UUID)
    aggregate_id    TEXT NOT NULL,    -- ID of the aggregate this event belongs to (UUID)
    version         INTEGER NOT NULL, -- Version of the aggregate after this event
    event_type      TEXT NOT NULL,    -- Describes the event (e.g., 'UserCreated', 'ItemAdded')
    event_data      BLOB NOT NULL,    -- Event payload (JSON, serialized)
    timestamp       TEXT NOT NULL,    -- Hybrid Logical Clock timestamp (e.g., '1400000000000:0:nodeA')
    metadata        BLOB,             -- Additional context (e.g., user_id, device_id, JSON)
    CONSTRAINT ux_aggregate_version UNIQUE (aggregate_id, version)
);

CREATE INDEX idx_events_aggregate_id ON events (aggregate_id);
CREATE INDEX idx_events_timestamp ON events (timestamp); -- Useful for sync
```

**SQLite Optimizations:**
* **WAL Mode (Write-Ahead Logging):** `PRAGMA journal_mode = WAL;` is highly recommended for better concurrency and durability.
* **Synchronous Mode:** For local-first, `PRAGMA synchronous = NORMAL;` can offer a good balance between safety and performance. For the server, `FULL` might be preferred for stronger guarantees, but `NORMAL` is often sufficient.
* **Indexes:** As shown, index `aggregate_id` for efficient aggregate stream retrieval and `timestamp` for sync operations.

---

## C Client Implementation (Wasm)

The C client will handle local event storage, materialized view projections, and communication with the Go backend. Compiling to WebAssembly is key for web-based deployment (including VSCode webviews).

### Embedding SQLite in C (with Wasm)

For WebAssembly, you'll use **`wa-sqlite`**, which is the official SQLite Wasm build. It handles persistence by integrating with browser storage mechanisms like **IndexedDB** or the **Origin Private File System (OPFS)**.

Your C code will interact with SQLite using the standard SQLite C API (`sqlite3_open`, `sqlite3_exec`, `sqlite3_prepare_v2`, `sqlite3_step`, `sqlite3_finalize`, `sqlite3_close`). The `wa-sqlite` JavaScript wrapper exposes these C functions to your JavaScript/TypeScript code.

```c
// Example: C function to insert an event
int insert_event(sqlite3* db, const char* event_id, const char* aggregate_id, int version,
                 const char* event_type, const char* event_data, const char* timestamp,
                 const char* metadata) {
    sqlite3_stmt *stmt;
    const char *sql = "INSERT INTO events (event_id, aggregate_id, version, event_type, event_data, timestamp, metadata) VALUES (?, ?, ?, ?, ?, ?, ?);";

    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Failed to prepare statement: %s\n", sqlite3_errmsg(db));
        return rc;
    }

    sqlite3_bind_text(stmt, 1, event_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, aggregate_id, -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 3, version);
    sqlite3_bind_text(stmt, 4, event_type, -1, SQLITE_STATIC);
    sqlite3_bind_blob(stmt, 5, event_data, strlen(event_data), SQLITE_STATIC); // Assuming event_data is JSON string
    sqlite3_bind_text(stmt, 6, timestamp, -1, SQLITE_STATIC);
    sqlite3_bind_blob(stmt, 7, metadata, strlen(metadata), SQLITE_STATIC); // Assuming metadata is JSON string

    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        fprintf(stderr, "Failed to insert event: %s\n", sqlite3_errmsg(db));
    }

    sqlite3_finalize(stmt);
    return rc;
}
```

### Materialized View Projection Engine (C)

Your C application will implement a projection engine that reads events from the event log and updates the materialized view database.

```c
// Simplified C structure for an HLC
typedef struct {
    long long physical_time;
    int counter;
    char node_id[37]; // UUID string + null terminator
} HLC;

// Function to parse HLC string (e.g., "1700000000000:0:nodeA") into HLC struct
HLC hlc_parse(const char* hlc_str) {
    HLC hlc = {0};
    sscanf(hlc_str, "%lld:%d:%36s", &hlc.physical_time, &hlc.counter, hlc.node_id);
    return hlc;
}

// Function to format HLC struct back to string
void hlc_format(HLC hlc, char* buffer, size_t buffer_size) {
    snprintf(buffer, buffer_size, "%lld:%d:%s", hlc.physical_time, hlc.counter, hlc.node_id);
}

// Global HLC state for this client
static HLC current_hlc;

// HLC generation (you'll need a UUID generation function)
// For simplicity, this example assumes UUID is passed directly.
// In a real scenario, `uuid_str` would be generated by a C function
// (e.g., using libuuid or similar).
const char* hlc_now(const char* uuid_str) {
    long long current_physical_time = (long long)time(NULL) * 1000; // milliseconds
    static char hlc_buffer[256];

    if (current_physical_time > current_hlc.physical_time) {
        current_hlc.physical_time = current_physical_time;
        current_hlc.counter = 0;
    } else if (current_physical_time == current_hlc.physical_time) {
        current_hlc.counter++;
    } else { // Clock went backwards, use logical time
        current_hlc.physical_time = current_hlc.physical_time + 1;
        current_hlc.counter = 0;
    }

    strncpy(current_hlc.node_id, uuid_str, sizeof(current_hlc.node_id) - 1);
    current_hlc.node_id[sizeof(current_hlc.node_id) - 1] = '\0';

    hlc_format(current_hlc, hlc_buffer, sizeof(hlc_buffer));
    return hlc_buffer;
}

// HLC comparison function (returns -1 if hlc1 < hlc2, 0 if equal, 1 if hlc1 > hlc2)
int hlc_compare(const char* hlc_str1, const char* hlc_str2) {
    HLC hlc1 = hlc_parse(hlc_str1);
    HLC hlc2 = hlc_parse(hlc_str2);

    if (hlc1.physical_time < hlc2.physical_time) return -1;
    if (hlc1.physical_time > hlc2.physical_time) return 1;

    if (hlc1.counter < hlc2.counter) return -1;
    if (hlc1.counter > hlc2.counter) return 1;

    return strcmp(hlc1.node_id, hlc2.node_id); // Tie-breaker by node ID
}

// Register custom HLC functions with SQLite
void register_hlc_functions(sqlite3* db) {
    sqlite3_create_function(db, "hlc_now", 1, SQLITE_UTF8, NULL,
                            (void (*)(sqlite3_context*,int,sqlite3_value**))hlc_now_sqlite, NULL, NULL);
    sqlite3_create_function(db, "hlc_compare", 2, SQLITE_UTF8, NULL,
                            (void (*)(sqlite3_context*,int,sqlite3_value**))hlc_compare_sqlite, NULL, NULL);
}

// Wrapper for hlc_now for SQLite C API
void hlc_now_sqlite(sqlite3_context* context, int argc, sqlite3_value** argv) {
    const char* uuid_str = (const char*)sqlite3_value_text(argv[0]);
    const char* hlc = hlc_now(uuid_str);
    sqlite3_result_text(context, hlc, -1, SQLITE_TRANSIENT);
}

// Wrapper for hlc_compare for SQLite C API
void hlc_compare_sqlite(sqlite3_context* context, int argc, sqlite3_value** argv) {
    const char* hlc_str1 = (const char*)sqlite3_value_text(argv[0]);
    const char* hlc_str2 = (const char*)sqlite3_value_text(argv[1]);
    int result = hlc_compare(hlc_str1, hlc_str2);
    sqlite3_result_int(context, result);
}
```

The projection engine will:
1.  **Open two database connections:** one for `event_log.db` and another for `materialized_view.db`.
2.  **Maintain a `last_processed_hlc`:** A value stored in the materialized view DB (e.g., in a `_metadata` table) indicating the HLC of the last event successfully projected.
3.  **Fetch new events:** Query the `event_log.db` for events with a `timestamp` greater than `last_processed_hlc`.
4.  **Iterate and Project:** Loop through fetched events. For each event:
    * Deserialize `event_data` (e.g., using a JSON parsing library like `jansson` or `parson`).
    * Use a **dispatcher pattern** (e.g., a `switch` statement on `event_type` or a map of function pointers) to call specific projection handlers.
    * **Projection Handlers:** These are C functions that execute SQL `INSERT`, `UPDATE`, or `DELETE` statements on the `materialized_view.db` based on the event's data.
    * **Transactionality:** Wrap a batch of projection updates in a SQLite transaction (`BEGIN TRANSACTION; ... COMMIT;`) for atomicity and performance.
5.  **Update `last_processed_hlc`:** After successfully projecting a batch, update the `last_processed_hlc` in `materialized_view.db`.

---

## Go Backend (Sync Server)

The Go backend will serve the web application and manage server-side event persistence and synchronization.

### Go Event Storage

The Go server will also use a SQLite database for its event log, mirroring the client's schema. You can use Go's `database/sql` package with the `mattn/go-sqlite3` driver.

### Synchronization Mechanisms

* **WebSockets (Primary):** **Highly recommended** for bidirectional, real-time sync. It allows the client to push events and the server to push new events to clients.
* **SSE (Server-Sent Events):** Useful for server-to-client notifications or one-way event streaming, but not for client-to-server pushes. Can complement WebSockets for specific notification patterns.
* **WebRTC:** Best for peer-to-peer communication (e.g., direct client-to-client sync without a central server). While technically possible for event streams, it adds significant complexity (signaling server, NAT traversal) that is likely unnecessary given the requirement for a central sync server.

For this architecture, **WebSockets** will be the backbone of your synchronization.

### Go Sync Server Logic (Git-like Pull-Before-Push)

The sync server will handle two main types of client requests: pushing events and pulling events. The "pull-before-push" strategy ensures that clients always synchronize their state with the server's latest events before committing their own changes.

#### Sync Protocol (Simplified WebSocket Messages)

1.  **`client_sync_request`:**
    ```json
    {
        "type": "client_sync_request",
        "last_synced_hlc": "1700000000000:0:serverNodeID", // HLC of the last event client received from server
        "local_events": [ /* Array of client's new, uncommitted events */ ]
    }
    ```
2.  **`server_sync_response`:**
    ```json
    {
        "type": "server_sync_response",
        "status": "OK" | "PULL_REQUIRED",
        "missing_events": [ /* Array of events client needs to pull */ ],
        "new_server_hlc": "1700000000000:0:serverNodeID" // Latest HLC on server
    }
    ```
3.  **`client_push_events`:** (Sent after `PULL_REQUIRED` and local rebase)
    ```json
    {
        "type": "client_push_events",
        "rebased_events": [ /* Client's events after rebasing on server's latest */ ]
    }
    ```
4.  **`server_new_events`:** (Server push to all connected clients)
    ```json
    {
        "type": "server_new_events",
        "events": [ /* Newly committed events by any client, including rebased ones */ ]
    }
    ```

#### Server-Side Logic (Go)

```go
package main

import (
    "database/sql"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "sync"
    "time"

    "github.com/gorilla/websocket"
    _ "github.com/mattn/go-sqlite3"
)

// Define your Event struct mirroring the SQLite schema
type Event struct {
    EventID      string          `json:"event_id"`
    AggregateID  string          `json:"aggregate_id"`
    Version      int             `json:"version"`
    EventType    string          `json:"event_type"`
    EventData    json.RawMessage `json:"event_data"`
    Timestamp    string          `json:"timestamp"` // HLC string
    Metadata     json.RawMessage `json:"metadata"`
}

// HLC representation in Go
type HLC struct {
    PhysicalTime int64
    Counter      int
    NodeID       string
}

// Parse HLC string to struct
func ParseHLC(hlcStr string) (HLC, error) {
    var hlc HLC
    _, err := fmt.Sscanf(hlcStr, "%d:%d:%s", &hlc.PhysicalTime, &hlc.Counter, &hlc.NodeID)
    if err != nil {
        return HLC{}, fmt.Errorf("failed to parse HLC string: %w", err)
    }
    return hlc, nil
}

// Compare HLCs
func CompareHLC(hlc1, hlc2 HLC) int {
    if hlc1.PhysicalTime < hlc2.PhysicalTime { return -1 }
    if hlc1.PhysicalTime > hlc2.PhysicalTime { return 1 }
    if hlc1.Counter < hlc2.Counter { return -1 }
    if hlc1.Counter > hlc2.Counter { return 1 }
    return 0 // Nodes are tie-breaker by ID, but for strict causal order, physical time and counter are primary
}

// WebSocket Upgrader
var upgrader = websocket.Upgrader{
    ReadBufferSize:  1024,
    WriteBufferSize: 1024,
    CheckOrigin: func(r *http.Request) bool { return true }, // Allow all origins for example
}

// Store for active WebSocket connections
var clients = make(map[*websocket.Conn]bool)
var broadcast = make(chan Event) // Channel to broadcast new events
var clientsMux sync.Mutex

// Event store database
var db *sql.DB

func init() {
    var err error
    db, err = sql.Open("sqlite3", "./server_events.db")
    if err != nil {
        log.Fatal(err)
    }
    createTableSQL := `
    CREATE TABLE IF NOT EXISTS events (
        event_id TEXT PRIMARY KEY,
        aggregate_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        event_data BLOB NOT NULL,
        timestamp TEXT NOT NULL,
        metadata BLOB,
        UNIQUE(aggregate_id, version)
    );
    CREATE INDEX IF NOT EXISTS idx_server_events_timestamp ON events (timestamp);
    `
    _, err = db.Exec(createTableSQL)
    if err != nil {
        log.Fatal(err)
    }
    log.Println("Server SQLite event store initialized.")
}

func handleConnections(w http.ResponseWriter, r *http.Request) {
    ws, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Printf("Upgrade error: %v", err)
        return
    }
    defer ws.Close()

    clientsMux.Lock()
    clients[ws] = true
    clientsMux.Unlock()

    log.Printf("Client connected from %s", r.RemoteAddr)

    for {
        var msg map[string]json.RawMessage
        err := ws.ReadJSON(&msg)
        if err != nil {
            log.Printf("Read error: %v", err)
            clientsMux.Lock()
            delete(clients, ws)
            clientsMux.Unlock()
            break
        }

        msgType := string(msg["type"])
        switch msgType {
        case `"client_sync_request"`: // Note: JSON string comes with quotes
            handleClientSyncRequest(ws, msg)
        case `"client_push_events"`:
            handleClientPushEvents(ws, msg)
        default:
            log.Printf("Unknown message type: %s", msgType)
        }
    }
    log.Printf("Client disconnected from %s", r.RemoteAddr)
}

func handleClientSyncRequest(ws *websocket.Conn, msg map[string]json.RawMessage) {
    var clientLastSyncedHLCStr string
    json.Unmarshal(msg["last_synced_hlc"], &clientLastSyncedHLCStr)
    
    var clientEvents []Event
    json.Unmarshal(msg["local_events"], &clientEvents)

    serverLatestHLCStr := getServerLatestHLC()
    if serverLatestHLCStr == "" { // No events on server yet
        if len(clientEvents) > 0 { // Client has events, accept them directly
            ingestEvents(clientEvents)
            // Respond with OK and new server HLC
            ws.WriteJSON(map[string]interface{}{
                "type": "server_sync_response",
                "status": "OK",
                "missing_events": []Event{},
                "new_server_hlc": getServerLatestHLC(),
            })
            return
        }
        // No events anywhere, nothing to do
        ws.WriteJSON(map[string]interface{}{
            "type": "server_sync_response",
            "status": "OK",
            "missing_events": []Event{},
            "new_server_hlc": "", // Still no events
        })
        return
    }

    serverLatestHLC, _ := ParseHLC(serverLatestHLCStr)
    clientLastSyncedHLC, err := ParseHLC(clientLastSyncedHLCStr)
    if err != nil {
        log.Printf("Error parsing client HLC: %v", err)
        // Treat as if client needs all events from server
        clientLastSyncedHLC = HLC{PhysicalTime: 0, Counter: 0, NodeID: ""}
    }

    // Determine if client needs to pull
    if CompareHLC(clientLastSyncedHLC, serverLatestHLC) < 0 {
        // Server has newer events. Client must pull.
        missingEvents := getEventsSinceHLC(clientLastSyncedHLCStr)
        log.Printf("Server has newer events. Client needs to pull %d events.", len(missingEvents))
        ws.WriteJSON(map[string]interface{}{
            "type": "server_sync_response",
            "status": "PULL_REQUIRED",
            "missing_events": missingEvents,
            "new_server_hlc": serverLatestHLCStr,
        })
        return
    }

    // Client is up-to-date or ahead. Accept client events.
    if len(clientEvents) > 0 {
        ingestEvents(clientEvents)
    }

    ws.WriteJSON(map[string]interface{}{
        "type": "server_sync_response",
        "status": "OK",
        "missing_events": []Event{},
        "new_server_hlc": getServerLatestHLC(),
    })
}

func handleClientPushEvents(ws *websocket.Conn, msg map[string]json.RawMessage) {
    var rebasedEvents []Event
    json.Unmarshal(msg["rebased_events"], &rebasedEvents)

    if len(rebasedEvents) > 0 {
        ingestEvents(rebasedEvents)
        ws.WriteJSON(map[string]interface{}{
            "type": "server_sync_response",
            "status": "OK",
            "missing_events": []Event{}, // Client just pushed, shouldn't need to pull more immediately
            "new_server_hlc": getServerLatestHLC(),
        })
    } else {
        ws.WriteJSON(map[string]interface{}{
            "type": "server_sync_response",
            "status": "OK", // No events to push, nothing changed
            "missing_events": []Event{},
            "new_server_hlc": getServerLatestHLC(),
        })
    }
}

// Ingests events into the server's event store and broadcasts them
func ingestEvents(events []Event) {
    tx, err := db.Begin()
    if err != nil {
        log.Printf("Failed to begin transaction: %v", err)
        return
    }
    stmt, err := tx.Prepare(`
        INSERT INTO events (event_id, aggregate_id, version, event_type, event_data, timestamp, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(event_id) DO NOTHING; -- Handle potential duplicates from retries
    `)
    if err != nil {
        log.Printf("Failed to prepare statement: %v", err)
        tx.Rollback()
        return
    }
    defer stmt.Close()

    for _, event := range events {
        _, err := stmt.Exec(event.EventID, event.AggregateID, event.Version, event.EventType, event.EventData, event.Timestamp, event.Metadata)
        if err != nil {
            log.Printf("Failed to insert event %s: %v", event.EventID, err)
            // Decide how to handle conflicts/errors. For now, log and continue.
            // If it's a version conflict, it means another client pushed something
            // for the same aggregate. HLCs should help order this.
        } else {
            // Only broadcast if successfully inserted (not a duplicate)
            broadcast <- event
        }
    }
    err = tx.Commit()
    if err != nil {
        log.Printf("Failed to commit transaction: %v", err)
    }
}

// Retrieves events from server since a given HLC
func getEventsSinceHLC(lastHLC string) []Event {
    rows, err := db.Query("SELECT event_id, aggregate_id, version, event_type, event_data, timestamp, metadata FROM events WHERE timestamp > ? ORDER BY timestamp ASC", lastHLC)
    if err != nil {
        log.Printf("Error querying events since HLC %s: %v", lastHLC, err)
        return nil
    }
    defer rows.Close()

    var events []Event
    for rows.Next() {
        var event Event
        var eventData, metadata []byte
        if err := rows.Scan(&event.EventID, &event.AggregateID, &event.Version, &event.EventType, &eventData, &event.Timestamp, &metadata); err != nil {
            log.Printf("Error scanning event row: %v", err)
            continue
        }
        event.EventData = json.RawMessage(eventData)
        event.Metadata = json.RawMessage(metadata)
        events = append(events, event)
    }
    return events
}

// Gets the latest HLC from the server's event store
func getServerLatestHLC() string {
    var hlc string
    err := db.QueryRow("SELECT timestamp FROM events ORDER BY timestamp DESC LIMIT 1").Scan(&hlc)
    if err != nil && err != sql.ErrNoRows {
        log.Printf("Error getting latest HLC: %v", err)
        return ""
    }
    return hlc
}

// Broadcaster to push new events to all connected clients
func handleMessages() {
    for {
        msg := <-broadcast
        clientsMux.Lock()
        for client := range clients {
            err := client.WriteJSON(map[string]interface{}{
                "type": "server_new_events",
                "events": []Event{msg},
            })
            if err != nil {
                log.Printf("Error writing to client: %v", err)
                client.Close()
                delete(clients, client)
            }
        }
        clientsMux.Unlock()
    }
}

func main() {
    go handleMessages() // Start broadcaster

    http.HandleFunc("/ws", handleConnections)
    http.Handle("/", http.FileServer(http.Dir("./web"))) // Serve static web files

    log.Println("Go Server listening on :8080")
    err := http.ListenAndServe(":8080", nil)
    if err != nil {
        log.Fatal("ListenAndServe: ", err)
    }
}
```

#### Git-like Pull-Before-Push Logic

1.  **Client initiates sync:** Sends `client_sync_request` with its `last_synced_hlc` and `local_events`.
2.  **Server evaluates `last_synced_hlc`:**
    * If `server_latest_hlc > client_last_synced_hlc`: The server has events the client doesn't. Server responds with `PULL_REQUIRED` and the `missing_events`.
    * If `server_latest_hlc <= client_last_synced_hlc`: Client is up-to-date or ahead. Server proceeds to ingest `local_events`.
3.  **Client handles `PULL_REQUIRED`:**
    * Client receives `missing_events`.
    * Client applies these `missing_events` to its local event log and updates its materialized view.
    * Client then performs a "rebase" of its `local_events` onto the newly pulled server events. This means re-evaluating the aggregate state and generating new HLCs for its local events to ensure they are causally after the server's latest events. The `hlc_now(uuid())` function is crucial here, as it generates HLCs that are always strictly increasing based on the current logical time and node ID.
    * Client then sends `client_push_events` with its `rebased_events`.
4.  **Server handles `client_push_events`:**
    * Server receives `rebased_events`. It ingests these into its event log. HLCs ensure proper ordering.
    * Server broadcasts new events to all connected clients.

---

## Schema Evolution of Materialized Views

One of the great benefits of event sourcing is the ability to easily evolve your read models (materialized views) without data migration nightmares.

The process is straightforward:

1.  **Stop the client application(s)** that depend on the materialized view.
2.  **Backup the old materialized view database** (optional but recommended).
3.  **Delete the old materialized view database file (`materialized_view.db`)**.
4.  **Update the schema definition** for your materialized view tables in your C projection code.
5.  **Restart the client application.** Upon startup, the projection engine will detect the absence of the materialized view database, create it with the **new schema**, and then **replay all events** from the event log (starting from the beginning) to populate the new materialized view. This process automatically transforms your historical event data into the new desired state.

---

## Runnable Example: A Simple Counter Application

Let's build a "Distributed Counter" to illustrate the concepts.

**Events:**
* `CounterIncremented`: `{"value": 1}`
* `CounterDecremented`: `{"value": 1}`

**Materialized View (Both Client & Server):**
```sql
CREATE TABLE current_count (
    id      INTEGER PRIMARY KEY DEFAULT 1,
    value   INTEGER NOT NULL
);
```

### Components

1.  **C Client (Wasm):**
    * **HTML/JS:** A simple web page (`index.html`) or VSCode webview that loads the Wasm module. It has buttons to increment/decrement the counter and display the current value.
    * **C Code (`counter.c`):**
        * Manages two SQLite DBs (`client_events.db`, `client_mv.db`).
        * Exposes functions to JavaScript: `increment_counter()`, `decrement_counter()`. These functions generate `CounterIncremented` or `CounterDecremented` events, store them in `client_events.db` (with HLCs), and then run the projection locally to update `client_mv.db`.
        * Connects to the Go server via WebSocket to sync events.
        * **Projection:** A C function `project_events()` that reads from `client_events.db` and updates `client_mv.db` (`UPDATE current_count SET value = value + ? WHERE id = 1;`).
        * **HLC functions:** `hlc_now` and `hlc_compare` are registered.

2.  **Go Backend:**
    * **Go Code (`main.go`):** (As provided in the section above)
        * Serves `index.html` and the Wasm module.
        * Manages its own `server_events.db` and a materialized view (e.g., `server_mv.db`).
        * Handles WebSocket connections, `client_sync_request`, `client_push_events`, and broadcasts `server_new_events`.
        * **Projection:** A Go function that performs the same projection logic as the C client, updating the server's `server_mv.db`.

### Example Flow

1.  **Client A starts:** Loads `index.html`, Wasm module initializes, creates empty `client_events.db` and `client_mv.db`. Current count: 0.
2.  **Client A increments:** C function generates `CounterIncremented` event, stores it in `client_events.db` (e.g., HLC `1:0:A`), updates `client_mv.db`. Counter: 1.
3.  **Client A syncs:** Sends `client_sync_request` with `last_synced_hlc=""` and its `CounterIncremented` event.
4.  **Go Server receives:** Ingests the event, broadcasts it. Server's count: 1.
5.  **Client B starts:** Loads `index.html`, Wasm module. Current count: 0.
6.  **Client B syncs:** Sends `client_sync_request` with `last_synced_hlc=""`.
7.  **Go Server responds:** Sends `server_sync_response` with `status: OK` and Client A's `CounterIncremented` event.
8.  **Client B processes:** Stores event, updates `client_mv.db`. Counter: 1.
9.  **Client A goes offline, increments twice:** `CounterIncremented` (HLC `2:0:A`), `CounterIncremented` (HLC `3:0:A`). Local count: 3.
10. **Client B increments once:** `CounterIncremented` (HLC `1:0:B`). Local count: 2. Syncs with server. Server's count becomes 2.
11. **Client A comes online, syncs:**
    * Sends `client_sync_request` (last synced `1:0:server`, local events `2:0:A`, `3:0:A`).
    * **Server responds:** `PULL_REQUIRED` (server has `1:0:B` which Client A doesn't have). Server sends `1:0:B` to Client A.
    * **Client A processes `1:0:B`:** Updates its local DBs.
    * **Client A re-applies its `local_events`:** It now has `1:0:A`, `1:0:B` locally. It re-creates `2:0:A'` and `3:0:A'` with new HLCs that are strictly after the latest server HLC (e.g., `4:0:A`, `5:0:A`), ensuring causal ordering.
    * **Client A pushes `rebased_events`:** Sends `client_push_events` with `4:0:A`, `5:0:A`.
    * **Server receives:** Ingests `4:0:A`, `5:0:A`. Server's total count: 5. Broadcasts to all clients.

### Setting up the Example

1.  **Go Backend:**
    * Save the Go code above as `main.go`.
    * Create a `web` directory.
    * Inside `web`, create `index.html` and your compiled `counter.wasm` and `counter.js` (from your C code).
    * Run `go mod init yourproject`, `go get github.com/gorilla/websocket github.com/mattn/go-sqlite3`.
    * Run `go run main.go`.

2.  **C Client (Wasm):**
    * Write your `counter.c` (implementing the core logic, HLC, and projections).
    * Compile `counter.c` to Wasm. This typically involves `emscripten`:
        ```bash
        emcc counter.c -o web/counter.js -s EXPORTED_FUNCTIONS='["_increment_counter", "_decrement_counter", "_init_db", "_sync_events"]' -s EXTRA_EXPORTED_RUNTIME_METHODS='["cwrap"]' -s WASM=1 -s USE_SQLITE3=1 -s DISABLE_PTHREADS=1 -s MODULARIZE=1 -s EXPORT_ES6=1 -s USE_ZLIB=0 -s USE_BZIP2=0 --embed-file ./client_events.db --embed-file ./client_mv.db
        ```
        You'll need `wa-sqlite`'s specific Emscripten setup to ensure it uses IndexedDB for persistence and allows custom function registration. `wa-sqlite` essentially provides the necessary SQLite `.a` or `.bc` files for Emscripten to link against.
    * Your `index.html` would load `counter.js` and interact with the Wasm module using `cwrap` or similar methods.

### Tests

1.  **Unit Tests (C):**
    * Test `hlc_now` for correct HLC generation (monotonicity, node ID inclusion).
    * Test `hlc_compare` for correct ordering.
    * Test individual projection handlers in isolation.
    * Test SQLite interaction in C (e.g., event insertion, query by HLC).
2.  **Unit Tests (Go):**
    * Test HLC parsing and comparison.
    * Test `ingestEvents` (event insertion, duplicate handling).
    * Test `getEventsSinceHLC`.
    * Test the `handleClientSyncRequest` logic in isolation (mock WebSocket `WriteJSON` calls).
3.  **Integration Tests (Go/JS/C):**
    * **Local-only:** Verify events are written and projected correctly without network.
    * **Basic Sync:** Client pushes events, server receives and broadcasts, another client pulls.
    * **Offline Changes + Sync:** Client goes offline, makes changes, comes back online, pulls server changes, pushes its rebased changes. Verify final state across all clients and server.
    * **Schema Evolution:** Test dropping and replaying materialized views.

---

This architecture provides a robust, local-first event-sourced system that leverages the strengths of SQLite, C, and Go for performance, durability, and flexible synchronization.