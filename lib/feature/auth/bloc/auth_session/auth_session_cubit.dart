import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';
import 'package:hec_chat/feature/auth/bloc/auth_session/auth_session_state.dart';
 import 'package:hec_chat/feature/auth/repository/auth_repository.dart';

class AuthSessionCubit extends Cubit<AuthSessionState> {

  AuthSessionCubit() : super(AuthUnauthenticated()) {
    // Initialize auth status when cubit is created
    checkAuthStatus();
  }

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
