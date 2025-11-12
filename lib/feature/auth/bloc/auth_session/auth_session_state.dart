import '../../model/auth_model.dart';

abstract class AuthSessionState {}

class AuthAuthenticated extends AuthSessionState {
  final LoginResponse loginResponse;
  final String token;

  AuthAuthenticated({required this.loginResponse, required this.token});
}

class AuthUnauthenticated extends AuthSessionState {}

class AuthLogoutLoading extends AuthSessionState {}

class AuthLogoutSuccess extends AuthSessionState {}

class AuthLogoutError extends AuthSessionState {
  final String message;

  AuthLogoutError(this.message);
}
