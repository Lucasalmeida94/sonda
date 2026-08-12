# Sonda 📡

App **radar de dispositivos eletrônicos**: visualiza aparelhos ao redor em um radar circular, com estimativa de distância por RSSI, modo busca "quente ou frio" e classificação por categoria.

O repositório tem duas versões:

| Versão | Pasta | Sinais | APK |
|---|---|---|---|
| **App real (Flutter + BLE)** | `flutter/` | Bluetooth LE de verdade (`flutter_blue_plus`) | `apk/sonda-ble.apk` |
| Protótipo de UX (Capacitor/WebView) | `www/` + `android/` | 100% simulados | `apk/sonda-debug.apk` |

> Os dois usam o mesmo pipeline de sinal (log-distance + filtro de Kalman 1D) e a mesma linguagem visual. O protótipo serviu para validar a UX antes do BLE real. **Ambos têm o mesmo application id** (`com.palascoding.sonda`), então instalar um substitui o outro no aparelho.

## App real (Flutter + BLE)

- **Scan BLE contínuo** com `flutter_blue_plus` (modo low-latency, atualizações por advertisement).
- **Radar ao vivo**: cada dispositivo detectado vira uma bolha que se aproxima/afasta do centro conforme o RSSI filtrado (Kalman por dispositivo); TTL de 10 s com fade em 3 s.
- **Classificação heurística**: nome anunciado → serviços GATT (Fast Pair, HID, freq. cardíaca, Eddystone…) → Company ID do fabricante (subconjunto da tabela Bluetooth SIG).
- **Card do dispositivo**: distância com margem, barras de sinal, MAC/ID, fabricante, serviços, RSSI cru vs. filtrado, TxPower.
- **Modo busca quente/frio** com vibração progressiva real (HapticFeedback) e tendência por janelas de 1,5 s com histerese de 2 dB.
- **Permissões**: `BLUETOOTH_SCAN` (`neverForLocation`) no Android 12+; localização apenas para Android ≤ 11, como o sistema exige.

Compilar: instale o [Flutter](https://docs.flutter.dev/get-started/install), depois `cd flutter && flutter build apk --release`.

Limitações conhecidas desta primeira versão: só Android (iOS exige ajustes de Info.plist), sem Wi-Fi scan nem UWB ainda, tabela de fabricantes reduzida, e dispositivos iOS/Android modernos aparecem com MAC randomizado (é o comportamento esperado da plataforma — veja `docs/especificacao.md`).

## O que tem no protótipo (Capacitor)

- **Radar animado** (canvas): varredura, pulso, três zonas de proximidade (Distante / Próximo / Muito perto) e 9 dispositivos simulados que deslizam entre os anéis mudando de cor (azul → âmbar → vermelho).
- **Card do dispositivo**: nome, categoria, "o que faz", distância com margem de erro, barras de sinal e detalhes técnicos (MAC, fabricante, serviços GATT, RSSI cru vs. filtrado).
- **Modo busca quente/frio**: medidor circular, tendência por janelas de 1,5 s com histerese de 2 dB, vibração real (`navigator.vibrate`) que acelera com a força do sinal.
- **Lista ordenada por proximidade**, filtros por categoria e modo avançado (dBm nas bolhas).
- **TTL de dispositivos**: o Chromecast simulado para de anunciar a cada ~16 s — a bolha esmaece e some (expiração de 10 s).

## Estrutura

```
flutter/            ← app real (Flutter + flutter_blue_plus)
  lib/domain.dart          Kalman, estimador de distância, classificador
  lib/scanner.dart         BleScanner + DeviceRegistry (TTL)
  lib/radar_screen.dart    radar (CustomPainter), lista, card
  lib/finder_screen.dart   modo busca quente/frio + haptics
www/index.html      ← protótipo (HTML/CSS/JS vanilla, sinais simulados)
android/            ← projeto Android do protótipo (Capacitor)
apk/                ← APKs prontos para instalar
docs/especificacao.md ← arquitetura completa da visão final
```

## Instalar no celular

Baixe o APK desejado da pasta `apk/`, envie para o celular e instale (é preciso permitir "instalar apps de fontes desconhecidas"). Por não serem assinados para loja, o Android exibirá um aviso — é esperado.

- `sonda-ble.apk` — **app real**: pede a permissão "Dispositivos por perto" e mostra o que existe de verdade ao seu redor.
- `sonda-debug.apk` — protótipo com dados simulados (não pede permissão nenhuma).

## Próximos passos

Roteiro em [`docs/especificacao.md`](docs/especificacao.md): tabela completa OUI/Company ID embarcada (SQLite), Wi-Fi scan complementar no Android, UWB como modo precisão, filtros persistentes e apelidos para dispositivos favoritos.
