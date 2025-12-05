import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class NetworkChecker {
  static final Connectivity _connectivity = Connectivity();
  // List of fallback URLs to test internet connectivity
  static const List<String> _testUrls = [
    'https://www.google.com',
    'https://cloudflare.com',
    'https://api.github.com',
  ];
  static const int _timeoutSeconds = 8;
  static const int _maxRetries = 3;
  static const String _fallbackHost = '8.8.8.8'; // Google DNS for socket check
  static const int _fallbackPort = 53; // DNS port

  // Checks if the device is connected to any network (Wi-Fi, mobile, etc.)
  static Future<bool> isConnected() async {
    try {
      // Check connectivity status
      final connectivityResult = await _connectivity.checkConnectivity();

      if (connectivityResult == ConnectivityResult.none) {
        if (kDebugMode) {
          print('No network connectivity detected (ConnectivityResult.none)');
        }
        return false;
      }

      // Log the network type
      if (kDebugMode) {
        print('Network Type: ${connectivityResult.toString()}');
      }

      // Verify actual internet access
      bool hasInternet = await _checkInternetAccess();

      if (kDebugMode) {
        print('Internet Access: $hasInternet');
      }

      return hasInternet;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking connectivity: $e');
      }
      return false;
    }
  }

  // Performs multiple checks to verify internet connectivity
  static Future<bool> _checkInternetAccess() async {
    // Try HTTP checks first
    for (String url in _testUrls) {
      bool result = await _tryHttpCheck(url);
      if (result) {
        return true;
      }
    }

    // Fallback to socket check if HTTP fails
    bool socketResult = await _trySocketCheck();
    if (kDebugMode) {
      print('Socket Check Result: $socketResult');
    }
    return socketResult;
  }

  // Attempts an HTTP request to the given URL
  static Future<bool> _tryHttpCheck(String url) async {
    int attempts = 0;

    while (attempts < _maxRetries) {
      try {
        final response = await http
            .get(Uri.parse(url), headers: {'Connection': 'close'})
            .timeout(Duration(seconds: _timeoutSeconds));

        if (response.statusCode == 200) {
          if (kDebugMode) {
            print('HTTP check succeeded for $url');
          }
          return true;
        }

        if (kDebugMode) {
          print(
            'HTTP check failed for $url with status: ${response.statusCode}',
          );
        }
        return false;
      } catch (e) {
        attempts++;
        if (kDebugMode) {
          print('HTTP check attempt $attempts failed for $url: $e');
        }
        if (attempts >= _maxRetries) {
          return false;
        }
        // Wait briefly before retrying
        await Future.delayed(Duration(milliseconds: 1000));
      }
    }
    return false;
  }

  // Fallback socket connection check to Google DNS
  static Future<bool> _trySocketCheck() async {
    try {
      final socket = await Socket.connect(
        _fallbackHost,
        _fallbackPort,
        timeout: Duration(seconds: _timeoutSeconds),
      );
      socket.close();
      if (kDebugMode) {
        print('Socket connection to $_fallbackHost:$_fallbackPort succeeded');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Socket connection to $_fallbackHost:$_fallbackPort failed: $e');
      }
      return false;
    }
  }

  // Stream to listen for connectivity changes
  static Stream<bool> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged.asyncMap((result) async {
      if (result == ConnectivityResult.none) {
        if (kDebugMode) {
          print('Connectivity changed: No network');
        }
        return false;
      }
      if (kDebugMode) {
        print('Connectivity changed: Network type - ${result.toString()}');
      }
      return await _checkInternetAccess();
    });
  }

  // Alternative method to check internet connection
  static Future<bool> hasInternetConnection() async {
    return await _checkInternetAccess();
  }
}
