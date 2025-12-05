import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hec_chat/cores/constants/api_urls.dart';
import 'package:hec_chat/cores/network/api_response.dart';
import 'package:hec_chat/cores/network/dio_client.dart';
import 'package:hec_chat/cores/network/network_exceptions.dart';
import 'package:hec_chat/feature/home/model/chat_response_model.dart';
import 'package:hec_chat/cores/utils/file_validation.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

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

  // Multipart file upload helper for sending files with a message.
  Future<ApiResponse<MessageResponse>> sendFileMultipart({
    required String toId,
    required bool isGroup,
    required String filePath,
    int messageType = 1,
    String? message,
    String? replyTo,
    int isMyContact = 1,
    ProgressCallback? onSendProgress,
  });

  Future<ApiResponse<MessageReadResponse>> markAsRead({
    required int userId,
    required String otherUserId,
    required bool isGroup,
  });

  // Delete a single message from the current user's view.
  Future<ApiResponse<dynamic>> deleteMessageForMe({
    required String conversationId,
    required String previousMessageId,
  });

  // Delete a message for everyone in the conversation.
  Future<ApiResponse<dynamic>> deleteMessageForEveryone({
    required String conversationId,
    required String previousMessageId,
  });

  // Edit an existing message
  Future<ApiResponse<MessageResponse>> editMessage({
    required String messageId,
    required String newMessage,
  });

  //Reply to a message
  Future<ApiResponse<MessageResponse>> replyToMessage({
    required String conversationId,
    required String message,
    required String replyToMessageId,
    required String toId,
    required bool isGroup,
  });
}

class ChatRepository implements IChatRepository {
  final DioClient _dio;
  const ChatRepository(this._dio);

  @override
  Future<ApiResponse<MessageResponse>> editMessage({
    required String messageId,
    required String newMessage,
  }) async {
    try {
      final path = '${ApiUrls.baseUrl}/api/messages/$messageId/update';
      final response = await _dio.post(path, data: {'message': newMessage});

      if (response.statusCode == 200) {
        final respData = response.data;
        if (respData is Map<String, dynamic>) {
          if (respData['success'] == true) {
            // Wrap the response in expected format
            final wrappedResponse = {
              'success': true,
              'data': {'message': respData['message']},
              'message': 'Message updated successfully',
            };
            final messageData = MessageResponse.fromJson(wrappedResponse);
            return ApiResponse<MessageResponse>.success(
              messageData,
              message: 'Message updated successfully',
              statusCode: response.statusCode,
            );
          } else {
            return ApiResponse<MessageResponse>.error(
              respData['message']?.toString() ?? 'Failed to edit message',
            );
          }
        }
        return ApiResponse<MessageResponse>.error('Unexpected response format');
      }

      return ApiResponse<MessageResponse>.error(
        'Failed to edit message (status ${response.statusCode})',
      );
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<MessageResponse>.error(networkException.message);
    } catch (e) {
      return ApiResponse<MessageResponse>.error('Unexpected error: $e');
    }
  }

  @override
  Future<ApiResponse<MessageResponse>> replyToMessage({
    required String conversationId,
    required String message,
    required String replyToMessageId,
    required String toId,
    required bool isGroup,
  }) async {
    try {
      final path = '${ApiUrls.baseUrl}/api/messages/reply-message';
      final payload = {
        'conversation_id': conversationId,
        'message': message,
        'reply_to': replyToMessageId,
        'to_id': toId,
        'is_group': isGroup ? 1 : 0,
      };
      final response = await _dio.post(path, data: payload);

      print('🌐 API REQUEST to reply-message:');
      print('   Payload: $payload');
      if (response.statusCode == 200) {
        final respData = response.data;
        //  Log raw response
        print('🌐 API RAW RESPONSE:');
        print('   ${response.data}');
        if (respData is Map<String, dynamic>) {
          if (respData['success'] == true) {
            final messageData = MessageResponse.fromJson(respData);
            return ApiResponse<MessageResponse>.success(
              messageData,
              message: messageData.message,
              statusCode: response.statusCode,
            );
          } else {
            return ApiResponse<MessageResponse>.error(
              respData['message']?.toString() ?? 'Failed to send reply',
            );
          }
        }
        return ApiResponse<MessageResponse>.error('Unexpected response format');
      }

      return ApiResponse<MessageResponse>.error(
        'Failed to send reply (status ${response.statusCode})',
      );
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<MessageResponse>.error(networkException.message);
    } catch (e) {
      return ApiResponse<MessageResponse>.error('Unexpected error: $e');
    }
  }

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
        '${ApiUrls.baseUrl}/api/messages/$otherUserId/conversations',
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
        final respData = response.data;
        if (respData is Map<String, dynamic>) {
          if (respData['success'] == true) {
            final messageData = MessageResponse.fromJson(respData);
            return ApiResponse<MessageResponse>.success(
              messageData,
              message: messageData.message,
              statusCode: response.statusCode,
            );
          } else {
            // Return server-provided message if available (don't mask)
            final msg = respData['message']?.toString();
            final friendly = (msg != null && msg.isNotEmpty)
                ? msg
                : 'Failed to send message. Please try again.';
            return ApiResponse<MessageResponse>.error(friendly);
          }
        } else {
          // Non-JSON response — surface its string for debugging/user info
          final bodyStr =
              response.data?.toString() ?? 'Unexpected server response.';
          return ApiResponse<MessageResponse>.error(bodyStr);
        }
      } else {
        final respMsg =
            (response.data is Map && response.data['message'] != null)
            ? response.data['message'].toString()
            : (response.statusMessage ?? response.data?.toString());
        final friendly = (respMsg != null && respMsg.isNotEmpty)
            ? respMsg
            : 'Failed to send message (status ${response.statusCode}).';
        return ApiResponse<MessageResponse>.error(friendly);
      }
    } on DioException catch (e) {
      // Inspect response if present to present a friendly message for 5xx
      final status = e.response?.statusCode;
      if (status != null && status >= 500) {
        return ApiResponse<MessageResponse>.error(
          'Server error while sending message. Please try again later.',
        );
      }
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<MessageResponse>.error(networkException.message);
    } catch (e) {
      return ApiResponse<MessageResponse>.error(
        'Unexpected error: ${e.toString()}',
      );
    }
  }

  // using multipart upload. This posts the file under key 'file'.
  @override
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
        return ApiResponse<MessageResponse>.error('Selected file not found.');
      }

      // Extra safeguard: validate file on repository level so any caller that invokes this method cannot bypass client-side rules.
      final ext = p.extension(file.path).toLowerCase();
      FileCategory category = FileCategory.GENERIC;
      if ([
        '.png',
        '.jpg',
        '.jpeg',
        '.gif',
        '.webp',
        '.bmp',
        '.heic',
        '.heif',
      ].contains(ext)) {
        category = FileCategory.IMAGE;
      } else if ([
        '.mp4',
        '.mov',
        '.mkv',
        '.webm',
        '.avi',
        '.3gp',
      ].contains(ext))
        category = FileCategory.VIDEO;
      else if (ValidationRules.audioExt.contains(ext))
        category = FileCategory.AUDIO;
      else if (ValidationRules.docExt.contains(ext))
        category = FileCategory.DOCUMENT;

      final validation = await validateFileByCategory(file, category);
      if (!validation.isValid) {
        if (kDebugMode) {
          print(
            'Repository validation failed for $filePath: ${validation.message}',
          );
        }
        return ApiResponse<MessageResponse>.error(validation.message);
      }
      if (kDebugMode) {
        print(
          'Repository validation passed for $filePath (size=${validation.sizeBytes}, mime=${validation.mime})',
        );
      }

      // Ensure server receives a non-empty message string
      final inferredMessage = (message != null && message.trim().isNotEmpty)
          ? message.trim()
          : p.basename(filePath);

      // Build simple map of text fields; the DioClient.uploadFile helper will attach the file for us and handle MIME/filename correctly.
      final formMap = <String, dynamic>{
        'to_id': toId,
        'is_group': isGroup ? 1 : 0,
        'message_type': messageType, // use 1 for attachments
        'message': inferredMessage,
        'file_name': p.basename(filePath),
        'is_my_contact': isMyContact,
        if (replyTo != null) 'reply_to': replyTo,
      };

      if (kDebugMode) {
        print(
          '📤 Repository: starting upload to ${ApiUrls.sendMessage} for file: $filePath',
        );
      }
      // Upload using DioClient.uploadFile which builds FormData and sends
      final response = await _dio.uploadFile(
        ApiUrls.sendMessage,
        filePath,
        data: formMap,
        onSendProgress: onSendProgress,
      );
      if (kDebugMode) {
        print(
          'Repository: upload completed for file: $filePath status=${response.statusCode}',
        );
      }

      if (response.statusCode == 200) {
        final respData = response.data;
        if (respData is Map<String, dynamic>) {
          if (respData['success'] == true) {
            final msgData = MessageResponse.fromJson(respData);
            return ApiResponse<MessageResponse>.success(
              msgData,
              message: msgData.message,
              statusCode: response.statusCode,
            );
          } else {
            final msg = respData['message']?.toString();
            final friendly = (msg != null && msg.isNotEmpty)
                ? msg
                : 'Failed to send file. Please try again.';
            return ApiResponse<MessageResponse>.error(friendly);
          }
        } else {
          final bodyStr =
              response.data?.toString() ?? 'Unexpected server response.';
          return ApiResponse<MessageResponse>.error(bodyStr);
        }
      } else {
        final respMsg =
            (response.data is Map && response.data['message'] != null)
            ? response.data['message'].toString()
            : (response.statusMessage ?? response.data?.toString());
        final friendly = (respMsg != null && respMsg.isNotEmpty)
            ? respMsg
            : 'Failed to upload file (status ${response.statusCode}).';
        return ApiResponse<MessageResponse>.error(friendly);
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != null && status >= 500) {
        return ApiResponse<MessageResponse>.error(
          'Server error while uploading file. Please try again later.',
        );
      }
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<MessageResponse>.error(networkException.message);
    } catch (e) {
      return ApiResponse<MessageResponse>.error(
        'Unexpected error: ${e.toString()}',
      );
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

  @override
  Future<ApiResponse<dynamic>> deleteMessageForMe({
    required String conversationId,
    required String previousMessageId,
  }) async {
    try {
      final path =
          '${ApiUrls.baseUrl}/api/messages/conversations/message/$conversationId/delete';
      final response = await _dio.post(
        path,
        data: {'previousMessageId': previousMessageId},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>?;
        if (data != null && data['success'] == true) {
          return ApiResponse.success(
            data,
            message: data['message']?.toString(),
          );
        }
        return ApiResponse.error(
          data?['message']?.toString() ?? 'Failed to delete message',
        );
      }

      return ApiResponse.error(
        'Delete failed with status: ${response.statusCode}',
      );
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse.error(networkException.message);
    } catch (e) {
      return ApiResponse.error('Unexpected error: $e');
    }
  }

  @override
  Future<ApiResponse<dynamic>> deleteMessageForEveryone({
    required String conversationId,
    required String previousMessageId,
  }) async {
    try {
      final path =
          '${ApiUrls.baseUrl}/api/messages/conversations/$conversationId/delete-for-everyone';
      final response = await _dio.post(
        path,
        data: {'previousMessageId': previousMessageId},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>?;
        if (data != null && data['success'] == true) {
          return ApiResponse.success(
            data,
            message: data['message']?.toString(),
          );
        }
        return ApiResponse.error(
          data?['message']?.toString() ??
              'Failed to delete message for everyone',
        );
      }

      return ApiResponse.error(
        'Delete-for-everyone failed with status: ${response.statusCode}',
      );
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse.error(networkException.message);
    } catch (e) {
      return ApiResponse.error('Unexpected error: $e');
    }
  }
}
