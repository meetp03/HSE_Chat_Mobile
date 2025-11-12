import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/feature/auth/bloc/auth_session/auth_session_state.dart';
 import 'package:hsc_chat/feature/auth/repository/auth_repository.dart';
import 'package:hsc_chat/feature/home/bloc/conversation_cubit.dart';
  import 'package:hsc_chat/routes/navigation_service.dart';

class AuthSessionCubit extends Cubit<AuthSessionState> {
  final IAuthRepository _repository;

  AuthSessionCubit(this._repository) : super(AuthUnauthenticated()) {
    // Initialize auth status when cubit is created
    checkAuthStatus();
  }

  Future<void> checkAuthStatus() async {
    final token = SharedPreferencesHelper.getCurrentUserToken();
    final loginResponse = SharedPreferencesHelper.getStoredLoginResponse();

    if (loginResponse != null) {
      emit(AuthAuthenticated(token: token, loginResponse: loginResponse));
      // Reconnect socket when app starts with existing auth
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final conversationCubit = NavigationService
              .navigatorKey
              .currentContext
              ?.read<ConversationCubit>();
          if (conversationCubit != null) {
            conversationCubit.initializeSocketConnection(token);
          }
        } catch (e) {
          if (kDebugMode) {
            print('Failed to reconnect socket: $e');
          }
        }
      });
    } else {
      emit(AuthUnauthenticated());
    }
  }
}
