import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/lego_status_chip.dart';
import '../services/arduino_service.dart';
import '../config.dart';

/// State for device connection
class DeviceConnectionState {
  final ConnectionStatus status;
  final String? errorMessage;
  final String? deviceUrl;

  const DeviceConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.errorMessage,
    this.deviceUrl,
  });

  DeviceConnectionState copyWith({
    ConnectionStatus? status,
    String? errorMessage,
    String? deviceUrl,
  }) {
    return DeviceConnectionState(
      status: status ?? this.status,
      errorMessage: errorMessage,
      deviceUrl: deviceUrl ?? this.deviceUrl,
    );
  }
}

/// Notifier for managing device connection state
class DeviceConnectionNotifier extends StateNotifier<DeviceConnectionState> {
  final ArduinoService _arduinoService;

  DeviceConnectionNotifier(this._arduinoService)
    : super(const DeviceConnectionState());

  /// Check connection to the Arduino device
  Future<void> checkConnection() async {
    state = state.copyWith(status: ConnectionStatus.sending);

    try {
      final isConnected = await _arduinoService.checkConnection();

      if (isConnected) {
        state = state.copyWith(
          status: ConnectionStatus.connected,
          deviceUrl: AppConfig.arduinoBaseUrl,
          errorMessage: null,
        );
      } else {
        state = state.copyWith(
          status: ConnectionStatus.disconnected,
          errorMessage: 'Device not responding',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Set status to sending (when making API calls)
  void setSending() {
    state = state.copyWith(status: ConnectionStatus.sending);
  }

  /// Set status to connected
  void setConnected() {
    state = state.copyWith(
      status: ConnectionStatus.connected,
      errorMessage: null,
    );
  }

  /// Set status to error
  void setError(String message) {
    state = state.copyWith(
      status: ConnectionStatus.error,
      errorMessage: message,
    );
  }

  /// Reset to disconnected state
  void disconnect() {
    state = const DeviceConnectionState();
  }
}

/// Provider for ArduinoService
final arduinoServiceProvider = Provider<ArduinoService>((ref) {
  return ArduinoService();
});

/// Provider for device connection state
final deviceConnectionProvider =
    StateNotifierProvider<DeviceConnectionNotifier, DeviceConnectionState>((
      ref,
    ) {
      final arduinoService = ref.watch(arduinoServiceProvider);
      return DeviceConnectionNotifier(arduinoService);
    });
