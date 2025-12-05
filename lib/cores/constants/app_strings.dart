class AppStrings {
  // Auth Screen Strings
  static const String appName = 'HEC Chat';
  static const String welcomeToHecChat = 'Welcome to HEC Chat';
  static const String signInToContinue = 'Sign in to continue';
  static const String email = 'Email';
  static const String pleaseEnterYourEmail = 'Please enter your email';
  static const String pleaseEnterValidEmail =
      'Please enter a valid email address';
  static const String password = 'Password';
  static const String pleaseEnterYourPassword = 'Please enter your password';
  static const String passwordMinLength =
      'Password must be at least 6 characters';
  static const String rememberMe = 'Remember me';
  static const String signIn = 'Sign In';
  static const String dontHaveAccount = 'Don\'t have an account? Sign Up';
  static const String loginError = 'Login Error';
  static const String ok = 'OK';

  // Chat Screen Strings
  static const String online = 'online';
  static const String offline = 'offline';
  static const String group = 'Group';
  static const String userInfo = 'User Info';
  static const String groupInfo = 'Group Info';
  static const String noMessagesYet = 'No messages yet';
  static const String startConversation =
      'Send a message to start the conversation';
  static const String typeMessage = 'Type a message...';
  static const String editMessage = 'Edit message...';
  static const String editMessageTitle = 'Edit message';
  static const String replyingTo = 'Replying to';
  static const String send = 'Send';
  static const String reply = 'Reply';
  static const String edit = 'Edit';
  static const String deleteForMe = 'Delete for me';
  static const String deleteForEveryone = 'Delete for everyone';
  static const String cancel = 'Cancel';
  static const String delete = 'Delete';
  static const String photo = '📷 Photo';
  static const String message = 'Message';
  static const String fileStoredLocally = 'File stored locally';
  static const String saveToGallery = 'Save to Gallery';
  static const String savedToGallery = 'Saved to gallery';
  static const String failedToSaveToGallery = 'Failed to save to gallery';
  static const String download = 'Download';
  static const String cancelDownload = 'Cancel download';
  static const String downloaded = 'Downloaded';
  static const String downloadFailed = 'Download failed: ';
  static const String downloadCancelled = 'Download cancelled';
  static const String tapToPlay = 'Tap to play';
  static const String tapToDownload = 'Tap to download';
  static const String downloading = 'Downloading';
  static const String videoNotAvailable = 'Video not available';
  static const String failedToOpenVideo = 'Failed to open video: ';
  static const String documentNotAvailable = 'Document not available';
  static const String failedToOpenDocument = 'Failed to open document: ';
  static const String noAppAvailable = 'No App Available';
  static const String noAppFound = 'No app found to open files.';
  static const String installAppMessage =
      'Please install an appropriate app from the app store.';
  static const String fileSavedAt = 'File saved at: ';
  static const String retry = 'Retry';
  static const String messageUpdated = 'Message updated';
  static const String messageDeleted = 'Message deleted';
  static const String messageDeletedForEveryone =
      'Message deleted for everyone';
  static const String deleteMessage = 'Delete message';
  static const String deleteForYouQuestion = 'Delete this message for you?';
  static const String deleteForEveryoneQuestion =
      'This will remove the message for all participants. Continue?';
  static const String confirmDelete = 'Delete';
  static const String you = 'You';

  // Chat Request Strings
  static const String chatRequest = 'Chat Request';
  static const String wantsToStartConversation =
      'wants to start a conversation with you.';
  static const String decline = 'Decline';
  static const String accept = 'Accept';
  static const String acceptChatRequest = 'Accept Chat Request';
  static const String declineChatRequest = 'Decline Chat Request';
  static const String areYouSureDecline =
      'Are you sure you want to decline the chat request from';
  static const String chatRequestAccepted = 'Chat request accepted';
  static const String chatRequestDeclined = 'Chat request declined';
  static const String failedToAcceptRequest = 'Failed to accept chat request';
  static const String failedToDeclineRequest = 'Failed to decline chat request';
  static const String invalidRequestId = 'Invalid request ID';

  // UserSelectionScreen Strings
  static const String selectUsersTitle = 'Select Users';
  static const String nextButton = 'Next';
  static const String searchUsersHint = 'Search users...';
  static const String selectedLabel = 'Selected:';
  static const String usersLabel = 'users';
  static const String clearAllButton = 'Clear All';
  static const String errorPrefix = 'Error';
  static const String retryButton = 'Retry';
  static const String noUsersFound = 'No users found';
  static const String noUsersFoundForQuery = 'No users found for';

  // Block Status Strings
  static const String messagingDisabledBlocked =
      'Messaging disabled – this user is blocked';
  static const String messagingDisabledYouBlocked =
      'Messaging disabled – you are blocked by this user';
  static const String acceptToStartMessaging =
      'Accept the chat request to start messaging';
  static const String waitingForAcceptance =
      'Waiting for to accept your request';
  static const String chatRequestDeclinedStatus =
      'Chat request has been declined';
  static const String cannotSendTogether =
      'Cannot send text and file together.';
  static const String selectedFileNotFound = 'Selected file not found.';
  static const String validationFailed =
      'Failed to validate file before upload.';
  static const String audioNotSupported =
      'Audio files are not supported here. Please select an image, video, or document.';
  static const String messageCannotBeEmpty = 'Message cannot be empty';
  static const String replyCannotBeEmpty = 'Reply cannot be empty';
  static const String logoutTitle = 'Logout';
  static const String logoutConfirmMessage = 'Are you sure you want to logout?';
  static const String results = 'results';
  static const String error = 'Error';
  static const String allChats = 'All Chats';
  static const String unreadChats = 'Unread Chats';
  static const String searchConversations = 'Search conversations...';
  static const String noResultsFound = 'No results found';
  static const String noConversationsYet = 'No conversations yet';
  static const String noMoreConversations = 'No more conversations';
  static const String deleteConversation = 'Delete Conversation';
  static const String deleteConversationConfirm =
      'Are you sure you want to delete this conversation?';
  static const String conversationDeleted = 'Conversation deleted';
  static const String conversationDeleteFailed =
      'Failed to delete conversation';
  static const String noMessages = 'No messages';

  // Error Messages
  static const String somethingWentWrong =
      'Something went wrong. Please try again.';
  static const String networkError =
      'Network error. Please check your connection.';
  static const String invalidCredentials = 'Invalid email or password';
  static const String serverError = 'Server error. Please try again later.';
  static const String notifications = 'Notifications';
  static const String noNotifications = 'No notifications';

  // Audio Player Strings
  static const String invalidAudioUrl = 'Invalid audio URL';
  static const String failedToLoadAudio = 'Failed to load audio';
  static const String errorLoadingAudio = 'Error loading audio';
  static const String speed = 'Speed: ';
  static const String playingFromLocalFile = 'Playing from local file';

  // Contacts Screen Strings
  static const String startNewConversation = 'Start New Conversation';
  static const String myContacts = 'My Contacts';
  static const String newConversation = 'New Conversation';
  static const String blockedUsers = 'Blocked Users';
  static const String searchContacts = 'Search contacts...';
  static const String searchUsers = 'Search users...';
  static const String searchBlockedUsers = 'Search blocked users...';
  static const String noContactsFoundFor = 'No contacts found for';
  static const String clearSearch = 'Clear Search';
  static const String noContactsYet = 'No contacts yet';
  static const String questionMark = '?';
  static const String noUsersFoundFor = 'No users found for';
  static const String noBlockedUsersFound = 'No blocked users found';
  static const String noBlockedUsersFoundFor = 'No blocked users found for';
  static const String unblock = 'UNBLOCK';
  static const String unblockUser = 'Unblock User';
  static const String unblockUserConfirm = 'Are you sure you want to unblock';
  static const String hasBeenUnblocked = 'has been unblocked';
  static const String failedToUnblock = 'Failed to unblock';
  static const String pleaseTryAgain = 'Please try again';
  static const String errorWhileUnblocking = 'Error while unblocking';
  static const String openingExistingConversation =
      'Opening existing conversation...';
  static const String chatRequestSent = 'Chat request sent';
  static const String failedToSendChatRequest = 'Failed to send chat request';

  // Group Screen Strings
  static const String createChannel = 'Create Channel';
  static const String failedToPickImage = 'Failed to pick image';
  static const String selectAtLeastOneUser = 'Please select at least one user';
  static const String groupCreatedSuccessfully = 'Group created successfully';
  static const String channelName = 'Channel Name';
  static const String enterChannelName = 'Please enter channel name';
  static const String descriptionOptional = 'Description (Optional)';
  static const String selectedUsers = 'Selected Users';

  // User Info Screen Strings
  static const String about = 'About';
  static const String noCommonGroups = 'No common groups';
  static const String commonGroups = 'Common Groups';
  static const String members = 'members';
  static const String channelInformation = 'Channel Information';
  static const String deleteChannel = 'Delete Channel';
  static const String deleteChannelConfirm =
      'Are you sure you want to delete this channel? This action cannot be undone.';
  static const String invalidGroupId = 'Invalid group id';
  static const String channelDeletedSuccessfully =
      'Channel deleted successfully';
  static const String failedToDeleteChannel = 'Failed to delete channel';
  static const String youAreBlocked = 'You are blocked';
  static const String blockedUserMessage =
      'This user has blocked you. You cannot send messages to them.';
  static const String blockUser = 'Block User';
  static const String blockUserDescription =
      'Block this user to stop receiving messages from them.';
  static const String blocked = 'Blocked';
  static const String notBlocked = 'Not Blocked';
  static const String userBlocked = 'User blocked';
  static const String userUnblocked = 'User unblocked';
  static const String failedTo = 'Failed to';
  static const String block = 'block';
  static const String user = 'user';
  static const String admin = 'Admin';
  static const String member = 'Member';
  static const String dismissAsAdmin = 'Dismiss as Admin';
  static const String removeMember = 'Remove Member';
  static const String makeAdmin = 'Make Admin';
  static const String dismiss = 'Dismiss';
  static const String remove = 'Remove';
  static const String anAdminQuestion = 'an admin?';
  static const String asAdminQuestion = 'as admin?';
  static const String fromThisChannelQuestion = 'from this channel?';
  static const String makeAdminConfirm = 'Are you sure you want to make';
  static const String dismissAsAdminConfirm =
      'Are you sure you want to dismiss';
  static const String removeMemberConfirm = 'Are you sure you want to remove';
  static const String isNowAnAdmin = 'is now an admin';
  static const String failedToMake = 'Failed to make';
  static const String adminLowercase = 'admin';
  static const String dismissedAsAdmin = 'dismissed as admin';
  static const String failedToDismiss = 'Failed to dismiss';
  static const String removedFromChannel = 'removed from channel';
  static const String failedToRemove = 'Failed to remove';
  static const String editGroup = 'Edit Group';
  static const String groupName = 'Group Name';
  static const String groupDescription = 'Group Description';
  static const String groupNameCannotBeEmpty = 'Group name cannot be empty';
  static const String groupUpdatedSuccessfully = 'Group updated successfully';
  static const String failedToUpdateGroup = 'Failed to update group';
  static const String errorUpdatingGroup = 'Error updating group';
  static const String saveChanges = 'Save Changes';
  static const String addMembers = 'Add Members';
  static const String noContactsAvailableToAdd = 'No contacts available to add';
  static const String membersAddedSuccessfully = 'Members added successfully';
  static const String failedToAddMembers = 'Failed to add members';
  static const String errorAddingMembers = 'Error adding members';
  static const String addSelectedMembers = 'Add Selected Members';

  // Dialog Titles
  static const String success = 'Success';
  static const String warning = 'Warning';
  static const String info = 'Information';

  // Placeholders
  static const String enterEmail = 'Enter your email';
  static const String enterPassword = 'Enter your password';
  static const String search = 'Search...';

  // Navigation Labels
  static const String home = 'Home';
  static const String profile = 'Profile';
  static const String settings = 'Settings';
  static const String logout = 'Logout';

  // Chat Strings
  static const String conversations = 'Conversations';
  static const String newChat = 'New Chat';

  // Empty States
  static const String noConversations = 'No conversations yet';
  static const String startNewChat = 'Start a new chat';

  // File Types
  static const String audio = 'Audio';
  static const String photoLabel = 'Photo';
}
