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

  const CreateGroupScreen({
    Key? key,
    required this.selectedUserIds,
  }) : super(key: key);

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
      showCustomSnackBar(context, 'Failed to pick image: $e', type: SnackBarType.error);
    }
  }

  void _createGroup() {
    if (_formKey.currentState!.validate()) {
      if (widget.selectedUserIds.isEmpty) {
        showCustomSnackBar(context, 'Please select at least one user', type: SnackBarType.error);
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
          showCustomSnackBar(context, 'Group created successfully', type: SnackBarType.success);

          // Navigate back to home and refresh conversations
          Navigator.popUntil(context, (route) => route.isFirst);
        } else if (state is GroupError) {
          showCustomSnackBar(context, 'Error: ${state.message}', type: SnackBarType.error);
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
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: _selectedImagePath != null
                        ? FileImage(File(_selectedImagePath!))
                        : null,
                    child: _selectedImagePath == null
                        ? const Icon(Icons.camera_alt, size: 40, color: Colors.grey)
                        : null,
                  ),
                ),
                const SizedBox(height: 20),

                // Group Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Channel Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter group name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Description
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),

                // Selected Users Count
                Text(
                  'Selected Users: ${widget.selectedUserIds.length}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

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