import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/network/dio_client.dart';
import 'package:hec_chat/feature/auth/bloc/auth_session/auth_session_cubit.dart';
import 'package:hec_chat/feature/auth/bloc/sign_in/auth_signin_cubit.dart';
import 'package:hec_chat/feature/auth/repository/auth_repository.dart';
import 'package:hec_chat/feature/home/bloc/conversation_cubit.dart';
import 'package:hec_chat/feature/home/bloc/group_cubit.dart';
import 'package:hec_chat/feature/home/bloc/contacts_cubit.dart';
import 'package:hec_chat/feature/home/repository/chat_repository.dart';
import 'package:hec_chat/feature/home/repository/conversation_repository.dart';
import 'package:hec_chat/feature/home/repository/message_repository.dart';

class Providers {
  // Singletons
  static final DioClient _dioClient = DioClient();

  // Repositories
  static final AuthRepository _authRepository = AuthRepository(_dioClient);
  static final ConversationRepository _conversationRepository =
      ConversationRepository(_dioClient);
  static final MessageRepository _messageRepository = MessageRepository(
    _dioClient,
  );
  static final ChatRepository _chatRepository = ChatRepository(_dioClient);

  // Global BLoCs (single instance)
  static List<BlocProvider> get globalProviders => [
    BlocProvider<AuthSessionCubit>(create: (_) => AuthSessionCubit()),
    BlocProvider<AuthSignInCubit>(
      create: (_) => AuthSignInCubit(_authRepository),
    ),
    BlocProvider<ConversationCubit>(
      create: (_) => ConversationCubit(_conversationRepository),
    ),
    BlocProvider<MessageCubit>(
      create: (_) => MessageCubit(repository: _messageRepository),
    ),
    BlocProvider<GroupCubit>(create: (_) => GroupCubit(_messageRepository)),
  ];
}
