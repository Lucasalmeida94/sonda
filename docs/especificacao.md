# Sonda — Especificação de arquitetura (versão real)

Projeto do app detector e analisador de sinais eletrônicos. Este documento consolida a arquitetura, o fluxo de telas, o formato de dados e a lógica de distância que o protótipo (`www/index.html`) valida em simulação.

## Restrições reais das plataformas

- **iOS não permite escanear redes Wi-Fi** de terceiros (sem API pública para listar SSIDs, nem Probe Requests). No iOS o app é essencialmente **BLE + UWB** (`NearbyInteraction`, apenas entre dispositivos com chip U1/U2 que cooperem).
- **Android permite scan de Wi-Fi** (`WifiManager.startScan`), mas com throttling desde o Android 9 (≈4 scans/2min em foreground) — inviável para radar em tempo real via Wi-Fi. Captura de Probe Requests exige modo monitor (root) — fora do escopo.
- **MAC randomizado**: desde ~2017 iOS/Android randomizam MAC em broadcast. A consulta OUI funciona para roteadores, TVs e IoT antigos, mas falha para celulares modernos. O fingerprinting prioriza **GATT services, Appearance, Manufacturer Data e Company ID** do BLE, com OUI como fallback.
- **Distância por RSSI é estimativa grosseira** (±30–50% indoor). A UX comunica proximidade em faixas (perto/médio/longe), nunca metros exatos como promessa.

**Conclusão:** BLE é o motor primário do radar nas duas plataformas; Wi-Fi entra como camada complementar no Android; UWB como "modo precisão" opcional.

## Arquitetura (Flutter + canais nativos)

```
┌─────────────────────────────────────────────────┐
│                UI (Flutter/Dart)                │
│  RadarScreen · DeviceCard · FinderScreen        │
│  CustomPainter (radar) · haptics · i18n         │
├─────────────────────────────────────────────────┤
│           Estado (Riverpod ou Bloc)             │
│  DeviceRegistry (mapa id→Device, TTL/expiração) │
├─────────────────────────────────────────────────┤
│              Domínio (Dart puro)                │
│  DistanceEstimator (Kalman + log-distance)      │
│  DeviceClassifier (GATT/CompanyID/OUI→categoria)│
│  ProximityBucketizer (imediato/perto/longe)     │
├─────────────────────────────────────────────────┤
│         Camada de aquisição (por fonte)         │
│  BleScanner  → flutter_blue_plus                │
│  WifiScanner → wifi_scan (Android only)         │
│  UwbRanging  → canal nativo (NearbyInteraction /│
│                androidx.core.uwb)               │
├─────────────────────────────────────────────────┤
│  Dados locais: base OUI (SQLite embarcada)      │
│  + base CompanyID Bluetooth SIG                 │
│  + tabela GATT UUID → categoria (JSON no bundle)│
└─────────────────────────────────────────────────┘
```

Decisões-chave:

- **Bases de identificação embarcadas** (OUI IEEE + Company Identifiers Bluetooth SIG em SQLite): funciona offline e sem latência — o radar atualiza a cada ~1 s.
- **DeviceRegistry com TTL**: sem novo advertisement em ~10 s, a bolha esmaece e some (fade, nunca desaparecimento abrupto).
- **Um estimador de distância por dispositivo** (cada um com seu filtro de Kalman independente).
- **Permissões**: Android `BLUETOOTH_SCAN` + localização (Wi-Fi); iOS `NSBluetoothAlwaysUsageDescription`. Onboarding explica o porquê em linguagem leiga.

## Fluxo de telas

```
[0. Onboarding] ──► [1. Radar] ──tap na bolha──► [2. Card do dispositivo]
                        │                              │
                        │                        "Encontrar" ──► [3. Modo Busca]
                        │
                     [4. Lista] (alternância radar/lista)
                        │
                     [5. Ajustes / Modo avançado]
```

- **Radar:** usuário no centro; bolhas se movem suavemente entre três anéis de proximidade. Ângulo é estável por dispositivo mas **não** representa direção real (sem UWB não há azimute) — a UI deixa isso claro.
- **Card:** nome amigável, "o que faz", distância com margem (±), barras 1–5; dBm e serviços GATT só no modo avançado.
- **Modo Busca:** medidor circular + "quente/frio" por **tendência** do RSSI filtrado (janelas de 1,5 s, histerese ±2 dB) + vibração progressiva. Com UWB disponível, ganha seta direcional real.
- **Lista:** mesma informação ordenável — melhor para muitos dispositivos e para TalkBack/VoiceOver.

## Estrutura de dados do scanner

```json
{
  "id": "ble:5C-F3-70-8A-11-B2",
  "source": "ble",
  "name": { "raw": "WH-1000XM5", "display": "Fone Sony WH-1000XM5", "origin": "advertised_name" },
  "vendor": { "companyId": 301, "companyName": "Sony Corporation", "ouiFallback": null, "macRandomized": false },
  "category": {
    "key": "audio", "label": "Áudio / Fones", "icon": "headphones",
    "confidence": 0.95, "evidence": ["gatt:0x110B", "manufacturer_data"]
  },
  "signal": {
    "rssiRaw": -62, "rssiFiltered": -60.4, "txPowerAt1m": -59,
    "sampleCount": 47, "lastSeen": "2026-08-11T14:32:07.412Z"
  },
  "proximity": {
    "bucket": "near", "distanceMeters": 1.4, "distanceMarginMeters": 0.7,
    "trend": "approaching", "bars": 4
  },
  "capabilities": { "connectable": true, "services": ["0x110B", "0x180F"], "uwbAvailable": false }
}
```

## Distância a partir do RSSI (Dart)

```dart
/// Filtro de Kalman 1D para suavizar o RSSI (que flutua ±10 dBm parado).
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

class DistanceEstimator {
  final _filter = RssiKalmanFilter();

  /// [txPowerAt1m]: potência calibrada a 1 m (do advertisement quando houver).
  /// [pathLossExponent] n: 2.0 = campo aberto, 2.7–3.5 = indoor.
  ({double meters, ProximityBucket bucket}) update(
    int rssiRaw, {
    int txPowerAt1m = -59,
    double pathLossExponent = 2.7,
  }) {
    final rssi = _filter.update(rssiRaw);
    final meters =
        math.pow(10, (txPowerAt1m - rssi) / (10 * pathLossExponent)) as double;
    final bucket = switch (rssi) {
      > -50 => ProximityBucket.immediate, // ~ < 0,5 m
      >= -70 => ProximityBucket.near,     // ~ 0,5–3 m
      _ => ProximityBucket.far,           // ~ > 3 m
    };
    return (meters: meters.clamp(0.1, 50.0), bucket: bucket);
  }
}
```

Os buckets vêm do RSSI filtrado (não da distância convertida), porque limiares em dBm são mais estáveis. O "quente/frio" compara a média dos últimos ~3 s com os 3 s anteriores, com histerese de ±2 dBm.
