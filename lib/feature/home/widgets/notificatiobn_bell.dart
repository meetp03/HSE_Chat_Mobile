import 'package:flutter/material.dart';
import 'package:hec_chat/cores/constants/api_urls.dart';
import 'package:hec_chat/cores/constants/app_colors.dart';
import 'package:hec_chat/cores/network/socket_service.dart';
import 'package:hec_chat/cores/network/notification_badge_service.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';

class NotificationBell extends StatefulWidget {
  final VoidCallback? onTap;
  const NotificationBell({super.key, this.onTap});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  @override
  void initState() {
    super.initState();
    // Use SocketService's notification badge integration
    final socketSvc = SocketService();
    socketSvc.initNotificationBadge(
      apiBase: ApiUrls.baseUrl,
      token: SharedPreferencesHelper.getCurrentUserToken(),
      userId: SharedPreferencesHelper.getCurrentUserId(),
    );

    // Initialize socket only if not already initialized
    final token = SharedPreferencesHelper.getCurrentUserToken();
    if (token.isNotEmpty) {
      try {
        if (socketSvc.isConnected == false) {
          socketSvc.initializeSocket(token);
        }
      } catch (_) {}
    }

    // Fetch initial count from API
    NotificationBadgeService().fetchUnseenCount();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SocketService().unseenCount,
      builder: (context, count, _) {
        //  Cap display at 99+
        final display = count <= 0
            ? null
            : (count > 99 ? '99+' : count.toString());

        return IconButton(
          onPressed: () {
            // Sync with server when notification bell is tapped
            NotificationBadgeService().fetchUnseenCount();

            if (widget.onTap != null) widget.onTap!();
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications),
              if (display != null)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppClr.notificationBadge,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      display,
                      style: const TextStyle(
                        color: AppClr.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
