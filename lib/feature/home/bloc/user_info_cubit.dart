// user_info_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/feature/home/model/common_groups_response.dart';
import 'user_info_state.dart';
import 'package:hsc_chat/feature/home/repository/user_repository.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';

class UserInfoCubit extends Cubit<UserInfoState> {
  final UserRepository _repo;

  UserInfoCubit(this._repo) : super(UserInfoInitial());

  Future<void> loadUserInfo({required int otherUserId}) async {
    emit(UserInfoLoading());
    try {
      final currentUserId = SharedPreferencesHelper.getCurrentUserId();
      final List<GroupModel> groups = await _repo.fetchCommonGroups(
          currentUserId: currentUserId,
          otherUserId: otherUserId
      );

      emit(UserInfoLoaded(groups: groups, isBlocked: false));
    } catch (e) {
      emit(UserInfoError(e.toString()));
    }
  }

  Future<void> toggleBlock({
    required int otherUserId,
    required bool block
  }) async {
    if (state is! UserInfoLoaded) return;

    final currentState = state as UserInfoLoaded;
    emit(UserInfoLoading());

    try {
      final currentUserId = SharedPreferencesHelper.getCurrentUserId();
      final success = await _repo.blockUnblock(
          currentUserId: currentUserId,
          userId: otherUserId,
          isBlocked: block
      );

      if (!success) throw Exception('Failed to update block status');

      emit(UserInfoLoaded(
          groups: currentState.groups,
          isBlocked: block
      ));
    } catch (e) {
      emit(UserInfoError(e.toString()));
    }
  }

// In UserInfoCubit.dart - Update the deleteGroup method
  Future<bool> deleteGroup({
    required String groupId,
    required int otherUserId,
  }) async {
    try {
      print('🗑️ Deleting group: $groupId');

      final response = await _repo.deleteGroup(groupId);

      print('📦 Delete group response: ${response.success}');
      print('📦 Delete group message: ${response.message}');
      print('📦 Delete group data: ${response.data}');

      if (response.success) {
        print('✅ Group deleted successfully');
        return true;
      } else {
        print('❌ Group deletion failed: ${response.message}');
        return false;
      }
    } catch (e) {
      print('❌ Error deleting group: $e');
      return false;
    }
  }
}