part of 'main.dart';

// --- Custom painter for mini history sparkline ---

class _HomeTrendStripPainter extends CustomPainter {
  _HomeTrendStripPainter({required this.home, required this.city});

  final List<_HistoryPoint> home;
  final List<_HistoryPoint> city;

  void _drawSeries(
    Canvas canvas,
    Size size,
    List<_HistoryPoint> series,
    Color color,
  ) {
    if (series.length < 2) return;

    double minV = series.first.value;
    double maxV = series.first.value;
    for (final p in series) {
      if (p.value < minV) minV = p.value;
      if (p.value > maxV) maxV = p.value;
    }
    if ((maxV - minV).abs() < 0.001) {
      maxV = minV + 1;
    }

    final path = Path();
    final dx = size.width / (series.length - 1);
    for (int i = 0; i < series.length; i++) {
      final p = series[i];
      final x = i * dx;
      final norm = (p.value - minV) / (maxV - minV);
      final y = size.height - norm * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (int i = 0; i < 3; i++) {
      final y = size.height * (i / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    _drawSeries(canvas, size, home, Colors.tealAccent.withValues(alpha: 0.9));
    _drawSeries(canvas, size, city, Colors.orangeAccent.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant _HomeTrendStripPainter oldDelegate) {
    return !identical(oldDelegate.home, home) ||
        !identical(oldDelegate.city, city);
  }
}

class _SensorTrendPainter extends CustomPainter {
  _SensorTrendPainter(
    this.series, {
    required this.domainStart,
    required this.domainEnd,
    required this.lineColor,
    required this.gridColor,
    this.useIndexX = false,
  });

  final List<_HistoryPoint> series;
  final DateTime domainStart;
  final DateTime domainEnd;
  final Color lineColor;
  final Color gridColor;
  final bool useIndexX;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Basit yatay grid (4 çizgi)
    const gridLines = 4;
    for (int i = 0; i < gridLines; i++) {
      final t = i / (gridLines - 1);
      final y = size.height * t;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (series.isEmpty) return;

    double minV = series.first.value;
    double maxV = series.first.value;
    for (final p in series) {
      if (p.value < minV) minV = p.value;
      if (p.value > maxV) maxV = p.value;
    }
    if ((maxV - minV).abs() < 0.001) {
      maxV = minV + 1;
    }

    final path = Path();
    if (useIndexX) {
      final dx = series.length == 1 ? 0.0 : size.width / (series.length - 1);
      for (int i = 0; i < series.length; i++) {
        final p = series[i];
        final x = i * dx;
        final norm = (p.value - minV) / (maxV - minV);
        final y = size.height - norm * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
    } else {
      // X eksenini sabit [domainStart, domainEnd] aralığına göre ölçekle.
      var startMs = domainStart.millisecondsSinceEpoch.toDouble();
      var endMs = domainEnd.millisecondsSinceEpoch.toDouble();
      if (endMs <= startMs) {
        endMs = startMs + 1;
      }
      final spanMs = endMs - startMs;
      for (int i = 0; i < series.length; i++) {
        final p = series[i];
        final tMs = p.time.millisecondsSinceEpoch.toDouble();
        final frac = ((tMs - startMs) / spanMs).clamp(0.0, 1.0);
        final x = frac * size.width;
        final norm = (p.value - minV) / (maxV - minV);
        final y = size.height - norm * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
    }

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(path, linePaint);

    // Noktaları vurgula
    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    if (useIndexX) {
      final dx = series.length == 1 ? 0.0 : size.width / (series.length - 1);
      for (int i = 0; i < series.length; i++) {
        final p = series[i];
        final x = i * dx;
        final norm = (p.value - minV) / (maxV - minV);
        final y = size.height - norm * size.height;
        canvas.drawCircle(Offset(x, y), 2.5, pointPaint);
      }
    } else {
      var startMs = domainStart.millisecondsSinceEpoch.toDouble();
      var endMs = domainEnd.millisecondsSinceEpoch.toDouble();
      if (endMs <= startMs) {
        endMs = startMs + 1;
      }
      final spanMs = endMs - startMs;
      for (int i = 0; i < series.length; i++) {
        final p = series[i];
        final tMs = p.time.millisecondsSinceEpoch.toDouble();
        final frac = ((tMs - startMs) / spanMs).clamp(0.0, 1.0);
        final x = frac * size.width;
        final norm = (p.value - minV) / (maxV - minV);
        final y = size.height - norm * size.height;
        canvas.drawCircle(Offset(x, y), 2.5, pointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SensorTrendPainter oldDelegate) {
    return !identical(oldDelegate.series, series) ||
        oldDelegate.domainStart != domainStart ||
        oldDelegate.domainEnd != domainEnd ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.useIndexX != useIndexX;
  }
}

enum _SensorHistoryRange { last3h, day, week, month }

class _HomeDustLayer extends StatefulWidget {
  const _HomeDustLayer({required this.intensity});
  final int intensity;

  @override
  State<_HomeDustLayer> createState() => _HomeDustLayerState();
}

class _HomeDustLayerState extends State<_HomeDustLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final Color dustColor = brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.09)
        : Colors.black.withValues(alpha: 0.07);

    return IgnorePointer(
      child: CustomPaint(
        painter: _DustPainter(
          animation: _ctrl,
          intensity: widget.intensity,
          color: dustColor,
        ),
      ),
    );
  }
}

class _DustPainter extends CustomPainter {
  _DustPainter({
    required this.animation,
    required this.intensity,
    required this.color,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final int intensity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final t = animation.value;
    final count = intensity.clamp(5, 80);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      final seed = i * 9973;
      final baseX = (seed % 1000) / 1000.0;
      final baseY = ((seed ~/ 1000) % 1000) / 1000.0;
      // Zamanla değişen 2 faz: biri hızlı, biri yavaş
      final phase1 =
          t * 2 * math.pi + ((seed % 6283) / 1000.0); // 0..2π + seed ofset
      final phase2 =
          t * 1.3 * math.pi + (((seed ~/ 7) % 6283) / 1000.0); // ikinci faz

      // 0..1 aralığında dolaşan x/y oranları (random yürüyüş)
      double xFrac = baseX + 0.25 * math.sin(phase1) + 0.18 * math.sin(phase2);
      double yFrac =
          baseY + 0.22 * math.cos(phase1 * 0.9) + 0.16 * math.sin(phase2 * 1.1);

      // 0..1 aralığına sar (loop hissini azaltmak için wrap-around)
      while (xFrac < 0) {
        xFrac += 1.0;
      }
      while (xFrac > 1) {
        xFrac -= 1.0;
      }
      while (yFrac < 0) {
        yFrac += 1.0;
      }
      while (yFrac > 1) {
        yFrac -= 1.0;
      }

      final x = size.width * xFrac;
      final y = size.height * yFrac;
      final radius = 1.4 + ((seed % 5) * 0.35);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DustPainter oldDelegate) {
    return oldDelegate.intensity != intensity;
  }
}

class _HomeFlowerLayer extends StatefulWidget {
  const _HomeFlowerLayer({required this.intensity});
  final int intensity;

  @override
  State<_HomeFlowerLayer> createState() => _HomeFlowerLayerState();
}

class _HomeFlowerLayerState extends State<_HomeFlowerLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final Color petalColor = brightness == Brightness.dark
        ? Colors.pinkAccent.withValues(alpha: 0.55)
        : Colors.pink.withValues(alpha: 0.45);
    final Color centerColor = brightness == Brightness.dark
        ? Colors.amberAccent.withValues(alpha: 0.9)
        : Colors.orangeAccent.withValues(alpha: 0.9);

    return IgnorePointer(
      child: CustomPaint(
        painter: _FlowerPainter(
          animation: _ctrl,
          intensity: widget.intensity,
          petalColor: petalColor,
          centerColor: centerColor,
        ),
      ),
    );
  }
}

class _FlowerPainter extends CustomPainter {
  _FlowerPainter({
    required this.animation,
    required this.intensity,
    required this.petalColor,
    required this.centerColor,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final int intensity;
  final Color petalColor;
  final Color centerColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final t = animation.value;
    final count = intensity.clamp(6, 40);
    final petalPaint = Paint()
      ..color = petalColor
      ..style = PaintingStyle.fill;
    final centerPaint = Paint()
      ..color = centerColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      final seed = i * 7919;
      final baseX = (seed % 1000) / 1000.0;
      final baseY = ((seed ~/ 1000) % 1000) / 1000.0;
      final speed = 0.15 + ((seed % 5) * 0.08); // yavaş, hafif hareket
      final yFrac = (baseY + speed * t) % 1.0;
      final x = size.width * baseX;
      final y = size.height * (1.0 - yFrac);

      final petalRadius = 3.0 + ((seed % 4) * 0.4);
      final centerRadius = petalRadius * 0.55;

      // 4 yaprak: sağ, sol, yukarı, aşağı
      canvas.drawCircle(Offset(x + petalRadius, y), petalRadius, petalPaint);
      canvas.drawCircle(Offset(x - petalRadius, y), petalRadius, petalPaint);
      canvas.drawCircle(Offset(x, y + petalRadius), petalRadius, petalPaint);
      canvas.drawCircle(Offset(x, y - petalRadius), petalRadius, petalPaint);

      // Orta nokta
      canvas.drawCircle(Offset(x, y), centerRadius, centerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FlowerPainter oldDelegate) {
    return oldDelegate.intensity != intensity ||
        oldDelegate.petalColor != petalColor ||
        oldDelegate.centerColor != centerColor;
  }
}
