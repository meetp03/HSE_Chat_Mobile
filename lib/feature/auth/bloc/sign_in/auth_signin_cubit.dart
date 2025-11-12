import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/constants/app_strings.dart';
import 'package:hsc_chat/cores/network/network_checker.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/feature/auth/bloc/sign_in/auth_signin_state.dart';
import 'package:hsc_chat/feature/auth/model/auth_model.dart';
import 'package:hsc_chat/feature/auth/repository/auth_repository.dart';
import 'package:hsc_chat/feature/home/bloc/conversation_cubit.dart';
  import 'package:hsc_chat/routes/navigation_service.dart';

class AuthSignInCubit extends Cubit<AuthSignInState> {
  final IAuthRepository _repository;

  AuthSignInCubit(this._repository) : super(AuthSignInInitial());

  Future<void> signIn(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      emit(AuthSignInError('Please fill in all fields'));
      return;
    }
    if (!email.contains('@')) {
      emit(AuthSignInError('Please enter a valid email address'));
      return;
    }
    if (password.length < 6) {
      emit(AuthSignInError('Password must be at least 6 characters'));
      return;
    }
    if (!await NetworkChecker.isConnected()) {
      emit(AuthSignInError(AppStr.noInternetConnection));
      return;
    }

    emit(AuthSignInLoading());

    final response = await _repository.login(
      LoginRequest(email: email, password: password),
    );

    if (response.success && response.data != null) {
      await _saveUserData(response.data, email, password);
      emit(AuthSignInSuccess(response.data ?? LoginResponse()));
    } else {
      String errorMessage = response.message ?? 'Login failed';
      if (response.statusCode == 401) {
        errorMessage = 'Invalid email or password';
      }
      emit(AuthSignInError(errorMessage));
    }
  }

  Future<void> _saveUserData(
    LoginResponse? response,
    String? email,
    String? password,
  ) async {
    SharedPreferencesHelper.storeLoginResponse(response!);
    // Initialize socket connection after successful login
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final conversationCubit = NavigationService.navigatorKey.currentContext
            ?.read<ConversationCubit>();
        if (conversationCubit != null) {
          conversationCubit.initializeSocketConnection(response?.token ?? '');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Failed to initialize socket: $e');
        }
      }
    });
  }

  void clearError() {
    if (state is AuthSignInError) {
      emit(AuthSignInInitial());
    }
  }
}
