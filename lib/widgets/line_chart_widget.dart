// lib/widgets/line_chart_widget.dart
//
// Renders a line chart with 4 draggable threshold lines (A, B, C, D).
// Used on the playback screen after recording, and in the overlay.

import 'package:flutter/material.dart';

const lineColors = {
  'a': Color(0xFFef4444), // red - near down
  'b': Color(0xFF22c55e), // green - near up
  'c': Color(0xFFb91c1c), // dark red - far down
  'd': Color(0xFF15803d), // dark green - far up
};

const lineLabels = {
  'a': 'A  Near-down',
  'b': 'B  Near-up',
  'c': 'C  Far-down',
  'd': 'D  Far-up',
};

class LineChartWidget extends StatefulWidget {
  final List<double> chartData;
  final int activeLineIndex; // 0=A,1=B,2=C,3=D — current line being placed
  final Map<String, double> linePositions; // 0.0–1.0 as fraction of chart height
  final Map<String, bool> lineLocked;
  final void Function(String key, double newFraction) onLineDragged;
  final void Function(String key) onLockTapped;

  const LineChartWidget({
    super.key,
    required this.chartData,
    required this.activeLineIndex,
    required this.linePositions,
    required this.lineLocked,
    required this.onLineDragged,
    required this.onLockTapped,
  });

  @override
  State<LineChartWidget> createState() => _LineChartWidgetState();
}

class _LineChartWidgetState extends State<LineChartWidget> {
  String? _dragging;

  static const _keys = ['a', 'b', 'c', 'd'];

  bool _isVisible(int idx) {
    return idx <= widget.activeLineIndex || (widget.lineLocked[_keys[idx]] ?? false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final h = constraints.maxHeight;
      final w = constraints.maxWidth;

      return GestureDetector(
        onVerticalDragUpdate: (details) {
          if (_dragging == null) return;
          final RenderBox box = context.findRenderObject() as RenderBox;
          final local = box.globalToLocal(details.globalPosition);
          final frac = (local.dy / h).clamp(0.05, 0.95);
          widget.onLineDragged(_dragging!, frac);
        },
        onVerticalDragEnd: (_) => setState(() => _dragging = null),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0a0e14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              // Chart line
              CustomPaint(
                size: Size(w, h),
                painter: _ChartPainter(data: widget.chartData),
              ),
              // Center line
              Positioned(
                top: h / 2 - 0.5,
                left: 0, right: 0,
                child: Container(height: 1, color: Colors.white12),
              ),
              // 4 threshold lines
              ..._keys.asMap().entries.map((entry) {
                final idx = entry.key;
                final key = entry.value;
                if (!_isVisible(idx)) return const SizedBox.shrink();

                final frac = widget.linePositions[key] ?? 0.5;
                final locked = widget.lineLocked[key] ?? false;
                final isActive = idx == widget.activeLineIndex && !locked;
                final color = lineColors[key]!;
                final pct = ((0.5 - frac) * 10).toStringAsFixed(2);

                return Positioned(
                  top: (frac * h) - 14,
                  left: 0, right: 0,
                  height: 28,
                  child: GestureDetector(
                    onVerticalDragStart: locked ? null : (_) {
                      setState(() => _dragging = key);
                    },
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Positioned(
                          top: 13, left: 0, right: 0,
                          child: Container(
                            height: 2,
                            color: color.withOpacity(locked ? 0.7 : 1.0),
                            decoration: BoxDecoration(
                              boxShadow: isActive
                                  ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6)]
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${lineLabels[key]}  ${double.parse(pct) >= 0 ? '+' : ''}$pct%',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 8,
                          child: GestureDetector(
                            onTap: () => widget.onLockTapped(key),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                border: Border.all(color: color),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                locked ? Icons.lock : Icons.lock_open,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> data;
  _ChartPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final min = data.reduce((a, b) => a < b ? a : b);
    final max = data.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs();
    final pad = range * 0.15;

    double toY(double v) => size.height - ((v - min + pad) / (range + pad * 2)) * size.height;

    final path = Path();
    final stepX = size.width / (data.length - 1);
    path.moveTo(0, toY(data[0]));
    for (int i = 1; i < data.length; i++) {
      path.lineTo(stepX * i, toY(data[i]));
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF2dd4bf)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Dot at current end
    canvas.drawCircle(
      Offset(size.width, toY(data.last)),
      4,
      Paint()..color = const Color(0xFF2dd4bf),
    );
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.data != data;
}
