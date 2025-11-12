import 'package:flutter/material.dart';
import 'package:hsc_chat/feature/auth/view/auth_screen.dart';
import 'package:hsc_chat/feature/splash/splash_screen.dart';
import 'package:hsc_chat/routes/routes.dart';

class RouteGenerator {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RouteNames.splash:
        return MaterialPageRoute(builder: (context) => SplashScreen());

      case RouteNames.auth:
        return MaterialPageRoute(builder: (context) => AuthScreen());
      default:
        // Handle unknown routes
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}
