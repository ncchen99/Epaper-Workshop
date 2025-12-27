import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Represents a selectable image (either preset or user-uploaded)
class SelectableImage {
  final int id;
  final String assetPath; // For preset images (display only)
  final File? file; // For uploaded images
  final bool isPreset;
  final bool isDemo; // Flag for demo images
  final int? slot; // Arduino slot (1, 2, or 3)

  const SelectableImage({
    required this.id,
    required this.assetPath,
    this.file,
    this.isPreset = true,
    this.isDemo = false,
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
    bool isDemo = false,
  }) {
    return SelectableImage(
      id: id,
      assetPath: '',
      file: file,
      isPreset: false,
      isDemo: isDemo,
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
    _initDemoImages();
  }

  /// Initialize with demo images loaded as files (same as user uploads)
  Future<void> _initDemoImages() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final List<SelectableImage> demoImages = [];

      // Load demo images from assets and save to temp files
      final demoAssets = [
        {'path': 'assets/images/demo_1.jpg', 'slot': 1},
        {'path': 'assets/images/demo_2.jpg', 'slot': 2},
      ];

      for (int i = 0; i < demoAssets.length; i++) {
        final assetPath = demoAssets[i]['path'] as String;
        final slot = demoAssets[i]['slot'] as int;

        // Load asset as bytes
        final byteData = await rootBundle.load(assetPath);
        final bytes = byteData.buffer.asUint8List();

        // Save to temp file
        final fileName = 'demo_$slot.jpg';
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsBytes(bytes);

        demoImages.add(
          SelectableImage.uploaded(
            id: i,
            file: tempFile,
            slot: slot,
            isDemo: true,
          ),
        );
      }

      state = state.copyWith(availableImages: demoImages);
    } catch (e) {
      // Fallback to empty state if loading fails
      debugPrint('Failed to load demo images: $e');
    }
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
