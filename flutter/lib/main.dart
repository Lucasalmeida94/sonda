import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'radar_screen.dart';
import 'scanner.dart';
import 'theme.dart';
import 'wifi_scanner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: SondaColors.bg,
  ));
  runApp(const SondaApp());
}

class SondaApp extends StatelessWidget {
  const SondaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sonda',
      debugShowCheckedModeBanner: false,
      theme: sondaTheme(),
      home: const StartGate(),
    );
  }
}

/// Porta de entrada: explica as permissões em linguagem leiga, pede
/// autorização e só então entra no radar.
class StartGate extends StatefulWidget {
  const StartGate({super.key});

  @override
  State<StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<StartGate> {
  late final DeviceRegistry registry;
  late final BleScanner scanner;
  late final WifiScanner wifi;
  bool started = false;

  @override
  void initState() {
    super.initState();
    registry = DeviceRegistry();
    scanner = BleScanner(registry);
    wifi = WifiScanner(registry);
  }

  @override
  void dispose() {
    wifi.dispose();
    scanner.dispose();
    registry.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => started = true);
    await scanner.start();
  }

  @override
  Widget build(BuildContext context) {
    if (!started) return _intro(context);

    return ValueListenableBuilder<ScannerState>(
      valueListenable: scanner.state,
      builder: (context, s, _) => switch (s) {
        ScannerState.scanning =>
          RadarScreen(registry: registry, scanner: scanner, wifi: wifi),
        ScannerState.bluetoothOff => _message(
            icon: Icons.bluetooth_disabled,
            title: 'Bluetooth desligado',
            body:
                'Ligue o Bluetooth para o Sonda enxergar os aparelhos ao redor.',
            action: ('Tentar de novo', _start),
          ),
        ScannerState.noPermission => _message(
            icon: Icons.lock_outline,
            title: 'Sem permissão',
            body:
                'O Sonda precisa da permissão "Dispositivos por perto" (Bluetooth). '
                'Nada é enviado para a internet — a leitura fica só no seu celular.',
            action: ('Pedir permissão de novo', _start),
          ),
        ScannerState.unsupported => _message(
            icon: Icons.error_outline,
            title: 'Sem suporte a Bluetooth LE',
            body: 'Este aparelho não tem o Bluetooth de baixa energia '
                'necessário para o radar.',
            action: null,
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _intro(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.radar, size: 72, color: SondaColors.accent),
              const SizedBox(height: 20),
              Text('Sonda.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const Text(
                'Veja os aparelhos Bluetooth ao seu redor em um radar, '
                'com distância aproximada e modo busca quente/frio.\n\n'
                'Para isso o Android pede a permissão "Dispositivos por perto". '
                'A leitura acontece só no seu celular — nada vai para a internet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SondaColors.sub, height: 1.5),
              ),
              const SizedBox(height: 28),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: SondaColors.accent,
                  foregroundColor: const Color(0xFF04231F),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _start,
                child: const Text('Começar a escanear',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(
      {required IconData icon,
      required String title,
      required String body,
      (String, VoidCallback)? action}) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 56, color: SondaColors.sub),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: SondaColors.sub, height: 1.5)),
              if (action != null) ...[
                const SizedBox(height: 24),
                OutlinedButton(
                    onPressed: action.$2, child: Text(action.$1)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
