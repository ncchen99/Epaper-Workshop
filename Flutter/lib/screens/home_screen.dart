import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'dart:async';
import 'dart:io';

import '../config.dart';
import '../theme/lego_theme.dart';
import '../widgets/widgets.dart';
import '../providers/providers.dart';
import '../services/services.dart';
import '../models/models.dart';
import 'device_manage_screen.dart';

/// Main home screen for the LEGO E-Paper Controller app (MQTT version).
///
/// Layout:
/// - Header: LegoTopBar with MQTT connection status
/// - Device Selector: Select target E-Paper device
/// - Image Select: Grid of preset images
/// - Actions: Send, Upload, Device Management buttons
/// - Log: Recent status messages
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final ImagePicker _imagePicker = ImagePicker();
  final R2UploadService _r2Service = R2UploadService();
  final ImageProcessorService _imageProcessor = ImageProcessorService();
  StreamSubscription<DeviceStateMessage>? _stateSub;

  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 啟動後自動連線 MQTT
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectMqtt();
    });
  }

  Future<void> _connectMqtt() async {
    ref.read(logProvider.notifier).info('Connecting to MQTT Broker...');

    final success = await ref
        .read(mqttConnectionProvider.notifier)
        .connect(
          AppConfig.mqttBrokerHost,
          port: AppConfig.mqttBrokerPort,
          fallbackHosts: AppConfig.mqttBrokerCandidates().skip(1).toList(),
        );

    if (!mounted) return;

    if (success) {
      ref.read(logProvider.notifier).success('MQTT Connected!');

      // 監聽裝置狀態訊息
      final mqttService = ref.read(mqttServiceProvider);
      _stateSub?.cancel();
      _stateSub = mqttService.stateMessageStream.listen((stateMsg) {
        if (!mounted) return;
        final deviceName = _resolveDeviceNameByMac(stateMsg.mac);
        final details = stateMsg.message?.trim();
        final statusText =
            details != null && details.isNotEmpty
                ? '$deviceName: ${stateMsg.status} ($details)'
                : '$deviceName: ${stateMsg.status}';
        if (stateMsg.isSuccess) {
          ref.read(logProvider.notifier).success(statusText);
        } else if (stateMsg.isError) {
          ref.read(logProvider.notifier).error(statusText);
        } else {
          ref.read(logProvider.notifier).info(statusText);
        }
      });
    } else {
      final error = ref.read(mqttConnectionProvider).errorMessage;
      ref.read(logProvider.notifier).error('MQTT Failed: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final mqttState = ref.read(mqttConnectionProvider);
      if (!mqttState.isConnected && !mqttState.isConnecting) {
        _connectMqtt();
      }
    }
  }

  Future<void> _sendToEPaper() async {
    // 檢查是否已連線 MQTT
    final mqttState = ref.read(mqttConnectionProvider);
    if (!mqttState.isConnected) {
      ref.read(logProvider.notifier).warning('MQTT not connected');
      return;
    }

    // 檢查是否已選擇裝置
    final deviceState = ref.read(deviceListProvider);
    final targetDevice = deviceState.selectedDevice;
    if (targetDevice == null) {
      ref.read(logProvider.notifier).warning('Please select a device first');
      return;
    }

    // 檢查是否已選擇圖片
    final selectedImage = ref.read(imageSelectionProvider).selectedImage;
    if (selectedImage == null) {
      ref.read(logProvider.notifier).warning('Please select an image first');
      return;
    }

    if (!mounted) return;
    setState(() => _isSending = true);
    await WidgetsBinding.instance.endOfFrame;
    ref.read(logProvider.notifier).info('Processing image...');

    try {
      final mqttService = ref.read(mqttServiceProvider);

      if (selectedImage.file != null) {
        // ---- 處理圖片 → 上傳 R2 → MQTT 發送 URL ----
        ref
            .read(logProvider.notifier)
            .info('Processing: rotate, resize, crop...');

        // Step 1: 圖片處理
        final processResult = await _imageProcessor.processImage(
          selectedImage.file!,
        );
        if (!mounted) return;
        if (!processResult.success || processResult.processedFile == null) {
          throw Exception(processResult.error ?? 'Image processing failed');
        }

        ref.read(logProvider.notifier).info('Uploading to Cloudflare R2...');

        // Step 2: 上傳到 R2
        final filename = R2UploadService.generateFilename(
          targetDevice.macAddress,
        );
        final imageUrl = await _r2Service.uploadImage(
          processResult.processedFile!,
          filename,
        );
        if (!mounted) return;

        ref.read(logProvider.notifier).info('Sending MQTT command...');

        // Step 3: MQTT 發送更新指令
        final cmd = MqttCommand.update(
          imageUrl: imageUrl,
          slot: selectedImage.slot ?? 1,
        );
        await mqttService.publishCommand(targetDevice.macAddress, cmd);
        if (!mounted) return;

        // 清理暫存檔
        try {
          await processResult.processedFile!.delete();
        } catch (_) {}

        ref
            .read(logProvider.notifier)
            .success('Sent to ${targetDevice.displayName}!');
      } else {
        // Preset 圖片 → 顯示快取
        ref.read(logProvider.notifier).info('Sending show command...');
        final cmd = MqttCommand.show(slot: selectedImage.slot ?? 1);
        await mqttService.publishCommand(targetDevice.macAddress, cmd);
        if (!mounted) return;
        ref.read(logProvider.notifier).success('Show command sent!');
      }
    } catch (e) {
      if (!mounted) return;
      ref.read(logProvider.notifier).error('Failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _uploadPhoto() async {
    final source = await LegoBottomSheet.show(context);
    if (!mounted || source == null) return;

    try {
      final pickerSource =
          source == ImageSource.camera
              ? picker.ImageSource.camera
              : picker.ImageSource.gallery;

      final pickedFile = await _imagePicker.pickImage(source: pickerSource);

      if (!mounted) return;

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        ref.read(logProvider.notifier).info('Photo added!');
        ref.read(imageSelectionProvider.notifier).addUploadedImage(file);
        ref
            .read(logProvider.notifier)
            .success('Photo ready! Tap "Send" to upload.');
      }
    } catch (e) {
      if (!mounted) return;
      ref.read(logProvider.notifier).error('Failed to pick image: $e');
    }
  }

  void _goToDeviceManage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeviceManageScreen()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mqttState = ref.watch(mqttConnectionProvider);
    final deviceState = ref.watch(deviceListProvider);
    final imageState = ref.watch(imageSelectionProvider);
    final logState = ref.watch(logProvider);

    return Scaffold(
      backgroundColor: LegoColors.backgroundLight,
      body: Column(
        children: [
          // Header
          LegoTopBar(
            title: 'LEGO E-Ink Controller',
            connectionStatus: _mapMqttStatus(mqttState.status),
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

                  // Device Selector
                  _buildDeviceSelectorCard(deviceState),

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

  /// 將 MQTT 狀態映射為 Widget 所需的 ConnectionStatus
  ConnectionStatus _mapMqttStatus(MqttConnectionStatus status) {
    switch (status) {
      case MqttConnectionStatus.connected:
        return ConnectionStatus.connected;
      case MqttConnectionStatus.connecting:
        return ConnectionStatus.sending;
      case MqttConnectionStatus.error:
        return ConnectionStatus.error;
      case MqttConnectionStatus.disconnected:
        return ConnectionStatus.disconnected;
    }
  }

  Widget _buildDeviceSelectorCard(DeviceListState deviceState) {
    return LegoCard(
      color: LegoColors.white,
      studCount: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Target Device',
                  style: LegoTypography.titleMedium.copyWith(
                    color: LegoColors.black,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: LegoSpacing.sm),
              GestureDetector(
                onTap: _goToDeviceManage,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.settings, size: 16, color: LegoColors.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Manage',
                        style: LegoTypography.labelMedium.copyWith(
                          color: LegoColors.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: LegoSpacing.sm),

          if (deviceState.devices.isEmpty)
            GestureDetector(
              onTap: _goToDeviceManage,
              child: Container(
                padding: const EdgeInsets.all(LegoSpacing.md),
                decoration: BoxDecoration(
                  color: LegoColors.backgroundGray,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: LegoColors.darkGray.withValues(alpha: 0.3),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      color: LegoColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Add your first device',
                        style: LegoTypography.bodyMedium.copyWith(
                          color: LegoColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...deviceState.devices.asMap().entries.map((entry) {
              final index = entry.key;
              final device = entry.value;
              return DeviceCard(
                device: device,
                isSelected: deviceState.selectedIndex == index,
                onTap: () {
                  ref.read(deviceListProvider.notifier).selectDevice(index);
                },
              );
            }),
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

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: LegoSpacing.md,
              mainAxisSpacing: LegoSpacing.md,
              childAspectRatio: 1,
            ),
            itemCount: imageState.availableImages.length,
            itemBuilder: (context, index) {
              final image = imageState.availableImages[index];
              final isSelected = imageState.selectedIndex == index;

              return LegoImageTile(
                image:
                    image.file != null
                        ? FileImage(image.file!) as ImageProvider
                        : AssetImage(image.assetPath),
                isSelected: isSelected,
                onTap: () {
                  ref.read(imageSelectionProvider.notifier).selectImage(index);
                },
                label: image.isDemo ? 'Demo ${image.slot}' : 'Uploaded',
                rotateLeft: false,
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
            label: 'Reconnect MQTT',
            icon: Icons.refresh,
            type: LegoButtonType.danger,
            onPressed: _connectMqtt,
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
                        fontSize: 10,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(width: LegoSpacing.xs),
                    Expanded(
                      child: Text(
                        entry.message,
                        style: LegoTypography.bodyMedium.copyWith(
                          color: _getLogColor(entry.level),
                          fontSize: 12,
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

  String _resolveDeviceNameByMac(String mac) {
    final normalizedMac = EpaperDevice.normalizeMac(mac);
    if (normalizedMac.isEmpty) {
      return 'Unknown Device';
    }

    final devices = ref.read(deviceListProvider).devices;
    for (final device in devices) {
      if (EpaperDevice.normalizeMac(device.macAddress) == normalizedMac) {
        return device.displayName;
      }
    }

    return 'Unknown Device';
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
