import 'package:flutter/widgets.dart';

import '../event.dart';
import '../event_store/base.dart';

class EventNotification extends Notification {
  const EventNotification(this.event);

  final Event event;
}

class EventNotificationHandler extends StatelessWidget {
  const EventNotificationHandler({
    super.key,
    required this.eventStore,
    required this.child,
  });
  final EventStore eventStore;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<EventNotification>(
      onNotification: (event) {
        eventStore.add(event.event);
        return true;
      },
      child: child,
    );
  }
}

extension EventNotificationExtension on Event {
  /// Dispatch this event as a notification.
  void dispatch(BuildContext context) {
    EventNotification(this).dispatch(context);
  }
}