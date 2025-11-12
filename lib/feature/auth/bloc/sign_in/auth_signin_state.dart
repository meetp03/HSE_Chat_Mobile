import '../../model/auth_model.dart';

abstract class AuthSignInState {}

class AuthSignInInitial extends AuthSignInState {}

class AuthSignInLoading extends AuthSignInState {}

class AuthSignInSuccess extends AuthSignInState {
  final LoginResponse? response;

  AuthSignInSuccess(this.response);
}

class AuthSignInError extends AuthSignInState {
  final String errorMessage;

  AuthSignInError(this.errorMessage);
}
