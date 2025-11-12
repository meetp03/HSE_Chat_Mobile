import 'package:dio/dio.dart';
import 'package:hsc_chat/cores/constants/api_urls.dart';
import 'package:hsc_chat/cores/network/api_response.dart';
import 'package:hsc_chat/cores/network/dio_client.dart';
import 'package:hsc_chat/cores/network/network_exceptions.dart';
import '../model/auth_model.dart';

abstract class IAuthRepository {
  Future<ApiResponse<LoginResponse>> login(LoginRequest request);
}

class AuthRepository implements IAuthRepository {
  final DioClient _dioClient;

  const AuthRepository(this._dioClient);

  @override
  Future<ApiResponse<LoginResponse>> login(LoginRequest request) async {
    try {
      final response = await _dioClient.post(
        ApiUrls.baseUrlForLogin,
        data: request.toJson(),
      );

      if (response.statusCode == 401) {
        return ApiResponse.error('Invalid email or password', statusCode: 401);
      }

      if (response.statusCode == 200) {
         final loginResponse = LoginResponse.fromJson(response.data);
        return ApiResponse.success(
          loginResponse,
          message: loginResponse.message,
          statusCode: response.statusCode,
        );
      } else {
        return ApiResponse.error(
          response.data['message'] ?? 'Login failed',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return ApiResponse.error('Invalid email or password', statusCode: 401);
      }
      return ApiResponse.error(NetworkExceptions.getDioException(e).message);
    } catch (e) {
      return ApiResponse.error('An unexpected error occurred');
    }
  }
}
