import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Filtro de Kalman 1D para suavizar o RSSI (flutua ±10 dBm mesmo parado).
class RssiKalmanFilter {
  double _estimate = -70;
  double _errorCov = 1.0;
  final double processNoise;
  final double measurementNoise;

  RssiKalmanFilter({this.processNoise = 0.008, this.measurementNoise = 4.0});

  double update(int rssiRaw) {
    _errorCov += processNoise;
    final gain = _errorCov / (_errorCov + measurementNoise);
    _estimate += gain * (rssiRaw - _estimate);
    _errorCov *= (1 - gain);
    return _estimate;
  }
}

enum ProximityBucket { immediate, near, far }

extension ProximityBucketX on ProximityBucket {
  String get labelPT => switch (this) {
        ProximityBucket.immediate => 'Muito perto',
        ProximityBucket.near => 'Próximo',
        ProximityBucket.far => 'Distante',
      };
}

ProximityBucket bucketFor(double rssi) {
  if (rssi > -50) return ProximityBucket.immediate;
  if (rssi >= -70) return ProximityBucket.near;
  return ProximityBucket.far;
}

/// d = 10 ^ ((A - RSSI) / (10 * n)) — modelo log-distance.
double rssiToMeters(double rssi, {int txPowerAt1m = -59, double n = 2.7}) {
  final d = math.pow(10, (txPowerAt1m - rssi) / (10 * n)).toDouble();
  return d.clamp(0.1, 50.0);
}

int barsOf(double rssi) => ((rssi + 100) / 11).round().clamp(1, 5);

/// Categorias exibidas ao usuário.
class DeviceCategory {
  final String key;
  final String label;
  final String what;
  final IconData icon;
  const DeviceCategory(this.key, this.label, this.what, this.icon);
}

const _catAudio = DeviceCategory(
    'audio', 'Áudio / Fones', 'Reproduz áudio via Bluetooth', Icons.headphones);
const _catMedia = DeviceCategory(
    'media', 'Mídia / Display', 'Transmite vídeo e áudio', Icons.tv);
const _catWear = DeviceCategory(
    'wear', 'Vestível', 'Monitora atividade e notificações', Icons.watch);
const _catHome = DeviceCategory('home', 'Casa Inteligente',
    'Dispositivo IoT controlável pelo celular', Icons.home_outlined);
const _catComputing = DeviceCategory('computing', 'Computação',
    'Computador ou periférico com Bluetooth', Icons.laptop);
const _catPhone = DeviceCategory(
    'phone', 'Celular', 'Smartphone anunciando por perto', Icons.smartphone);
const _catBeacon = DeviceCategory(
    'beacon', 'Beacon', 'Transmissor de localização/identificação', Icons.sensors);
const _catUnknown = DeviceCategory(
    'unknown', 'Desconhecido', 'Dispositivo Bluetooth não identificado',
    Icons.bluetooth);

const allCategories = [
  _catAudio, _catMedia, _catWear, _catHome, _catComputing, _catPhone,
  _catBeacon, _catUnknown,
];

/// Subconjunto de Company Identifiers da Bluetooth SIG (a versão final
/// embarca a tabela completa em SQLite).
const companyNames = <int, String>{
  0x0006: 'Microsoft',
  0x004C: 'Apple',
  0x0059: 'Nordic Semiconductor',
  0x0075: 'Samsung Electronics',
  0x0087: 'Garmin',
  0x00E0: 'Google',
  0x012D: 'Sony',
  0x0157: 'Huami (Amazfit)',
  0x02E5: 'Espressif',
  0x038F: 'Xiaomi',
};

/// Classifica por nome anunciado, serviços GATT e fabricante — nessa ordem
/// de confiança. Heurística inicial; a versão final usa a tabela GATT completa.
DeviceCategory classify(String name, List<String> serviceUuids, int? companyId) {
  final n = name.toLowerCase();
  bool has(List<String> words) => words.any(n.contains);

  if (has(['bud', 'fone', 'head', 'airpod', 'jbl', 'bose', 'speaker', 'sound',
    'audio', 'boombox', 'wh-', 'wf-'])) {
    return _catAudio;
  }
  if (has(['tv', 'chromecast', 'cast', 'display', 'bravia', 'shield'])) {
    return _catMedia;
  }
  if (has(['watch', 'band', 'amazfit', 'fit', 'forerunner', 'venu'])) {
    return _catWear;
  }
  if (has(['lamp', 'hue', 'bulb', 'plug', 'tomada', 'light', 'led'])) {
    return _catHome;
  }
  if (has(['book', 'laptop', 'desktop', 'pc', 'mac', 'keyboard', 'mouse',
    'teclado'])) {
    return _catComputing;
  }
  if (has(['iphone', 'phone', 'galaxy', 'pixel', 'redmi', 'poco', 'moto'])) {
    return _catPhone;
  }

  final svc = serviceUuids.map((s) => s.toLowerCase()).toList();
  bool svcHas(String frag) => svc.any((s) => s.contains(frag));
  if (svcHas('180d') || svcHas('1826')) return _catWear;   // freq. cardíaca / fitness
  if (svcHas('fe2c')) return _catAudio;                    // Google Fast Pair
  if (svcHas('1812')) return _catComputing;                // HID
  if (svcHas('fd6f')) return _catPhone;                    // Exposure Notification
  if (svcHas('feaa')) return _catBeacon;                   // Eddystone

  switch (companyId) {
    case 0x02E5: return _catHome;      // Espressif → IoT
    case 0x0157: case 0x0087: return _catWear;
    case 0x004C: case 0x0075: return _catPhone; // Apple/Samsung sem nome → provável celular
  }
  return _catUnknown;
}

/// Um dispositivo rastreado pelo radar.
class TrackedDevice {
  final String id;
  String advName = '';
  int? companyId;
  List<String> serviceUuids = const [];
  int txPower;
  bool connectable = false;

  final filter = RssiKalmanFilter();
  int rssiRaw = -100;
  double rssiF = -100;
  final List<(DateTime, double)> hist = [];
  DateTime lastSeen = DateTime.now();
  DateTime firstSeen = DateTime.now();
  int sampleCount = 0;

  /// Ângulo estável no radar (não representa direção real).
  late final double angle =
      (id.codeUnits.fold(0, (a, c) => (a * 31 + c) & 0x7fffffff) % 360) *
          math.pi / 180;

  TrackedDevice(this.id, {this.txPower = -59});

  DeviceCategory get category => classify(advName, serviceUuids, companyId);

  String get vendor =>
      companyNames[companyId] ?? (companyId != null ? 'Fabricante 0x${companyId!.toRadixString(16).padLeft(4, '0').toUpperCase()}' : 'Desconhecido');

  String get displayName {
    if (advName.isNotEmpty) return advName;
    final v = companyNames[companyId];
    if (v != null) return 'Dispositivo $v';
    return 'Dispositivo ${id.substring(id.length - 5)}';
  }

  void addSample(int rssi, DateTime t) {
    rssiRaw = rssi;
    rssiF = filter.update(rssi);
    hist.add((t, rssiF));
    hist.removeWhere((h) => t.difference(h.$1).inMilliseconds > 3500);
    lastSeen = t;
    sampleCount++;
  }

  ProximityBucket get bucket => bucketFor(rssiF);
  double get meters => rssiToMeters(rssiF, txPowerAt1m: txPower);

  bool staleAfter(Duration d) => DateTime.now().difference(lastSeen) > d;

  /// Tendência quente/frio: média dos últimos 1,5 s vs 1,5 s anteriores,
  /// com histerese de 2 dB.
  String get trend {
    final t = DateTime.now();
    final a = <double>[], b = <double>[];
    for (final h in hist) {
      final age = t.difference(h.$1).inMilliseconds;
      if (age < 1500) {
        a.add(h.$2);
      } else if (age < 3000) {
        b.add(h.$2);
      }
    }
    if (a.length < 3 || b.length < 3) return 'flat';
    final ma = a.reduce((x, y) => x + y) / a.length;
    final mb = b.reduce((x, y) => x + y) / b.length;
    if (ma - mb > 2) return 'hotter';
    if (mb - ma > 2) return 'colder';
    return 'flat';
  }
}
