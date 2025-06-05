# Event Sourcing Flutter Examples

This repository demonstrates event sourcing patterns in Flutter using a modular event store and view store architecture. It includes two main example apps:

## Examples

### 1. Counter Example

A minimal event-sourced counter app. Features:
- Increment, decrement, and reset actions
- Event history view (see all events that changed the counter)
- Demonstrates how to use the event store and view store for simple state management

### 2. POS (Point of Sale) Example

A more advanced example simulating a point-of-sale system. Features:
- Customer and product management
- Inventory tracking
- Order creation, checkout, refund, and restore
- Event history for all actions
- Uses event sourcing to ensure all state changes are event-driven and auditable

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

## Getting Started

- Each example is a standalone Flutter app in its own directory (`examples/counter/`, `examples/pos/`).
- Run `flutter pub get` in the desired example directory, then `flutter run` to launch.
