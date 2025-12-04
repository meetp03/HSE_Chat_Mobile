import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/constants/app_colors.dart';
import 'package:hsc_chat/cores/utils/providers.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'feature/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPreferencesHelper.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: Providers.globalProviders,
      child: MaterialApp(
        title: 'HEChat',
        navigatorKey: MyApp.navigatorKey,
        home:   SplashScreen(),
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: AppClr.primaryColor,
          colorScheme: ColorScheme.fromSwatch().copyWith(
            primary: AppClr.primaryColor,
            secondary: AppClr.primaryColor,
          ),
          visualDensity: VisualDensity.adaptivePlatformDensity,
          appBarTheme: AppBarTheme(
            backgroundColor: AppClr.primaryColor,
            foregroundColor: Colors.white,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: AppClr.primaryColor,
          ),
        ),
      ),
    );
  }
}
