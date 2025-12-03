import 'package:flutter/material.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/routes/navigation_service.dart';
import 'package:hsc_chat/routes/routes.dart';

import '../../cores/constants/image_paths.dart';

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
        NavigationService.pushReplacementNamed(RouteNames.home);
      } else {
        // User is not logged in, navigate to auth
        NavigationService.pushReplacementNamed(RouteNames.auth);
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
