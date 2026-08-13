import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain.dart';
import 'finder_screen.dart';
import 'scanner.dart';
import 'theme.dart';
import 'wifi_scanner.dart';

/// Mapeia RSSI filtrado → raio normalizado no radar (0 = centro, 1 = borda).
double rssiToRadius(double rssi) => ((-32 - rssi) / 58).clamp(0.07, 0.97);

final zoneNear = rssiToRadius(-50);
final zoneFar = rssiToRadius(-70);

class RadarScreen extends StatefulWidget {
  final DeviceRegistry registry;
  final BleScanner scanner;
  final WifiScanner wifi;
  const RadarScreen(
      {super.key,
      required this.registry,
      required this.scanner,
      required this.wifi});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController sweep;
  String filter = 'all';
  bool advanced = false;
  bool listMode = false;

  @override
  void initState() {
    super.initState();
    sweep = AnimationController(
        vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() {
    sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.registry,
          builder: (context, _) {
            final all = widget.registry.visible;
            final shown = all
                .where((d) => filter == 'all' || d.category.key == filter)
                .toList()
              ..sort((a, b) => a.meters.compareTo(b.meters));
            return Column(
              children: [
                _topBar(shown.length),
                _chips(),
                Expanded(
                  child: listMode ? _list(shown) : _radar(shown),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Text(
                    'A posição no anel indica proximidade; o ângulo é apenas '
                    'ilustrativo. Toque em um aparelho.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10.5, color: SondaColors.sub),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          const Text('Sonda',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const Text('.',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: SondaColors.accent)),
          const SizedBox(width: 8),
          Text('$count aparelho${count == 1 ? '' : 's'}',
              style:
                  const TextStyle(fontSize: 12, color: SondaColors.sub)),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: SondaColors.accent.withValues(alpha: .12),
              border: Border.all(
                  color: SondaColors.accent.withValues(alpha: .3)),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Text('AO VIVO',
                style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                    color: SondaColors.accent)),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<WifiState>(
            valueListenable: widget.wifi.state,
            builder: (context, ws, _) => _iconToggle(
                Icons.wifi, ws == WifiState.scanning, _toggleWifi,
                tooltip: 'Camada Wi-Fi (Android)'),
          ),
          const SizedBox(width: 6),
          _iconToggle(Icons.info_outline, advanced,
              () => setState(() => advanced = !advanced),
              tooltip: 'Modo avançado (dBm)'),
          const SizedBox(width: 6),
          _iconToggle(Icons.list, listMode,
              () => setState(() => listMode = !listMode),
              tooltip: 'Ver em lista'),
        ],
      ),
    );
  }

  Future<void> _toggleWifi() async {
    if (widget.wifi.running) {
      widget.wifi.stop();
      return;
    }
    final ok = await widget.wifi.start();
    if (!ok && mounted) {
      final msg = switch (widget.wifi.state.value) {
        WifiState.noPermission =>
          'A camada Wi-Fi precisa da permissão de localização — é uma '
              'exigência do Android para listar redes.',
        WifiState.noLocationService =>
          'Ative a localização do aparelho para o Android liberar o scan '
              'de redes Wi-Fi.',
        _ => 'Scan de Wi-Fi não disponível neste aparelho.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _iconToggle(IconData icon, bool on, VoidCallback onTap,
      {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: SondaColors.panel,
            border: Border.all(
                color: on ? SondaColors.accent : SondaColors.line),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon,
              size: 18, color: on ? SondaColors.accent : SondaColors.text),
        ),
      ),
    );
  }

  Widget _chips() {
    final defs = [
      ('all', 'Todos', null),
      for (final c in allCategories.take(6)) (c.key, c.label.split(' ').first, c.icon),
    ];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          for (final (key, label, icon) in defs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: filter == key,
                showCheckmark: false,
                avatar: icon == null
                    ? null
                    : Icon(icon,
                        size: 15,
                        color: filter == key
                            ? SondaColors.accent
                            : SondaColors.sub),
                label: Text(label, style: const TextStyle(fontSize: 12)),
                backgroundColor: SondaColors.panel2,
                selectedColor: SondaColors.accent.withValues(alpha: .14),
                side: BorderSide(
                    color:
                        filter == key ? SondaColors.accent : SondaColors.line),
                onSelected: (_) => setState(() => filter = key),
              ),
            ),
        ],
      ),
    );
  }

  Widget _radar(List<TrackedDevice> devices) {
    return LayoutBuilder(builder: (context, box) {
      final side = math.min(box.maxWidth, box.maxHeight);
      final center = Offset(box.maxWidth / 2, box.maxHeight / 2);
      final radius = side / 2 - 30;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: sweep,
              builder: (_, __) => CustomPaint(
                painter: _RadarPainter(sweep.value),
              ),
            ),
          ),
          for (final d in devices)
            _bubble(d, center, radius),
        ],
      );
    });
  }

  Widget _bubble(TrackedDevice d, Offset center, double radius) {
    final r = rssiToRadius(d.rssiF) * radius;
    final pos = center + Offset(math.cos(d.angle) * r, math.sin(d.angle) * r);
    final fading = d.staleAfter(DeviceRegistry.staleFade);
    final color = SondaColors.forBucket(d.bucket);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      left: pos.dx - 28,
      top: pos.dy - 28,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 600),
        opacity: fading ? .18 : 1,
        child: GestureDetector(
          onTap: () => _openSheet(d),
          child: SizedBox(
            width: 56,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SondaColors.panel,
                    border: Border.all(color: color, width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: color.withValues(alpha: .35),
                          blurRadius: 12),
                    ],
                  ),
                  child: Icon(d.category.icon,
                      size: 20, color: SondaColors.text),
                ),
                const SizedBox(height: 3),
                Text(d.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 9, color: SondaColors.sub)),
                if (advanced)
                  Text('${d.rssiF.round()} dBm',
                      style: const TextStyle(
                          fontSize: 8.5,
                          color: SondaColors.accent,
                          fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(List<TrackedDevice> devices) {
    if (devices.isEmpty) {
      return const Center(
          child: Text('Nenhum aparelho por enquanto…',
              style: TextStyle(color: SondaColors.sub)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: devices.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: SondaColors.line),
      itemBuilder: (context, i) {
        final d = devices[i];
        final color = SondaColors.forBucket(d.bucket);
        return ListTile(
          onTap: () => _openSheet(d),
          leading: Icon(d.category.icon, color: SondaColors.text),
          title: Text(d.displayName,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(d.category.label,
              style:
                  const TextStyle(fontSize: 11, color: SondaColors.sub)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('~${d.meters.toStringAsFixed(1).replaceAll('.', ',')} m',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(d.bucket.labelPT,
                    style: TextStyle(fontSize: 9, color: color)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openSheet(TrackedDevice d) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SondaColors.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DeviceSheet(
        device: d,
        registry: widget.registry,
        onFind: () {
          Navigator.pop(context);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      FinderScreen(device: d, registry: widget.registry)));
        },
      ),
    );
  }
}

/// Fundo do radar: anéis de zona, cruz, varredura e pulso.
class _RadarPainter extends CustomPainter {
  final double t; // 0..1 do controlador
  _RadarPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 30;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // brilho central
    canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [
            SondaColors.accent.withValues(alpha: .06),
            SondaColors.accent.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: radius)));

    // anéis de zona
    canvas.drawCircle(c, radius * zoneNear,
        stroke..color = SondaColors.warm.withValues(alpha: .28));
    canvas.drawCircle(c, radius * zoneFar,
        stroke..color = SondaColors.cold.withValues(alpha: .25));
    canvas.drawCircle(c, radius * .97,
        stroke..color = SondaColors.line);

    // anéis menores + cruz
    stroke.color = SondaColors.text.withValues(alpha: .05);
    for (final f in [.2, .5, .82]) {
      canvas.drawCircle(c, radius * f, stroke);
    }
    canvas.drawLine(
        c - Offset(radius, 0), c + Offset(radius, 0), stroke);
    canvas.drawLine(
        c - Offset(0, radius), c + Offset(0, radius), stroke);

    // varredura
    final a = t * 2 * math.pi;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(Rect.fromCircle(center: c, radius: radius * .97),
            a - .8, .8, false)
        ..close(),
      Paint()
        ..shader = SweepGradient(
          startAngle: a - .8,
          endAngle: a,
          colors: [
            SondaColors.accent.withValues(alpha: 0),
            SondaColors.accent.withValues(alpha: .3),
          ],
          transform: GradientRotation(0),
        ).createShader(Rect.fromCircle(center: c, radius: radius)),
    );

    // pulso expansivo
    final p = (t * 2) % 1;
    canvas.drawCircle(
        c,
        radius * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = SondaColors.accent.withValues(alpha: .35 * (1 - p)));

    // você
    canvas.drawCircle(c, 5, Paint()..color = SondaColors.accent);
    canvas.drawCircle(c, 10,
        Paint()..color = SondaColors.accent.withValues(alpha: .25));
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t;
}

/// Card do dispositivo (bottom sheet), atualizado ao vivo.
class DeviceSheet extends StatelessWidget {
  final TrackedDevice device;
  final DeviceRegistry registry;
  final VoidCallback onFind;
  const DeviceSheet(
      {super.key,
      required this.device,
      required this.registry,
      required this.onFind});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final d = device;
        final color = SondaColors.forBucket(d.bucket);
        final meters = d.meters;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, 20 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                        color: SondaColors.line,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SondaColors.panel2,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(d.category.icon, color: SondaColors.text),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.displayName,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text('${d.category.label} · ${d.category.what}',
                          style: const TextStyle(
                              fontSize: 12, color: SondaColors.sub)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: _stat(
                        'DISTÂNCIA',
                        '~${meters.toStringAsFixed(1).replaceAll('.', ',')} m '
                        '(±${(meters * .45).toStringAsFixed(1).replaceAll('.', ',')})')),
                const SizedBox(width: 10),
                Expanded(child: _statBars('FORÇA DO SINAL', barsOf(d.rssiF))),
              ]),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: SondaColors.accent,
                  foregroundColor: const Color(0xFF04231F),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: onFind,
                icon: const Icon(Icons.search),
                label: const Text('Encontrar este aparelho',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 14),
                  collapsedShape: RoundedRectangleBorder(
                      side: const BorderSide(color: SondaColors.line),
                      borderRadius: BorderRadius.circular(12)),
                  shape: RoundedRectangleBorder(
                      side: const BorderSide(color: SondaColors.line),
                      borderRadius: BorderRadius.circular(12)),
                  title: const Text('Detalhes técnicos',
                      style: TextStyle(
                          fontSize: 13, color: SondaColors.sub)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: DefaultTextStyle(
                        style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.8,
                            color: SondaColors.sub,
                            fontFamily: 'monospace'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Endereço  ${d.id}'),
                            Text('Fabricante  ${d.vendor}'),
                            if (d.source == SignalSource.wifi)
                              Text('Wi-Fi  ${d.wifiInfo ?? '—'}')
                            else
                              Text(
                                  'Serviços  ${d.serviceUuids.isEmpty ? '—' : d.serviceUuids.join(', ')}'),
                            Text(
                                'RSSI cru ${d.rssiRaw} dBm · filtrado ${d.rssiF.toStringAsFixed(1)} dBm'),
                            Text(
                                'TxPower ${d.txPower} dBm · zona ${d.bucket.labelPT} · amostras ${d.sampleCount}'),
                            Text(
                                'Conectável  ${d.connectable ? 'sim' : 'não'}'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SondaColors.panel2,
          border: Border.all(color: SondaColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.2,
                    color: SondaColors.sub)),
            const SizedBox(height: 5),
            Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _statBars(String label, int bars) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SondaColors.panel2,
          border: Border.all(color: SondaColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.2,
                    color: SondaColors.sub)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 5; i++)
                  Container(
                    width: 9,
                    height: 5.0 + i * 2.75,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: i < bars
                          ? SondaColors.accent
                          : SondaColors.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
}
