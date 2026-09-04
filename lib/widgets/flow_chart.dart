import 'package:flutter/material.dart';
import '../models/telemetry_state.dart';

/// Biểu đồ đường thể hiện lưu lượng nước (f_speed) biến thiên theo thời
/// gian gần đây - vẽ tay bằng CustomPainter (không thêm thư viện biểu đồ
/// mới, giữ app nhẹ) từ lịch sử mẫu tích luỹ trong TelemetryState.flowHistory.
class FlowChart extends StatelessWidget {
  final List<FlowSample> samples;
  final double height;

  const FlowChart({super.key, required this.samples, this.height = 150});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (samples.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Đang thu thập dữ liệu để vẽ biểu đồ...',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _FlowChartPainter(
          samples: samples,
          lineColor: theme.colorScheme.primary,
          gridColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          labelColor: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _FlowChartPainter extends CustomPainter {
  final List<FlowSample> samples;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;

  _FlowChartPainter({
    required this.samples,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
  });

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  @override
  void paint(Canvas canvas, Size size) {
    const topPad = 18.0, bottomPad = 18.0;
    final chartRect = Rect.fromLTWH(0, topPad, size.width, size.height - topPad - bottomPad);

    final maxV = samples.map((s) => s.speed).reduce((a, b) => a > b ? a : b);
    // Luon bat dau tu 0 (luu luong khong am) va chua them 15% khoang trong
    // phia tren cho de doc, tranh duong ke dinh sat vien tren.
    final axisMax = maxV <= 0 ? 1.0 : maxV * 1.15;

    // --- Luoi ngang (3 duong) ---
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = chartRect.top + chartRect.height * i / 2;
      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), gridPaint);
    }

    Offset pointAt(int i) {
      final x = chartRect.left + chartRect.width * i / (samples.length - 1);
      final y = chartRect.bottom - (samples[i].speed / axisMax) * chartRect.height;
      return Offset(x, y);
    }

    final linePath = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < samples.length; i++) {
      final p = pointAt(i);
      linePath.lineTo(p.dx, p.dy);
    }

    // --- Vùng tô gradient dưới đường - tạo cảm giác "trau chuốt" hơn nét kẻ trơn ---
    final fillPath = Path()..addPath(linePath, Offset.zero);
    fillPath.lineTo(pointAt(samples.length - 1).dx, chartRect.bottom);
    fillPath.lineTo(pointAt(0).dx, chartRect.bottom);
    fillPath.close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lineColor.withValues(alpha: 0.30), lineColor.withValues(alpha: 0.0)],
      ).createShader(chartRect);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // --- Điểm nhấn giá trị hiện tại (mẫu cuối) ---
    final lastPoint = pointAt(samples.length - 1);
    canvas.drawCircle(lastPoint, 7, Paint()..color = lineColor.withValues(alpha: 0.22));
    canvas.drawCircle(lastPoint, 3.5, Paint()..color = lineColor);

    // --- Nhãn giá trị lớn nhất (góc trên trái) ---
    _drawLabel(canvas, '${maxV.toStringAsFixed(1)} L/h (đỉnh)', Offset(chartRect.left, 0), labelColor);

    // --- Nhãn thời gian đầu/cuối (trục dưới) ---
    _drawLabel(canvas, _fmtTime(samples.first.time), Offset(chartRect.left, chartRect.bottom + 4), labelColor);
    final endText = _fmtTime(samples.last.time);
    final endWidth = _textWidth(endText, labelColor);
    _drawLabel(canvas, endText, Offset(chartRect.right - endWidth, chartRect.bottom + 4), labelColor);
  }

  double _textWidth(String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 10.5)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 10.5)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _FlowChartPainter oldDelegate) => true;
}
