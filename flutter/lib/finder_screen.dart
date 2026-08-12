import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain.dart';
import 'scanner.dart';
import 'theme.dart';

/// Modo busca "quente ou frio": medidor circular + tendência + vibração
/// progressiva conforme o sinal fica mais forte.
class FinderScreen extends StatefulWidget {
  final TrackedDevice device;
  final DeviceRegistry registry;
  const FinderScreen(
      {super.key, required this.device, required this.registry});

  @override
  State<FinderScreen> createState() => _FinderScreenState();
}

class _FinderScreenState extends State<FinderScreen> {
  Timer? _haptics;

  @override
  void initState() {
    super.initState();
    _haptics = Timer.periodic(const Duration(milliseconds: 420), (_) {
      final s = _strength(widget.device.rssiF);
      if (s > .25 && math.Random().nextDouble() < s) {
        if (s > .75) {
          HapticFeedback.heavyImpact();
        } else if (s > .5) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.lightImpact();
        }
      }
    });
  }

  @override
  void dispose() {
    _haptics?.cancel();
    super.dispose();
  }

  /// 0 = sinal fraco (-90 dBm) … 1 = forte (-40 dBm).
  double _strength(double rssi) => ((rssi + 90) / 50).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.registry,
          builder: (context, _) {
            final d = widget.device;
            final lost = d.staleAfter(DeviceRegistry.staleGone);
            final s = _strength(d.rssiF);
            final color = SondaColors.forBucket(d.bucket);
            final trend = d.trend;
            final (trendText, trendColor) = lost
                ? ('Sinal perdido — volte um pouco…', SondaColors.sub)
                : switch (trend) {
                    'hotter' => (
                        'Você está chegando mais perto! 🔥',
                        SondaColors.hot
                      ),
                    'colder' => ('Afastando-se… ❄️', SondaColors.cold),
                    _ => (
                        d.bucket == ProximityBucket.immediate
                            ? 'Está bem aqui! Procure em volta.'
                            : 'Sinal estável — continue andando.',
                        SondaColors.sub
                      ),
                  };
            return Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Row(children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      style: IconButton.styleFrom(
                        backgroundColor: SondaColors.panel,
                        side: const BorderSide(color: SondaColors.line),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.displayName,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        Text(d.category.label,
                            style: const TextStyle(
                                fontSize: 11, color: SondaColors.sub)),
                      ],
                    ),
                  ]),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 240,
                          height: 240,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CustomPaint(
                                  painter: _GaugePainter(
                                      lost ? 0 : s, color)),
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      lost
                                          ? '—'
                                          : '~${d.meters.toStringAsFixed(1).replaceAll('.', ',')}',
                                      style: const TextStyle(
                                          fontSize: 34,
                                          fontWeight: FontWeight.w700,
                                          fontFeatures: [
                                            FontFeature.tabularFigures()
                                          ]),
                                    ),
                                    const Text('metros',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: SondaColors.sub)),
                                    const SizedBox(height: 4),
                                    Text(
                                      lost
                                          ? 'aguardando sinal'
                                          : '±${(d.meters * .45).toStringAsFixed(1).replaceAll('.', ',')} m · ${d.rssiF.round()} dBm',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: SondaColors.sub,
                                          fontFamily: 'monospace'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 26),
                        Text(trendText,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: trendColor)),
                        const SizedBox(height: 10),
                        const Text(
                          '📳 A vibração acelera conforme você se aproxima.\n'
                          'Ande devagar e observe a tendência.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              color: SondaColors.sub,
                              height: 1.6),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value; // 0..1
  final Color color;
  _GaugePainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = SondaColors.line;
    canvas.drawCircle(c, r, track);
    if (value > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * value,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}
