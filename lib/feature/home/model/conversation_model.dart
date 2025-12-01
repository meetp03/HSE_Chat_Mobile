import 'package:intl/intl.dart';

class ConversationResponse {
  final bool success;
  final ConversationData data;
  final Meta meta;
  final String message;
  ConversationResponse({
    required this.success,
    required this.data,
    required this.meta,
    required this.message,
  });
  factory ConversationResponse.fromJson(Map<String, dynamic> json) {
    return ConversationResponse(
      success: json['success'] ?? false,
      data: ConversationData.fromJson(json['data']),
      meta: Meta.fromJson(json['meta']),
      message: json['message'] ?? '',
    );
  }
}

class ConversationData {
  final List<Conversation> conversations;
  ConversationData({required this.conversations});
  factory ConversationData.fromJson(Map<String, dynamic> json) {
    final list = json['conversations'] as List<dynamic>? ?? [];
    return ConversationData(
      conversations: list.map((e) => Conversation.fromJson(e)).toList(),
    );
  }
}

class Meta {
  final int currentPage;
  final int perPage;
  final int total;
  final int lastPage;
  final bool hasNextPage;
  Meta({
    required this.currentPage,
    required this.perPage,
    required this.total,
    required this.lastPage,
    required this.hasNextPage,
  });
  factory Meta.fromJson(Map<String, dynamic> json) {
    // Support different possible keys returned by various backends
    final int currentPage = json['current_page'] ?? json['currentPage'] ?? 0;
    final int perPage = json['per_page'] ?? json['perPage'] ?? 0;
    final int total = json['total'] ?? json['total_records'] ?? 0;
    final int lastPage = json['last_page'] ?? json['lastPage'] ?? 0;

    // hasNextPage may be present in several shapes
    bool hasNext = false;
    if (json.containsKey('has_next_page')) {
      hasNext = json['has_next_page'] == true;
    } else if (json.containsKey('hasNextPage')) {
      hasNext = json['hasNextPage'] == true;
    } else if (json.containsKey('has_next')) {
      hasNext = json['has_next'] == true;
    } else if (json.containsKey('hasNext')) {
      hasNext = json['hasNext'] == true;
    }

    return Meta(
      currentPage: currentPage,
      perPage: perPage,
      total: total,
      lastPage: lastPage,
      hasNextPage: hasNext,
    );
  }
}

class Conversation {
  final String id;
  final String? groupId;
  final String title; // group.name  OR  user.name
  final String email;
  final String lastMessage;
  final DateTime timestamp;
  final int unreadCount;
  final String? avatarUrl;
  final bool isGroup;
  final bool isUnread;
  final bool isTyping;
  final String? typingUser;
  final List<Message>? messages;
  final List<Participant>? participants;
  final DateTime? lastReadAt;

  //   Chat Request Fields
  final String? chatRequestStatus;  // "pending" | "accepted" | "declined" | null
  final String? chatRequestFrom;    // User ID of requester
  final String? chatRequestTo;      // User ID of recipient
  final String? chatRequestId;      // Server ID for the request

  Conversation({
    required this.id,
    required this.groupId,
    required this.title,
    required this.email,
    required this.lastMessage,
    required this.timestamp,
    required this.unreadCount,
    this.avatarUrl,
    required this.isGroup,
    required this.isUnread,
    this.isTyping = false,
    this.typingUser,
    this.messages,
    this.participants,
    this.lastReadAt,
    this.chatRequestStatus,
    this.chatRequestFrom,
    this.chatRequestTo,
    this.chatRequestId,
  });
  factory Conversation.fromJson(Map<String, dynamic> json) {
    final bool isGroup = json['group_id'] != "0" && json['group_id'] != null;
    final group = json['group'] as Map<String, dynamic>?;
    final user = json['user'] as Map<String, dynamic>?;

    // ---- ID FIX: Use other user ID for direct, group_id for group ----
    final String convId = isGroup
        ? (json['group_id']?.toString() ?? '')
        : (user?['id']?.toString() ??
        json['to_id']?.toString() ??
        json['from_id']?.toString() ??
        '');

    // ---- Title -------------------------------------------------
    final String title = isGroup
        ? (group?['name'] ?? 'Unknown Group')
        : (user?['name'] ?? 'Unknown User');
    // ---- Title -------------------------------------------------
    // (email extracted below using robust extractor)

    final String? avatar = isGroup
        ? (group?['photo_url'] as String?)
        : (user?['photo_url'] as String?);
    // ---- Timestamp ---------------------------------------------
    final DateTime timestamp = DateTime.parse(
      json['created_at'] ?? DateTime.now().toIso8601String(),
    );

    // ---- Unread ------------------------------------------------
    final int unread =
        int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0;

    // ---- Messages ----------------------------------------------
    final List<Message> messages = (json['messages'] as List<dynamic>? ?? [])
        .map((messageJson) => Message.fromJson(messageJson))
        .toList();

    // ---- Participants ------------------------------------------
    // Some backend responses include participants under `participants`,
    // others embed them inside `group['users']`. Prefer `participants` if
    // present; otherwise fall back to `group['users']`.
    List<Participant> participants = [];
    final rawParticipants = json['participants'] as List<dynamic>?;
    if (rawParticipants != null && rawParticipants.isNotEmpty) {
      participants = rawParticipants.map((p) => Participant.fromJson(p as Map<String, dynamic>)).toList();
    } else if (group != null) {
      final groupUsers = group['users'] as List<dynamic>?;
      if (groupUsers != null && groupUsers.isNotEmpty) {
        participants = groupUsers.map((u) {
          // The 'users' object shape is compatible with Participant.fromJson
          return Participant.fromJson(u as Map<String, dynamic>);
        }).toList();
      }
    }

    // ---- sanitize last message: strip HTML tags and decode common entities
    String rawMsg = json['message']?.toString() ?? '';
    String cleanedMsg = rawMsg.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    cleanedMsg = _decodeHtmlEntities(cleanedMsg);

    // ---- Email extraction (robust) ----------------------------
    String extractEmail() {
      // 1) top-level email
      if (json['email'] != null && json['email'].toString().trim().isNotEmpty) {
        return json['email'].toString().trim();
      }

      // 2) user object
      if (user != null) {
        final uemail = (user['email'] ?? user['user_email'] ?? user['email_address']);
        if (uemail != null && uemail.toString().trim().isNotEmpty) return uemail.toString().trim();
      }

      // 3) group object (sometimes group owner or first member email is provided)
      if (group != null) {
        if (group['email'] != null && group['email'].toString().trim().isNotEmpty) return group['email'].toString().trim();
        // try members array first user email
        final members = group['users'] as List<dynamic>?;
        if (members != null && members.isNotEmpty) {
          final first = members.first as Map<String, dynamic>?;
          final memEmail = first != null ? (first['email'] ?? first['user_email']) : null;
          if (memEmail != null && memEmail.toString().trim().isNotEmpty) return memEmail.toString().trim();
        }
      }

      // 4) fallback fields sometimes used by backend
      if (json['user_email'] != null && json['user_email'].toString().trim().isNotEmpty) return json['user_email'].toString().trim();

      return 'Unknown';
    }

    final String email = extractEmail();

    return Conversation(
      id: convId,
      groupId: json['group_id']?.toString(),
      title: title,
      email: email,
      lastMessage: cleanedMsg,
      timestamp: timestamp,
      unreadCount: unread,
      avatarUrl: avatar,
      isGroup: isGroup,
      isUnread: unread > 0,
      isTyping: false,
      typingUser: null,
      messages: messages,
      participants: participants,
      lastReadAt: null,
      chatRequestStatus: json['chat_request_status']?.toString(),
      chatRequestFrom: json['chat_request_from']?.toString(),
      chatRequestTo: json['chat_request_to']?.toString(),
      chatRequestId: json['chat_request_id']?.toString(),
    );
  }

  // Minimal HTML entity decoder for common entities we see in messages
  static String _decodeHtmlEntities(String input) {
    return input
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'&[#0-9a-zA-Z]+;'), '');
  }

  // ---- Copy with method for updates ----
  Conversation copyWith({
    String? id,
    String? groupId,
    String? title,
    String? email,
    String? lastMessage,
    DateTime? timestamp,
    int? unreadCount,
    String? avatarUrl,
    bool? isGroup,
    bool? isUnread,
    bool? isTyping,
    String? typingUser,
    List<Message>? messages,
    List<Participant>? participants,
    DateTime? lastReadAt,
    String? chatRequestStatus,
    String? chatRequestFrom,
    String? chatRequestTo,
    String? chatRequestId,

  }) {
    return Conversation(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      title: title ?? this.title,
      email: email ?? this.email,
      lastMessage: lastMessage ?? this.lastMessage,
      timestamp: timestamp ?? this.timestamp,
      unreadCount: unreadCount ?? this.unreadCount,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isGroup: isGroup ?? this.isGroup,
      isUnread: isUnread ?? this.isUnread,
      isTyping: isTyping ?? this.isTyping,
      typingUser: typingUser ?? this.typingUser,
      messages: messages ?? this.messages,
      participants: participants ?? this.participants,
      lastReadAt: lastReadAt ?? this.lastReadAt,

      chatRequestStatus: chatRequestStatus ?? this.chatRequestStatus,
      chatRequestFrom: chatRequestFrom ?? this.chatRequestFrom,
      chatRequestTo: chatRequestTo ?? this.chatRequestTo,
      chatRequestId: chatRequestId ?? this.chatRequestId,
    );
  }

  // ---- Update with new message ----
  Conversation updateWithNewMessage(Message newMessage) {
    return copyWith(
      lastMessage: newMessage.content,
      timestamp: newMessage.timestamp,
      unreadCount: unreadCount + 1,
      isUnread: true,
      messages: messages != null ? [...messages!, newMessage] : [newMessage],
    );
  }

  // ---- Mark as read ----
  Conversation markAsRead() {
    return copyWith(
      unreadCount: 0,
      isUnread: false,
      lastReadAt: DateTime.now(),
    );
  }

  // ---- Update typing status ----
  Conversation updateTypingStatus(bool typing, {String? user}) {
    return copyWith(isTyping: typing, typingUser: user);
  }

  // ---- Human readable time ----
  String get formattedTime {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    if (timestamp.isAfter(today)) {
      return DateFormat('HH:mm').format(timestamp);
    } else if (timestamp.isAfter(yesterday)) {
      return 'Yesterday';
    } else {
      return DateFormat('MM/dd/yyyy').format(timestamp);
    }
  }

  // ---- Get last message preview ----
  String get lastMessagePreview {
    if (lastMessage.length > 50) {
      return '${lastMessage.substring(0, 50)}...';
    }
    return lastMessage;
  }

  // ---- Check if user is participant ----
  bool isParticipant(String userId) {
    return participants?.any((participant) => participant.id == userId) ??
        false;
  }

  // ---- Get other participants (for 1-on-1 chats) ----
  List<Participant> getOtherParticipants(String currentUserId) {
    return participants
            ?.where((participant) => participant.id != currentUserId)
            .toList() ??
        [];
  }
}

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final MessageType type;
  final MessageStatus status;
  final DateTime timestamp;
  final DateTime? readAt;
  final DateTime? deliveredAt;
  final Map<String, dynamic>? metadata;
  final List<MessageReaction>? reactions;
  final Message? replyTo;
  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.type = MessageType.text,
    this.status = MessageStatus.sent,
    required this.timestamp,
    this.readAt,
    this.deliveredAt,
    this.metadata,
    this.reactions,
    this.replyTo,
  });

  // Compatibility aliases: some parts of the codebase expect `message`/`updatedAt`
  // (from the other Message model). Provide read-only aliases to avoid refactors.
  String get message => content;
  DateTime get updatedAt => timestamp;

  factory Message.fromJson(Map<String, dynamic> json) {
    final reply = json['reply_to'] as Map<String, dynamic>?;

    return Message(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString() ?? '',
      senderId: json['from_id']?.toString() ?? '',
      content: json['message']?.toString() ?? '',
      timestamp: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      type: MessageType.values[json['message_type'] ?? 0],
      status: MessageStatus.values[json['status'] ?? 0],
       replyTo: reply != null ? Message.fromJson(reply) : null,
      reactions: (json['reactions'] as List<dynamic>? ?? [])
          .map((r) => MessageReaction.fromJson(r))
          .toList(),
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'type': type.name,
      'status': status.name,
      'timestamp': timestamp.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'metadata': metadata,
      'reactions': reactions?.map((reaction) => reaction.toJson()).toList(),
      'reply_to': replyTo?.toJson(),
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    MessageType? type,
    MessageStatus? status,
    DateTime? timestamp,
    DateTime? readAt,
    DateTime? deliveredAt,
    Map<String, dynamic>? metadata,
    List<MessageReaction>? reactions,
    Message? replyTo,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      type: type ?? this.type,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      readAt: readAt ?? this.readAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      metadata: metadata ?? this.metadata,
      reactions: reactions ?? this.reactions,
      replyTo: replyTo ?? this.replyTo,
    );
  }

  Message markAsDelivered() {
    return copyWith(
      status: MessageStatus.delivered,
      deliveredAt: DateTime.now(),
    );
  }

  Message markAsRead() {
    return copyWith(status: MessageStatus.read, readAt: DateTime.now());
  }

  bool get isSent => status == MessageStatus.sent;
  bool get isDelivered => status == MessageStatus.delivered;
  bool get isRead => status == MessageStatus.read;
  String get formattedTime {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    if (difference.inMinutes < 1) return 'Now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return DateFormat('HH:mm').format(timestamp);
    if (difference.inDays < 7) return '${difference.inDays}d';
    return DateFormat('MM/dd/yy').format(timestamp);
  }
}

class Participant {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? email;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final String role; // 'admin', 'member', etc.
  Participant({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.email,
    this.isOnline = false,
    this.lastSeenAt,
    this.role = 'member',
  });
  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Unknown User',
      avatarUrl: json['photo_url'] ?? json['avatar_url'],
      email: json['email'] ?? json['user_email'] ?? json['email_address'],
      // Server sometimes returns 0/1 for booleans. Coerce to a bool safely.
      isOnline: (json['is_online'] == 1) || (json['is_online'] == true),
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'])
          : null,
      role: json['role'] ?? 'member',
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'photo_url': avatarUrl,
      'email': email,
      'is_online': isOnline,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'role': role,
    };
  }

  String get lastSeenFormatted {
    if (isOnline) return 'Online';
    if (lastSeenAt == null) return 'Offline';
    final now = DateTime.now();
    final difference = now.difference(lastSeenAt!);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return DateFormat('MM/dd/yy').format(lastSeenAt!);
  }
}

class MessageReaction {
  final String emoji;
  final String userId;
  final DateTime timestamp;
  MessageReaction({
    required this.emoji,
    required this.userId,
    required this.timestamp,
  });
  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      emoji: json['emoji'] ?? '👍',
      userId: json['user_id']?.toString() ?? '',
      timestamp: DateTime.parse(
        json['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'emoji': emoji,
      'user_id': userId,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

enum MessageType { text, image, video, audio, file, location, system }

enum MessageStatus { sending, sent, delivered, read, failed }

// Socket Event Models
class SocketMessageEvent {
  final String event;
  final dynamic data;
  final String conversationId;
  SocketMessageEvent({
    required this.event,
    required this.data,
    required this.conversationId,
  });
  factory SocketMessageEvent.fromJson(Map<String, dynamic> json) {
    return SocketMessageEvent(
      event: json['event'] ?? '',
      data: json['data'],
      conversationId: json['conversation_id'] ?? '',
    );
  }
}

class TypingEvent {
  final String conversationId;
  final String userId;
  final bool isTyping;
  final String? userName;
  TypingEvent({
    required this.conversationId,
    required this.userId,
    required this.isTyping,
    this.userName,
  });
  factory TypingEvent.fromJson(Map<String, dynamic> json) {
    return TypingEvent(
      conversationId: json['conversation_id'] ?? '',
      userId: json['user_id'] ?? '',
      isTyping: json['is_typing'] ?? false,
      userName: json['user_name'],
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'conversation_id': conversationId,
      'user_id': userId,
      'is_typing': isTyping,
      'user_name': userName,
    };
  }
}

class MessageStatusEvent {
  final String messageId;
  final String conversationId;
  final MessageStatus status;
  final DateTime timestamp;
  MessageStatusEvent({
    required this.messageId,
    required this.conversationId,
    required this.status,
    required this.timestamp,
  });
  factory MessageStatusEvent.fromJson(Map<String, dynamic> json) {
    return MessageStatusEvent(
      messageId: json['message_id'] ?? '',
      conversationId: json['conversation_id'] ?? '',
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.sent,
      ),
      timestamp: DateTime.parse(
        json['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}
