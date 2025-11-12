// message_model.dart (Key parts to check/update)

class Message {
  final String id;
  final int fromId;
  final String toId;
  final String message;
  final int status;
  final int messageType;
  final String? fileName;
  final String? fileUrl;
  final String? replyTo;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Sender sender;
  final Message? replyMessage;
  final bool isSentByMe;

  Message({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.message,
    required this.status,
    required this.messageType,
    this.fileName,
    this.fileUrl,
    this.replyTo,
    required this.createdAt,
    required this.updatedAt,
    required this.sender,
    this.replyMessage,
    required this.isSentByMe,
  });

  // ✅ CRITICAL: This determines message alignment
  factory Message.fromJson(Map<String, dynamic> json, int currentUserId) {
    // Parse fromId properly (could be int or string)
    final fromId = json['from_id'] is String
        ? int.tryParse(json['from_id']) ?? 0
        : (json['from_id'] as int? ?? 0);

    print('🔍 Parsing message - fromId: $fromId, currentUserId: $currentUserId');
    // Build sender first so we can also use sender.id as fallback
    final sender = Sender.fromJson(json['sender'] ?? {});
    final bySenderId = sender.id;
    final isSent = (fromId != 0 && fromId == currentUserId) || (bySenderId != 0 && bySenderId == currentUserId);
    print('🔍 isSentByMe computed -> fromId==currentUserId: ${fromId == currentUserId}, sender.id==currentUserId: ${bySenderId == currentUserId} => $isSent');

    return Message(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      fromId: fromId,
      toId: json['to_id']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      status: json['status'] as int? ?? 0,
      messageType: json['message_type'] as int? ?? 0,
      fileName: json['file_name']?.toString(),
      fileUrl: json['file_url']?.toString(),
      replyTo: json['reply_to']?.toString(),
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        json['updated_at'] ?? DateTime.now().toIso8601String(),
      ),
      sender: sender,
      replyMessage: json['reply_message'] != null
          ? Message.fromJson(json['reply_message'], currentUserId)
          : null,
      // ✅ This is the critical line for alignment
      isSentByMe: isSent,
    );
  }

  Message copyWith({
    String? id,
    int? fromId,
    String? toId,
    String? message,
    int? status,
    int? messageType,
    String? fileName,
    String? fileUrl,
    String? replyTo,
    DateTime? createdAt,
    DateTime? updatedAt,
    Sender? sender,
    Message? replyMessage,
    bool? isSentByMe,
  }) {
    return Message(
      id: id ?? this.id,
      fromId: fromId ?? this.fromId,
      toId: toId ?? this.toId,
      message: message ?? this.message,
      status: status ?? this.status,
      messageType: messageType ?? this.messageType,
      fileName: fileName ?? this.fileName,
      fileUrl: fileUrl ?? this.fileUrl,
      replyTo: replyTo ?? this.replyTo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sender: sender ?? this.sender,
      replyMessage: replyMessage ?? this.replyMessage,
      isSentByMe: isSentByMe ?? this.isSentByMe,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'from_id': fromId,
      'to_id': toId,
      'message': message,
      'status': status,
      'message_type': messageType,
      'file_name': fileName,
      'file_url': fileUrl,
      'reply_to': replyTo,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sender': sender.toJson(),
      'reply_message': replyMessage?.toJson(),
    };
  }
}

class Sender {
  final int id;
  final String name;
  final String? photoUrl;

  Sender({
    required this.id,
    required this.name,
    this.photoUrl,
  });

  factory Sender.fromJson(Map<String, dynamic> json) {
    // Sender id may be string or int
    final rawId = json['id'];
    final parsedId = rawId is String
        ? int.tryParse(rawId) ?? 0
        : (rawId as int? ?? 0);

    return Sender(
      id: parsedId,
      name: json['name']?.toString() ?? 'Unknown',
      photoUrl: json['photo_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'photo_url': photoUrl,
    };
  }
}

// Top-level enum to classify messages for UI rendering
enum MessageKind { SYSTEM, IMAGE, VIDEO, AUDIO, FILE, TEXT }

extension MessageKindHelper on Message {
  MessageKind kind() {
    // messageType mapping: assume 9 = system, 0 = text, others for files
    if (messageType == 9) return MessageKind.SYSTEM;

    // Prefer explicit fileUrl, then fileName
    final candidate = (fileUrl ?? fileName ?? '').toLowerCase();

    if (candidate.isNotEmpty) {
      if (candidate.endsWith('.png') || candidate.endsWith('.jpg') || candidate.endsWith('.jpeg') || candidate.endsWith('.gif')) {
        return MessageKind.IMAGE;
      }
      if (candidate.endsWith('.mp4') || candidate.endsWith('.mov') || candidate.endsWith('.mkv') || candidate.contains('video')) {
        return MessageKind.VIDEO;
      }
      if (candidate.endsWith('.mp3') || candidate.endsWith('.wav') || candidate.endsWith('.m4a') || candidate.contains('audio')) {
        return MessageKind.AUDIO;
      }
      // If we have a candidate but no known extension, treat as FILE
      if (candidate.isNotEmpty) return MessageKind.FILE;
    }

    // Fallback: if message contains HTML-like media tags, try to detect
    final msgLower = message.toLowerCase();
    if (msgLower.contains('<img') || msgLower.contains('<video') || msgLower.contains('data:image')) {
      if (msgLower.contains('<video')) return MessageKind.VIDEO;
      return MessageKind.IMAGE;
    }

    return MessageKind.TEXT;
  }
}
