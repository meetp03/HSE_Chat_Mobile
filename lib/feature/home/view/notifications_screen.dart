import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/feature/home/bloc/notification_cubit.dart';
import 'package:hec_chat/feature/home/repository/notification_repository.dart';
import 'package:hec_chat/cores/constants/app_colors.dart';
import 'package:hec_chat/cores/constants/app_strings.dart';
import 'package:intl/intl.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';
import '../../../cores/network/notification_badge_service.dart';
import '../../../cores/network/socket_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();

    // Fetch authoritative count from server when opening notifications
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationBadgeService().fetchUnseenCount().then((_) {
        // After fetching, mark all as read
        _markAllNotificationsRead();
      });
    });
  }

  Future<void> _markAllNotificationsRead() async {
    try {
      final userId = SharedPreferencesHelper.getCurrentUserId();
      final repository = NotificationRepository();
      await repository.markAllNotificationsRead(userId);

      // Reset badge count after marking all read
      SocketService().resetUnseenCount();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to mark notifications as read: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          NotificationCubit(NotificationRepository())..loadNotifications(),
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppClr.primaryColor,
          title: const Text(
            AppStrings.notifications,
            style: TextStyle(fontWeight: FontWeight.bold, color: AppClr.white),
          ),
        ),
        body: BlocBuilder<NotificationCubit, NotificationState>(
          builder: (context, state) {
            if (state is NotificationLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is NotificationError) {
              return Center(
                child: Text('${AppStrings.error}: ${state.message}'),
              );
            } else if (state is NotificationLoaded) {
              final list = state.response.notifications;

              if (list.isEmpty) {
                return const Center(
                  child: Text(
                    AppStrings.noNotifications,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, idx) {
                  final n = list[idx];
                  final dt = DateFormat.yMMMd().add_jm().format(
                    n.createdAt.toLocal(),
                  );

                  return GestureDetector(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppClr.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppClr.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Notification Icon Circle
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppClr.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Icon(
                              Icons.notifications,
                              size: 26,
                              color: AppClr.primaryColor,
                            ),
                          ),

                          const SizedBox(width: 14),

                          // Notification Text & Time
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  n.data.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  n.data.body,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Time badge
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      dt,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
