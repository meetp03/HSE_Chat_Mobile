import 'package:hsc_chat/cores/constants/api_urls.dart';

class LoginRequest {
  final String email;
  final String password;

  LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() {
    return {'email': email, 'password': password};
  }
}
class LoginResponse {
  final String? status;
  final String? message;
  final int? id; // Change from String to int
  final String? name;
  final String? email;
  final String? token;

  LoginResponse({
      this.status,
      this.message,
      this.id, // Now it's int
      this.name,
      this.email,
      this.token,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      status: json['status'] ?? '',
      message: json['message'] ?? '',
      id: _parseId(json['id']), // Use helper method to parse id
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      token: json['token'] ?? '',
    );
  }

  // Helper method to parse id from different types
  static int _parseId(dynamic id) {
    if (id == null) return 0;
    if (id is int) return id;
    if (id is String) return int.tryParse(id) ?? 0;
    return 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'message': message,
      'id': id, // Store as int
      'name': name,
      'email': email,
      'token': token,
    };
  }
}
