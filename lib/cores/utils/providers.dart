// providers.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/network/dio_client.dart';
import 'package:hsc_chat/cores/network/socket_service.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/feature/auth/bloc/auth_session/auth_session_cubit.dart';
import 'package:hsc_chat/feature/auth/bloc/sign_in/auth_signin_cubit.dart';
import 'package:hsc_chat/feature/auth/repository/auth_repository.dart';
import 'package:hsc_chat/feature/home/bloc/chat_cubit.dart';
import 'package:hsc_chat/feature/home/bloc/conversation_cubit.dart';
 import 'package:hsc_chat/feature/home/bloc/group_cubit.dart';
import 'package:hsc_chat/feature/home/bloc/messege_cubit.dart';
import 'package:hsc_chat/feature/home/repository/chat_repository.dart';
import 'package:hsc_chat/feature/home/repository/conversation_repository.dart';
import 'package:hsc_chat/feature/home/repository/message_repository.dart';

class Providers {
  // Singletons
  static final DioClient _dioClient = DioClient();
  static final SocketService _socketService = SocketService();

  // Repositories
  static final AuthRepository _authRepository = AuthRepository(_dioClient);
  static final ConversationRepository _conversationRepository = ConversationRepository(_dioClient);
  static final MessageRepository _messageRepository = MessageRepository(_dioClient);
  static final ChatRepository _chatRepository = ChatRepository(_dioClient);

  // Global BLoCs (single instance)
  static List<BlocProvider> get globalProviders => [
    BlocProvider<AuthSessionCubit>(
      create: (_) => AuthSessionCubit(_authRepository),
    ),
    BlocProvider<AuthSignInCubit>(
      create: (_) => AuthSignInCubit(_authRepository),
    ),
    BlocProvider<ConversationCubit>(
      create: (_) => ConversationCubit(_conversationRepository),
    ),
    BlocProvider<MessageCubit>(
      create: (_) => MessageCubit(
        repository: _messageRepository,
        userId: SharedPreferencesHelper.getCurrentUserId(),
      ),
    ),
    BlocProvider<GroupCubit>(
      create: (_) => GroupCubit(_messageRepository),
    ),
  ];

  // Factory for per-chat Cubit (created per screen)
  static ChatCubit createChatCubit() {
    return ChatCubit(
      chatRepository: _chatRepository,
      socketService: _socketService,
    );
  }
}