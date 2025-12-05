import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/feature/home/model/common_groups_response.dart';
import 'package:hec_chat/feature/home/model/chat_models.dart';
import 'user_info_state.dart';
import 'package:hec_chat/feature/home/repository/user_repository.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';

class UserInfoCubit extends Cubit<UserInfoState> {
  final UserRepository _repo;

  UserInfoCubit(this._repo) : super(UserInfoInitial());

  Future<void> loadUserInfo({required int otherUserId}) async {
    emit(UserInfoLoading());
    try {
      final currentUserId = SharedPreferencesHelper.getCurrentUserId();
      final List<GroupModel> groups = await _repo.fetchCommonGroups(
        currentUserId: currentUserId,
        otherUserId: otherUserId,
      );

      emit(UserInfoLoaded(groups: groups, isBlocked: false));
    } catch (e) {
      emit(UserInfoError(e.toString()));
    }
  }

  Future<void> toggleBlock({
    required int otherUserId,
    required bool block,
  }) async {
    if (state is! UserInfoLoaded) return;

    final currentState = state as UserInfoLoaded;
    emit(UserInfoLoading());

    try {
      final currentUserId = SharedPreferencesHelper.getCurrentUserId();
      final success = await _repo.blockUnblock(
        currentUserId: currentUserId,
        userId: otherUserId,
        isBlocked: block,
      );

      if (!success) throw Exception('Failed to update block status');

      emit(UserInfoLoaded(groups: currentState.groups, isBlocked: block));
    } catch (e) {
      emit(UserInfoError(e.toString()));
    }
  }

  Future<bool> deleteGroup({
    required String groupId,
    required int otherUserId,
  }) async {
    try {
      final response = await _repo.deleteGroup(groupId);

      if (response.success) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
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
      if (kDebugMode) {
        print('makeAdmin error: $e');
      }
      return false;
    }
  }

  Future<bool> dismissAdmin({
    required String groupId,
    required int memberId,
  }) async {
    try {
      final resp = await _repo.dismissAdmin(
        groupId: groupId,
        memberId: memberId,
      );
      if (resp.success) return true;
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('dismissAdmin error: $e');
      }
      return false;
    }
  }

  Future<bool> removeMember({
    required String groupId,
    required int memberId,
  }) async {
    try {
      final resp = await _repo.removeMember(
        groupId: groupId,
        memberId: memberId,
      );
      if (resp.success) return true;
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('removeMember error: $e');
      }
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
        return ChatGroup.fromJson(resp.data);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('updateGroup error: $e');
      }
      return null;
    }
  }

  Future<bool> addMembers({
    required String groupId,
    required List<int> memberIds,
  }) async {
    try {
      final resp = await _repo.addMembers(
        groupId: groupId,
        memberIds: memberIds,
      );
      return resp.success;
    } catch (e) {
      if (kDebugMode) {
        print('addMembers error: $e');
      }
      return false;
    }
  }
}
