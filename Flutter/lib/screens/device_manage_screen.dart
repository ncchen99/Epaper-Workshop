import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/lego_theme.dart';
import '../widgets/widgets.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import 'qr_scanner_screen.dart';

/// 裝置管理畫面
///
/// 功能：
/// - 顯示已綁定的裝置列表
/// - 手動輸入 MAC Address 新增裝置
/// - 滑動刪除裝置
class DeviceManageScreen extends ConsumerStatefulWidget {
  const DeviceManageScreen({super.key});

  @override
  ConsumerState<DeviceManageScreen> createState() => _DeviceManageScreenState();
}

class _DeviceManageScreenState extends ConsumerState<DeviceManageScreen> {
  final _macController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _macController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _addDevice() async {
    if (!_formKey.currentState!.validate()) return;

    final mac = _macController.text.trim();
    final nickname =
        _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim();

    await ref
        .read(deviceListProvider.notifier)
        .addDevice(mac, nickname: nickname);

    if (!mounted) return;

    _macController.clear();
    _nicknameController.clear();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('裝置 $mac 已新增'),
          backgroundColor: LegoColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _removeDevice(EpaperDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('移除裝置'),
            content: Text('確定要移除 ${device.displayName}？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: LegoColors.error),
                child: const Text('移除'),
              ),
            ],
          ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      await ref
          .read(deviceListProvider.notifier)
          .removeDevice(device.macAddress);
    }
  }

  Future<void> _scanQrCode() async {
    final scannedMac = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScannerScreen()));

    if (!mounted || scannedMac == null || scannedMac.isEmpty) return;

    _macController.text = scannedMac;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已掃描 MAC: $scannedMac，請輸入暱稱後新增裝置'),
        backgroundColor: LegoColors.info,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String? _validateMac(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '請輸入 MAC Address';
    }

    // 移除分隔符號
    final cleaned =
        value.trim().replaceAll(':', '').replaceAll('-', '').toUpperCase();

    if (cleaned.length != 12) {
      return 'MAC Address 必須是 12 位十六進位字元';
    }

    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(cleaned)) {
      return 'MAC Address 只能包含 0-9 和 A-F';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final deviceState = ref.watch(deviceListProvider);

    return Scaffold(
      backgroundColor: LegoColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          '裝置管理',
          style: LegoTypography.titleMedium.copyWith(color: LegoColors.white),
        ),
        backgroundColor: LegoColors.primary,
        iconTheme: const IconThemeData(color: LegoColors.white),
      ),
      body: Column(
        children: [
          // 新增裝置表單
          _buildAddDeviceForm(),

          const Divider(height: 1),

          // 裝置列表
          Expanded(child: _buildDeviceList(deviceState)),
        ],
      ),
    );
  }

  Widget _buildAddDeviceForm() {
    return Container(
      padding: const EdgeInsets.all(LegoSpacing.md),
      color: LegoColors.white,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '新增裝置',
              style: LegoTypography.titleMedium.copyWith(fontSize: 16),
            ),
            const SizedBox(height: LegoSpacing.sm),

            // MAC Address 輸入
            TextFormField(
              controller: _macController,
              decoration: InputDecoration(
                labelText: 'MAC Address',
                hintText: 'AA:BB:CC:11:22:33',
                prefixIcon: const Icon(Icons.wifi),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              textCapitalization: TextCapitalization.characters,
              validator: _validateMac,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
            const SizedBox(height: LegoSpacing.sm),

            // 暱稱輸入（選填）
            TextFormField(
              controller: _nicknameController,
              decoration: InputDecoration(
                labelText: '暱稱（選填）',
                hintText: '例如：客廳電子紙',
                prefixIcon: const Icon(Icons.label_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: LegoSpacing.md),

            LegoButton(
              label: '掃描 QR Code',
              icon: Icons.qr_code_scanner,
              type: LegoButtonType.secondary,
              onPressed: _scanQrCode,
            ),
            const SizedBox(height: LegoSpacing.sm),

            // 新增按鈕
            LegoButton(
              label: '新增裝置',
              icon: Icons.add,
              type: LegoButtonType.primary,
              onPressed: _addDevice,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(DeviceListState deviceState) {
    if (deviceState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (deviceState.devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices_other,
              size: 64,
              color: LegoColors.darkGray.withValues(alpha: 0.3),
            ),
            const SizedBox(height: LegoSpacing.md),
            Text(
              '尚未綁定任何裝置',
              style: LegoTypography.bodyMedium.copyWith(
                color: LegoColors.darkGray,
              ),
            ),
            const SizedBox(height: LegoSpacing.xs),
            Text(
              '請在上方輸入 ESP32 的 MAC Address',
              style: LegoTypography.bodyMedium.copyWith(
                color: LegoColors.darkGray.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(LegoSpacing.md),
      itemCount: deviceState.devices.length,
      itemBuilder: (context, index) {
        final device = deviceState.devices[index];
        return Dismissible(
          key: Key(device.macAddress),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: LegoColors.error,
            child: const Icon(Icons.delete, color: LegoColors.white),
          ),
          confirmDismiss: (_) async {
            await _removeDevice(device);
            return false; // We handle it manually
          },
          child: DeviceCard(
            device: device,
            isSelected: deviceState.selectedIndex == index,
            onTap: () {
              ref.read(deviceListProvider.notifier).selectDevice(index);
            },
            onDelete: () => _removeDevice(device),
          ),
        );
      },
    );
  }
}
