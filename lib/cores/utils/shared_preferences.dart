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

  // Boolean methods
  static Future<bool> setBool(String key, bool value) async {
    await init();
    return _prefs!.setBool(key, value);
  }

  static bool? getBool(String key) {
    return _prefs?.getBool(key);
  }

  // Integer methods
  static Future<bool> setInt(String key, int value) async {
    await init();
    return _prefs!.setInt(key, value);
  }

  static int? getInt(String key) {
    return _prefs?.getInt(key);
  }

  // Double methods
  static Future<bool> setDouble(String key, double value) async {
    await init();
    return _prefs!.setDouble(key, value);
  }

  static double? getDouble(String key) {
    return _prefs?.getDouble(key);
  }

  // List<String> methods
  static Future<bool> setStringList(String key, List<String> value) async {
    await init();
    return _prefs!.setStringList(key, value);
  }

  static List<String>? getStringList(String key) {
    return _prefs?.getStringList(key);
  }

  // Object methods (using JSON serialization)
  static Future<bool> setObject(String key, Object value) async {
    await init();
    return _prefs!.setString(key, json.encode(value));
  }

  static T? getObject<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final jsonString = _prefs?.getString(key);
    if (jsonString != null) {
      try {
        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        return fromJson(jsonMap);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // Remove methods
  static Future<bool> remove(String key) async {
    await init();
    return _prefs!.remove(key);
  }

  // Clear all preferences
  static Future<bool> clear() async {
    await init();
    return _prefs!.clear();
  }

  // Check if key exists
  static bool containsKey(String key) {
    return _prefs?.containsKey(key) ?? false;
  }

  // Get all keys
  static Set<String> getKeys() {
    return _prefs?.getKeys() ?? <String>{};
  }

  // User data helpers
  static Future<void> saveUserData(Map<String, dynamic> userData) async {
    await setString('user_data', json.encode(userData));
  }

  static Map<String, dynamic>? getUserData() {
    final userDataString = getString('user_data');
    if (userDataString != null) {
      try {
        return json.decode(userDataString) as Map<String, dynamic>;
      } catch (e) {
        return null;
      }
    }
    return null;
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

  static String getCurrentUserEmail() {
    final loginResponse = getStoredLoginResponse();
    return loginResponse?.email ?? '';
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

  // Optional: Clear user data on logout
  static Future<void> clearUserData() async {
    await SharedPreferencesHelper.remove('auth_token');
    await SharedPreferencesHelper.remove('user_data');
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
