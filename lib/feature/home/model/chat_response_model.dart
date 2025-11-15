// chat_response_model.dart

class ChatConversationResponse {
  final bool success;
  final String message;
  final ChatConversationData data;
  final ChatMeta meta;

  ChatConversationResponse({
    required this.success,
    required this.message,
    required this.data,
    required this.meta,
  });

  factory ChatConversationResponse.fromJson(Map<String, dynamic> json) {
    return ChatConversationResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      data: ChatConversationData.fromJson(json['data'] ?? {}),
      meta: ChatMeta.fromJson(json['meta'] ?? {}),
    );
  }
}

class ChatConversationData {
  final Map<String, dynamic> user;
  final dynamic group;
  // Conversations are returned as raw JSON maps from the backend.
  // Keep this as dynamic so callers can convert to Message models as needed.
  final List<dynamic> conversations;
  final List<dynamic> media;
  final bool chatRequest;
  final int unreadCount;

  ChatConversationData({
    required this.user,
    required this.group,
    required this.conversations,
    required this.media,
    required this.chatRequest,
    required this.unreadCount,
  });

  factory ChatConversationData.fromJson(Map<String, dynamic> json) {
    final convs = (json['conversations'] as List<dynamic>?) ?? [];
    return ChatConversationData(
      user: json['user'] ?? {},
      group: json['group'],
      conversations: convs,
      media: json['media'] ?? [],
      chatRequest: json['chat_request'] ?? false,
      unreadCount: json['unread_count'] ?? 0,
    );
  }
}

class ChatMeta {
  final int currentPage;
  final int perPage;
  final bool hasMore;
  final int? nextPage;
  final int totalLoaded;

  ChatMeta({
    required this.currentPage,
    required this.perPage,
    required this.hasMore,
    this.nextPage,
    required this.totalLoaded,
  });

  factory ChatMeta.fromJson(Map<String, dynamic> json) {
    return ChatMeta(
      currentPage: json['current_page'] ?? 1,
      perPage: json['per_page'] ?? 15,
      hasMore: json['has_more'] ?? false,
      nextPage: json['next_page'],
      totalLoaded: json['total_loaded'] ?? 0,
    );
  }
}

// Make sure your MessageResponse looks like this:

class MessageResponse {
  final bool success;
  final MessageData data;
  final String message;

  MessageResponse({
    required this.success,
    required this.data,
    required this.message,
  });

  factory MessageResponse.fromJson(Map<String, dynamic> json) {
    return MessageResponse(
      success: json['success'] ?? false,
      data: MessageData.fromJson(json['data'] ?? {}),
      message: json['message'] ?? '',
    );
  }
}

class MessageData {
  // ✅ Keep this as Map, not Message object
  final Map<String, dynamic> message;

  MessageData({
    required this.message,
  });

  factory MessageData.fromJson(Map<String, dynamic> json) {
    return MessageData(
      // ✅ Store as Map, convert to Message in cubit
      message: json['message'] as Map<String, dynamic>? ?? {},
    );
  }
}



class MessageReadResponse {
  final bool success;
  final String message;
  final int updated;
  final Map<String, dynamic> notificationsMarkedRead;

  MessageReadResponse({
    required this.success,
    required this.message,
    required this.updated,
    required this.notificationsMarkedRead,
  });

  factory MessageReadResponse.fromJson(Map<String, dynamic> json) {
    return MessageReadResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      updated: json['updated'] ?? 0,
      notificationsMarkedRead: json['notifications_marked_read'] ?? {},
    );
  }
}