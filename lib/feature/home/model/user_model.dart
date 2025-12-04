/*
// models/user_model.dart
import 'package:hec_chat/feature/home/model/pagination_model.dart';

class UserModel {
  final int id;
  final String name;
  final String email;
  final String photoUrl; // maps from photo_url
  final bool isOnline; // maps from is_online
  final String lastSeen; // maps from last_seen

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.photoUrl,
    this.isOnline = false,
    required this.lastSeen,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      name: json['name'] ?? '',
      email: json['email'],
      photoUrl: json['photo_url'],
      isOnline: json['is_online'] == null ? false : (json['is_online'] is bool ? json['is_online'] : (json['is_online'].toString() == '1' || json['is_online'].toString().toLowerCase() == 'true')),
      lastSeen: json['last_seen'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'photo_url': photoUrl,
        'is_online': isOnline,
        'last_seen': lastSeen,
      };
}

class UserResponse {
  final bool success;
  final int? status;
  final String? message;
  final int? count;
  final List<UserModel> contacts;
  final Pagination? pagination;
  final List<int> myContactIds;

  UserResponse({
    required this.success,
    this.status,
    this.message,
    this.count,
    required this.contacts,
    this.pagination,
    required this.myContactIds,
  });

  factory UserResponse.fromJson(Map<String, dynamic> json) {
    return UserResponse(
      success: json['success'] ?? false,
      status: json['status'] is int ? json['status'] : (json['status'] != null ? int.tryParse(json['status'].toString()) : null),
      message: json['message'],
      count: json['count'] is int ? json['count'] : (json['count'] != null ? int.tryParse(json['count'].toString()) : null),
      contacts: (json['data'] as List?)
              ?.map((e) => UserModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      pagination: json['pagination'] != null ? Pagination.fromJson(json['pagination']) : null,
      myContactIds: (json['myContactIds'] as List?)
              ?.map((e) => e is int ? e : int.parse(e.toString()))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'status': status,
        'message': message,
        'count': count,
        'data': contacts.map((c) => c.toJson()).toList(),
        'pagination': pagination != null ? pagination : null,
        'myContactIds': myContactIds,
      };
}*/
