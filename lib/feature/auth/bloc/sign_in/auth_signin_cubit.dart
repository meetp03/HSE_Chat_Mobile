import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/network/network_checker.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';
import 'package:hec_chat/feature/auth/bloc/sign_in/auth_signin_state.dart';
import 'package:hec_chat/feature/auth/model/auth_model.dart';
import 'package:hec_chat/feature/auth/repository/auth_repository.dart';

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
      emit(AuthSignInError('No internet connection'));
      return;
    }

    emit(AuthSignInLoading());

    final response = await _repository.login(
      LoginRequest(email: email, password: password),
    );

    if (response.success && response.data != null) {
      await _saveUserData(response.data);
      emit(AuthSignInSuccess(response.data ?? LoginResponse()));
    } else {
      String errorMessage = response.message ?? 'Login failed';
      if (response.statusCode == 401) {
        errorMessage = 'Invalid email or password';
      }
      emit(AuthSignInError(errorMessage));
    }
  }

  Future<void> _saveUserData(LoginResponse? response) async {
    SharedPreferencesHelper.storeLoginResponse(response!);
  }

  void clearError() {
    if (state is AuthSignInError) {
      emit(AuthSignInInitial());
    }
  }
}
