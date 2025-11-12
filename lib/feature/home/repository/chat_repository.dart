// chat_repository.dart
import 'package:dio/dio.dart';
import 'package:hsc_chat/cores/constants/api_urls.dart';
import 'package:hsc_chat/cores/network/api_response.dart';
import 'package:hsc_chat/cores/network/dio_client.dart';
import 'package:hsc_chat/cores/network/network_exceptions.dart';
import 'package:hsc_chat/feature/home/model/chat_response_model.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

abstract class IChatRepository {
  Future<ApiResponse<ChatConversationResponse>> getConversations({
    required int userId,
    required String otherUserId,
    required bool isGroup,
    int page = 1,
    int limit = 15,
  });

  Future<ApiResponse<MessageResponse>> sendMessage({
    required String toId,
    required String message,
    required bool isGroup,
    int isArchiveChat = 0,
    int messageType = 0,
    String? fileName,
    String? replyTo,
    int isMyContact = 1,
  });

  Future<ApiResponse<MessageReadResponse>> markAsRead({
    required int userId,
    required String otherUserId,
    required bool isGroup,
  });
}

class ChatRepository implements IChatRepository {
  final DioClient _dio;

  const ChatRepository(this._dio);

  @override
  Future<ApiResponse<ChatConversationResponse>> getConversations({
    required int userId,
    required String otherUserId,
    required bool isGroup,
    int page = 1,
    int limit = 15,
  }) async {
    try {
      final response = await _dio.post(
        '${ApiUrls.baseUrl}messages/$otherUserId/conversations',
        queryParameters: {
          'user_id': userId,
          'is_group': isGroup ? 1 : 0,
          'page': page,
          'limit': limit,
        },
      );

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          final data = ChatConversationResponse.fromJson(response.data);
          return ApiResponse<ChatConversationResponse>.success(
            data,
            message: data.message,
            statusCode: response.statusCode,
          );
        } else {
          return ApiResponse<ChatConversationResponse>.error(
            response.data['message'] ?? 'Failed to load conversations',
          );
        }
      } else {
        return ApiResponse<ChatConversationResponse>.error(
          response.data['message'] ?? 'Failed to load conversations',
        );
      }
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<ChatConversationResponse>.error(
        networkException.message,
      );
    } catch (e) {
      return ApiResponse<ChatConversationResponse>.error(
        'Unexpected error: $e',
      );
    }
  }

  @override
  Future<ApiResponse<MessageResponse>> sendMessage({
    required String toId,
    required String message,
    required bool isGroup,
    int isArchiveChat = 0,
    int messageType = 0,
    String? fileName,
    String? replyTo,
    int isMyContact = 1,
  }) async {
    try {
      final data = {
        'to_id': toId,
        'message': message,
        'is_archive_chat': isArchiveChat,
        'message_type': messageType,
        'file_name': fileName,
        'reply_to': replyTo,
        'is_my_contact': isMyContact,
        'is_group': isGroup ? 1 : 0,
      };

      // Remove null values
      data.removeWhere((key, value) => value == null);

      final response = await _dio.post(ApiUrls.sendMessage, data: data);

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          final messageData = MessageResponse.fromJson(response.data);
          return ApiResponse<MessageResponse>.success(
            messageData,
            message: messageData.message,
            statusCode: response.statusCode,
          );
        } else {
          return ApiResponse<MessageResponse>.error(
            response.data['message'] ?? 'Failed to send message',
          );
        }
      } else {
        return ApiResponse<MessageResponse>.error(
          response.data['message'] ?? 'Failed to send message',
        );
      }
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<MessageResponse>.error(networkException.message);
    } catch (e) {
      return ApiResponse<MessageResponse>.error('Unexpected error: $e');
    }
  }

  /// Send a file together with message fields to the send-message endpoint
  /// using multipart upload. This posts the file under key 'file'.
  Future<ApiResponse<MessageResponse>> sendFileMultipart({
    required String toId,
    required bool isGroup,
    required String filePath,
    int messageType = 1,
    String? message,
    String? replyTo,
    int isMyContact = 1,
    ProgressCallback? onSendProgress,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ApiResponse<MessageResponse>.error('File not found: $filePath');
      }

      // Ensure server receives a non-empty message string
      final inferredMessage = (message != null && message.trim().isNotEmpty)
          ? message.trim()
          : p.basename(filePath);

      // Build simple map of text fields; the DioClient.uploadFile helper
      // will attach the file for us and handle MIME/filename correctly.
      final formMap = <String, dynamic>{
        'to_id': toId,
        'is_group': isGroup ? 1 : 0,
        'message_type': messageType, // use 1 for attachments
        'message': inferredMessage,
        'file_name': p.basename(filePath),
        'is_my_contact': isMyContact,
        if (replyTo != null) 'reply_to': replyTo,
      };

      // Upload using DioClient.uploadFile which builds FormData and sends
      final response = await _dio.uploadFile(
        ApiUrls.sendMessage,
        filePath,
        data: formMap,
        onSendProgress: onSendProgress,
      );

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          final msgData = MessageResponse.fromJson(response.data);
          return ApiResponse<MessageResponse>.success(
            msgData,
            message: msgData.message,
            statusCode: response.statusCode,
          );
        } else {
          return ApiResponse<MessageResponse>.error(
            response.data['message'] ?? 'Failed to send file message',
          );
        }
      } else {
        return ApiResponse<MessageResponse>.error(
          response.data['message'] ?? 'Failed to send file message',
        );
      }
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<MessageResponse>.error(networkException.message);
    } catch (e) {
      return ApiResponse<MessageResponse>.error('Unexpected error: $e');
    }
  }

  @override
  Future<ApiResponse<MessageReadResponse>> markAsRead({
    required int userId,
    required String otherUserId,
    required bool isGroup,
  }) async {
    try {
      final response = await _dio.post(
        ApiUrls.readMessage,
        data: {
          'user_id': userId,
          'is_group': isGroup ? 1 : 0,
          'group_id': otherUserId,
        },
      );

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {

          final data = MessageReadResponse.fromJson(response.data);
          return ApiResponse<MessageReadResponse>.success(
            data,
            message: data.message,
            statusCode: response.statusCode,
          );
        } else {
          return ApiResponse<MessageReadResponse>.error(
            response.data['message'] ?? 'Failed to mark messages as read',
          );
        }
      } else {
        return ApiResponse<MessageReadResponse>.error(
          response.data['message'] ?? 'Failed to mark messages as read',
        );
      }
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<MessageReadResponse>.error(networkException.message);
    } catch (e) {
      return ApiResponse<MessageReadResponse>.error('Unexpected error: $e');
    }
  }
}
