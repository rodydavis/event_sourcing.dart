import 'package:flutter/material.dart';
import 'package:event_sourcing/event_sourcing.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'store.dart';

class EventHistoryScreen extends StatelessWidget {
  const EventHistoryScreen({super.key, required this.store});

  final CounterStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Event History')),
      body: StreamBuilder<Event>(
        stream: store.eventStore.onEvent(),
        builder: (context, _) {
          return FutureBuilder<List<Event>>(
            future: (() async => store.eventStore.getAll())(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final events = snapshot.data!;
              if (events.isEmpty) {
                return const Center(child: Text('No events yet.'));
              }
              // Displaying latest events first
              final reversed = events.reversed.toList();
              return ListView.separated(
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemCount: reversed.length,
                itemBuilder: (context, index) {
                  final event = reversed[index];
                  final date = event.id.dateTime;
                  final dateStr = timeago.format(date);
                  final subtitle = '${event.type} at $dateStr';
                  return ListTile(
                    title: Text(subtitle),
                    subtitle: Text(event.data.toString()),
                    trailing: TextButton(
                      // Disable restore for the most recent event if it's the current state
                      onPressed:
                          index == 0
                              ? null
                              : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                await store.restoreToEvent(event);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Restored to event: ${event.id}',
                                    ),
                                  ),
                                );
                              },
                      child: const Text('Restore'),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
