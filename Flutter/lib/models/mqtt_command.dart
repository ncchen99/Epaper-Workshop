import 'dart:convert';

/// Flutter → ESP32 的 MQTT 指令
class MqttCommand {
  final String action; // "update" | "show" | "clear"
  final String? imageUrl; // Cloudflare R2 公開 URL
  final int? slot; // 顯示插槽 (1, 2, 3)

  const MqttCommand({required this.action, this.imageUrl, this.slot});

  /// 建立圖片更新指令
  factory MqttCommand.update({required String imageUrl, int slot = 1}) {
    return MqttCommand(action: 'update', imageUrl: imageUrl, slot: slot);
  }

  /// 建立顯示快取圖片指令
  factory MqttCommand.show({int slot = 1}) {
    return MqttCommand(action: 'show', slot: slot);
  }

  /// 建立清除畫面指令
  factory MqttCommand.clear() {
    return const MqttCommand(action: 'clear');
  }

  /// 序列化為 JSON 字串（發送到 MQTT）
  String toJsonString() {
    final map = <String, dynamic>{'action': action};
    if (imageUrl != null) map['url'] = imageUrl;
    if (slot != null) map['slot'] = slot;
    return jsonEncode(map);
  }
}

/// ESP32 → Flutter 的狀態回報訊息
class DeviceStateMessage {
  final String mac; // 裝置 MAC
  final String status; // "online" | "downloading" | "decoding" | "displaying" | "success" | "error" | "busy"
  final String? message; // 附加訊息

  const DeviceStateMessage({
    required this.mac,
    required this.status,
    this.message,
  });

  /// 從 JSON 字串反序列化
  factory DeviceStateMessage.fromJsonString(String jsonString) {
    final map = jsonDecode(jsonString) as Map<String, dynamic>;
    return DeviceStateMessage(
      mac: map['mac'] as String? ?? '',
      status: map['status'] as String? ?? 'unknown',
      message: map['message'] as String?,
    );
  }

  /// 判斷是否為成功狀態
  bool get isSuccess => status == 'success';

  /// 判斷是否為錯誤狀態
  bool get isError => status == 'error';

  /// 判斷是否為進行中狀態
  bool get isInProgress =>
      status == 'downloading' ||
      status == 'decoding' ||
      status == 'displaying' ||
      status == 'queued';
}
