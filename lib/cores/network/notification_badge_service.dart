// Lightweight wrapper that delegates notification badge responsibilities
// to the single `SocketService` instance. This prevents duplicate socket
// connections and keeps unseenCount in one place.

import 'package:flutter/widgets.dart';
import 'package:hsc_chat/cores/network/socket_service.dart';

class NotificationBadgeService with WidgetsBindingObserver {
  // Singleton wrapper
  static final NotificationBadgeService _instance = NotificationBadgeService._internal();
  factory NotificationBadgeService() => _instance;
  NotificationBadgeService._internal();

  // Expose the same ValueNotifier from SocketService so UI can listen to it
  ValueNotifier<int> get unseenCount => SocketService().unseenCount;

  /// Initialize badge config (delegates to SocketService)
  void init({required String apiBase, String? token, int? userId}) {
    SocketService().initNotificationBadge(apiBase: apiBase, token: token, userId: userId);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Set currently open conversation to avoid increments for active convo
  void setSelectedConversation({String? id, String? type}) {
    SocketService().setSelectedConversation(id: id, type: type);
  }

  /// Request an authoritative fetch of unseen notifications
  Future<void> fetchUnseenCount() => SocketService().refreshUnseenCount();

  /// Reset unseen count locally
  void resetCount() => SocketService().resetUnseenCount();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Let SocketService debounce and resync
      SocketService().refreshUnseenCount();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // don't dispose SocketService's unseenCount here - it's managed by SocketService
  }
}
