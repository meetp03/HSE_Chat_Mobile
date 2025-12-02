import 'package:flutter/foundation.dart';

import '../../../cores/utils/utils.dart';

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


    // Helpers
    int parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    String parseString(dynamic v) {
      if (v == null) return '';
      return v.toString();
    }

    DateTime parseDate(dynamic v) {
      return Utils.parseUtcDate(v);
    }
    try {
      // Parse fromId properly (could be int or string)
      final fromId = parseInt(json['from_id']);

      // Build sender robustly
      final senderMap = (json['sender'] is Map<String, dynamic>) ? (json['sender'] as Map<String, dynamic>) : <String, dynamic>{};
      final sender = Sender.fromJson(senderMap);
      final bySenderId = sender.id;

      final isSent = (fromId != 0 && fromId == currentUserId) || (bySenderId != 0 && bySenderId == currentUserId);

      // Reply message may be a Map; if so, parse safely. If it's not a Map, ignore.
      Message? replyMsg;
      final replyRaw = json['reply_message'];
      if (replyRaw is Map<String, dynamic>) {
        replyMsg = Message.fromJson(replyRaw, currentUserId);
      }

      return Message(
        id: parseString(json['_id'] ?? json['id']),
        fromId: fromId,
        toId: parseString(json['to_id']),
        message: parseString(json['message']),
        status: parseInt(json['status']),
        messageType: parseInt(json['message_type']),
        fileName: json['file_name'] != null ? parseString(json['file_name']) : null,
        fileUrl: json['other_file_url'] != null ? parseString(json['other_file_url']) : (json['file_url'] != null ? parseString(json['file_url']) : null),
        replyTo: json['reply_to'] != null ? parseString(json['reply_to']) : null,
        createdAt: parseDate(json['created_at']),
        updatedAt: parseDate(json['updated_at']),
        sender: sender,
        replyMessage: replyMsg,
        isSentByMe: isSent,
      );
    } catch (e, st) {
      // Fallback: create a minimal Message to avoid crashing the UI
      debugPrint('⚠️ Message.fromJson error: $e\n$st');
      return Message(
        id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
        fromId: parseInt(json['from_id']),
        toId: json['to_id']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        status: parseInt(json['status']),
        messageType: parseInt(json['message_type']),
        fileName: json['file_name']?.toString(),
        fileUrl: json['other_file_url']?.toString() ?? json['file_url']?.toString(),
        replyTo: json['reply_to']?.toString(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        sender: Sender(id: 0, name: 'Unknown'),
        replyMessage: null,
        isSentByMe: false,
      );
    }
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

  // Compatibility aliases so code that expects the other Message shape
  // (used in Conversation model) continues to work. This avoids large
  // refactors across the codebase where both `message`/`updatedAt` and
  // `content`/`timestamp` are used interchangeably.
  String get content => message;
  DateTime get timestamp => updatedAt;

  String get formattedTime {
    return Utils.formatConversationTime(createdAt);
  }

  String get chatTime {
    return Utils.formatTimeOnly(createdAt);
  }

  String get relativeTime {
    return Utils.formatRelativeTime(createdAt);
  }

  String get debugTimeInfo {
    return Utils.getDebugTimeInfo(createdAt);
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

    // ✅ Check if message is deleted FIRST
    final normalizedMessage = message.toLowerCase().trim();
    if (normalizedMessage == 'this message was deleted' ||
        normalizedMessage.contains('message was deleted')) {
      return MessageKind.TEXT;
    }
    // Prefer server-provided `messageType` when available to avoid false-positive
    // detections based on filename/URL. This prevents trying to decode video/audio
    // bytes as an image which triggers FlutterJNI decode errors.
    // Mapping notes (server):
    // 9 = system, 0 = text, 1 = image/attachment, 4 = audio (example), 5 = video
    if (messageType == 9) return MessageKind.SYSTEM;
    if (messageType == 0) return MessageKind.TEXT;
    if (messageType == 1) return MessageKind.IMAGE;
    if (messageType == 5) return MessageKind.VIDEO;
    if (messageType == 4) return MessageKind.AUDIO;

    // Fallback to inspect fileUrl/fileName if messageType is unknown/ambiguous
    final candidate = (fileUrl ?? fileName ?? '').toLowerCase();
    if (candidate.isNotEmpty) {
      if (candidate.endsWith('.png') || candidate.endsWith('.jpg') || candidate.endsWith('.jpeg') || candidate.endsWith('.gif') || candidate.endsWith('.webp')) return MessageKind.IMAGE;
      if (candidate.endsWith('.mp4') || candidate.endsWith('.mov') || candidate.endsWith('.mkv') || candidate.endsWith('.webm') || candidate.contains('video')) return MessageKind.VIDEO;
      if (candidate.endsWith('.mp3') || candidate.endsWith('.wav') || candidate.endsWith('.m4a') || candidate.contains('audio')) return MessageKind.AUDIO;
      return MessageKind.FILE;
    }

    // Last-resort: inspect message HTML for embedded media tags
    final msgLower = message.toLowerCase();
    if (msgLower.contains('<video')) return MessageKind.VIDEO;
    if (msgLower.contains('<img') || msgLower.contains('data:image')) return MessageKind.IMAGE;

    return MessageKind.TEXT;
  }
}
