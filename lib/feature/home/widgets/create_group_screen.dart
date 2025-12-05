import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hec_chat/cores/constants/app_colors.dart';
import 'package:hec_chat/cores/constants/app_strings.dart';
import 'package:hec_chat/feature/home/bloc/group_cubit.dart';
import 'package:hec_chat/cores/utils/snackbar.dart';
import '../../../cores/utils/shared_preferences.dart';

class CreateGroupScreen extends StatefulWidget {
  final List<int> selectedUserIds;

  const CreateGroupScreen({super.key, required this.selectedUserIds});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _selectedImagePath;
  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _selectedImagePath = image.path;
        });
      }
    } catch (e) {
      showCustomSnackBar(
        context,
        '${AppStrings.failedToPickImage}: $e',
        type: SnackBarType.error,
      );
    }
  }

  void _createGroup() {
    if (_formKey.currentState!.validate()) {
      if (widget.selectedUserIds.isEmpty) {
        showCustomSnackBar(
          context,
          AppStrings.selectAtLeastOneUser,
          type: SnackBarType.error,
        );
        return;
      }
      // Get current user ID and include it in members
      final currentUserId = SharedPreferencesHelper.getCurrentUserId();
      final allMembers = [...widget.selectedUserIds, currentUserId];

      context.read<GroupCubit>().createGroup(
        name: _nameController.text.trim(),
        members: allMembers,
        description: _descriptionController.text.trim(),
        photoPath: _selectedImagePath,
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<GroupCubit, GroupState>(
      listener: (context, state) {
        if (state is GroupCreated) {
          showCustomSnackBar(
            context,
            AppStrings.groupCreatedSuccessfully,
            type: SnackBarType.success,
          );

          // Navigate back to home and refresh conversations
          Navigator.popUntil(context, (route) => route.isFirst);
        } else if (state is GroupError) {
          showCustomSnackBar(
            context,
            '${AppStrings.error}: ${state.message}',
            type: SnackBarType.error,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.createChannel),
          backgroundColor: AppClr.primaryColor,
          foregroundColor: AppClr.white,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Group Image
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppClr.primaryColor,
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: AppClr.groupAvatarBackground,
                        backgroundImage: _selectedImagePath != null
                            ? FileImage(File(_selectedImagePath!))
                            : null,
                        child: _selectedImagePath == null
                            ? const Icon(
                                Icons.camera_alt,
                                size: 40,
                                color: AppClr.grey,
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Group Name
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: AppStrings.channelName,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppClr.grey, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppClr.primaryColor,
                          width: 2.0,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return AppStrings.enterChannelName;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: AppStrings.descriptionOptional,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppClr.grey,
                          width: 1.5,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppClr.primaryColor,
                          width: 2.0,
                        ),
                      ),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),

                  // Selected Users Count
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppClr.selectedUsersBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppClr.primaryColor, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Icon(
                          Icons.people,
                          color: AppClr.primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${AppStrings.selectedUsers}: ${widget.selectedUserIds.length}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppClr.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 100),

                  // Create Button
                  BlocBuilder<GroupCubit, GroupState>(
                    builder: (context, state) {
                      if (state is GroupCreating) {
                        return const CircularProgressIndicator();
                      }

                      return ElevatedButton(
                        onPressed: _createGroup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppClr.primaryColor,
                          foregroundColor: AppClr.white,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: const Text(
                          AppStrings.createChannel,
                          style: TextStyle(fontSize: 16),
                        ),
                      );
                    },
                  ),
                  const SizedBox(
                    height: 20,
                  ), // Added extra space at bottom for better scrolling
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
