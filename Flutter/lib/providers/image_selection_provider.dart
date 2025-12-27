import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents a selectable image (either preset or user-uploaded)
class SelectableImage {
  final int id;
  final String assetPath; // For preset images
  final File? file; // For uploaded images
  final bool isPreset;
  final int? slot; // Arduino slot (1, 2, or 3)

  const SelectableImage({
    required this.id,
    required this.assetPath,
    this.file,
    this.isPreset = true,
    this.slot,
  });

  /// Create from asset path (preset images)
  factory SelectableImage.preset({
    required int id,
    required String assetPath,
    int? slot,
  }) {
    return SelectableImage(
      id: id,
      assetPath: assetPath,
      isPreset: true,
      slot: slot,
    );
  }

  /// Create from file (uploaded images)
  factory SelectableImage.uploaded({
    required int id,
    required File file,
    int? slot,
  }) {
    return SelectableImage(
      id: id,
      assetPath: '',
      file: file,
      isPreset: false,
      slot: slot,
    );
  }
}

/// State for image selection
class ImageSelectionState {
  final List<SelectableImage> availableImages;
  final int? selectedIndex;
  final bool isUploading;

  const ImageSelectionState({
    this.availableImages = const [],
    this.selectedIndex,
    this.isUploading = false,
  });

  SelectableImage? get selectedImage =>
      selectedIndex != null && selectedIndex! < availableImages.length
          ? availableImages[selectedIndex!]
          : null;

  ImageSelectionState copyWith({
    List<SelectableImage>? availableImages,
    int? selectedIndex,
    bool? isUploading,
    bool clearSelection = false,
  }) {
    return ImageSelectionState(
      availableImages: availableImages ?? this.availableImages,
      selectedIndex:
          clearSelection ? null : (selectedIndex ?? this.selectedIndex),
      isUploading: isUploading ?? this.isUploading,
    );
  }
}

/// Notifier for managing image selection
class ImageSelectionNotifier extends StateNotifier<ImageSelectionState> {
  ImageSelectionNotifier() : super(const ImageSelectionState()) {
    _initPresetImages();
  }

  /// Initialize with preset demo images
  void _initPresetImages() {
    state = state.copyWith(
      availableImages: [
        SelectableImage.preset(
          id: 0,
          assetPath: 'assets/images/demo_1.jpg',
          slot: 1,
        ),
        SelectableImage.preset(
          id: 1,
          assetPath: 'assets/images/demo_2.jpg',
          slot: 2,
        ),
      ],
    );
  }

  /// Select an image by index
  void selectImage(int index) {
    if (index >= 0 && index < state.availableImages.length) {
      state = state.copyWith(selectedIndex: index);
    }
  }

  /// Clear selection
  void clearSelection() {
    state = state.copyWith(clearSelection: true);
  }

  /// Add an uploaded image
  void addUploadedImage(File file, {int? slot}) {
    final newImage = SelectableImage.uploaded(
      id: state.availableImages.length,
      file: file,
      slot: slot ?? 3, // Default to slot 3 for uploaded images
    );

    final updatedImages = [...state.availableImages, newImage];
    state = state.copyWith(
      availableImages: updatedImages,
      selectedIndex: updatedImages.length - 1, // Auto-select the new image
    );
  }

  /// Set uploading state
  void setUploading(bool isUploading) {
    state = state.copyWith(isUploading: isUploading);
  }
}

/// Provider for image selection state
final imageSelectionProvider =
    StateNotifierProvider<ImageSelectionNotifier, ImageSelectionState>((ref) {
      return ImageSelectionNotifier();
    });
