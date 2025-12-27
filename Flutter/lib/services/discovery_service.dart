import 'dart:async';
import 'package:nsd/nsd.dart' as nsd;
import '../config.dart';

/// Service for discovering Arduino E-Paper device via mDNS/DNS-SD.
///
/// Uses native Android NSD and iOS Bonjour APIs for reliable discovery.
class DiscoveryService {
  nsd.Discovery? _discovery;
  final List<nsd.Service> _discoveredServices = [];

  /// Stream controller for discovered devices
  final _servicesController = StreamController<List<nsd.Service>>.broadcast();

  /// Stream of discovered services
  Stream<List<nsd.Service>> get servicesStream => _servicesController.stream;

  /// Currently discovered services
  List<nsd.Service> get discoveredServices =>
      List.unmodifiable(_discoveredServices);

  /// Start discovering E-Paper devices on the network
  ///
  /// Looks for HTTP services advertised as "_http._tcp"
  Future<void> startDiscoveryProcess() async {
    // Stop any existing discovery
    await stopDiscoveryProcess();

    _discoveredServices.clear();

    try {
      _discovery = await nsd.startDiscovery('_http._tcp');

      _discovery!.addServiceListener((service, status) {
        // ignore: avoid_print
        print(
          'mDNS service ${status.name}: ${service.name} (${service.host}:${service.port})',
        );

        if (status == nsd.ServiceStatus.found) {
          // Check if this is our E-Paper device
          final name = service.name?.toLowerCase() ?? '';
          final host = service.host?.toLowerCase() ?? '';

          if (name.contains('epaper') || host.contains('epaper')) {
            // Avoid duplicates
            final exists = _discoveredServices.any(
              (s) => s.host == service.host && s.port == service.port,
            );

            if (!exists && service.host != null) {
              _discoveredServices.add(service);
              _servicesController.add(List.from(_discoveredServices));

              // ignore: avoid_print
              print(
                'Found E-Paper device: ${service.name} at ${service.host}:${service.port}',
              );
            }
          }
        } else if (status == nsd.ServiceStatus.lost) {
          _discoveredServices.removeWhere(
            (s) => s.host == service.host && s.port == service.port,
          );
          _servicesController.add(List.from(_discoveredServices));
        }
      });

      // ignore: avoid_print
      print('mDNS discovery started...');
    } catch (e) {
      // ignore: avoid_print
      print('Failed to start mDNS discovery: $e');
    }
  }

  /// Stop mDNS discovery
  Future<void> stopDiscoveryProcess() async {
    if (_discovery != null) {
      await nsd.stopDiscovery(_discovery!);
      _discovery = null;
    }
  }

  /// Get the best URL to connect to the Arduino
  ///
  /// Priority:
  /// 1. Discovered device via mDNS
  /// 2. Fallback IP address from config
  String? getArduinoUrl() {
    if (_discoveredServices.isNotEmpty) {
      final service = _discoveredServices.first;
      final host = service.host;
      final port = service.port ?? 80;

      if (host != null) {
        return 'http://$host:$port';
      }
    }

    // Fallback to configured IP
    return AppConfig.arduinoIpUrl;
  }

  /// Quick discovery - wait for device or timeout
  ///
  /// Returns the found URL or null if not found within timeout
  Future<String?> discoverDevice({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await startDiscoveryProcess();

    // Wait for discovery or timeout
    try {
      await servicesStream
          .where((services) => services.isNotEmpty)
          .first
          .timeout(timeout);

      return getArduinoUrl();
    } on TimeoutException {
      // ignore: avoid_print
      print('mDNS discovery timed out, using fallback IP');
      return AppConfig.arduinoIpUrl;
    } finally {
      await stopDiscoveryProcess();
    }
  }

  /// Dispose the service
  void dispose() {
    stopDiscoveryProcess();
    _servicesController.close();
  }
}
