import 'package:dio/dio.dart';
import 'package:hsc_chat/cores/constants/api_urls.dart';
import 'package:hsc_chat/cores/network/api_response.dart';
import 'package:hsc_chat/cores/network/dio_client.dart';
import 'package:hsc_chat/cores/network/network_exceptions.dart';
import 'package:hsc_chat/feature/home/model/conversation_model.dart';
 
abstract class IConversationRepository {
  Future<ApiResponse<ConversationResponse>> getConversations({
    int page = 1,
    String query = '',
  });

  Future<ApiResponse<ConversationResponse>> getUnreadConversations({
    int page = 1,
    String query = '',
  });

  Future<ApiResponse<dynamic>> deleteConversation({
    required String conversationId,
  });

  //   Chat request methods
  Future<ApiResponse<dynamic>> acceptChatRequest({
    required String requestId,
  });

  Future<ApiResponse<dynamic>> declineChatRequest({
    required String requestId,
  });
}



class ConversationRepository implements IConversationRepository {
  final DioClient _dio;

  const ConversationRepository(this._dio);

  //   Accept chat request
  @override
  Future<ApiResponse<dynamic>> acceptChatRequest({
    required String requestId,
  }) async {
    try {
      final path = '${ApiUrls.baseUrl}messages/accept-chat-request';
      final response = await _dio.post(
        path,
        data: {'id': requestId},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>?;
        if (data != null && data['success'] == true) {
          return ApiResponse.success(
            data,
            message: data['message']?.toString() ?? 'Chat request accepted',
          );
        }
        return ApiResponse.error(
          data?['message']?.toString() ?? 'Failed to accept chat request',
        );
      }

      return ApiResponse.error(
        'Accept failed with status: ${response.statusCode}',
      );
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse.error(networkException.message);
    } catch (e) {
      return ApiResponse.error('Unexpected error: $e');
    }
  }

  //  Decline chat request
  @override
  Future<ApiResponse<dynamic>> declineChatRequest({
    required String requestId,
  }) async {
    try {
      final path = '${ApiUrls.baseUrl}messages/decline-chat-request';
      final response = await _dio.post(
        path,
        data: {'id': requestId},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>?;
        if (data != null && data['success'] == true) {
          return ApiResponse.success(
            data,
            message: data['message']?.toString() ?? 'Chat request declined',
          );
        }
        return ApiResponse.error(
          data?['message']?.toString() ?? 'Failed to decline chat request',
        );
      }

      return ApiResponse.error(
        'Decline failed with status: ${response.statusCode}',
      );
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse.error(networkException.message);
    } catch (e) {
      return ApiResponse.error('Unexpected error: $e');
    }
  }

  @override
  Future<ApiResponse<ConversationResponse>> getConversations({
    int page = 1,
    String query = '',
  }) async {
    try {

      final Map<String, dynamic> queryParams = {
        'page': page,
        'per_page': 10,
      };

      final Map<String, dynamic> requestData = {
        'page': page,
        'per_page': 10,
      };

      if (query.isNotEmpty) {
        queryParams['search'] = query;
        requestData['search'] = query;
      }

      final response = await _dio.post(
        ApiUrls.conversations,
        data: requestData,
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          final data = ConversationResponse.fromJson(response.data);
          return ApiResponse<ConversationResponse>.success(
            data,
            message: data.message,
            statusCode: response.statusCode,
          );
        } else {
          return ApiResponse<ConversationResponse>.error(
            response.data['message'] ?? 'Failed to load conversations',
          );
        }
      } else {
        return ApiResponse<ConversationResponse>.error(
          response.data['message'] ?? 'Failed to load conversations',
        );
      }
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<ConversationResponse>.error(networkException.message);
    } catch (e) {
      return ApiResponse<ConversationResponse>.error('Unexpected error: $e');
    }
  }

  @override
  Future<ApiResponse<ConversationResponse>> getUnreadConversations({
    int page = 1,
    String query = '',
  }) async {
    try {

      final Map<String, dynamic> queryParams = {
        'page': page,
        'per_page': 10,
      };

      if (query.isNotEmpty) {
        queryParams['search'] = query;
      }

      print('📍 Making unread request to: ${ApiUrls.unreadConversations}');
      print('🔍 Query Params: $queryParams');

      final response = await _dio.post(
        ApiUrls.unreadConversations,
        queryParameters: queryParams,
      );

      print('✅ Unread Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          final data = ConversationResponse.fromJson(response.data);
          print('✅ Parsed ${data.data.conversations.length} unread conversations');

          return ApiResponse<ConversationResponse>.success(
            data,
            message: data.message,
            statusCode: response.statusCode,
          );
        } else {
          return ApiResponse<ConversationResponse>.error(
            response.data['message'] ?? 'Failed to load unread conversations',
          );
        }
      } else {
        return ApiResponse<ConversationResponse>.error(
          response.data['message'] ?? 'Failed to load unread conversations',
        );
      }
    } on DioException catch (e) {
      print('❌ DioException (Unread): ${e.message}');
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse<ConversationResponse>.error(networkException.message);
    } catch (e) {
      print('❌ Exception (Unread): $e');
      return ApiResponse<ConversationResponse>.error('Unexpected error: $e');
    }
  }

  /// Delete a conversation by id (user or group). Endpoint: POST /messages/conversations/{id}/delete
  Future<ApiResponse<dynamic>> deleteConversation({
    required String conversationId,
  }) async {
    try {
      final path = '${ApiUrls.baseUrl}messages/conversations/$conversationId/delete';
      final response = await _dio.post(path);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>?;
        if (data != null && data['success'] == true) {
          return ApiResponse.success(data, message: data['message']?.toString());
        }
        return ApiResponse.error(data?['message']?.toString() ?? 'Failed to delete conversation');
      }
      return ApiResponse.error('Delete failed with status: ${response.statusCode}');
    } on DioException catch (e) {
      final networkException = NetworkExceptions.getDioException(e);
      return ApiResponse.error(networkException.message);
    } catch (e) {
      return ApiResponse.error('Unexpected error: $e');
    }
  }
}