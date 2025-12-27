import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'dart:io';

import '../theme/lego_theme.dart';
import '../widgets/widgets.dart';
import '../providers/providers.dart';
import '../services/services.dart';

/// Main home screen for the LEGO E-Paper Controller app.
///
/// Layout:
/// - Header: LegoTopBar with title and connection status
/// - Image Select: Grid of preset images
/// - Actions: Send, Upload, Reconnect buttons
/// - Log: Recent status messages
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final UploadService _uploadService = UploadService();

  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Check connection on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    ref.read(logProvider.notifier).info('Checking device connection...');
    await ref.read(deviceConnectionProvider.notifier).checkConnection();

    final status = ref.read(deviceConnectionProvider).status;
    if (status == ConnectionStatus.connected) {
      ref.read(logProvider.notifier).success('Device connected!');
    } else {
      ref.read(logProvider.notifier).warning('Device not found');
    }
  }

  Future<void> _sendToEPaper() async {
    final selectedImage = ref.read(imageSelectionProvider).selectedImage;

    if (selectedImage == null) {
      ref.read(logProvider.notifier).warning('Please select an image first');
      return;
    }

    setState(() => _isSending = true);
    ref.read(deviceConnectionProvider.notifier).setSending();
    ref.read(logProvider.notifier).info('Sending to E-Paper...');

    try {
      final slot = selectedImage.slot ?? 1;
      final arduinoService = ref.read(arduinoServiceProvider);

      // If it's an uploaded image, we need to upload first then update
      if (!selectedImage.isPreset && selectedImage.file != null) {
        ref.read(logProvider.notifier).info('Uploading image to cloud...');
        final uploadResult = await _uploadService.uploadImage(
          selectedImage.file!,
          slot,
        );

        if (!uploadResult.success) {
          throw Exception(uploadResult.error);
        }

        ref.read(logProvider.notifier).success('Upload complete!');

        // Now tell Arduino to update from cloud
        final result = await arduinoService.updateImage(slot);
        if (!result.success) {
          throw Exception(result.error);
        }
      } else {
        // For preset images, just show the existing slot
        final result = await arduinoService.showImage(slot);
        if (!result.success) {
          throw Exception(result.error);
        }
      }

      ref.read(deviceConnectionProvider.notifier).setConnected();
      ref.read(logProvider.notifier).success('E-Paper updated successfully!');
    } catch (e) {
      ref.read(deviceConnectionProvider.notifier).setError(e.toString());
      ref.read(logProvider.notifier).error('Failed: $e');
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _uploadPhoto() async {
    final source = await LegoBottomSheet.show(context);

    if (source == null) return;

    try {
      final pickerSource =
          source == ImageSource.camera
              ? picker.ImageSource.camera
              : picker.ImageSource.gallery;

      final pickedFile = await _imagePicker.pickImage(
        source: pickerSource,
        maxWidth: 800,
        maxHeight: 600,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        ref.read(imageSelectionProvider.notifier).addUploadedImage(file);
        ref.read(logProvider.notifier).success('Photo added!');
      }
    } catch (e) {
      ref.read(logProvider.notifier).error('Failed to pick image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(deviceConnectionProvider);
    final imageState = ref.watch(imageSelectionProvider);
    final logState = ref.watch(logProvider);

    return Scaffold(
      backgroundColor: LegoColors.backgroundLight,
      body: Column(
        children: [
          // Header
          LegoTopBar(
            title: 'LEGO E-Ink Controller',
            connectionStatus: connectionState.status,
          ),

          // Main content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(LegoSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Image Selection Area
                  _buildImageSelectionCard(imageState),

                  const SizedBox(height: LegoSpacing.md),

                  // Action Buttons
                  _buildActionsCard(),

                  const SizedBox(height: LegoSpacing.md),

                  // Log Area
                  _buildLogCard(logState),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSelectionCard(ImageSelectionState imageState) {
    return LegoCard(
      color: LegoColors.white,
      studCount: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Image',
            style: LegoTypography.titleMedium.copyWith(color: LegoColors.black),
          ),
          const SizedBox(height: LegoSpacing.sm),

          // Grid of images
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: LegoSpacing.sm,
              mainAxisSpacing: LegoSpacing.sm,
              childAspectRatio: 1.0,
            ),
            itemCount: imageState.availableImages.length,
            itemBuilder: (context, index) {
              final image = imageState.availableImages[index];
              final isSelected = imageState.selectedIndex == index;

              return LegoImageTile(
                image:
                    image.isPreset
                        ? AssetImage(image.assetPath)
                        : FileImage(image.file!) as ImageProvider,
                isSelected: isSelected,
                onTap: () {
                  ref.read(imageSelectionProvider.notifier).selectImage(index);
                },
                label: image.isPreset ? 'Demo ${image.slot}' : 'Uploaded',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    return LegoCard(
      color: LegoColors.backgroundGray,
      studCount: 4,
      child: Column(
        children: [
          LegoButton(
            label: 'Send to E-Ink',
            icon: Icons.send,
            type: LegoButtonType.primary,
            isLoading: _isSending,
            onPressed: _isSending ? null : _sendToEPaper,
          ),

          const SizedBox(height: LegoSpacing.md),

          LegoButton(
            label: 'Upload Photo',
            icon: Icons.add_photo_alternate,
            type: LegoButtonType.secondary,
            onPressed: _uploadPhoto,
          ),

          const SizedBox(height: LegoSpacing.md),

          LegoButton(
            label: 'Reconnect Device',
            icon: Icons.refresh,
            type: LegoButtonType.danger,
            onPressed: _checkConnection,
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(LogState logState) {
    return LegoCard(
      color: LegoColors.black,
      studCount: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terminal, color: LegoColors.green, size: 16),
              const SizedBox(width: LegoSpacing.xs),
              Text(
                'Status Log',
                style: LegoTypography.labelMedium.copyWith(
                  color: LegoColors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: LegoSpacing.sm),

          // Log entries
          if (logState.entries.isEmpty)
            Text(
              'No activity yet...',
              style: LegoTypography.bodyMedium.copyWith(
                color: LegoColors.white.withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              ),
            )
          else
            ...logState.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '[${entry.formattedTime}]',
                      style: LegoTypography.labelMedium.copyWith(
                        color: LegoColors.white.withValues(alpha: 0.6),
                        fontFamily: 'monospace',
                        fontSize: 8,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(width: LegoSpacing.xs),
                    Expanded(
                      child: Text(
                        entry.message,
                        style: LegoTypography.bodyMedium.copyWith(
                          color: _getLogColor(entry.level),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getLogColor(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return LegoColors.white;
      case LogLevel.success:
        return LegoColors.success;
      case LogLevel.warning:
        return LegoColors.warning;
      case LogLevel.error:
        return LegoColors.error;
    }
  }
}

/// Image picker instance
class ImagePicker {
  final picker.ImagePicker _picker = picker.ImagePicker();

  Future<picker.XFile?> pickImage({
    required picker.ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) {
    return _picker.pickImage(
      source: source,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
    );
  }
}
