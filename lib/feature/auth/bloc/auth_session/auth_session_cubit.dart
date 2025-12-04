import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/feature/auth/bloc/auth_session/auth_session_state.dart';
 import 'package:hsc_chat/feature/auth/repository/auth_repository.dart';

class AuthSessionCubit extends Cubit<AuthSessionState> {
  final IAuthRepository _repository;

  AuthSessionCubit(this._repository) : super(AuthUnauthenticated()) {
    // Initialize auth status when cubit is created
    checkAuthStatus();
  }

// In auth_session_cubit.dart

  Future<void> checkAuthStatus() async {
    final token = SharedPreferencesHelper.getCurrentUserToken();
    final loginResponse = SharedPreferencesHelper.getStoredLoginResponse();

    if (loginResponse != null) {
      emit(AuthAuthenticated(token: token, loginResponse: loginResponse));
    } else {
      emit(AuthUnauthenticated());
    }
  }
}
