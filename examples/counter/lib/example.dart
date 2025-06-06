/// Counter Example App
///
/// This widget demonstrates a simple event-sourced counter with increment, decrement, reset, and event history features.
library;

import 'package:event_sourcing/event_sourcing_flutter.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import 'store.dart';
import 'events.dart';

/// The main counter example widget.
class CounterExample extends StatefulWidget {
  /// Create a counter example with the given [store].
  const CounterExample({super.key, required this.store});

  /// The store managing counter state and events.
  final CounterStore store;

  @override
  State<CounterExample> createState() => _CounterExampleState();
}

/// State for [CounterExample].
///
/// Handles event dispatching and UI updates for the counter demo.
class _CounterExampleState extends State<CounterExample> {
  /// Builds the main scaffold and counter UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Counter Example'),
        actions: [EventHistoryScreen.buildIconButton(context, widget.store)],
      ),
      body: Watch.builder(
        builder: (context) {
          final data = widget.store.counters();
          final count = data[CounterStore.counterKey] ?? 0;
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // Counter at top left
                Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    'Count: $count',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const Spacer(),
                // Actions at bottom left
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          IncrementEvent(
                            CounterStore.counterKey,
                          ).dispatch(context);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Increment'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(120, 40),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () {
                          DecrementEvent(
                            CounterStore.counterKey,
                          ).dispatch(context);
                        },
                        icon: const Icon(Icons.remove),
                        label: const Text('Decrement'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(120, 40),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          SetValueEvent(
                            CounterStore.counterKey,
                            0,
                          ).dispatch(context);
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(120, 40),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
