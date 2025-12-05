import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/constants/app_colors.dart';
import 'package:hec_chat/cores/constants/app_strings.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';
import 'package:hec_chat/feature/auth/bloc/sign_in/auth_signin_cubit.dart';
import 'package:hec_chat/feature/auth/bloc/sign_in/auth_signin_state.dart';
import 'package:hec_chat/feature/home/bloc/conversation_cubit.dart';
import '../../../cores/constants/image_paths.dart';
import '../../home/view/home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void onLoginSuccess() {
    final token = SharedPreferencesHelper.getCurrentUserToken();

    final conversationCubit = context.read<ConversationCubit>();
    conversationCubit.initializeSocketConnection(token);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppClr.scaffoldBackground,
      body: SafeArea(
        child: BlocListener<AuthSignInCubit, AuthSignInState>(
          listener: (context, state) {
            if (state is AuthSignInSuccess) {
              onLoginSuccess();
            } else if (state is AuthSignInError) {
              _showErrorDialog(context, state.errorMessage);
            }
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 60),
                  _buildHeader(),
                  const SizedBox(height: 48),
                  _buildEmailField(),
                  const SizedBox(height: 16),
                  _buildPasswordField(),
                  const SizedBox(height: 32),
                  _buildLoginButton(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Center(
      child: Column(
        children: [
          Image.asset(AppImg.appLogo),
          const SizedBox(height: 24),
          Text(
            AppStrings.welcomeToHecChat,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppClr.primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.signInToContinue,
            style: TextStyle(
              fontSize: 16,
              color: AppClr.gray600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      decoration: InputDecoration(
        labelText: AppStrings.email,
        hintText: AppStrings.enterEmail,
        prefixIcon: const Icon(Icons.email, color: AppClr.gray500),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppClr.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppClr.borderColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppClr.focusedBorderColor, width: 2.0),
        ),
        labelStyle: const TextStyle(color: AppClr.gray600),
        floatingLabelStyle: const TextStyle(color: AppClr.primaryColor),
      ),
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return AppStrings.pleaseEnterYourEmail;
        }
        if (!value.contains('@')) {
          return AppStrings.pleaseEnterValidEmail;
        }
        return null;
      },
      onChanged: (_) => _clearError(),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      decoration: InputDecoration(
        labelText: AppStrings.password,
        hintText: AppStrings.enterPassword,
        prefixIcon: const Icon(Icons.lock, color: AppClr.gray500),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility : Icons.visibility_off,
            color: AppClr.gray500,
          ),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppClr.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppClr.borderColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppClr.focusedBorderColor, width: 2.0),
        ),
        labelStyle: const TextStyle(color: AppClr.gray600),
        floatingLabelStyle: const TextStyle(color: AppClr.primaryColor),
      ),
      obscureText: _obscurePassword,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return AppStrings.pleaseEnterYourPassword;
        }
        if (value.length < 6) {
          return AppStrings.passwordMinLength;
        }
        return null;
      },
      onChanged: (_) => _clearError(),
    );
  }


  Widget _buildLoginButton(BuildContext context) {
    return BlocBuilder<AuthSignInCubit, AuthSignInState>(
      builder: (context, state) {
        return SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: state is AuthSignInLoading
                ? null
                : () => _login(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppClr.primaryColor,
              disabledBackgroundColor: AppClr.gray400,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: state is AuthSignInLoading
                ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppClr.white),
              ),
            )
                : Text(
              AppStrings.signIn,
              style: const TextStyle(
                fontSize: 16,
                color: AppClr.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }


  void _login(BuildContext context) {
    if (_formKey.currentState!.validate()) {
      context.read<AuthSignInCubit>().signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );
    }
  }

  void _clearError() {
    context.read<AuthSignInCubit>().clearError();
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppStrings.loginError,
          style: const TextStyle(color: AppClr.error),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppStrings.ok,
              style: const TextStyle(color: AppClr.primaryColor),
            ),
          ),
        ],
        backgroundColor: AppClr.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}