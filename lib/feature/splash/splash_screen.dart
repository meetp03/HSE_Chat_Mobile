import 'package:flutter/material.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';
import '../../cores/constants/image_paths.dart';
import '../auth/view/auth_screen.dart';
import '../home/view/home_screen.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  void _checkAuthStatus() async {
    // Wait for a bit for the splash screen to show
    await Future.delayed(Duration(milliseconds: 1500));
    if (mounted) {
      // Check if user is authenticated and navigate accordingly
      if (SharedPreferencesHelper.isUserAuthenticated()) {
        // User is already logged in, navigate to home
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        // User is not logged in, navigate to auth
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) =>   AuthScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Image.asset(AppImg.appLogo),
            ),
          ],
        ),
      ),
    );
  }
}
