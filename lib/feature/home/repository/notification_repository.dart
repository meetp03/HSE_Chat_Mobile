// notification_repository.dart
import 'package:hsc_chat/cores/network/dio_client.dart';
import 'package:hsc_chat/cores/network/api_response.dart';
import 'package:hsc_chat/feature/home/model/notification_model.dart';

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
}
