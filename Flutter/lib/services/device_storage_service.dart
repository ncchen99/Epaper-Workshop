import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 裝置綁定本地儲存服務
///
/// 使用 SharedPreferences 將已綁定的裝置列表持久化儲存。
class DeviceStorageService {
  static const String _storageKey = 'bound_devices';

  /// 載入所有已綁定的裝置
  Future<List<EpaperDevice>> loadDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((json) => EpaperDevice.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('DeviceStorage: Failed to load devices: $e');
      return [];
    }
  }

  /// 儲存所有裝置（覆蓋）
  Future<void> _saveAll(List<EpaperDevice> devices) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = devices.map((d) => d.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('DeviceStorage: Failed to save devices: $e');
    }
  }

  /// 新增一台裝置
  Future<void> saveDevice(EpaperDevice device) async {
    final devices = await loadDevices();

    // 移除已存在的同 MAC 裝置（避免重複）
    devices.removeWhere((d) => d.macAddress == device.macAddress);
    devices.add(device);

    await _saveAll(devices);
    debugPrint('DeviceStorage: Saved device ${device.macAddress}');
  }

  /// 移除一台裝置
  Future<void> removeDevice(String macAddress) async {
    final devices = await loadDevices();
    devices.removeWhere((d) => d.macAddress == macAddress);
    await _saveAll(devices);
    debugPrint('DeviceStorage: Removed device $macAddress');
  }

  /// 更新裝置資訊
  Future<void> updateDevice(EpaperDevice device) async {
    final devices = await loadDevices();
    final index =
        devices.indexWhere((d) => d.macAddress == device.macAddress);
    if (index >= 0) {
      devices[index] = device;
      await _saveAll(devices);
    }
  }

  /// 清除所有裝置
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
