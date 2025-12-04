import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/constants/app_colors.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/feature/auth/bloc/sign_in/auth_signin_cubit.dart';
import 'package:hsc_chat/feature/auth/bloc/sign_in/auth_signin_state.dart';
import 'package:hsc_chat/feature/home/bloc/conversation_cubit.dart';
import '../../../cores/constants/image_paths.dart';
import '../../home/view/home_screen.dart';

class AuthScreen extends StatefulWidget {
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
            padding: EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 60),
                  _buildHeader(),
                  SizedBox(height: 48),
                  _buildEmailField(),
                  SizedBox(height: 16),
                  _buildPasswordField(),
                  SizedBox(height: 32),
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
          SizedBox(height: 24),
          Text(
            'Welcome to HEC Chat',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppClr.primaryColor,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Sign in to continue',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      decoration: InputDecoration(
        labelText: 'Email',
        prefixIcon: Icon(Icons.email),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppClr.primaryColor, width: 2.0),
        ),
      ),
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your email';
        }
        if (!value.contains('@')) {
          return 'Please enter a valid email address';
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
        labelText: 'Password',
        prefixIcon: Icon(Icons.lock),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppClr.primaryColor, width: 2.0),
        ),
      ),
      obscureText: _obscurePassword,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your password';
        }
        if (value.length < 6) {
          return 'Password must be at least 6 characters';
        }
        return null;
      },
      onChanged: (_) => _clearError(),
    );
  }

  Widget _buildRememberMeCheckbox() {
    return Row(
      children: [
        Checkbox(
          value: _rememberMe,
          onChanged: (value) {
            setState(() {
              _rememberMe = value ?? false;
            });
          },
          activeColor: AppClr.primaryColor,
        ),
        Text('Remember me'),
      ],
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: state is AuthSignInLoading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Sign In',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSignUpOption(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () {
          // Navigate to sign up screen
          // Navigator.pushNamed(context, '/signup');
        },
        child: Text(
          "Don't have an account? Sign Up",
          style: TextStyle(
            color: AppClr.primaryColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
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
        title: Text('Login Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
}
