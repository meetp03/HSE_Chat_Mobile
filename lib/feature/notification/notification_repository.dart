 import 'package:flutter/foundation.dart';
import 'package:hec_chat/cores/network/dio_client.dart';
import 'package:hec_chat/cores/network/api_response.dart';
import 'package:hec_chat/feature/home/model/notification_model.dart';
import '../../../cores/constants/api_urls.dart';

class NotificationRepository {
  final DioClient _dio = DioClient();

  Future<ApiResponse<NotificationsResponse>> getNotifications({int page = 1, int perPage = 5}) async {
    try {
      final resp = await _dio.get(ApiUrls.getNotification, queryParameters: {'page': page, 'per_page': perPage});

      if (resp.statusCode == 200) {
        final data = resp.data as Map<String, dynamic>;
        final parsed = NotificationsResponse.fromJson(data);
        return ApiResponse.success(parsed, message: 'Notifications loaded');
      }

      return ApiResponse.error('Failed to load notifications: ${resp.statusCode}');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Fetch just the unseen count (lightweight call)
  Future<int?> fetchUnseenCount() async {
    try {
      // Use the same endpoint but with minimal data
      final resp = await _dio.get(ApiUrls.getNotification, queryParameters: {'page': 1, 'per_page': 1});

      if (resp.statusCode == 200) {
        final body = resp.data as Map<String, dynamic>;

        // Try multiple possible locations for unseen_count
        int? count;

        // Check root level
        if (body.containsKey('unseen_count')) {
          count = _parseCount(body['unseen_count']);
        }
        // Check data level
        else if (body['data'] != null && body['data'] is Map) {
          final data = body['data'] as Map<String, dynamic>;
          if (data.containsKey('unseen_count')) {
            count = _parseCount(data['unseen_count']);
          }
        }
        // Check meta level
        else if (body['meta'] != null && body['meta'] is Map) {
          final meta = body['meta'] as Map<String, dynamic>;
          if (meta.containsKey('unseen_count')) {
            count = _parseCount(meta['unseen_count']);
          }
        }

        return count ?? 0;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('NotificationRepository: failed to fetch unseen count: $e');
      }
      return null;
    }
  }

  int? _parseCount(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}