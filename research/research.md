# **Designing and Implementing a Local-First Event-Sourced System with SQLite (C/WASM), Go, and Real-time Synchronization**

## **1. Introduction: The Local-First Event Sourcing Paradigm**

This report outlines a robust architectural approach for a local-first event-sourced application, leveraging SQLite for local persistence, a pure C core for high performance and custom functionality, and a Go backend for scalable synchronization. This design separates the immutable event log from query-optimized materialized views, achieving flexible schema evolution and enhanced read performance. The integration of Hybrid Logical Clocks (HLC) directly within SQLite facilitates distributed ordering and enables sophisticated Git-like synchronization with conflict detection. Real-time communication via WebSockets ensures efficient, bidirectional event stream replication, supporting an intuitive offline-first user experience with optional background synchronization.

### **1.1. Core Concepts of Event Sourcing and its Benefits**

Event Sourcing represents a fundamental architectural pattern where an application's state changes are recorded as an immutable sequence of events within an append-only log, rather than merely storing the current state.1 This paradigm shifts the authoritative source of truth from the current data snapshot to the complete chronological history of events.3 Each event captures a single, atomic state transition within a specific domain, such as "UserCreated" or "OrderShipped," and includes all relevant data, a timestamp, and a unique identifier.1 The current state of any system entity is then dynamically derived by replaying these historical events in their recorded order.2

This event-centric approach yields a multitude of advantages. Firstly, it provides an unparalleled audit trail, offering a complete, immutable, and verifiable record of all actions and changes within the system over time, which is critical for compliance and understanding system evolution.1 Secondly, the ability to reconstruct past states by replaying events up to any specific point in time offers significant benefits for debugging, analyzing system behavior, and conducting "what-if" scenarios.1 This also facilitates comprehensive root cause analysis, enabling business events to be traced back to their origins, providing full traceability across workflows.1

Furthermore, event streams are inherently robust logs, contributing to superior fault tolerance and recovery capabilities. Should a system component fail, its state can be reliably rebuilt by replaying events from the immutable event store, ensuring strong backup and recovery characteristics.1 The pattern also promotes decoupling and scalability; events serve as a loose coupling mechanism between distinct system components or microservices. This decoupling enables asynchronous processing, independent development, and horizontal scaling of services that consume these events, leading to more resilient and performant systems.1 The rich business context embedded within events also enhances observability, allowing for unprecedented real-time analytics and deeper insights into system and user behavior.1 Finally, a significant advantage lies in schema evolution: materialized views, which are read-optimized projections of the event stream, can be effortlessly rebuilt from the authoritative event log when their schema requires modification, thereby simplifying database migrations for read models.2

### **1.2. Principles and Advantages of Local-First Architecture**

Local-first software design fundamentally prioritizes the user experience by ensuring that application functionality remains uninterrupted, irrespective of network connectivity.9 The core tenet is that the availability of a remote computer should never impede a user's ability to work.9 In this paradigm, data is primarily stored and manipulated directly on the client device. Synchronization with remote servers or other collaborating devices then occurs in the background, making network interaction an optional, non-blocking process for core application operations.10

This architectural philosophy delivers substantial benefits. Foremost among them is instant responsiveness and near-zero latency; user interactions, such as queries and updates, execute directly against the local datastore, eliminating network round-trip delays and ensuring immediate user interface feedback.9 This significantly enhances the user's perception of speed and fluidity. Crucially, local-first applications maintain full functionality even when offline, allowing users to continue reading and writing data. Any changes made during disconnection are automatically queued and synchronized once network connectivity is re-established.10

The combination of instant responsiveness and offline capability fosters a fluid, always-available user experience that feels inherently fast and reliable.9 Moreover, local-first designs inherently support collaborative features, enabling multiple devices to work on the same dataset with changes seamlessly synchronized across all of them in the background, akin to collaborative editing tools.9 From a backend perspective, this approach can reduce server load; instead of frequent, small requests, local-first architectures can batch changes and push/pull them in larger, more efficient chunks during synchronization.10 Lastly, the local datastore itself effectively functions as a reliable and quickly accessible cache for all user actions, simplifying the implementation of complex multi-layer caching mechanisms.10

### **1.3. Rationale for SQLite as the Local Event Store and Materialized View Database**

SQLite stands out as an optimal choice for the local persistence layer in this architecture due to its unique characteristics. As a self-contained, serverless, zero-configuration, and transactional SQL database engine, its embedded nature allows the database to reside directly on the client device, eliminating the need for a separate database server. This significantly reduces operational overhead, making it highly suitable for local-first applications.12

SQLite is widely recognized for its robustness and simplicity, requiring minimal setup and management.14 When properly configured and with an efficient schema design, SQLite can deliver excellent performance for both local read and write operations. Key performance best practices include enabling Write-Ahead Logging (WAL) for improved concurrency and data durability, relaxing the synchronization mode to NORMAL for a balance of performance and safety, defining efficient table schemas with appropriate indexes (e.g., INTEGER PRIMARY KEY, multi-column indexes), and critically, batching multiple write operations within a single transaction to minimize disk I/O overhead.15

The flexibility of SQLite further enhances its suitability. It supports various data types, including BLOB, which is highly efficient for storing serialized event payloads (e.g., JSON or Protocol Buffers) directly within the database, often outperforming direct filesystem calls for smaller data sizes.15 Its C codebase is highly portable and can be compiled for a wide range of environments, including native desktop/mobile applications and WebAssembly (WASM) for web-based applications, ensuring consistent database behavior across diverse platforms.17 Finally, SQLite's capability to manage multiple database files, for instance, through the ATTACH DATABASE command, makes it straightforward to implement the separation of the event store and materialized view databases, a design pattern that aligns perfectly with the Command Query Responsibility Segregation (CQRS) principle.15

### **1.4. System Architecture Overview: C/WASM, Go, and Web Integration**

The proposed system architecture is designed to deliver a high-performance, local-first event-sourced application with robust synchronization capabilities. It comprises distinct client-side and backend components, integrated through specific communication protocols.

On the **client-side**, which will manifest as a web application and potentially a VSCode extension, the foundational data persistence layer is powered by **SQLite**. The pure C SQLite amalgamation, along with custom functionality, will be compiled to WebAssembly (WASM) using Emscripten. This compilation allows the SQLite instance to run directly within the web browser environment, managing two distinct SQLite database files: one dedicated to the immutable event log and another for query-optimized materialized views. For persistent storage in the browser, the WASM SQLite instance will leverage the Origin Private File System (OPFS), ensuring that local database files (events.db, views.db) remain available across browser sessions, thereby fulfilling the "local-first" requirement.18 The web application's user interface, built with modern JavaScript, will interact with this WASM-compiled SQLite instance via a thin JavaScript wrapper, performing all local data operations. As an optional but significant enhancement, this C/WASM SQLite core can be integrated into a VSCode extension, enabling developers or power users to directly inspect, query, and manage the local databases from within their integrated development environment. This integration could expose the custom C functions for advanced debugging or data manipulation, providing a powerful development and diagnostic tool.20

The **backend** is a **Go application** serving as the central synchronization hub and webserver. Its primary responsibilities include receiving events pushed from clients, storing them in a central event log (or acting as a broker for replication), broadcasting new events to connected clients, serving historical events for client pulls, and orchestrating conflict detection and resolution. The Go application will also serve the static assets of the web application frontend, acting as a unified server for both data synchronization and content delivery.

**Synchronization** between clients and the backend will primarily utilize **WebSockets**. This protocol is chosen for its bidirectional, low-latency, and persistent connection capabilities, which are ideal for real-time event stream replication.21 This choice enables a "Git-like" pull-before-push mechanism for event stream replication, ensuring data consistency across distributed clients.

A critical component for distributed ordering and conflict detection will be **Hybrid Logical Clocks (HLCs)**. These will be implemented as custom functions directly within the C SQLite core. This design ensures that HLC timestamps are generated and compared consistently at the data layer itself, providing a robust foundation for maintaining causal order across distributed nodes.23

## **2\. Event Store Implementation with SQLite (C Core)**

This section details the construction of the immutable event store using SQLite, focusing on the pure C implementation and the integration of Hybrid Logical Clocks for distributed consistency.

### **2.1. Designing the Immutable Event Store Schema in SQLite**

The event store, serving as the single source of truth for the system, is fundamentally designed as an append-only log where events are never modified or deleted.1 Each entry in this log represents a discrete, atomic change in the system's state. The schema for the events table in SQLite is meticulously designed to support this paradigm and facilitate efficient querying and synchronization:

* **event\_id** (TEXT/BLOB, PRIMARY KEY): This column will store a globally unique identifier for each event, typically a UUID. Using TEXT for UUID strings or BLOB for binary UUIDs ensures uniqueness and efficient lookup.16  
* **aggregate\_id** (TEXT/BLOB, NOT NULL): This identifies the specific domain aggregate (e.g., a User ID, Order ID) to which the event pertains. This is crucial for retrieving all events related to a particular entity efficiently.  
* **event\_type** (TEXT, NOT NULL): A descriptive string that categorizes the event (e.g., "UserCreated," "TaskCompleted," "OrderShipped"). This field is vital for event handlers and projection logic to correctly interpret and apply the event's payload.5  
* **event\_data** (BLOB, NOT NULL): The serialized payload of the event, encompassing all data relevant to the state change. JSON is a common and flexible format for this purpose. Storing it as a BLOB is efficient for small-to-medium sized data within SQLite, as it minimizes filesystem calls and can be faster than storing data in external files.15  
* **hlc\_timestamp** (TEXT, NOT NULL): This column will hold the Hybrid Logical Clock timestamp. This value is generated by the custom hlc\_now() SQLite function, ensuring distributed ordering and causality across all participating nodes. Storing it as TEXT facilitates straightforward comparison and serialization.  
* **version** (INTEGER, NOT NULL): An aggregate-specific version number that monotonically increases with each new event appended for a given aggregate\_id. This versioning is fundamental for implementing optimistic concurrency control during write operations, preventing conflicting updates.5  
* **created\_at** (INTEGER, NOT NULL): A standard Unix timestamp representing the physical time when the event was recorded. This is useful for human-readable audits, general time-based queries, and debugging purposes.

An effective **indexing strategy** is paramount for the performance of the event store. The event\_id column, being the PRIMARY KEY, is automatically indexed, allowing for rapid lookups by event identifier. An index on aggregate\_id is essential for efficiently retrieving all events associated with a specific domain object.15 A composite index on aggregate\_id and version is critical for ordering events within an aggregate and for performing optimistic concurrency checks, enabling fast retrieval of events for a given aggregate in their correct sequence.15 Finally, an index on hlc\_timestamp will accelerate global ordering and synchronization operations, allowing the system to quickly identify and retrieve events based on their causal order.

To optimize SQLite performance, several **best practices** will be applied. Enabling **Write-Ahead Logging (WAL) mode** for the event store significantly improves concurrency by allowing multiple readers to operate without blocking writers, while also enhancing data durability.14 When WAL is active, setting the synchronization mode to PRAGMA synchronous \= NORMAL provides a robust balance between performance and data safety, ensuring that data typically reaches the disk even if the application experiences an unexpected crash.15 For optimal write throughput, it is crucial to **batch multiple event insertions into a single SQLite transaction**. This approach dramatically reduces the overhead of frequent disk writes and database locks, leading to more efficient persistence.16 While event\_id will be a UUID, for other tables or if a simple monotonic sequence is needed, INTEGER PRIMARY KEY can be highly efficient. For tables where rowid access is not explicitly needed and space optimization is paramount, WITHOUT ROWID can be considered to reduce storage overhead.15

### **2.2. Implementing Core SQLite Interactions in Pure C**

All interactions with the SQLite databases, encompassing both the event store and materialized views, will be implemented directly using the pure C API. This low-level approach provides maximum control over database operations and ensures optimal performance.

The foundation of these interactions relies on several key SQLite C API functions. sqlite3\_open\_v2() is used for establishing database connections with specific flags (e.g., SQLITE\_OPEN\_READWRITE | SQLITE\_OPEN\_CREATE) to manage the separate event and materialized view database files.26 For initial schema creation or simple, non-parameterized SQL commands, sqlite3\_exec() can be employed.26 However, for recurring operations such as inserting events, fetching events by aggregate ID, or querying materialized views, sqlite3\_prepare\_v2() and sqlite3\_step() are essential. Prepared statements are critical for preventing SQL injection vulnerabilities and offer superior performance compared to sqlite3\_exec for repeated queries.15 Parameters are bound to these prepared statements using sqlite3\_bind\_\*() functions, ensuring correct data type handling and security. Data is retrieved from query results using sqlite3\_column\_\*() functions. After execution, sqlite3\_finalize() is crucial for releasing resources associated with prepared statements, and sqlite3\_close() is used for gracefully closing database connections.26

Given the low-level nature of C, robust error handling is paramount. sqlite3\_errmsg() will be utilized to retrieve detailed error messages from SQLite, which are invaluable for debugging and logging system issues.26 Careful attention to memory management is also required. Functions like sqlite3\_free() must be used to deallocate memory returned by SQLite, such as error messages. When returning string or BLOB data from custom functions or queries, employing SQLITE\_TRANSIENT or explicit memory copying is often necessary to ensure the validity of the data beyond the scope of the SQLite statement.29 The SQLite "amalgamation," a single sqlite3.c source file and sqlite3.h header, simplifies embedding the entire SQLite library directly into the C application. This single-file approach streamlines compilation and distribution, making it an ideal choice for this embedded database solution.12

### **2.3. Integrating the Hybrid Logical Clock (HLC) as a Custom SQLite Function**

The integration of Hybrid Logical Clocks (HLCs) as custom functions directly within the SQLite C core is a pivotal architectural decision. HLCs are designed to provide a timestamp that is sufficiently close to physical time while simultaneously capturing the causal relationships between events in a distributed system.23 This capability is critical for maintaining consistency and resolving conflicts in environments prone to network latency and clock drift. HLCs achieve this by combining a physical timestamp, a Lamport clock counter, and a unique node identifier (UUID).24

Embedding HLC logic directly into SQLite as custom functions, specifically hlc\_now() for generation and hlc\_compare() for comparison, transforms SQLite from a generic data store into a causality-aware event log. This approach ensures that HLC timestamps are generated atomically with event persistence, minimizing the window for race conditions and simplifying the complex distributed logic that would otherwise need to reside in higher-level Go and JavaScript code. It allows for direct database-level filtering and ordering based on causal relationships, which is fundamental for robust synchronization and conflict resolution. This design effectively pushes distributed systems concerns closer to the data, making the overall system more robust and easier to reason about, especially in a local-first model where the local database is the immediate source of truth.

The custom HLC functions will be implemented using sqlite3\_create\_function().

* **hlc\_now(uuid TEXT) Function:** This scalar function will generate a new HLC timestamp.  
  * **Signature:** int sqlite3\_create\_function(db, "hlc\_now", 1, SQLITE\_UTF8 | SQLITE\_DETERMINISTIC, NULL, \&hlc\_now\_func, NULL, NULL); 30  
  * **Logic (inside hlc\_now\_func):**  
    1. The function first retrieves the current physical time (pt.j).  
    2. It then accesses the last known HLC state (l\_prev, c\_prev) for the local node. This state must be persistently stored, for example, in a dedicated hlc\_state table within the SQLite database or a small file managed by the C core, and loaded at application startup.24  
    3. The HLC algorithm is applied to compute the new logical time (l\_new) and counter (c\_new): l\_new \= max(l\_prev, pt.j); if (l\_new \== l\_prev) { c\_new \= c\_prev \+ 1; } else { c\_new \= 0; }.23  
    4. The uuid argument, representing the unique identifier of the current node, is retrieved.  
    5. l\_new, c\_new, and the uuid are then serialized into a canonical HLC string format (e.g., physical\_time:counter:uuid).  
    6. The persistent local HLC state is updated with l\_new and c\_new.  
    7. Finally, the serialized HLC string is returned using sqlite3\_result\_text(context, hlc\_string, \-1, SQLITE\_TRANSIENT);.29  
* **hlc\_compare(hlc1 TEXT, hlc2 TEXT) Function:** This scalar function will compare two HLC timestamps.  
  * **Signature:** int sqlite3\_create\_function(db, "hlc\_compare", 2, SQLITE\_UTF8 | SQLITE\_DETERMINISTIC, NULL, \&hlc\_compare\_func, NULL, NULL); 30  
  * **Logic (inside hlc\_compare\_func):**  
    1. The function parses hlc1 and hlc2 into their respective l, c, and node\_id components.  
    2. The HLC comparison logic is implemented as follows:  
       * If l1 \> l2, hlc1 is considered greater.  
       * If l1 \< l2, hlc2 is considered greater.  
       * If l1 \== l2:  
         * If c1 \> c2, hlc1 is greater.  
         * If c1 \< c2, hlc2 is greater.  
         * If c1 \== c2: The node\_ids are compared lexicographically to provide a deterministic tie-breaker.24  
    3. An integer indicating the comparison result (e.g., \-1 if hlc1 \< hlc2, 0 if equal, 1 if hlc1 \> hlc2) is returned.

Both hlc\_now and hlc\_compare should be registered with the SQLITE\_DETERMINISTIC flag. This flag informs SQLite's query planner that the function will consistently return the same result for the same inputs within a single SQL statement, allowing for additional query optimizations.31 The persistence of the local HLC state (l and c components) across application restarts is crucial to ensure monotonic progress and correct causality. This state can be stored in a dedicated, single-row SQLite table (e.g., CREATE TABLE hlc\_state (last\_l INTEGER, last\_c INTEGER);) or a small configuration file managed by the C core.24

\<br\>

**Table 4: HLC Structure and Operations**

| Component/Function | Description | Pseudo-code Logic |
| :---- | :---- | :---- |
| **HLC Components** |  |  |
| l (Logical Time / Max Physical Time) | An integer representing the dominant logical time, typically derived from the maximum of the local logical time and the physical clock. |  |
| c (Counter) | An integer counter that increments only when the logical time (l) does not advance, used to differentiate concurrent events at the same logical time. |  |
| node\_id (UUID) | A unique identifier for the node (client device) generating the HLC, used as a tie-breaker when l and c are identical. |  |
| **hlc\_now(uuid TEXT) Function** | Generates a new HLC timestamp. | function hlc\_now(current\_node\_uuid):\<br\> pt\_j \= current\_physical\_time()\<br\> (l\_prev, c\_prev) \= load\_local\_hlc\_state()\<br\>\<br\> l\_new \= max(l\_prev, pt\_j)\<br\> if l\_new \== l\_prev:\<br\> c\_new \= c\_prev \+ 1\<br\> else:\<br\> c\_new \= 0\<br\>\<br\> save\_local\_hlc\_state(l\_new, c\_new)\<br\> return serialize\_hlc(l\_new, c\_new, current\_node\_uuid) |
| **hlc\_compare(hlc1 TEXT, hlc2 TEXT) Function** | Compares two HLC timestamps. | function hlc\_compare(hlc1\_str, hlc2\_str):\<br\> (l1, c1, node\_id1) \= parse\_hlc(hlc1\_str)\<br\> (l2, c2, node\_id2) \= parse\_hlc(hlc2\_str)\<br\>\<br\> if l1\!= l2:\<br\> return compare(l1, l2)\<br\> else if c1\!= c2:\<br\> return compare(c1, c2)\<br\> else:\<br\> return compare\_lexicographically(node\_id1, node\_id2) |

\<br\>

### **2.4. Considerations for a VSCode Extension (C/WebAssembly)**

The requirement for a "pure C (possibly as a VSCode extension)" component introduces a significant architectural consideration: the C core must function seamlessly in both native environments (e.g., for standalone desktop tools or server-side CGO integration) and WebAssembly (WASM) environments (for the web application and VSCode extension). This necessitates a robust, multi-target build system, typically employing Emscripten for WASM compilation and a standard C compiler for native builds. A careful design of the C API is also required to abstract away environment-specific concerns, such as direct file I/O versus JavaScript interoperability for memory access.

The WASM compilation pipeline for the pure C SQLite core, including the custom HLC functions, will be managed by Emscripten. This process involves specifying particular compilation flags and linker options to ensure that the necessary C functions are exported and callable from JavaScript. The SQLITE\_EXTRA\_INIT compilation flag is particularly important for automatically registering custom SQLite functions, such as hlc\_now and hlc\_compare, when the WASM SQLite database is initialized.17

While SQLite's official WASM build (wa-sqlite serves as a valuable reference 19) provides some high-level JavaScript bindings, custom C functions will necessitate explicit JavaScript wrappers. This involves meticulous management of argument and result type conversions between C's native types (e.g., pointers, integers) and JavaScript's types (e.g., strings, numbers, objects). The sqlite3.capi namespace and functions like wasm.installFunction() are relevant for creating these bindings, allowing JavaScript to interact with the underlying C functions.17

The architecture of a VSCode extension incorporating this functionality would involve several layers. To prevent blocking the main UI thread of the VSCode extension (or the web browser), the WASM SQLite instance should ideally run within a Web Worker. This ensures that potentially long-running database operations, such as materialized view rebuilds, do not freeze the user interface, maintaining a responsive experience.18 Communication between the main VSCode extension thread (or the web application's main thread) and the Web Worker will occur via message passing, typically using postMessage, which involves serializing commands and results between the two contexts. The VSCode extension can then expose commands (e.g., "Open Event Store," "Query Materialized View," "Rebuild View," "Initiate Sync") that trigger corresponding operations on the local SQLite databases through the Web Worker.20 For the web-based example and the VSCode extension, which often operates in a browser-like environment, the WASM SQLite instance can leverage the Origin Private File System (OPFS) for persistent storage. This ensures that the local database files (events.db, views.db) remain available across browser sessions, fulfilling the "local-first" requirement.18

The performance characteristics and available features of the C core, particularly concerning file I/O and direct memory access versus JavaScript interop, must be carefully considered during the design phase. The ability to compile the same C codebase to both native and WASM targets streamlines development and ensures consistency across different deployment environments.

## **3\. Materialized Views and Schema Evolution**

Materialized views are a cornerstone of Command Query Responsibility Segregation (CQRS) within an event-sourced system. They provide query-optimized representations of the underlying immutable event stream, enabling efficient data retrieval without the overhead of replaying events for every read operation.

### **3.1. Designing Materialized View Schemas in a Separate SQLite Database**

In an event-sourced architecture, materialized views serve as read models, providing optimized data structures for specific query requirements.2 These views are distinct from the event store and are typically highly denormalized to enhance read performance, avoiding complex joins that would be necessary if querying the raw event log.34 By separating the read and write models, the system gains independent scaling capabilities, allowing each model to be optimized for its specific workload.34

The materialized view database will reside in a separate SQLite file (e.g., views.db) from the event store (events.db). This physical separation reinforces the logical separation of concerns inherent in CQRS. The schema for materialized views will be tailored to the specific query patterns of the application. For example, a "User Profile" view might denormalize user creation and update events into a single users table with columns like user\_id, name, email, and last\_updated\_hlc. Similarly, a "Task List" view could aggregate TaskCreated, TaskCompleted, and TaskAssigned events into a tasks table with fields such as task\_id, description, status, assigned\_to, and completion\_hlc.

Indexing in the materialized view database will focus on accelerating common queries. For instance, user\_id in a users table or task\_id in a tasks table would be primary keys or have unique indexes. Other frequently filtered or sorted columns, like status or assigned\_to, would also benefit from appropriate indexes.15 The use of BLOB for storing complex, non-queryable data within a materialized view, similar to the event store, can be efficient for small data.15

### **3.2. Projection Logic for Materialized View Reconstruction**

Projections are the mechanisms responsible for transforming events from the immutable event store into the query-optimized materialized views.1 This process involves applying event data to update the state represented in the read model. The projection logic is essentially a set of event handlers that listen for specific event types and update the corresponding materialized view tables.

When a new event is appended to the event store, it can trigger a notification, prompting subscribers (the projection engine) to perform follow-up actions, such as running a projection to update the read model.1 This update process is typically asynchronous, meaning there might be a slight delay between an event being recorded in the event store and its reflection in the materialized view, leading to eventual consistency.7 The system must be designed to account for this eventual consistency, and users should be aware that read data might not immediately reflect the most recent changes.7

The ability to easily change the schema for materialized views is a significant advantage of event sourcing. If the read model schema needs to evolve, the materialized view database can simply be rebuilt from scratch by replaying all events from the event store.2 This "replayability" is a powerful feature: the complete sequence of events can be replayed at any point in time to generate a new materialized view or to integrate alterations in the event processing logic.2 This contrasts sharply with traditional database migrations, which often involve complex, risky, and time-consuming schema alterations on live data. For instance, if a new business requirement emerges that necessitates a different aggregation of user activity, the existing materialized view can be dropped, the projection logic updated, and the new view rebuilt by replaying the entire event stream. This ensures that the read model can adapt to changing business needs without impacting the integrity or immutability of the core event log.2

The projection engine, likely implemented in C to maintain performance parity with the event store, will subscribe to new events and apply them to the materialized views. This could involve a simple event loop that reads new events from the event store (ordered by hlc\_timestamp and version), deserializes their event\_data, and executes appropriate SQL INSERT, UPDATE, or DELETE statements on the materialized view database. The HLC timestamps can be used to track the "last processed event" for each projection, allowing the engine to resume processing from the correct point after restarts or disconnections.

## **4\. Synchronization with Go Backend and Web Clients**

Synchronization is a critical aspect of local-first architectures, ensuring data consistency across distributed clients and a central backend. This system will leverage WebSockets for real-time, bidirectional communication, with a Go backend orchestrating the sync process and handling conflicts.

### **4.1. Choosing the Right Communication Protocol: WebRTC, WebSockets, or SSE**

Selecting the appropriate communication protocol for synchronization is crucial for achieving real-time updates and efficient data exchange. The primary candidates are WebRTC, WebSockets, and Server-Sent Events (SSE).

**Server-Sent Events (SSE)** are designed exclusively for one-way communication, from the server to the client.21 They are ideal for scenarios like live news feeds or sports scores where the client only needs to receive real-time updates without sending data back to the server.21 While SSE offers low latency for server-to-client communication and automatically reconnects on connection loss, its unidirectional nature makes it unsuitable for the bidirectional synchronization required in an event-sourced system where clients also push changes.21

**WebRTC (Web Real-Time Communication)** is an open-source project primarily designed for high-performance, peer-to-peer media transfer (audio, video) directly between browsers or mobile applications.21 While it offers high-quality data transmission and is peer-to-peer for media, it still requires a "signaling server" to establish the initial connection and exchange metadata.21 This signaling server typically runs over WebSockets or similar protocols, which means WebRTC doesn't fully replace the need for a central server for event stream synchronization. Given that the core requirement is event stream replication rather than direct media exchange, WebRTC introduces unnecessary complexity for this specific use case.21

**WebSockets** emerge as the optimal choice for this system's synchronization needs. They establish persistent, bidirectional (full-duplex) communication channels over a single TCP connection between clients and servers.22 This "always-on" connection eliminates the overhead of constantly establishing new HTTP connections (as in long-polling) and provides the lowest latency for real-time applications where immediate data exchange is critical.21 WebSockets are ideal for scenarios requiring constant data exchange, such as live chat, multiplayer gaming, and, crucially, real-time data broadcasting and synchronization.22 Go's strong support for concurrency (goroutines and channels) and its rich standard library make it an excellent choice for implementing scalable and efficient WebSocket servers.36 This allows for efficient handling of a large number of simultaneous connections and real-time event handling, where actions can be triggered based on specific events or updates without continuous polling.36

### **4.2. Go Backend Sync Server and Webserver**

The Go application will serve a dual role: acting as both the webserver for the client-side application and the central synchronization server for event streams. This consolidation simplifies deployment and management.

As a **webserver**, the Go application will serve the static HTML, CSS, and JavaScript files that constitute the web application frontend. This is a standard capability of Go's net/http package.

As the **sync server**, its primary function is to facilitate the exchange of events between connected clients and maintain the authoritative central event log. The server will expose a WebSocket endpoint for clients to connect. When a client connects, the server will manage its state, including the last HLC timestamp it acknowledged from the server.

The sync server will handle two main operations: **pulling** and **pushing** events. When a client initiates a pull, it sends its latest known HLC timestamp. The server then queries its central event store (which could also be a SQLite database, or a more robust distributed database like PostgreSQL if scale demands it) for all events with an HLC timestamp greater than the client's provided timestamp, ordered by HLC. These new events are then streamed back to the client over the WebSocket connection. When a client pushes changes, it sends a batch of its locally generated events to the server. The server validates these events, applies them to its central event store, and then broadcasts them to all other connected clients (excluding the originating client) to ensure eventual consistency across the system.

The Go backend will also be responsible for **conflict detection and resolution**. When a client pushes changes, the server must check for conflicts. The HLC timestamps are instrumental here. If the server detects that a client's pushed events conflict with events already processed on the server (e.g., two clients modified the same aggregate concurrently, resulting in different event sequences or values for the same logical time), the server will use the hlc\_compare logic to determine the causal order. The server can then implement a conflict resolution strategy. For instance, it might apply a "last-write-wins" approach based on HLC timestamps, or it could queue conflicts for manual review or more sophisticated business-rule-driven merging. The Go backend's robust concurrency model makes it well-suited for handling these complex synchronization and conflict resolution tasks efficiently.

### **4.3. Git-like Sync Logic and Conflict Resolution**

The user's requirement for "Git-like" sync logic, specifically "when the user tries to push changes but needs to pull first," implies a robust mechanism for managing concurrent modifications and ensuring data integrity across distributed nodes. This approach mirrors Git's workflow where a user must git pull (fetch and merge remote changes) before git push (send local changes to the remote) if the remote history has diverged.37

In this event-sourced system, the HLC timestamps are the key enablers for this Git-like behavior. Each client maintains its local event log, with events stamped by its local HLC. When a client wants to synchronize its local changes with the backend:

1. **Local Commit:** The client first "commits" its local changes by appending new events to its local event store, each stamped with hlc\_now(uuid()). These events are initially "unpushed" or "uncommitted" from the perspective of the central server.  
2. **Pull Phase (Fetch Remote Events):** Before pushing, the client initiates a "pull" operation. It sends its current highest HLC timestamp for each aggregate (or a global HLC if all events are part of a single stream) to the Go sync server. The server responds with all events that have occurred on the server since that timestamp, ordered by HLC.  
3. **Local Merge/Replay:** The client then integrates these newly pulled events into its local event store. This involves replaying the new events. During this replay, the client's projection engine updates its materialized views. If any of the pulled events conflict with the client's *unpushed* local events (i.e., they affect the same aggregate at causally overlapping HLCs), a conflict is detected.  
4. **Conflict Detection and Resolution:** The hlc\_compare function, embedded in SQLite, becomes critical here. For each conflicting aggregate, the client can compare the HLCs of its local unpushed events with the newly pulled events.  
   * If the system implements a "last-write-wins" strategy, the event with the later HLC (as determined by hlc\_compare) prevails.  
   * For more complex scenarios, the client-side application logic (or the C core) might need to present the conflict to the user for manual resolution, or apply specific business rules for merging (e.g., merging partial fields if event payloads allow).10 The ability to replay events allows for "time travel" to analyze the state before and after conflicting events, aiding in resolution.1  
   * After resolution, new "resolution events" might be generated and appended locally.  
5. **Push Phase (Send Local Events):** Once all conflicts are resolved locally (or if no conflicts were detected), the client sends its *newly generated and resolved* local events (those not yet seen by the server) to the Go sync server. The server processes these, applies them to its central event store, and broadcasts them to other connected clients. The server will also use HLCs and optimistic concurrency (checking aggregate versions) to detect and manage conflicts on its end, potentially rejecting pushes if the client's base state is too old.5

This Git-like flow, facilitated by HLCs, ensures that clients always work with the most up-to-date information before contributing their own changes, minimizing the occurrence of unresolvable conflicts and maintaining eventual consistency across the distributed system. The optional nature of sync means the client can continue working offline, and this pull-before-push mechanism only engages when connectivity is available and synchronization is desired.

## **5\. Running Example and Testing Strategy**

To demonstrate the viability and functionality of this architecture, a concrete running example and a comprehensive testing strategy are essential.

### **5.1. Running Example: A Collaborative To-Do List Application**

A collaborative to-do list application serves as an excellent running example for this architecture. It inherently involves local-first operations, synchronization, and potential conflicts.

**Client-Side (Web Application):**

* **User Interface:** A simple web interface built with HTML, CSS, and JavaScript.  
* **Local Data Layer:** The JavaScript frontend interacts with the WASM-compiled SQLite instance (running in a Web Worker) for all CRUD operations on to-do items.  
  * When a user creates a new to-do item, marks it complete, or edits its description, the JavaScript code constructs a corresponding domain event (e.g., TodoCreated, TodoCompleted, TodoDescriptionUpdated).  
  * These events are then passed to the C/WASM SQLite core, which appends them to the local events.db table, using hlc\_now(client\_uuid) to timestamp each event.  
  * The C/WASM core's projection logic immediately updates the local views.db (e.g., a todos table with id, description, status, hlc\_timestamp, last\_modified\_by) to reflect the change, providing instant UI feedback.  
  * Read operations (displaying the to-do list) query the views.db for fast retrieval.  
* **Synchronization Logic:**  
  * An "Online/Offline" indicator visually communicates connectivity status.  
  * When online, a background WebSocket connection is established with the Go sync server.  
  * A "Sync" button (or automatic background sync) triggers the Git-like pull-before-push process:  
    1. Client sends its latest hlc\_timestamp from events.db to the server.  
    2. Server sends back all new events.  
    3. Client replays new events, resolving conflicts (e.g., last write wins based on HLC for TodoDescriptionUpdated conflicts, or appending both if distinct items).  
    4. Client pushes its locally generated, un-synced events to the server.  
  * The HLC functions in SQLite ensure correct ordering and conflict detection during this process.

**Backend-Side (Go Server):**

* **Webserver:** Serves the static web application files.  
* **Sync Server:**  
  * Manages WebSocket connections from multiple clients.  
  * Maintains a central events table (similar schema to client's events.db) and a central todos materialized view.  
  * Handles pull requests: queries its events table for events newer than the client's provided HLC and streams them.  
  * Handles push requests: receives client events, applies them to its central events table (using hlc\_now(server\_uuid) for server-originated events and hlc\_compare for conflict checks), and updates its central todos materialized view.  
  * Broadcasts new events to all other connected clients to maintain real-time consistency.

**Demonstration Scenarios:**

1. **Offline Work:** User creates and completes tasks while offline. UI updates instantly.  
2. **Online Sync:** User connects, presses "Sync." Local changes are pushed, remote changes are pulled and merged.  
3. **Conflict Resolution:** Two users simultaneously edit the same to-do item's description while offline. Upon syncing, the system demonstrates how the conflict is detected (using HLC) and resolved (e.g., last-write-wins by HLC, or both versions shown with a flag).  
4. **Schema Evolution:** A new field, e.g., due\_date, is added to the Todo aggregate. The projection logic is updated. Clients can rebuild their views.db from the existing events.db to incorporate the new field without data loss.

### **5.2. Test Cases**

A comprehensive testing strategy will cover unit, integration, and end-to-end tests across both client and server components.

**Unit Tests (C Core):**

* **SQLite API Wrappers:** Test individual sqlite3\_open, sqlite3\_exec, sqlite3\_prepare\_v2, sqlite3\_bind, sqlite3\_step, sqlite3\_column, sqlite3\_finalize, sqlite3\_close calls for expected behavior and error conditions.  
* **HLC Functions:**  
  * hlc\_now(uuid()): Test generation of HLCs, ensuring monotonicity and correct incrementing of the counter (c) when physical time (l) does not advance. Verify persistence and loading of local HLC state.  
  * hlc\_compare(hlc1, hlc2): Test comparison logic for all cases (HLC1 \< HLC2, HLC1 \> HLC2, HLC1 \== HLC2), including tie-breaking by UUID.  
* **Event Store Operations:** Test insert\_event, get\_events\_by\_aggregate\_id, get\_events\_since\_hlc for correctness and performance.  
* **Projection Logic:** Test individual event handlers within the C core, ensuring they correctly update the materialized view schema based on specific event types.

**Integration Tests (Client-side):**

* **JavaScript-WASM Interop:** Test the communication layer between JavaScript and the WASM C core, ensuring correct argument passing and result retrieval for database operations and custom HLC functions.  
* **Local Event Sourcing Flow:** Simulate user actions (create, update, delete to-dos) and verify that events are correctly appended to events.db and materialized views in views.db are updated.  
* **Offline Functionality:** Disconnect from network and verify that local operations continue to function and events are queued.

**Integration Tests (Go Backend):**

* **WebSocket Connectivity:** Test establishing and maintaining WebSocket connections.  
* **Sync Protocol:**  
  * Test pull requests: client sends HLC, server returns correct events.  
  * Test push requests: client sends events, server persists them and updates its materialized view.  
  * Test server-side conflict detection and resolution logic for various scenarios (e.g., concurrent updates to the same aggregate).  
* **Event Broadcasting:** Verify that new events pushed by one client are correctly broadcast to other connected clients.

**End-to-End Tests (Client-Backend-Client):**

* **Multi-Client Synchronization:** Simulate two or more clients (web browsers) interacting with the same to-do list via the Go backend.  
  * Verify that changes made by one client are correctly synchronized and reflected on other clients.  
  * **Conflict Scenarios:** Create specific test cases for concurrent modifications leading to conflicts (e.g., two users edit the same to-do item offline, then sync). Verify that the system detects and resolves these conflicts according to the defined strategy (e.g., HLC-based last-write-wins).  
* **Offline-Online Transition:** Test the entire flow of working offline, reconnecting, and syncing, ensuring data consistency.  
* **Schema Evolution Rebuild:** Automate a test that simulates a schema change in the materialized view, triggers a full rebuild from the event store, and verifies the new schema and data integrity.

This structured testing approach will ensure the robustness, correctness, and performance of the local-first event-sourced system across all its components.

## **6\. Conclusions and Recommendations**

The comprehensive analysis of building a local-first event-sourced system with SQLite, a pure C core, Go, and real-time synchronization reveals a highly capable and resilient architectural pattern. This approach offers significant benefits in user experience, data integrity, and system adaptability.

The selection of **SQLite** as the local persistence layer is well-justified due to its embedded nature, reliability, and performance characteristics, especially when configured with WAL and efficient indexing strategies. The decision to implement the core database interactions and, crucially, the **Hybrid Logical Clock (HLC) functions in pure C** within SQLite is a powerful architectural choice. This ensures that causality-aware timestamps are generated atomically with event persistence, pushing complex distributed systems concerns closer to the data layer. This design reduces the burden on higher-level application code, making the overall system more robust and easier to reason about, particularly in a local-first context where the local database is the immediate source of truth.

The separation of the **event store and materialized views into two distinct SQLite databases** aligns with the Command Query Responsibility Segregation (CQRS) pattern. This separation optimizes read performance by allowing query-specific schemas while preserving the immutable, append-only nature of the event log. A key advantage of this design is the simplified **schema evolution for materialized views**, which can be rebuilt entirely from the event stream when changes are required, mitigating the complexities typically associated with database migrations.

For **synchronization**, WebSockets are the superior choice, providing the necessary bidirectional, low-latency, and persistent communication channel for real-time event stream replication. The **Go backend** effectively serves as both the webserver and the central synchronization hub, leveraging Go's concurrency features to handle multiple client connections and manage the central event store. The implementation of a **Git-like pull-before-push synchronization logic**, heavily reliant on HLCs for ordering and conflict detection, provides a robust mechanism for maintaining data consistency across distributed clients, even in the face of concurrent offline modifications.

**Recommendations:**

1. **Prioritize C Core Development for HLC and Event Store:** Invest significant effort in the pure C implementation of the SQLite event store and the custom HLC functions. This foundational layer will dictate the system's core performance and consistency guarantees. Rigorous unit testing of these C components is essential.  
2. **Strategic WebAssembly Integration:** Develop the WASM compilation pipeline for the C core early in the development cycle. Ensure robust JavaScript interoperability layers are in place, potentially utilizing Web Workers to maintain UI responsiveness in the web application and VSCode extension.  
3. **Refine Conflict Resolution Strategies:** While HLCs provide the mechanism for conflict detection, the specific resolution strategy (e.g., last-write-wins, user-mediated, or business-logic-driven merging) should be clearly defined and implemented in the Go backend and client-side application logic. Comprehensive end-to-end tests for various conflict scenarios are critical.  
4. **Modular Go Backend Design:** Design the Go sync server with clear separation of concerns for WebSocket handling, event persistence, and event broadcasting. This modularity will facilitate scalability and maintainability as the system grows.  
5. **Iterative Materialized View Development:** Begin with simple materialized views that address immediate query needs. As the application evolves and new query patterns emerge, iterate on the materialized view schemas and projection logic, leveraging the rebuildability feature to adapt efficiently.  
6. **Optional Sync Feature:** Ensure the client-side application is fully functional in an offline mode, with synchronization as an opt-in or background feature. This reinforces the local-first principle and enhances user experience.

By adhering to these architectural principles and recommendations, the proposed system can achieve a highly performant, resilient, and user-friendly local-first event-sourced application with robust distributed synchronization capabilities.

#### **Works cited**

1. Beginner's Guide to Event Sourcing \- Kurrent, accessed May 29, 2025, [https://www.kurrent.io/event-sourcing](https://www.kurrent.io/event-sourcing)  
2. Event sourcing database architecture—Design, challenges, and solutions \- Redpanda, accessed May 29, 2025, [https://www.redpanda.com/guides/event-stream-processing-event-sourcing-database](https://www.redpanda.com/guides/event-stream-processing-event-sourcing-database)  
3. The Ultimate Guide to Event-Driven Architecture Patterns \- Solace, accessed May 29, 2025, [https://solace.com/event-driven-architecture-patterns/](https://solace.com/event-driven-architecture-patterns/)  
4. Comprehensive Guide to Event Sourcing Database Architecture \- RisingWave, accessed May 29, 2025, [https://risingwave.com/blog/comprehensive-guide-to-event-sourcing-database-architecture/](https://risingwave.com/blog/comprehensive-guide-to-event-sourcing-database-architecture/)  
5. Event Sourcing in Go :: Victor's Blog — Ramblings of a Software ..., accessed May 29, 2025, [https://victoramartinez.com/posts/event-sourcing-in-go/](https://victoramartinez.com/posts/event-sourcing-in-go/)  
6. Event sourcing pattern \- AWS Prescriptive Guidance, accessed May 29, 2025, [https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/event-sourcing.html](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/event-sourcing.html)  
7. Event Sourcing pattern \- Azure Architecture Center | Microsoft Learn, accessed May 29, 2025, [https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing](https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing)  
8. What is Event Sourcing? : r/programming \- Reddit, accessed May 29, 2025, [https://www.reddit.com/r/programming/comments/1iq20v8/what\_is\_event\_sourcing/](https://www.reddit.com/r/programming/comments/1iq20v8/what_is_event_sourcing/)  
9. Local-first architecture with Expo, accessed May 29, 2025, [https://docs.expo.dev/guides/local-first/](https://docs.expo.dev/guides/local-first/)  
10. Zero Latency Local First Apps with RxDB – Sync, Encryption and ..., accessed May 29, 2025, [https://rxdb.info/articles/zero-latency-local-first.html](https://rxdb.info/articles/zero-latency-local-first.html)  
11. Local-First SQLite, Cloud-Connected with Turso Embedded Replicas, accessed May 29, 2025, [https://turso.tech/blog/local-first-cloud-connected-sqlite-with-turso-embedded-replicas](https://turso.tech/blog/local-first-cloud-connected-sqlite-with-turso-embedded-replicas)  
12. SQLITE with C for an embedded application \- Stack Overflow, accessed May 29, 2025, [https://stackoverflow.com/questions/28494829/sqlite-with-c-for-an-embedded-application](https://stackoverflow.com/questions/28494829/sqlite-with-c-for-an-embedded-application)  
13. User-Defined Functions in SQLite: Enhancing SQL with Custom C\# Procedures, accessed May 29, 2025, [https://www.jocheojeda.com/2024/01/15/user-defined-functions-in-sqlite-enhancing-sql-with-custom-c-procedures/](https://www.jocheojeda.com/2024/01/15/user-defined-functions-in-sqlite-enhancing-sql-with-custom-c-procedures/)  
14. Best practices using sqlite with my local storage : r/node \- Reddit, accessed May 29, 2025, [https://www.reddit.com/r/node/comments/1d2klm1/best\_practices\_using\_sqlite\_with\_my\_local\_storage/](https://www.reddit.com/r/node/comments/1d2klm1/best_practices_using_sqlite_with_my_local_storage/)  
15. Best practices for SQLite performance | App quality \- Android Developers, accessed May 29, 2025, [https://developer.android.com/topic/performance/sqlite-performance-best-practices](https://developer.android.com/topic/performance/sqlite-performance-best-practices)  
16. Essential SQLite Best Practices (for Efficient DB Design) \- Dragonfly, accessed May 29, 2025, [https://www.dragonflydb.io/databases/best-practices/sqlite](https://www.dragonflydb.io/databases/best-practices/sqlite)  
17. Building custom extensions into a WASM Distribution of SQLite, accessed May 29, 2025, [https://sqlite.org/forum/info/1e1c04f3ed1bc96b](https://sqlite.org/forum/info/1e1c04f3ed1bc96b)  
18. Learning about sqlite3 WASM \- DeepakNess, accessed May 29, 2025, [https://deepakness.com/blog/sqlite3-wasm/](https://deepakness.com/blog/sqlite3-wasm/)  
19. wa-sqlite \- NPM, accessed May 29, 2025, [https://npmjs.com/package/wa-sqlite](https://npmjs.com/package/wa-sqlite)  
20. vscode-sqlite \- Visual Studio Marketplace, accessed May 29, 2025, [https://marketplace.visualstudio.com/items?itemName=alexcvzz.vscode-sqlite](https://marketplace.visualstudio.com/items?itemName=alexcvzz.vscode-sqlite)  
21. WebSockets vs Server-Sent-Events vs Long-Polling vs WebRTC vs WebTransport | RxDB \- JavaScript Database, accessed May 29, 2025, [https://rxdb.info/articles/websockets-sse-polling-webrtc-webtransport.html](https://rxdb.info/articles/websockets-sse-polling-webrtc-webtransport.html)  
22. WebSockets Guide: How They Work, Benefits, and Use Cases \- Momento, accessed May 29, 2025, [https://www.gomomento.com/blog/websockets-guide-how-they-work-benefits-and-use-cases/](https://www.gomomento.com/blog/websockets-guide-how-they-work-benefits-and-use-cases/)  
23. Hybrid Logical Clocks | Kevin Sookocheff, accessed May 29, 2025, [https://sookocheff.com/post/time/hybrid-logical-clocks/](https://sookocheff.com/post/time/hybrid-logical-clocks/)  
24. CharlieTap/hlc: A Kotlin multiplatform implementation of a hybrid logical clock \- GitHub, accessed May 29, 2025, [https://github.com/CharlieTap/hlc](https://github.com/CharlieTap/hlc)  
25. Event Sourcing and CQRS with Marten \- CODE Magazine, accessed May 29, 2025, [https://www.codemag.com/Article/2209071/Event-Sourcing-and-CQRS-with-Marten](https://www.codemag.com/Article/2209071/Event-Sourcing-and-CQRS-with-Marten)  
26. SQLite C/C++ Interface \- Tutorialspoint, accessed May 29, 2025, [https://www.tutorialspoint.com/sqlite/sqlite\_c\_cpp.htm](https://www.tutorialspoint.com/sqlite/sqlite_c_cpp.htm)  
27. Writing a Custom SQLite Function (in C) \- Part 1, accessed May 29, 2025, [https://www.openmymind.net/Writing-A-Custom-Sqlite-Function-Part-1/](https://www.openmymind.net/Writing-A-Custom-Sqlite-Function-Part-1/)  
28. Generation of SQL Queries via C-language \- SQLTeam.com Forums, accessed May 29, 2025, [https://forums.sqlteam.com/t/generation-of-sql-queries-via-c-language/1533](https://forums.sqlteam.com/t/generation-of-sql-queries-via-c-language/1533)  
29. Writing a Custom SQLite Function (in C) \- Part 2, accessed May 29, 2025, [https://www.openmymind.net/Writing-A-Custom-Sqlite-Function-Part-2/](https://www.openmymind.net/Writing-A-Custom-Sqlite-Function-Part-2/)  
30. Application-Defined SQL Functions \- SQLite, accessed May 29, 2025, [https://www.sqlite.org/appfunc.html](https://www.sqlite.org/appfunc.html)  
31. Create Or Redefine SQL Functions \- SQLite, accessed May 29, 2025, [https://www.sqlite.org/c3ref/create\_function.html](https://www.sqlite.org/c3ref/create_function.html)  
32. hallgren/eventsourcing: Event Sourcing in Go \- GitHub, accessed May 29, 2025, [https://github.com/hallgren/eventsourcing](https://github.com/hallgren/eventsourcing)  
33. C-style API \- SQLite, accessed May 29, 2025, [https://sqlite.org/wasm/doc/trunk/api-c-style.md](https://sqlite.org/wasm/doc/trunk/api-c-style.md)  
34. CQRS Pattern \- Azure Architecture Center | Microsoft Learn, accessed May 29, 2025, [https://learn.microsoft.com/en-us/azure/architecture/patterns/cqrs](https://learn.microsoft.com/en-us/azure/architecture/patterns/cqrs)  
35. WebRTC vs WebSockets Tutorial — Web Real-Time Communication \- Requestum, accessed May 29, 2025, [https://requestum.com/blog/webrtc-vs-websockets](https://requestum.com/blog/webrtc-vs-websockets)  
36. Implementing Websockets in Go Real-Time Communication and Event Handling | MoldStud, accessed May 29, 2025, [https://moldstud.com/articles/p-implementing-websockets-in-go-real-time-communication-and-event-handling](https://moldstud.com/articles/p-implementing-websockets-in-go-real-time-communication-and-event-handling)  
37. git pull and resolve conflicts \- Stack Overflow, accessed May 29, 2025, [https://stackoverflow.com/questions/35025587/git-pull-and-resolve-conflicts](https://stackoverflow.com/questions/35025587/git-pull-and-resolve-conflicts)  
38. Cool frontend arts of local-first: storage, sync, conflicts \- Evil Martians, accessed May 29, 2025, [https://evilmartians.com/chronicles/cool-front-end-arts-of-local-first-storage-sync-and-conflicts](https://evilmartians.com/chronicles/cool-front-end-arts-of-local-first-storage-sync-and-conflicts)