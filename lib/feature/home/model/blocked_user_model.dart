import 'package:hec_chat/feature/home/model/pagination_model.dart';
class BlockedUserModel {
  final int id;
  final String name;
  final String? photoUrl;
  final bool isOnline;
  final String? lastSeen;
  final String email;

  BlockedUserModel({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.isOnline,
    this.lastSeen,
    required this.email,
  });

  factory BlockedUserModel.fromJson(Map<String, dynamic> json) {
    return BlockedUserModel(
      id: json['id'],
      name: json['name'],
      photoUrl: json['photo_url'],
      isOnline: json['is_online'] == 1,
      lastSeen: json['last_seen'],
      email: json['email'],
    );
  }
}

class BlockedUserResponse {
  final bool success;
  final String message;
  final List<BlockedUserModel> users;
  final Pagination pagination;

  BlockedUserResponse({
    required this.success,
    required this.message,
    required this.users,
    required this.pagination,
  });

  factory BlockedUserResponse.fromJson(Map<String, dynamic> json) {
    return BlockedUserResponse(
      success: json['success'],
      message: json['message'],
      users: (json['data']['users'] as List)
          .map((user) => BlockedUserModel.fromJson(user))
          .toList(),
      pagination: Pagination.fromJson(json['data']['meta']),
    );
  }
}