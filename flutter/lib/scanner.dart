import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'domain.dart';

/// Registro central de dispositivos vistos, com expiração (TTL).
class DeviceRegistry extends ChangeNotifier {
  final Map<String, TrackedDevice> _devices = {};
  Timer? _tick;

  static const staleFade = Duration(seconds: 3);
  static const staleGone = Duration(seconds: 10);
  static const staleDrop = Duration(seconds: 30);

  DeviceRegistry() {
    // Notifica em cadência fixa: a UI anima suave sem rebuild por advertisement.
    _tick = Timer.periodic(const Duration(milliseconds: 400), (_) {
      _devices.removeWhere((_, d) => d.staleAfter(staleDrop));
      notifyListeners();
    });
  }

  List<TrackedDevice> get visible =>
      _devices.values.where((d) => !d.staleAfter(staleGone)).toList();

  TrackedDevice upsert(String id) =>
      _devices.putIfAbsent(id, () => TrackedDevice(id));

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}

enum ScannerState { idle, noPermission, bluetoothOff, scanning, unsupported }

/// Envolve o flutter_blue_plus: permissões, estado do adaptador e o scan
/// contínuo que alimenta o [DeviceRegistry].
class BleScanner {
  final DeviceRegistry registry;
  final state = ValueNotifier<ScannerState>(ScannerState.idle);
  StreamSubscription? _scanSub;
  StreamSubscription? _adapterSub;

  BleScanner(this.registry);

  Future<bool> requestPermissions() async {
    // Android 12+: BLUETOOTH_SCAN/CONNECT. Android <12: localização.
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final locOk =
        statuses[Permission.locationWhenInUse]?.isGranted ?? false;
    return scanOk || locOk;
  }

  Future<void> start() async {
    if (await FlutterBluePlus.isSupported == false) {
      state.value = ScannerState.unsupported;
      return;
    }
    if (!await requestPermissions()) {
      state.value = ScannerState.noPermission;
      return;
    }

    _adapterSub ??= FlutterBluePlus.adapterState.listen((s) {
      if (s == BluetoothAdapterState.on) {
        _beginScan();
      } else {
        state.value = ScannerState.bluetoothOff;
      }
    });

    final s = await FlutterBluePlus.adapterState.first;
    if (s != BluetoothAdapterState.on) {
      state.value = ScannerState.bluetoothOff;
      try {
        await FlutterBluePlus.turnOn(); // Android mostra o diálogo do sistema
      } catch (_) {/* usuário recusou; permanece bluetoothOff */}
    }
  }

  Future<void> _beginScan() async {
    if (FlutterBluePlus.isScanningNow) return;
    _scanSub ??= FlutterBluePlus.onScanResults.listen(_onResults,
        onError: (e) => debugPrint('scan error: $e'));
    await FlutterBluePlus.startScan(
      continuousUpdates: true,
      androidScanMode: AndroidScanMode.lowLatency,
      removeIfGone: null,
    );
    state.value = ScannerState.scanning;
  }

  void _onResults(List<ScanResult> results) {
    final t = DateTime.now();
    for (final r in results) {
      final d = registry.upsert(r.device.remoteId.str);
      final adv = r.advertisementData;
      if (adv.advName.isNotEmpty) d.advName = adv.advName;
      if (adv.txPowerLevel != null) d.txPower = adv.txPowerLevel!;
      if (adv.serviceUuids.isNotEmpty) {
        d.serviceUuids = adv.serviceUuids.map((g) => g.str).toList();
      }
      if (adv.manufacturerData.isNotEmpty) {
        d.companyId = adv.manufacturerData.keys.first;
      }
      d.connectable = adv.connectable;
      d.addSample(r.rssi, t);
    }
  }

  Future<void> stop() async {
    await FlutterBluePlus.stopScan();
    state.value = ScannerState.idle;
  }

  void dispose() {
    _scanSub?.cancel();
    _adapterSub?.cancel();
    stop();
  }
}
