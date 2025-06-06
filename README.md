# Event Sourcing Flutter Examples

This repository demonstrates event sourcing patterns in Flutter using a modular event store and view store architecture. It includes two main example apps:

## Examples

### 1. Counter Example

[example](examples/counter/)

A minimal event-sourced counter app. Features:
- Increment, decrement, and reset actions
- Event history view (see all events that changed the counter)
- Demonstrates how to use the event store and view store for simple state management

### 2. POS (Point of Sale) Example

[example](examples/pos/)

A more advanced example simulating a point-of-sale system. Features:
- Customer and product management
- Inventory tracking
- Order creation, checkout, refund, and restore
- Event history for all actions
- Uses event sourcing to ensure all state changes are event-driven and auditable

### 3. NoSQL Example

[example](examples/nosql/)

A document-oriented event-sourced store. Features:
- Collection and document management (create, update, delete)
- Patch and set operations for document data
- Demonstrates event-driven NoSQL-like storage and querying

### 4. Key-Value (KV) Example

[example](examples/kv/)

A simple key-value event-sourced store. Features:
- Set and delete key-value pairs
- Supports any JSON-serializable value
- Demonstrates minimal event-driven state for key-value use cases

## Architecture

### Event Store

The `EventStore` is responsible for persisting and replaying all events. It provides:
- Methods to add, retrieve, and clear events
- Event processing and streaming
- Support for restoring state to a specific event

### View Store

The `ViewStore` is an abstract class that reacts to events and manages the application state. It provides:
- Initialization and disposal hooks
- An `onEvent` method to handle each event and update state
- A `restoreToEvent` method to reset and replay events up to a given point

This separation allows for robust, testable, and auditable state management in Flutter apps.

## Architecture Diagram

```mermaid
graph TD
  subgraph App
    UI["Flutter UI"]
    UI --> ViewStore
  end

  subgraph Core
    ViewStore["ViewStore\n(State Management)"]
    EventStore["EventStore\n(Persistence & Replay)"]
    ViewStore -- onEvent/restoreToEvent --> EventStore
    EventStore -- emits events --> ViewStore
  end

  subgraph Storage
    File["File (JSON/SQLite/Memory)"]
    EventStore -- persists events --> File
  end

  UI --> "User Actions" --> ViewStore
  EventStore --> "Streams/History" --> UI
```

This diagram shows how the Flutter UI interacts with the `ViewStore` for state management, which in turn processes events and interacts with the `EventStore` for persistence and replay. The `EventStore` can use different storage backends (file, SQLite, memory) and streams events back to the UI for history or debugging.
