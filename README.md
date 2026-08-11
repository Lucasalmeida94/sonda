# Sonda 📡

Protótipo navegável de um app **radar de dispositivos eletrônicos**: visualiza aparelhos ao redor em um radar circular, com estimativa de distância por RSSI, modo busca "quente ou frio" e classificação por categoria.

> ⚠️ **Os sinais são 100% simulados.** Este é um protótipo de UX/UI empacotado como app Android (WebView via Capacitor). Cada aparelho tem uma distância virtual que deriva no tempo; o RSSI é gerado pelo modelo log-distance com ruído gaussiano e suavizado por um filtro de Kalman 1D antes de chegar à interface — o mesmo pipeline planejado para a versão real com BLE.

## O que tem no protótipo

- **Radar animado** (canvas): varredura, pulso, três zonas de proximidade (Distante / Próximo / Muito perto) e 9 dispositivos simulados que deslizam entre os anéis mudando de cor (azul → âmbar → vermelho).
- **Card do dispositivo**: nome, categoria, "o que faz", distância com margem de erro, barras de sinal e detalhes técnicos (MAC, fabricante, serviços GATT, RSSI cru vs. filtrado).
- **Modo busca quente/frio**: medidor circular, tendência por janelas de 1,5 s com histerese de 2 dB, vibração real (`navigator.vibrate`) que acelera com a força do sinal.
- **Lista ordenada por proximidade**, filtros por categoria e modo avançado (dBm nas bolhas).
- **TTL de dispositivos**: o Chromecast simulado para de anunciar a cada ~16 s — a bolha esmaece e some (expiração de 10 s).

## Estrutura

```
www/index.html      ← todo o app (HTML/CSS/JS vanilla, sem dependências)
android/            ← projeto Android gerado pelo Capacitor
apk/                ← APK de debug pronto para instalar
capacitor.config.json
```

## Instalar no celular

Baixe `apk/sonda-debug.apk`, envie para o celular e instale (é preciso permitir "instalar apps de fontes desconhecidas"). Por ser um APK de debug não assinado para loja, o Android exibirá um aviso — é esperado.

## Compilar do zero

Requisitos: Node 18+, JDK 17+ e Android SDK (`ANDROID_HOME` configurado).

```bash
npm install
npx cap sync android
cd android && ./gradlew assembleDebug
# APK em android/app/build/outputs/apk/debug/app-debug.apk
```

## Próximos passos (versão real)

O plano de arquitetura completo está em [`docs/especificacao.md`](docs/especificacao.md): Flutter + `flutter_blue_plus` com o BLE como motor primário do radar, Wi-Fi como camada complementar no Android, UWB como modo precisão, bases OUI/Company ID embarcadas e o mesmo `DistanceEstimator` (Kalman + log-distance) já validado neste protótipo.
