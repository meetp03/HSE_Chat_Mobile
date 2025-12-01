// user_info_cubit.dart
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/feature/home/model/common_groups_response.dart';
import 'package:hsc_chat/feature/home/model/chat_models.dart';
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

  Future<bool> makeAdmin({
    required String groupId,
    required int memberId,
  }) async {
    try {
      final resp = await _repo.makeAdmin(groupId: groupId, memberId: memberId);
      if (resp.success) {
        // Optionally update local state or refetch groups
        return true;
      }
      return false;
    } catch (e) {
      print('❌ makeAdmin error: $e');
      return false;
    }
  }

  Future<bool> dismissAdmin({
    required String groupId,
    required int memberId,
  }) async {
    try {
      final resp = await _repo.dismissAdmin(groupId: groupId, memberId: memberId);
      if (resp.success) return true;
      return false;
    } catch (e) {
      print('❌ dismissAdmin error: $e');
      return false;
    }
  }

  Future<bool> removeMember({
    required String groupId,
    required int memberId,
  }) async {
    try {
      final resp = await _repo.removeMember(groupId: groupId, memberId: memberId);
      if (resp.success) return true;
      return false;
    } catch (e) {
      print('❌ removeMember error: $e');
      return false;
    }
  }

  Future<ChatGroup?> updateGroup({
    required String groupId,
    required String name,
    required String description,
    required File? photo,
  }) async {
    try {
      final resp = await _repo.updateGroup(
        groupId: groupId,
        name: name,
        description: description,
        photo: photo,
      );
      if (resp.success && resp.data != null) {
        // Assuming resp.data is the updated group map
        return ChatGroup.fromJson(resp.data);
      }
      return null;
    } catch (e) {
      print('❌ updateGroup error: $e');
      return null;
    }
  }

  Future<bool> addMembers({
    required String groupId,
    required List<int> memberIds,
  }) async {
    try {
      final resp = await _repo.addMembers(groupId: groupId, memberIds: memberIds);
      return resp.success;
    } catch (e) {
      print('❌ addMembers error: $e');
      return false;
    }
  }
}