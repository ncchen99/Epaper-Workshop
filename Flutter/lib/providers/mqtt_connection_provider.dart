import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/mqtt_service.dart';

/// MQTT 連線狀態管理
class MqttConnectionState {
  final MqttConnectionStatus status;
  final String? errorMessage;
  final String? brokerHost;
  final int? brokerPort;

  const MqttConnectionState({
    this.status = MqttConnectionStatus.disconnected,
    this.errorMessage,
    this.brokerHost,
    this.brokerPort,
  });

  MqttConnectionState copyWith({
    MqttConnectionStatus? status,
    String? errorMessage,
    String? brokerHost,
    int? brokerPort,
  }) {
    return MqttConnectionState(
      status: status ?? this.status,
      errorMessage: errorMessage,
      brokerHost: brokerHost ?? this.brokerHost,
      brokerPort: brokerPort ?? this.brokerPort,
    );
  }

  bool get isConnected => status == MqttConnectionStatus.connected;
  bool get isConnecting => status == MqttConnectionStatus.connecting;
}

/// MQTT 連線管理 Notifier
class MqttConnectionNotifier extends StateNotifier<MqttConnectionState> {
  final MqttService _mqttService;
  StreamSubscription<MqttConnectionStatus>? _connectionSubscription;

  MqttConnectionNotifier(this._mqttService)
    : super(const MqttConnectionState()) {
    // 監聽連線狀態變化
    _connectionSubscription = _mqttService.connectionStream.listen((status) {
      if (!mounted) return;
      state = state.copyWith(
        status: status,
        errorMessage:
            status == MqttConnectionStatus.error
                ? _mqttService.lastError
                : null,
      );
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  /// 連線到 MQTT Broker
  Future<bool> connect(
    String host, {
    int port = 1883,
    List<String> fallbackHosts = const [],
  }) async {
    if (!mounted) return false;
    state = state.copyWith(
      status: MqttConnectionStatus.connecting,
      brokerHost: host,
      brokerPort: port,
    );

    final success = await _mqttService.connect(
      host,
      port: port,
      fallbackHosts: fallbackHosts,
    );

    if (!mounted) return false;

    if (!success) {
      state = state.copyWith(
        status: MqttConnectionStatus.error,
        errorMessage: _mqttService.lastError ?? 'Connection failed',
      );
    }

    return success;
  }

  /// 斷開連線
  void disconnect() {
    _mqttService.disconnect();
    state = const MqttConnectionState();
  }
}

/// MqttService 全域 Provider
final mqttServiceProvider = Provider<MqttService>((ref) {
  final service = MqttService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// MQTT 連線狀態 Provider
final mqttConnectionProvider =
    StateNotifierProvider<MqttConnectionNotifier, MqttConnectionState>((ref) {
      final mqttService = ref.watch(mqttServiceProvider);
      return MqttConnectionNotifier(mqttService);
    });
