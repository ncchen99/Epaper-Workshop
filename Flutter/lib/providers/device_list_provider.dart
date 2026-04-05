import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'mqtt_connection_provider.dart';

/// 裝置列表狀態
class DeviceListState {
  final List<EpaperDevice> devices;
  final int? selectedIndex;
  final bool isLoading;

  const DeviceListState({
    this.devices = const [],
    this.selectedIndex,
    this.isLoading = false,
  });

  EpaperDevice? get selectedDevice =>
      selectedIndex != null && selectedIndex! < devices.length
          ? devices[selectedIndex!]
          : null;

  DeviceListState copyWith({
    List<EpaperDevice>? devices,
    int? selectedIndex,
    bool? isLoading,
    bool clearSelection = false,
  }) {
    return DeviceListState(
      devices: devices ?? this.devices,
      selectedIndex:
          clearSelection ? null : (selectedIndex ?? this.selectedIndex),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 裝置列表管理 Notifier
class DeviceListNotifier extends StateNotifier<DeviceListState> {
  final DeviceStorageService _storageService;
  final MqttService _mqttService;
  StreamSubscription? _stateSubscription;

  DeviceListNotifier(this._storageService, this._mqttService)
    : super(const DeviceListState()) {
    _loadDevices();
    _listenToStateMessages();
  }

  /// 從本地載入裝置
  Future<void> _loadDevices() async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true);
    final devices = await _storageService.loadDevices();
    if (!mounted) return;
    state = state.copyWith(
      devices: devices,
      isLoading: false,
      selectedIndex: devices.isNotEmpty ? 0 : null,
    );

    // 訂閱所有已綁定裝置的狀態 topic
    for (final device in devices) {
      _mqttService.subscribeToDeviceState(device.macAddress);
    }
  }

  /// 監聽裝置狀態訊息
  void _listenToStateMessages() {
    _stateSubscription = _mqttService.stateMessageStream.listen((stateMsg) {
      if (!mounted) return;
      // 找到對應的裝置並更新狀態
      final devices = List<EpaperDevice>.from(state.devices);
      final messageMac = EpaperDevice.normalizeMac(stateMsg.mac);
      final index = devices.indexWhere(
        (d) => EpaperDevice.normalizeMac(d.macAddress) == messageMac,
      );

      if (index >= 0) {
        devices[index].updateStatus(stateMsg.status, message: stateMsg.message);
        state = state.copyWith(devices: devices);
      }
    });
  }

  /// 新增裝置
  Future<void> addDevice(String macAddress, {String? nickname}) async {
    if (!mounted) return;
    // 標準化 MAC（移除冒號、轉大寫）
    final normalizedMac =
        macAddress.replaceAll(':', '').replaceAll('-', '').toUpperCase();

    // 檢查是否已存在
    if (state.devices.any((d) => d.macAddress == normalizedMac)) {
      debugPrint('DeviceList: Device $normalizedMac already exists');
      return;
    }

    final device = EpaperDevice(macAddress: normalizedMac, nickname: nickname);

    await _storageService.saveDevice(device);
    if (!mounted) return;

    final updatedDevices = [...state.devices, device];
    state = state.copyWith(
      devices: updatedDevices,
      selectedIndex: updatedDevices.length - 1,
    );

    // 訂閱該裝置的狀態
    _mqttService.subscribeToDeviceState(normalizedMac);

    debugPrint('DeviceList: Added device $normalizedMac');
  }

  /// 移除裝置
  Future<void> removeDevice(String macAddress) async {
    await _storageService.removeDevice(macAddress);
    if (!mounted) return;

    _mqttService.unsubscribeFromDeviceState(macAddress);

    final updatedDevices =
        state.devices.where((d) => d.macAddress != macAddress).toList();

    int? newSelectedIndex = state.selectedIndex;
    if (updatedDevices.isEmpty) {
      newSelectedIndex = null;
    } else if (newSelectedIndex != null &&
        newSelectedIndex >= updatedDevices.length) {
      newSelectedIndex = updatedDevices.length - 1;
    }

    state = state.copyWith(
      devices: updatedDevices,
      selectedIndex: newSelectedIndex,
    );

    debugPrint('DeviceList: Removed device $macAddress');
  }

  /// 選擇裝置
  void selectDevice(int index) {
    if (index >= 0 && index < state.devices.length) {
      state = state.copyWith(selectedIndex: index);
    }
  }

  /// 重新載入裝置列表
  Future<void> reload() async {
    if (!mounted) return;
    await _loadDevices();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    super.dispose();
  }
}

/// 裝置列表 Provider
final deviceListProvider =
    StateNotifierProvider<DeviceListNotifier, DeviceListState>((ref) {
      final storageService = DeviceStorageService();
      final mqttService = ref.watch(mqttServiceProvider);
      return DeviceListNotifier(storageService, mqttService);
    });
