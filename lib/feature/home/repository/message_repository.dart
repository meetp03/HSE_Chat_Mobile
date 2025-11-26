// repository/message_repository.dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hsc_chat/cores/constants/api_urls.dart';
import 'package:hsc_chat/cores/network/api_response.dart';
import 'package:hsc_chat/cores/network/dio_client.dart';
import 'package:hsc_chat/cores/network/network_exceptions.dart';
import 'package:hsc_chat/feature/home/model/blocked_user_model.dart';
import 'package:hsc_chat/feature/home/model/contact_model.dart';
import 'package:hsc_chat/feature/home/model/group_model.dart';
import 'package:hsc_chat/feature/home/model/user_model.dart';

abstract class IMessageRepository {
  Future<ApiResponse<ContactResponse>> getMyContacts({
    required int userId,
    int page = 1,
    int perPage = 10,
    String query = '',
  });

  Future<ApiResponse<ContactResponse>> getUsersList({
    required int userId,
    int page = 1,
    int perPage = 10,
    String query = '',
  });

  Future<ApiResponse<BlockedUserResponse>> getBlockedUsers({
    required int userId,
    int page = 1,
    int perPage = 10,
    String query = '',
  });

  Future<ApiResponse<CreateGroupResponse>> createGroup({
    required String name,
    required List<int> members,
    String description = '',
    String? photoPath,
  });

  Future<ApiResponse<void>> sendChatRequest({
    required int fromId,
    required String toId,
  });
}

class MessageRepository implements IMessageRepository {
  final DioClient _dio;

  const MessageRepository(this._dio);
  @override
  Future<ApiResponse<CreateGroupResponse>> createGroup({
    required String name,
    required List<int> members,
    String description = '',
    String? photoPath,
  }) async {
    try {
      // Create form data
      final formData = FormData.fromMap({
        'name': name,
        'members': json.encode(members),
        'description': description,
      });

      // Add photo if provided - using Dio's built-in file handling
      if (photoPath != null && photoPath.isNotEmpty) {
        formData.files.add(
          MapEntry('photo_url', await MultipartFile.fromFile(photoPath)),
        );
      }

      final response = await _dio.post(
        ApiUrls.createGroup,
        data: formData,
      );

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          final data = CreateGroupResponse.fromJson(response.data);
          return ApiResponse<CreateGroupResponse>.success(
            data,
            message: 'Group created successfully',
            statusCode: response.statusCode,
          );
        } else {
          return ApiResponse<CreateGroupResponse>.error(
            response.data['message'] ?? 'Failed to create group',
          );
        }
      } else {
        return ApiResponse<CreateGroupResponse>.error(
          response.data['message'] ?? 'Failed to create group',
        );
      }
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<CreateGroupResponse>.error(networkException.message);
    } catch (e) {
      return ApiResponse<CreateGroupResponse>.error('Unexpected error: $e');
    }
  }

  @override
  Future<ApiResponse<ContactResponse>> getMyContacts({
    required int userId,
    int page = 1,
    int perPage = 10,
    String query = '',
  }) async {
    try {
      final Map<String, dynamic> queryParams = {
        'page': page,
        'per_page': perPage,
      };

      // Add search query if provided
      if (query.isNotEmpty) {
        queryParams['search'] = query;
      }

      final response = await _dio.post(
        ApiUrls.myContacts,
        queryParameters: queryParams,
        data: {'user_id': userId},
      );

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          final data = ContactResponse.fromJson(response.data);
          return ApiResponse<ContactResponse>.success(
            data,
            message: data.message,
            statusCode: response.statusCode,
          );
        } else {
          return ApiResponse<ContactResponse>.error(
            response.data['message'] ?? 'Failed to load contacts',
          );
        }
      } else {
        return ApiResponse<ContactResponse>.error(
          response.data['message'] ?? 'Failed to load contacts',
        );
      }
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<ContactResponse>.error(networkException.message);
    } catch (e) {
      return ApiResponse<ContactResponse>.error('Unexpected error: $e');
    }
  }

  @override
  Future<ApiResponse<ContactResponse>> getUsersList({
    required int userId,
    int page = 1,
    int perPage = 10,
    String query = '',
  }) async {
    try {
      final Map<String, dynamic> queryParams = {
        'page': page,
        'per_page': perPage,
        'user_id': userId,
      };

      // Add search query if provided
      if (query.isNotEmpty) {
        queryParams['search'] = query;
      }

      final response = await _dio.get(
        ApiUrls.usersList,
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          final data = ContactResponse.fromJson(response.data);
          return ApiResponse<ContactResponse>.success(
            data,
            message: data.message,
            statusCode: response.statusCode,
          );
        } else {
          return ApiResponse<ContactResponse>.error(
            response.data['message'] ?? 'Failed to load users',
          );
        }
      } else {
        return ApiResponse<ContactResponse>.error(
          response.data['message'] ?? 'Failed to load users',
        );
      }
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<ContactResponse>.error(networkException.message);
    } catch (e) {
      return ApiResponse<ContactResponse>.error('Unexpected error: $e');
    }
  }

  @override
  Future<ApiResponse<BlockedUserResponse>> getBlockedUsers({
    required int userId,
    int page = 1,
    int perPage = 10,
    String query = '',
  }) async {
    try {
      final Map<String, dynamic> queryParams = {
        'page': page,
        'per_page': perPage,
      };

      // Add search query if provided
      if (query.isNotEmpty) {
        queryParams['search'] = query;
      }

      final response = await _dio.post(
        ApiUrls.blockedUsers,
        queryParameters: queryParams,
        data: {'user_id': userId},
      );
print('🚀 Blocked Users ID: $userId');
      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          final data = BlockedUserResponse.fromJson(response.data);
          return ApiResponse<BlockedUserResponse>.success(
            data,
            message: data.message,
            statusCode: response.statusCode,
          );
        } else {
          return ApiResponse<BlockedUserResponse>.error(
            response.data['message'] ?? 'Failed to load blocked users',
          );
        }
      } else {
        return ApiResponse<BlockedUserResponse>.error(
          response.data['message'] ?? 'Failed to load blocked users',
        );
      }
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<BlockedUserResponse>.error(networkException.message);
    } catch (e) {
      return ApiResponse<BlockedUserResponse>.error('Unexpected error: $e');
    }
  }

  @override
  Future<ApiResponse<void>> sendChatRequest({
    required int fromId,
    required String toId,
  }) async {
    try {
      final response = await _dio.post(
        ApiUrls.sendChatRequest,
        data: {
          'from_id': fromId,
          'to_id': toId,
        },
      );

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          return ApiResponse<void>.success(null, message: response.data['message']);
        } else {
          return ApiResponse<void>.error(response.data['message'] ?? 'Failed to send chat request');
        }
      }

      return ApiResponse<void>.error(response.data['message'] ?? 'Failed to send chat request');
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<void>.error(networkException.message);
    } catch (e) {
      return ApiResponse<void>.error('Unexpected error: $e');
    }
  }
}
