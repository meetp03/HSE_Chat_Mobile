import 'package:flutter/material.dart';
import 'package:hsc_chat/feature/auth/view/auth_screen.dart';
import 'package:hsc_chat/feature/home/view/home_screen.dart';
import 'package:hsc_chat/feature/splash/splash_screen.dart';

class RouteNames {
  static const String splash = '/';
  static const String auth = '/auth';
  static const String forget = '/forget';
  static const String landing = '/landing';
  static const String questionnaireFlow = '/questionnaire_flow';
  static const String onBoarding = '/on_boarding';
  static const String home = '/home';
  static const String workout = '/workout';
  static const String workoutInner = '/workout_inner';
  static const String workoutList = '/workout_list';
  static const String workOutJourney = '/workout_journey';
  static const String planTarget = '/plan_target';
  static const String planInner = '/plan_inner';
  static const String mealItems = '/meal_items';
  static const String manualPlan = '/manual_plan';
  static const String setting = '/setting';
  static const String chat = '/chat';
  static const String chatHeyThere = '/chat_hey_there';
  static const String chatBubbles = '/chat_bubbles';
}

class AppRoutes {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RouteNames.splash:
        return MaterialPageRoute(builder: (_) => SplashScreen());

      case RouteNames.home:
        return MaterialPageRoute(builder: (_) => HomeScreen());

      case RouteNames.auth:
        return MaterialPageRoute(builder: (_) => AuthScreen());

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}
