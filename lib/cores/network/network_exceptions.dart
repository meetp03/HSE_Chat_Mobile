import 'package:dio/dio.dart';

class NetworkExceptions implements Exception {
  final String message;
  final int? statusCode;

  const NetworkExceptions(this.message, {this.statusCode});

  static NetworkExceptions getDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkExceptions('Connection timeout');

      case DioExceptionType.badResponse:
        return NetworkExceptions(
          _handleStatusCode(error.response?.statusCode),
          statusCode: error.response?.statusCode,
        );

      case DioExceptionType.cancel:
        return const NetworkExceptions('Request cancelled');

      case DioExceptionType.connectionError:
        return const NetworkExceptions('No internet connection');

      case DioExceptionType.unknown:
      default:
        return const NetworkExceptions('Something went wrong');
    }
  }

  static String _handleStatusCode(int? statusCode) {
    switch (statusCode) {
      case 400:
        return 'Bad request';
      case 401:
        return 'Unauthorized access';
      case 403:
        return 'Forbidden access';
      case 404:
        return 'Not found';
      case 422:
        return 'Validation error';
      case 500:
        return 'Internal server error';
      case 502:
        return 'Bad gateway';
      case 503:
        return 'Service unavailable';
      default:
        return 'Something went wrong';
    }
  }

  @override
  String toString() => message;
}
