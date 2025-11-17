// notification_state.dart
part of 'notification_cubit.dart';

abstract class NotificationState {}

class NotificationInitial extends NotificationState {}
class NotificationLoading extends NotificationState {}
class NotificationLoaded extends NotificationState {
  final NotificationsResponse response;
  NotificationLoaded({required this.response});
}
class NotificationError extends NotificationState {
  final String message;
  NotificationError(this.message);
}

