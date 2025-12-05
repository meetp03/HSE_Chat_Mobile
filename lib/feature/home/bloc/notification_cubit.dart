import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/network/api_response.dart';
import 'package:hec_chat/feature/home/model/notification_model.dart';
import 'package:hec_chat/feature/home/repository/notification_repository.dart';
part 'notification_state.dart';

class NotificationCubit extends Cubit<NotificationState> {
  final NotificationRepository _repo;

  NotificationCubit(this._repo) : super(NotificationInitial());

  Future<void> loadNotifications({int page = 1, int perPage = 5}) async {
    emit(NotificationLoading());
    try {
      final ApiResponse<NotificationsResponse> resp = await _repo.getNotifications(page: page, perPage: perPage);
      if (!resp.success || resp.data == null) {
        emit(NotificationError(resp.message ?? 'Failed to load notifications'));
        return;
      }
      emit(NotificationLoaded(response: resp.data!));
    } catch (e) {
      emit(NotificationError(e.toString()));
    }
  }
}

