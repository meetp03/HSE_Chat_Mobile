// models/user_model.dart
import 'package:hsc_chat/feature/home/model/pagination_model.dart';

class UserModel {
  final int id;
  final String name;
  final String email;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      name: json['name'],
      email: json['email'],
    );
  }
}

class UserResponse {
  final bool success;
  final String message;
  final List<UserModel> users;
  final Pagination pagination;

  UserResponse({
    required this.success,
    required this.message,
    required this.users,
    required this.pagination,
  });

  factory UserResponse.fromJson(Map<String, dynamic> json) {
    return UserResponse(
      success: json['success'],
      message: json['message'],
      users: (json['data'] as List)
          .map((user) => UserModel.fromJson(user))
          .toList(),
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}