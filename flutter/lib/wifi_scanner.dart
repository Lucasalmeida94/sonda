import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

import 'domain.dart';
import 'scanner.dart';

enum WifiState { off, noPermission, noLocationService, scanning, unsupported }

/// Camada complementar de sinal (Android): redes Wi-Fi entram no radar como
/// categoria Rede, com o mesmo pipeline de distância (Kalman + log-distance).
///
/// O Android 9+ limita `startScan` a ~4 chamadas por 2 minutos em foreground,
/// então o scan ativo roda a cada 35 s; entre eles, uma leitura passiva
/// aproveita resultados de scans feitos pelo sistema ou por outros apps.
class WifiScanner {
  final DeviceRegistry registry;
  final state = ValueNotifier<WifiState>(WifiState.off);

  Timer? _active;
  Timer? _passive;
  StreamSubscription<List<WiFiAccessPoint>>? _sub;

  /// Potência típica de um AP medida a 1 m (mais forte que periférico BLE).
  static const _txPowerAt1m = -45;

  WifiScanner(this.registry);

  bool get running => state.value == WifiState.scanning;

  Future<bool> start() async {
    if (!Platform.isAndroid) {
      state.value = WifiState.unsupported;
      return false;
    }
    // Resultados de scan Wi-Fi são gated por localização em todas as versões.
    final loc = await Permission.locationWhenInUse.request();
    if (!loc.isGranted) {
      state.value = WifiState.noPermission;
      return false;
    }
    final can =
        await WiFiScan.instance.canGetScannedResults(askPermissions: true);
    switch (can) {
      case CanGetScannedResults.yes:
        break;
      case CanGetScannedResults.noLocationServiceDisabled:
        state.value = WifiState.noLocationService;
        return false;
      case CanGetScannedResults.noLocationPermissionRequired:
      case CanGetScannedResults.noLocationPermissionDenied:
      case CanGetScannedResults.noLocationPermissionUpgradeAccuracy:
        state.value = WifiState.noPermission;
        return false;
      default:
        state.value = WifiState.unsupported;
        return false;
    }

    _sub ??= WiFiScan.instance.onScannedResultsAvailable.listen(_onResults,
        onError: (e) => debugPrint('wifi scan error: $e'));
    await _requestScan();
    _active ??=
        Timer.periodic(const Duration(seconds: 35), (_) => _requestScan());
    _passive ??= Timer.periodic(const Duration(seconds: 10), (_) async {
      _onResults(await WiFiScan.instance.getScannedResults());
    });
    state.value = WifiState.scanning;
    return true;
  }

  Future<void> _requestScan() async {
    // Respeita o throttling: só dispara se o sistema permitir agora.
    if (await WiFiScan.instance.canStartScan() == CanStartScan.yes) {
      await WiFiScan.instance.startScan();
    }
  }

  void _onResults(List<WiFiAccessPoint> aps) {
    if (!running) return;
    final t = DateTime.now();
    for (final ap in aps) {
      if (ap.bssid.isEmpty) continue;
      final d = registry.upsert('wifi:${ap.bssid.toUpperCase()}',
          source: SignalSource.wifi, txPower: _txPowerAt1m);
      if (ap.ssid.isNotEmpty) d.advName = ap.ssid;
      d.wifiInfo = '${_band(ap.frequency)} · ${_security(ap.capabilities)}';
      d.addSample(ap.level, t);
    }
  }

  static String _band(int freqMhz) {
    if (freqMhz >= 5925) return '6 GHz';
    if (freqMhz >= 4900) return '5 GHz';
    return '2,4 GHz';
  }

  static String _security(String caps) {
    if (caps.contains('WPA3') || caps.contains('SAE')) return 'WPA3';
    if (caps.contains('WPA2')) return 'WPA2';
    if (caps.contains('WPA')) return 'WPA';
    if (caps.contains('WEP')) return 'WEP';
    return 'aberta';
  }

  void stop() {
    _active?.cancel();
    _passive?.cancel();
    _active = null;
    _passive = null;
    state.value = WifiState.off;
  }

  void dispose() {
    stop();
    _sub?.cancel();
  }
}
