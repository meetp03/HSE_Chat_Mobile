
class GroupActionData {
  final int? id;
  final int? fromId;
  final String? toId;
  final String? message;
  final int? messageType;
  final DateTime? createdAt;

  GroupActionData({
    this.id,
    this.fromId,
    this.toId,
    this.message,
    this.messageType,
    this.createdAt,
  });

  factory GroupActionData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return GroupActionData();
    return GroupActionData(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id'] ?? ''}'),
      fromId: json['from_id'] is int ? json['from_id'] : int.tryParse('${json['from_id'] ?? ''}'),
      toId: json['to_id']?.toString(),
      message: json['message']?.toString(),
      messageType: json['message_type'] is int ? json['message_type'] : int.tryParse('${json['message_type'] ?? ''}'),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }
}

class GroupActionResponse {
  final bool success;
  final String? message;
  final GroupActionData? data;

  GroupActionResponse({required this.success, this.message, this.data});

  factory GroupActionResponse.fromJson(Map<String, dynamic> json) {
    return GroupActionResponse(
      success: json['success'] == true,
      message: json['message']?.toString(),
      data: GroupActionData.fromJson(json['data'] as Map<String, dynamic>?),
    );
  }
}

