// notification_model.dart
import 'package:meta/meta.dart';

class AppNotificationData {
  final int id;
  final String type;
  final String title;
  final String body;
  final String? groupId;
  final int? removedUserId;
  final int? byUserId;
  final int? systemMessageId;
  final DateTime createdAt;

  AppNotificationData({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.groupId,
    this.removedUserId,
    this.byUserId,
    this.systemMessageId,
    required this.createdAt,
  });

  factory AppNotificationData.fromJson(Map<String, dynamic>? json) {
    if (json == null) throw ArgumentError('data is null');
    return AppNotificationData(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      groupId: json['group_id']?.toString(),
      removedUserId: json['removed_user_id'] is int
          ? json['removed_user_id']
          : int.tryParse('${json['removed_user_id'] ?? ''}'),
      byUserId: json['by_user_id'] is int
          ? json['by_user_id']
          : int.tryParse('${json['by_user_id'] ?? ''}'),
      systemMessageId: json['system_message_id'] is int
          ? json['system_message_id']
          : int.tryParse('${json['system_message_id'] ?? ''}'),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class AppNotification {
  final String id;
  final String type;
  final String notifiableType;
  final String notifiableId;
  final AppNotificationData data;
  final bool seen;
  final DateTime createdAt;
  final String? openChatId;

  AppNotification({
    required this.id,
    required this.type,
    required this.notifiableType,
    required this.notifiableId,
    required this.data,
    required this.seen,
    required this.createdAt,
    this.openChatId,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      notifiableType: json['notifiable_type']?.toString() ?? '',
      notifiableId: json['notifiable_id']?.toString() ?? '',
      data: AppNotificationData.fromJson(json['data'] as Map<String, dynamic>?),
      seen: json['seen'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      openChatId: json['open_chat_id']?.toString(),
    );
  }
}

class NotificationsResponse {
  final List<AppNotification> notifications;
  final int unseenCount;
  final int total;
  final int perPage;
  final int page;
  final int totalPages;

  NotificationsResponse({
    required this.notifications,
    required this.unseenCount,
    required this.total,
    required this.perPage,
    required this.page,
    required this.totalPages,
  });

  factory NotificationsResponse.fromJson(Map<String, dynamic> json) {
    final notifs = (json['notifications'] as List<dynamic>?) ?? [];
    final notifications = notifs.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
    final meta = json['meta'] as Map<String, dynamic>?;
    return NotificationsResponse(
      notifications: notifications,
      unseenCount: json['unseen_count'] is int ? json['unseen_count'] : int.tryParse('${json['unseen_count'] ?? 0}') ?? 0,
      total: meta != null && meta['total'] is int ? meta['total'] : int.tryParse('${meta?['total'] ?? 0}') ?? 0,
      perPage: meta != null && meta['per_page'] is int ? meta['per_page'] : int.tryParse('${meta?['per_page'] ?? 0}') ?? 0,
      page: meta != null && meta['page'] is int ? meta['page'] : int.tryParse('${meta?['page'] ?? 1}') ?? 1,
      totalPages: meta != null && meta['total_pages'] is int ? meta['total_pages'] : int.tryParse('${meta?['total_pages'] ?? 1}') ?? 1,
    );
  }
}

