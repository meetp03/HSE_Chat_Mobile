// notification_repository.dart
import 'package:hec_chat/cores/network/dio_client.dart';
import 'package:hec_chat/cores/network/api_response.dart';
import 'package:hec_chat/feature/home/model/notification_model.dart';
import '../../../cores/constants/api_urls.dart';

class NotificationRepository {
   final String? authToken;
  final DioClient _dio;

  NotificationRepository({  this.authToken})
      : _dio = DioClient();

  Future<ApiResponse<NotificationsResponse>> getNotifications({int page = 1, int perPage = 5}) async {
    try {
      final resp = await _dio.get(
          ApiUrls.getNotification,
          queryParameters: {'page': page, 'per_page': perPage}
      );

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

  /// Fetch authoritative unseen notifications count from API
  Future<int?> fetchUnseenCount() async {
    try {
      // Get first page with minimal data to check unseen_count
      final resp = await _dio.get(
          ApiUrls.getNotification,
          queryParameters: {'page': 1, 'per_page': 1}
      );

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
      print('❌ NotificationRepository: failed to fetch unseen count: $e');
      return null;
    }
  }

  int? _parseCount(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  // For backward compatibility
  Future<ApiResponse<int>> getUnseenCount() async {
    try {
      final count = await fetchUnseenCount();
      if (count != null) {
        return ApiResponse.success(count, message: 'Unseen count fetched');
      }
      return ApiResponse.error('Failed to fetch unseen count');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

   Future<ApiResponse<void>> markAllNotificationsRead(int userId) async {
     try {
       final resp = await _dio.post(
         ApiUrls.markAllNotificationsRead,
         data: {'user_id': userId},
       );

       if (resp.statusCode == 200) {
         return ApiResponse.success(
             null,
             message: 'All notifications marked as read'
         );
       }

       return ApiResponse.error(
           'Failed to mark notifications as read: ${resp.statusCode}'
       );
     } catch (e) {
       return ApiResponse.error('Network error: $e');
     }
   }
}