// user_info_state.dart
import 'package:equatable/equatable.dart';
 import 'package:hec_chat/feature/home/model/common_groups_response.dart';

abstract class UserInfoState extends Equatable {
  const UserInfoState();
  @override
  List<Object?> get props => [];
}

class UserInfoInitial extends UserInfoState {}

class UserInfoLoading extends UserInfoState {}

class UserInfoLoaded extends UserInfoState {
  final List<GroupModel> groups;
  final bool isBlocked;

  const UserInfoLoaded({required this.groups, required this.isBlocked});

  @override
  List<Object?> get props => [groups, isBlocked];
}

class UserInfoError extends UserInfoState {
  final String message;
  const UserInfoError(this.message);

  @override
  List<Object?> get props => [message];
}