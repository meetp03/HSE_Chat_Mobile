import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../feature/auth/view/auth_screen.dart';
import '../../main.dart';
import '../constants/api_urls.dart';
import '../utils/shared_preferences.dart';
import 'network_exceptions.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

class DioClient {
  static final DioClient _instance = DioClient._internal();
  late Dio _dio;

  factory DioClient() => _instance;

  DioClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiUrls.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        validateStatus: (status) {
          return status != null && status < 500;
        },
      ),
    );

    _setupInterceptors();
  }

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = SharedPreferencesHelper.getString('auth_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          if (kDebugMode) {
            debugPrint(
              'REQUEST[${options.method}] => 🔗 🔗 🔗 PATH: ${options.path}',
              wrapWidth: 1200,
            );
            debugPrint('Headers: ${options.headers}', wrapWidth: 1200);
            // Avoid printing potentially huge raw bodies here
            debugPrint('📦 📦 📦 Data type: ${options.data.runtimeType}', wrapWidth: 1200);
          }

          handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode) {
            debugPrint(
              'RESPONSE[${response.statusCode}] => PATH: ${response.requestOptions.path}',
              wrapWidth: 1200,
            );

            // If this is the conversations endpoint, pretty-print the full JSON using debugPrint
            try {
              final path = response.requestOptions.path;
              if (path.contains('/api/messages/') && path.contains('/conversations')) {
                // Print full pretty JSON for conversation endpoints so developer
                // can inspect all messages returned by the server (debug only).
                try {
                  final encoder = const JsonEncoder.withIndent('  ');
                  final pretty = encoder.convert(response.data);
                  debugPrint('--- FULL RESPONSE for ${response.requestOptions.uri} ---', wrapWidth: 1200);
                  const int chunkSize = 2000;
                  for (var i = 0; i < pretty.length; i += chunkSize) {
                    final end = (i + chunkSize < pretty.length) ? i + chunkSize : pretty.length;
                    debugPrint(pretty.substring(i, end), wrapWidth: 1200);
                  }
                  debugPrint('--- END FULL RESPONSE ---', wrapWidth: 1200);
                } catch (e) {
                  debugPrint('⚠️ Failed to pretty-print conversations response: $e', wrapWidth: 1200);
                  debugPrint(response.data.toString(), wrapWidth: 1200);
                }
              } else {
                // For other endpoints print a concise summary
                debugPrint('📦 Response data type: ${response.data.runtimeType}', wrapWidth: 1200);
              }
            } catch (e) {
              debugPrint('⚠️ Error while pretty-printing response: $e', wrapWidth: 1200);
              // fallback: show truncated response string safely
              try {
                debugPrint(response.data.toString(), wrapWidth: 1200);
              } catch (_) {}
            }
          }

          // Check for 401 errors in response and handle them
          if (response.statusCode == 401) {
            _handleUnauthorizedError();
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.badResponse,
              ),
            );
            return;
          }
          handler.next(response);
        },
        onError: (error, handler) {
          if (kDebugMode) {
            debugPrint(
              '❌  ❌  ❌ ERROR[${error.response?.statusCode}] => PATH: ${error.requestOptions.path}',
              wrapWidth: 1200,
            );
            debugPrint('Message: ${error.message}', wrapWidth: 1200);

            try {
              final path = error.requestOptions.path;
              if (path.contains('/api/messages/') && path.contains('/conversations')) {
                debugPrint('--- FULL ERROR RESPONSE for ${error.requestOptions.uri} ---', wrapWidth: 1200);
                if (error.response != null && error.response!.data != null) {
                  final encoder = const JsonEncoder.withIndent('  ');
                  String pretty;
                  try {
                    pretty = encoder.convert(error.response!.data);
                  } catch (_) {
                    pretty = error.response!.data.toString();
                  }
                  const int chunkSize = 2000;
                  for (var i = 0; i < pretty.length; i += chunkSize) {
                    final end = (i + chunkSize < pretty.length) ? i + chunkSize : pretty.length;
                    debugPrint(pretty.substring(i, end), wrapWidth: 1200);
                  }
                } else {
                  debugPrint(error.toString(), wrapWidth: 1200);
                }
                debugPrint('--- END FULL ERROR RESPONSE ---', wrapWidth: 1200);
              } else {
                debugPrint('Error response data: ${error.response?.data}', wrapWidth: 1200);
              }
            } catch (e) {
              debugPrint('⚠️ Error while logging error response: $e', wrapWidth: 1200);
            }
          }

          // Handle 401 errors from onError as well
          if (error.response?.statusCode == 401) {
            _handleUnauthorizedError();
          }
          handler.next(error);
        },
      ),
    );
  }

  void _handleUnauthorizedError() async {
    await SharedPreferencesHelper.remove('auth_token');
    await SharedPreferencesHelper.remove('user_data');

    final context = MyApp.navigatorKey.currentContext;
    if (context != null && context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => AuthScreen(),
          settings: const RouteSettings(arguments: {'showUnauthorizedError': true}),
        ),
            (route) => false,
      );
    }
  }

  // GET Request
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get(path, queryParameters: queryParameters);
      return response;
    } on DioException catch (e) {
      throw NetworkExceptions.getDioException(e);
    }
  }
  // Patch Request
   Future<Response> patch(
      String path, {
        dynamic data,
        Map<String, dynamic>? queryParameters,
      }) async {
    try {
      final response = await _dio.patch(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      return response;
    } on DioException catch (e) {
      throw NetworkExceptions.getDioException(e);
    }
  }
  Future<Response> post(
      String path, {
        dynamic data,
        Map<String, dynamic>? queryParameters,
      }) async {
    try {
      debugPrint('🌐 POST Request: $path', wrapWidth: 1200);
      debugPrint('📝 Query Params: $queryParameters', wrapWidth: 1200);
      debugPrint('📦 payload  : $data ', wrapWidth: 1200);

      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      debugPrint('📦 Body Data: response status: ${response.statusCode}', wrapWidth: 1200);
      return response;
    } on DioException catch (e) {
      throw NetworkExceptions.getDioException(e);
    }
  }
  // PUT Request
  Future<Response> put(String path, {dynamic data}) async {
    try {
      final response = await _dio.put(path, data: data);
      return response;
    } on DioException catch (e) {
      throw NetworkExceptions.getDioException(e);
    }
  }

  // DELETE Request
  Future<Response> delete(String path) async {
    try {
      final response = await _dio.delete(path);
      return response;
    } on DioException catch (e) {
      throw NetworkExceptions.getDioException(e);
    }
  }

  Future<Response> uploadFile(String path, String filePath, {Map<String, dynamic>? data, ProgressCallback? onSendProgress}) async {
     final filename = p.basename(filePath);
     final mime = lookupMimeType(filePath) ?? 'application/octet-stream';
     final parts = mime.split('/');
     final multipart = await MultipartFile.fromFile(filePath, filename: filename, contentType: MediaType(parts[0], parts.length > 1 ? parts[1] : ''));

     final map = <String, dynamic>{};
     if (data != null) map.addAll(data);
     map['file'] = multipart;
     map['file_name'] = filename;

     final formData = FormData.fromMap(map);

     if (kDebugMode) _debugPrintLarge('UPLOAD REQUEST', 'PATH: $path form fields: ${data ?? {}} file: $filename mime: $mime');

     try {
       final response = await _dio.post(
         path,
         data: formData,
         onSendProgress: (count, total) {
           if (kDebugMode) print('📤 upload progress $filename: $count/$total');
           if (onSendProgress != null) onSendProgress(count, total);
         },
       );
       if (kDebugMode) {
         _debugPrintLarge('UPLOAD RESPONSE', 'STATUS: ${response.statusCode} PATH: ${response.requestOptions.path}');
         _debugPrintLarge('UPLOAD RESPONSE BODY', response.data);
       }
        return response;
     } on DioException catch (e) {
       if (kDebugMode) {
         _debugPrintLarge('UPLOAD ERROR', 'message: ${e.message}');
         _debugPrintLarge('UPLOAD ERROR RESPONSE', e.response?.data);
       }
       throw e;
     }
   }

   /// Download raw bytes from a URL using the same Dio instance (so headers/interceptors apply)
   Future<Response<List<int>>> downloadBytes(
     String url, {
     ProgressCallback? onReceiveProgress,
     Map<String, dynamic>? queryParameters,
     CancelToken? cancelToken,
   }) async {
     try {
       if (kDebugMode) debugPrint('🌐 DOWNLOAD Request: $url', wrapWidth: 1200);
       final response = await _dio.get<List<int>>(url,
         options: Options(responseType: ResponseType.bytes),
         queryParameters: queryParameters,
         onReceiveProgress: onReceiveProgress,
         cancelToken: cancelToken,
       );
       if (kDebugMode) debugPrint('📦 DOWNLOAD Response status: ${response.statusCode}', wrapWidth: 1200);
       return response;
     } on DioException catch (e) {
       if (kDebugMode) debugPrint('❌ DOWNLOAD ERROR: ${e.message}', wrapWidth: 1200);
       rethrow;
     }
   }

   void _debugPrintLarge(String tag, Object? object) {
     final msg = object == null ? 'null' : object.toString();
     const chunkSize = 800;
     for (var i = 0; i < msg.length; i += chunkSize) {
       final end = (i + chunkSize < msg.length) ? i + chunkSize : msg.length;
       if (kDebugMode) print('[$tag] ${msg.substring(i, end)}');
     }
   }
 }
