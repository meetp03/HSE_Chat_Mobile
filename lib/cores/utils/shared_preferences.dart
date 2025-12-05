import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hec_chat/feature/auth/model/auth_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesHelper {
  static SharedPreferences? _prefs;

  // Initialize SharedPreferences
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // String methods
  static Future<bool> setString(String key, String value) async {
    await init();
    return _prefs!.setString(key, value);
  }

  static String? getString(String key) {
    return _prefs?.getString(key);
  }

  // Clear all preferences
  static Future<bool> clear() async {
    await init();
    return _prefs!.clear();
  }

  // Remove methods
  static Future<bool> remove(String key) async {
    await init();
    return _prefs!.remove(key);
  }

  static LoginResponse? getStoredLoginResponse() {
    try {
      final userJson = SharedPreferencesHelper.getString('user_data');
      if (userJson != null) {
        return LoginResponse.fromJson(json.decode(userJson));
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting stored user data: $e');
      }
    }
    return null;
  }

  static int getCurrentUserId() {
    final loginResponse = getStoredLoginResponse();
    return loginResponse?.id ?? 0; // Now returns int
  }

  static String getCurrentUserToken() {
    final loginResponse = getStoredLoginResponse();
    return loginResponse?.token ?? '';
  }

  static String getCurrentUserName() {
    final loginResponse = getStoredLoginResponse();
    return loginResponse?.name ?? '';
  }

  static bool isUserAuthenticated() {
    final token = SharedPreferencesHelper.getString('auth_token');
    return token != null && token.isNotEmpty;
  }

  // Optional: Store login response after successful login
  static Future<void> storeLoginResponse(LoginResponse response) async {
    await SharedPreferencesHelper.setString('auth_token', response.token ?? '');
    await SharedPreferencesHelper.setString(
      'user_data',
      json.encode(response.toJson()),
    );
  }

  static String? getCurrentUserPhotoUrl() {
    final prefs = _prefs;
    if (prefs == null) return null;

    // Assuming you store user data as JSON
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return null;

    try {
      final userData = json.decode(userDataString);
      return userData['photo_url'] as String?;
    } catch (e) {
      return null;
    }
  }
}
