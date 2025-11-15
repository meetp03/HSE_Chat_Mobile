// user_repository.dart
import 'package:dio/dio.dart';
import 'package:hsc_chat/cores/constants/api_urls.dart';
import 'package:hsc_chat/cores/network/api_response.dart';
import 'package:hsc_chat/cores/network/dio_client.dart';
import 'package:hsc_chat/feature/home/model/common_groups_response.dart';

class UserRepository {
  final DioClient _dio = DioClient();

  /// Fetch common groups between [currentUserId] and [otherUserId].
  /// Returns a list of GroupModel on success.
  Future<List<GroupModel>> fetchCommonGroups({
    required int currentUserId,
    required int otherUserId,
  }) async {
    final payload = {'user_id': otherUserId};
    try {
      final resp = await _dio.post(
        "${ApiUrls.commonGroup}/$currentUserId",
        data: payload,
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final response = CommonGroupsResponse.fromJson(resp.data);

        if (response.success) {
          return response.groups;
        } else {
          throw Exception(response.message);
        }
      }
      throw Exception('Failed to load groups: ${resp.statusCode}');
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }

  /// Block or unblock [userId] by [currentUserId].
  /// Returns true on success.
  Future<bool> blockUnblock({
    required int currentUserId,
    required int userId,
    required bool isBlocked,
  }) async {
    final path = '${ApiUrls.blockUnblockUsers}/$currentUserId/block-unblock';
    final payload = {'user_id': userId, 'is_blocked': isBlocked};
    try {
      final resp = await _dio.put(path, data: payload);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final response = BaseResponse.fromJson(resp.data);
        return response.success;
      }
      return false;
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }

  /// Delete a group by [groupId] as [currentUserId]. Returns true on success.
  // In UserRepository.dart - Ensure proper response handling
  Future<ApiResponse> deleteGroup(String groupId) async {
    try {
      final response = await _dio.delete(
        '${ApiUrls.baseUrl}messages/groups/$groupId/remove',
      );

      print('🗑️ Delete group API response status: ${response.statusCode}');
      print('🗑️ Delete group API response data: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic> && data['success'] == true) {
          return ApiResponse.success(data);
        } else {
          return ApiResponse.error(data['message'] ?? 'Delete failed');
        }
      } else {
        return ApiResponse.error(
          'Delete failed with status: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Delete group repository error: $e');
      return ApiResponse.error('Network error: $e');
    }
  }
}
