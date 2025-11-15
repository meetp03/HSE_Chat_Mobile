// models/contact_model.dart
import 'package:hsc_chat/feature/home/model/pagination_model.dart';

class ContactModel {
  final int id;
  final String name;
  final String? photoUrl;
  final bool isOnline;
  final String? lastSeen;
  final String email;

  ContactModel({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.isOnline,
    this.lastSeen,
    required this.email,
  });

  factory ContactModel.fromJson(Map<String, dynamic> json) {
    return ContactModel(
      id: json['id'],
      name: json['name'],
      photoUrl: json['photo_url'],
      // Coerce server boolean-like values (0/1 or true/false) into Dart bool
      isOnline: (json['is_online'] == 1) || (json['is_online'] == true),
      lastSeen: json['last_seen'],
      email: json['email'],
    );
  }
}

class ContactResponse {
  final bool success;
  final String message;
  final List<ContactModel> contacts;
  final Pagination pagination;

  ContactResponse({
    required this.success,
    required this.message,
    required this.contacts,
    required this.pagination,
  });

  factory ContactResponse.fromJson(Map<String, dynamic> json) {
    return ContactResponse(
      success: json['success'],
      message: json['message'],
      contacts: (json['data'] as List)
          .map((contact) => ContactModel.fromJson(contact))
          .toList(),
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}