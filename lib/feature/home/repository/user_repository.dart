import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hec_chat/cores/constants/api_urls.dart';
import 'package:hec_chat/cores/network/api_response.dart';
import 'package:hec_chat/cores/network/dio_client.dart';
import 'package:hec_chat/feature/home/model/common_groups_response.dart';
import 'package:hec_chat/feature/home/model/group_action.dart';

class UserRepository {
  final DioClient _dio = DioClient();

  // Fetch common groups between [currentUserId] and [otherUserId].Returns a list of GroupModel on success.
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

  // Block or unblock [userId] by [currentUserId].Returns true on success.
  Future<bool> blockUnblock({
    required int currentUserId,
    required int userId,
    required bool isBlocked,
  }) async {
    final path = '${ApiUrls.blockUnblockUsers}/$userId/block-unblock';
    final payload = {'user_id': currentUserId, 'is_blocked': isBlocked};
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

  // Delete a group by [groupId] as [currentUserId]. Returns true on success.
  Future<ApiResponse> deleteGroup(String groupId) async {
    try {
      final response = await _dio.delete(
        '${ApiUrls.baseUrl}/api/messages/groups/$groupId/remove',
      );

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
      if (kDebugMode) {
        print('❌ Delete group repository error: $e');
      }
      return ApiResponse.error('Network error: $e');
    }
  }

  //Make a member admin in a group. Returns GroupActionResponse parsed from server.
  Future<GroupActionResponse> makeAdmin({
    required String groupId,
    required int memberId,
  }) async {
    try {
      final path =
          '${ApiUrls.baseUrl}/api/messages/groups/$groupId/members/$memberId/make-admin';
      final resp = await _dio.put(path);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return GroupActionResponse.fromJson(resp.data as Map<String, dynamic>);
      }
      throw Exception('Failed to make admin: ${resp.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Dismiss a member from admin role
  Future<GroupActionResponse> dismissAdmin({
    required String groupId,
    required int memberId,
  }) async {
    try {
      final path =
          '${ApiUrls.baseUrl}/api/messages/groups/$groupId/members/$memberId/dismiss-as-admin';
      final resp = await _dio.put(path);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return GroupActionResponse.fromJson(resp.data as Map<String, dynamic>);
      }
      throw Exception('Failed to dismiss admin: ${resp.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Remove member from group
  Future<GroupActionResponse> removeMember({
    required String groupId,
    required int memberId,
  }) async {
    try {
      final path =
          '${ApiUrls.baseUrl}/api/messages/groups/$groupId/members/$memberId';
      final resp = await _dio.delete(path);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return GroupActionResponse.fromJson(resp.data as Map<String, dynamic>);
      }
      throw Exception('Failed to remove member: ${resp.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Update group information
  Future<ApiResponse> updateGroup({
    required String groupId,
    required String name,
    required String description,
    required File? photo,
  }) async {
    try {
      final path = '${ApiUrls.baseUrl}/api/messages/group-update/$groupId';
      final formData = FormData.fromMap({
        'name': name,
        'description': description,
        if (photo != null)
          'photo_url': await MultipartFile.fromFile(photo.path),
      });
      final resp = await _dio.patch(path, data: formData);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return ApiResponse.success(resp.data);
      }
      return ApiResponse.error('Update failed with status: ${resp.statusCode}');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  //Add members to group
  Future<ApiResponse> addMembers({
    required String groupId,
    required List<int> memberIds,
  }) async {
    try {
      final path =
          '${ApiUrls.baseUrl}/api/messages/groups/$groupId/add-members';
      final payload = {'members': memberIds};
      final resp = await _dio.put(path, data: payload);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return ApiResponse.success(resp.data);
      }
      return ApiResponse.error(
        'Add members failed with status: ${resp.statusCode}',
      );
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }
}
