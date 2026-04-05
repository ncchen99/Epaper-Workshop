import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../config.dart';

/// MQTT 連線狀態
enum MqttConnectionStatus { disconnected, connecting, connected, error }

/// MQTT 核心服務
///
/// 封裝 mqtt_client 套件，提供連線/斷線/發布/訂閱功能。
/// 用於 Flutter App 與 MQTT Broker 的所有通訊。
class MqttService {
  MqttServerClient? _client;
  MqttConnectionStatus _connectionStatus = MqttConnectionStatus.disconnected;
  String? _lastError;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>?
  _updatesSubscription;
  bool _isDisposed = false;

  // Stream controllers
  final _connectionController =
      StreamController<MqttConnectionStatus>.broadcast();
  final _stateMessageController =
      StreamController<DeviceStateMessage>.broadcast();

  // 追蹤已訂閱的 topics
  final Set<String> _subscribedTopics = {};
  final Set<String> _desiredStateTopics = {};

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
  Future<bool> connect(
    String brokerHost, {
    int port = 1883,
    List<String> fallbackHosts = const [],
  }) async {
    if (_isDisposed) {
      _lastError = 'MQTT service disposed';
      return false;
    }

    // 如果已連線，先斷開
    if (_client != null && isConnected) {
      disconnect();
    }

    _updateStatus(MqttConnectionStatus.connecting);

    final candidates = <String>[brokerHost];
    for (final host in fallbackHosts) {
      if (!candidates.contains(host) && host.trim().isNotEmpty) {
        candidates.add(host);
      }
    }

    String? latestError;

    for (final host in candidates) {
      final clientId = 'flutter_epaper_${const Uuid().v4().substring(0, 8)}';
      String resolvedHost = host;

      try {
        resolvedHost = await _resolveBrokerHost(host);

        _client =
            MqttServerClient(resolvedHost, clientId)
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
        final connMsgBuilder =
            MqttConnectMessage().withClientIdentifier(clientId).startClean();
        _client!.connectionMessage = connMsgBuilder;

        debugPrint(
          'MQTT: Attempting candidate $host (resolved: $resolvedHost):$port, clientId: $clientId',
        );

        await _client!.connect().timeout(
          Duration(seconds: AppConfig.mqttConnectTimeoutSeconds),
        );

        if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
          _updateStatus(MqttConnectionStatus.connected);
          debugPrint('MQTT: Connected successfully with candidate $host');

          // 監聽所有收到的訊息
          await _updatesSubscription?.cancel();
          _updatesSubscription = _client!.updates?.listen(_onMessage);
          _resubscribeStateTopics();
          return true;
        }

        latestError =
            'Candidate $host failed: ${_client!.connectionStatus?.state} (${_client!.connectionStatus?.returnCode})';
        debugPrint('MQTT: $latestError');
      } catch (e, stackTrace) {
        latestError = 'Candidate $host failed (resolved: $resolvedHost): $e';
        debugPrint('MQTT: Connection error: $latestError');
        debugPrint('MQTT: StackTrace: $stackTrace');
      }

      try {
        _client?.disconnect();
      } catch (_) {}
      _client = null;
    }

    _lastError = latestError ?? 'Connection failed: no candidate succeeded';
    _updateStatus(MqttConnectionStatus.error);
    return false;
  }

  /// 斷開連線
  void disconnect() {
    _subscribedTopics.clear();
    _updatesSubscription?.cancel();
    _updatesSubscription = null;
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
    final topic = 'devices/$macAddress/state';
    _desiredStateTopics.add(topic);
    _subscribeTopicIfNeeded(topic);
  }

  /// 取消訂閱裝置狀態 Topic
  void unsubscribeFromDeviceState(String macAddress) {
    final topic = 'devices/$macAddress/state';
    _desiredStateTopics.remove(topic);

    if (_client == null) return;
    if (!_subscribedTopics.contains(topic)) return;

    _client!.unsubscribe(topic);
    _subscribedTopics.remove(topic);
    debugPrint('MQTT: Unsubscribed from $topic');
  }

  void _subscribeTopicIfNeeded(String topic) {
    if (!isConnected || _client == null) return;
    if (_subscribedTopics.contains(topic)) return;

    _client!.subscribe(topic, MqttQos.atLeastOnce);
    _subscribedTopics.add(topic);
    debugPrint('MQTT: Subscribed to $topic');
  }

  void _resubscribeStateTopics() {
    // Broker side subscriptions may be lost after reconnect; re-apply desired topics.
    _subscribedTopics.clear();
    for (final topic in _desiredStateTopics) {
      _subscribeTopicIfNeeded(topic);
    }
  }

  // ---- 私有方法 ----

  Future<String> _resolveBrokerHost(String brokerHost) async {
    if (!brokerHost.toLowerCase().endsWith('.local')) {
      return brokerHost;
    }

    // Android 上 multicast_dns 可能因 reusePort 限制失敗，直接交給系統 resolver。
    if (Platform.isAndroid) {
      return _resolveBySystemLookup(brokerHost);
    }

    final mdns = MDnsClient();
    try {
      await mdns.start();

      final ipv4 = mdns
          .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(brokerHost),
          )
          .first
          .timeout(Duration(seconds: AppConfig.mqttMdnsLookupTimeoutSeconds));
      try {
        final record = await ipv4;
        final ip = record.address.address;
        debugPrint('MQTT: mDNS resolved $brokerHost -> $ip');
        return ip;
      } on TimeoutException {
        debugPrint('MQTT: mDNS IPv4 lookup timeout for $brokerHost');
      } on StateError {
        debugPrint('MQTT: mDNS IPv4 no answer for $brokerHost');
      }

      final ipv6 = mdns
          .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv6(brokerHost),
          )
          .first
          .timeout(Duration(seconds: AppConfig.mqttMdnsLookupTimeoutSeconds));
      try {
        final record = await ipv6;
        final ip = record.address.address;
        debugPrint('MQTT: mDNS resolved $brokerHost -> $ip');
        return ip;
      } on TimeoutException {
        debugPrint('MQTT: mDNS IPv6 lookup timeout for $brokerHost');
      } on StateError {
        debugPrint('MQTT: mDNS IPv6 no answer for $brokerHost');
      }

      final fallback = await _resolveBySystemLookup(brokerHost);
      if (fallback != brokerHost) {
        return fallback;
      }

      debugPrint(
        'MQTT: mDNS lookup had no answer for $brokerHost, fallback to hostname',
      );
      return brokerHost;
    } on SocketException catch (e) {
      debugPrint('MQTT: mDNS lookup failed: $e');
      return _resolveBySystemLookup(brokerHost);
    } finally {
      mdns.stop();
    }
  }

  Future<String> _resolveBySystemLookup(String brokerHost) async {
    try {
      final lookup = await InternetAddress.lookup(
        brokerHost,
      ).timeout(Duration(seconds: AppConfig.mqttMdnsLookupTimeoutSeconds));
      if (lookup.isEmpty) {
        return brokerHost;
      }

      final sorted = _prioritizeAddresses(lookup);
      final selected = sorted
          .where((a) => !_isLoopbackOrLinkLocal(a))
          .cast<InternetAddress>()
          .firstWhere((_) => true, orElse: () => sorted.first);

      debugPrint(
        'MQTT: DNS fallback resolved $brokerHost -> ${selected.address} (candidates: ${sorted.map((a) => a.address).join(', ')})',
      );
      return selected.address;
    } on TimeoutException {
      debugPrint('MQTT: DNS fallback timeout for $brokerHost');
      return brokerHost;
    } catch (e) {
      debugPrint('MQTT: DNS fallback failed for $brokerHost: $e');
      return brokerHost;
    }
  }

  List<InternetAddress> _prioritizeAddresses(List<InternetAddress> addresses) {
    final unique = <String, InternetAddress>{};
    for (final address in addresses) {
      unique[address.address] = address;
    }

    final result = unique.values.toList();
    result.sort((a, b) => _addressPriority(a).compareTo(_addressPriority(b)));
    return result;
  }

  int _addressPriority(InternetAddress address) {
    if (address.isLoopback) {
      return 300;
    }
    if (_isLinkLocal(address)) {
      return 200;
    }
    if (address.type == InternetAddressType.IPv4) {
      return 0;
    }
    if (address.type == InternetAddressType.IPv6) {
      return 100;
    }
    return 150;
  }

  bool _isLoopbackOrLinkLocal(InternetAddress address) {
    return address.isLoopback || _isLinkLocal(address);
  }

  bool _isLinkLocal(InternetAddress address) {
    final raw = address.rawAddress;

    if (address.type == InternetAddressType.IPv4 && raw.length == 4) {
      // IPv4 link-local: 169.254.0.0/16
      return raw[0] == 169 && raw[1] == 254;
    }

    if (address.type == InternetAddressType.IPv6 && raw.length == 16) {
      // IPv6 link-local: fe80::/10
      return raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80;
    }

    return false;
  }

  void _updateStatus(MqttConnectionStatus status) {
    if (_isDisposed || _connectionController.isClosed) return;
    _connectionStatus = status;
    _connectionController.add(status);
  }

  void _onConnected() {
    debugPrint('MQTT: onConnected callback');
    _updateStatus(MqttConnectionStatus.connected);
  }

  void _onDisconnected() {
    debugPrint('MQTT: onDisconnected callback');
    _subscribedTopics.clear();
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
    _resubscribeStateTopics();
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage?>> messages) {
    if (_isDisposed || _stateMessageController.isClosed) return;

    for (final message in messages) {
      final topic = message.topic;
      final pubMessage = message.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        pubMessage.payload.message,
      );

      debugPrint('MQTT: Received [$topic]: $payload');

      // 解析狀態訊息
      if (topic.endsWith('/state')) {
        try {
          final topicMac = _extractMacFromStateTopic(topic);
          final stateMsg = DeviceStateMessage.fromJsonString(
            payload,
            fallbackMac: topicMac,
          );
          if (!_isDisposed && !_stateMessageController.isClosed) {
            _stateMessageController.add(stateMsg);
          }
        } catch (e) {
          debugPrint('MQTT: Failed to parse state message: $e');
        }
      }
    }
  }

  String _extractMacFromStateTopic(String topic) {
    final parts = topic.split('/');
    if (parts.length >= 3 && parts.first == 'devices') {
      return parts[1];
    }
    return '';
  }

  /// 釋放資源
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _subscribedTopics.clear();
    _updatesSubscription?.cancel();
    _updatesSubscription = null;

    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;

    if (!_connectionController.isClosed) {
      _connectionController.close();
    }
    if (!_stateMessageController.isClosed) {
      _stateMessageController.close();
    }
  }
}
