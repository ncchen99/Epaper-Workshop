import 'dart:convert';

/// 代表一台已綁定的 E-Paper 裝置
class EpaperDevice {
  final String macAddress; // e.g., "AABBCC112233"
  final String? nickname; // 使用者自訂名稱
  final DateTime addedAt; // 綁定時間
  String? lastStatus; // 最後回報狀態
  String? lastStatusMessage; // 最後回報訊息
  DateTime? lastStatusAt; // 最後回報時間

  EpaperDevice({
    required String macAddress,
    this.nickname,
    DateTime? addedAt,
    this.lastStatus,
    this.lastStatusMessage,
    this.lastStatusAt,
  }) : macAddress = normalizeMac(macAddress),
       addedAt = addedAt ?? DateTime.now();

  /// 標準化 MAC（移除分隔符號、轉大寫）
  static String normalizeMac(String mac) {
    return mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();
  }

  /// 該裝置的 MQTT 指令 Topic
  String get cmdTopic => 'devices/$macAddress/cmd';

  /// 該裝置的 MQTT 狀態回報 Topic
  String get stateTopic => 'devices/$macAddress/state';

  /// 顯示用的名稱（優先使用暱稱）
  String get displayName => nickname ?? 'E-Paper $formattedMac';

  /// 格式化的 MAC（加入冒號分隔）
  String get formattedMac {
    if (macAddress.length != 12) return macAddress;
    final parts = <String>[];
    for (int i = 0; i < 12; i += 2) {
      parts.add(macAddress.substring(i, i + 2));
    }
    return parts.join(':');
  }

  /// 從 JSON map 反序列化
  factory EpaperDevice.fromJson(Map<String, dynamic> json) {
    return EpaperDevice(
      macAddress: json['macAddress'] as String,
      nickname: json['nickname'] as String?,
      addedAt:
          json['addedAt'] != null
              ? DateTime.parse(json['addedAt'] as String)
              : null,
      lastStatus: json['lastStatus'] as String?,
      lastStatusMessage: json['lastStatusMessage'] as String?,
      lastStatusAt:
          json['lastStatusAt'] != null
              ? DateTime.parse(json['lastStatusAt'] as String)
              : null,
    );
  }

  /// 序列化為 JSON map
  Map<String, dynamic> toJson() {
    return {
      'macAddress': macAddress,
      'nickname': nickname,
      'addedAt': addedAt.toIso8601String(),
      'lastStatus': lastStatus,
      'lastStatusMessage': lastStatusMessage,
      'lastStatusAt': lastStatusAt?.toIso8601String(),
    };
  }

  /// 從 JSON 字串反序列化
  factory EpaperDevice.fromJsonString(String jsonString) {
    return EpaperDevice.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  /// 序列化為 JSON 字串
  String toJsonString() => jsonEncode(toJson());

  /// 更新裝置狀態
  void updateStatus(String status, {String? message}) {
    lastStatus = status;
    lastStatusMessage = message;
    lastStatusAt = DateTime.now();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpaperDevice && macAddress == other.macAddress;

  @override
  int get hashCode => macAddress.hashCode;
}
