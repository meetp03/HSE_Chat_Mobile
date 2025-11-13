// screens/create_group_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hsc_chat/cores/constants/app_colors.dart';
import 'package:hsc_chat/feature/home/bloc/group_cubit.dart';
import 'package:hsc_chat/cores/utils/snackbar.dart';

class CreateGroupScreen extends StatefulWidget {
  final List<int> selectedUserIds;

  const CreateGroupScreen({Key? key, required this.selectedUserIds})
    : super(key: key);

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
        'Failed to pick image: $e',
        type: SnackBarType.error,
      );
    }
  }

  void _createGroup() {
    if (_formKey.currentState!.validate()) {
      if (widget.selectedUserIds.isEmpty) {
        showCustomSnackBar(
          context,
          'Please select at least one user',
          type: SnackBarType.error,
        );
        return;
      }

      context.read<GroupCubit>().createGroup(
        name: _nameController.text.trim(),
        members: widget.selectedUserIds,
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
            'Group created successfully',
            type: SnackBarType.success,
          );

          // Navigate back to home and refresh conversations
          Navigator.popUntil(context, (route) => route.isFirst);
        } else if (state is GroupError) {
          showCustomSnackBar(
            context,
            'Error: ${state.message}',
            type: SnackBarType.error,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Create Channel'),
          backgroundColor: AppClr.primaryColor,
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Group Image
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppClr.primaryColor, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: _selectedImagePath != null
                          ? FileImage(File(_selectedImagePath!))
                          : null,
                      child: _selectedImagePath == null
                          ? const Icon(
                              Icons.camera_alt,
                              size: 40,
                              color: Colors.grey,
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
                    labelText: 'Channel Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey, width: 1.5),
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
                      return 'Please enter channel name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Description
                TextFormField(
                  controller: _descriptionController,

                  decoration: InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.grey,
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
                    color: AppClr.primaryColor.withValues(
                      alpha: 0.15,
                    ), // light green transparent background
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppClr.primaryColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Icon(Icons.people, color: AppClr.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Selected Users: ${widget.selectedUserIds.length}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Spacer(),
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
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text(
                        'Create Channel',
                        style: TextStyle(fontSize: 16),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
