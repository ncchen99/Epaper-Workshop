import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';

/// MQTT 連線狀態
enum MqttConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// MQTT 核心服務
///
/// 封裝 mqtt_client 套件，提供連線/斷線/發布/訂閱功能。
/// 用於 Flutter App 與 MQTT Broker 的所有通訊。
class MqttService {
  MqttServerClient? _client;
  MqttConnectionStatus _connectionStatus = MqttConnectionStatus.disconnected;
  String? _lastError;

  // Stream controllers
  final _connectionController =
      StreamController<MqttConnectionStatus>.broadcast();
  final _stateMessageController =
      StreamController<DeviceStateMessage>.broadcast();

  // 追蹤已訂閱的 topics
  final Set<String> _subscribedTopics = {};

  /// 當前連線狀態
  MqttConnectionStatus get connectionStatus => _connectionStatus;

  /// 最後一次錯誤訊息
  String? get lastError => _lastError;

  /// 連線狀態 Stream
  Stream<MqttConnectionStatus> get connectionStream =>
      _connectionController.stream;

  /// 裝置狀態訊息 Stream
  Stream<DeviceStateMessage> get stateMessageStream =>
      _stateMessageController.stream;

  /// 是否已連線
  bool get isConnected => _connectionStatus == MqttConnectionStatus.connected;

  /// 連線到 MQTT Broker
  Future<bool> connect(String brokerHost, {int port = 1883}) async {
    // 如果已連線，先斷開
    if (_client != null && isConnected) {
      disconnect();
    }

    _updateStatus(MqttConnectionStatus.connecting);

    try {
      final clientId = 'flutter_epaper_${const Uuid().v4().substring(0, 8)}';

      _client = MqttServerClient(brokerHost, clientId)
        ..port = port
        ..keepAlivePeriod = 30
        ..autoReconnect = true
        ..resubscribeOnAutoReconnect = true
        ..onAutoReconnect = _onAutoReconnect
        ..onAutoReconnected = _onAutoReconnected
        ..onConnected = _onConnected
        ..onDisconnected = _onDisconnected
        ..logging(on: false)
        ..setProtocolV311();

      // 設定 Will Message（斷線時通知）
      final connMsgBuilder = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
      _client!.connectionMessage = connMsgBuilder;

      debugPrint('MQTT: Connecting to $brokerHost:$port...');

      await _client!.connect();

      if (_client!.connectionStatus?.state ==
          MqttConnectionState.connected) {
        _updateStatus(MqttConnectionStatus.connected);
        debugPrint('MQTT: Connected successfully');

        // 監聽所有收到的訊息
        _client!.updates?.listen(_onMessage);

        return true;
      } else {
        _lastError = 'Connection failed: ${_client!.connectionStatus}';
        _updateStatus(MqttConnectionStatus.error);
        return false;
      }
    } catch (e) {
      _lastError = e.toString();
      _updateStatus(MqttConnectionStatus.error);
      debugPrint('MQTT: Connection error: $e');
      return false;
    }
  }

  /// 斷開連線
  void disconnect() {
    _subscribedTopics.clear();
    _client?.disconnect();
    _client = null;
    _updateStatus(MqttConnectionStatus.disconnected);
    debugPrint('MQTT: Disconnected');
  }

  /// 發布指令到指定裝置
  Future<void> publishCommand(String macAddress, MqttCommand cmd) async {
    if (!isConnected || _client == null) {
      throw Exception('MQTT not connected');
    }

    final topic = 'devices/$macAddress/cmd';
    final payload = cmd.toJsonString();

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    debugPrint('MQTT: Published to $topic: $payload');
  }

  /// 訂閱裝置狀態 Topic
  void subscribeToDeviceState(String macAddress) {
    if (!isConnected || _client == null) return;

    final topic = 'devices/$macAddress/state';
    if (_subscribedTopics.contains(topic)) return;

    _client!.subscribe(topic, MqttQos.atLeastOnce);
    _subscribedTopics.add(topic);
    debugPrint('MQTT: Subscribed to $topic');
  }

  /// 取消訂閱裝置狀態 Topic
  void unsubscribeFromDeviceState(String macAddress) {
    if (_client == null) return;

    final topic = 'devices/$macAddress/state';
    if (!_subscribedTopics.contains(topic)) return;

    _client!.unsubscribe(topic);
    _subscribedTopics.remove(topic);
    debugPrint('MQTT: Unsubscribed from $topic');
  }

  // ---- 私有方法 ----

  void _updateStatus(MqttConnectionStatus status) {
    _connectionStatus = status;
    _connectionController.add(status);
  }

  void _onConnected() {
    debugPrint('MQTT: onConnected callback');
    _updateStatus(MqttConnectionStatus.connected);
  }

  void _onDisconnected() {
    debugPrint('MQTT: onDisconnected callback');
    if (_connectionStatus != MqttConnectionStatus.connecting) {
      _updateStatus(MqttConnectionStatus.disconnected);
    }
  }

  void _onAutoReconnect() {
    debugPrint('MQTT: Auto-reconnecting...');
    _updateStatus(MqttConnectionStatus.connecting);
  }

  void _onAutoReconnected() {
    debugPrint('MQTT: Auto-reconnected');
    _updateStatus(MqttConnectionStatus.connected);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage?>> messages) {
    for (final message in messages) {
      final topic = message.topic;
      final pubMessage = message.payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(pubMessage.payload.message);

      debugPrint('MQTT: Received [$topic]: $payload');

      // 解析狀態訊息
      if (topic.endsWith('/state')) {
        try {
          final stateMsg = DeviceStateMessage.fromJsonString(payload);
          _stateMessageController.add(stateMsg);
        } catch (e) {
          debugPrint('MQTT: Failed to parse state message: $e');
        }
      }
    }
  }

  /// 釋放資源
  void dispose() {
    disconnect();
    _connectionController.close();
    _stateMessageController.close();
  }
}
