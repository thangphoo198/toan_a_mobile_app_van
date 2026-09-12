import 'package:flutter/material.dart';
import '../models/telemetry_state.dart';

/// Biểu đồ đường thể hiện lưu lượng nước (f_speed) biến thiên theo thời
/// gian gần đây - vẽ tay bằng CustomPainter (không thêm thư viện biểu đồ
/// mới, giữ app nhẹ) từ lịch sử mẫu tích luỹ trong TelemetryState.flowHistory.
/// [FIX] Duong cong lam muot (Catmull-Rom -> Bezier) thay vi noi thang tung
/// doan - "rang cua" truoc day khong phai do THIEU du lieu (cal_flow_sensor()
/// ben firmware gui ##MON## moi ~1-5s khi co luu luong - kha day), ma do CACH
/// VE noi diem bang duong thang. Them truc Y co nhan so (truoc day chi co 3
/// gach ngang khong nhan) va nhieu moc thoi gian hon o truc X.
class FlowChart extends StatelessWidget {
  final List<FlowSample> samples;
  final double height;

  const FlowChart({super.key, required this.samples, this.height = 170});

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
    const topPad = 20.0, bottomPad = 18.0;
    // [NEW] Danh cho truc Y ben trai - can du cho nhan so (vd "12.3") -
    // truoc day bieu do chiem het chieu rong, khong co truc Y nao ca.
    const leftAxisW = 36.0;
    final chartRect = Rect.fromLTWH(leftAxisW, topPad, size.width - leftAxisW, size.height - topPad - bottomPad);

    final maxV = samples.map((s) => s.speed).reduce((a, b) => a > b ? a : b);
    final lastV = samples.last.speed;
    // Luon bat dau tu 0 (luu luong khong am) va chua them 15% khoang trong
    // phia tren cho de doc, tranh duong ke dinh sat vien tren.
    final axisMax = maxV <= 0 ? 1.0 : maxV * 1.15;

    // --- Truc Y: 4 muc (0, 1/3, 2/3, day) kem nhan so + duong ke ngang ---
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final frac = i / 3;
      final y = chartRect.bottom - chartRect.height * frac;
      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), gridPaint);
      final labelVal = axisMax * frac;
      final tp = _layout(labelVal.toStringAsFixed(labelVal < 10 ? 1 : 0), labelColor, 9.5);
      tp.paint(canvas, Offset(leftAxisW - tp.width - 4, y - tp.height / 2));
    }
    // Duong truc doc mong ben trai cho ro rang "day la truc", khong chi la
    // 1 duong ke ngang troi giua khoang trong.
    canvas.drawLine(Offset(chartRect.left, chartRect.top), Offset(chartRect.left, chartRect.bottom), gridPaint);

    // --- Quy doi mau sang toa do man hinh ---
    final points = <Offset>[
      for (var i = 0; i < samples.length; i++)
        Offset(
          chartRect.left + chartRect.width * i / (samples.length - 1),
          chartRect.bottom - (samples[i].speed / axisMax) * chartRect.height,
        ),
    ];

    // [FIX] Duong cong muot (Catmull-Rom -> Bezier, he so cang 1/6 chuan) -
    // thay the noi thang tung doan truoc day tao cam giac "gay khuc"/tho khi
    // co nhieu mau bien thien nhanh. On dinh, khong vong bat thuong voi du
    // lieu don dieu/it nhieu nhu luu luong nuoc thuc te.
    final linePath = _smoothPath(points);

    // --- Vùng tô gradient dưới đường - tạo cảm giác "trau chuốt" hơn nét kẻ trơn ---
    final fillPath = Path()
      ..addPath(linePath, Offset.zero)
      ..lineTo(points.last.dx, chartRect.bottom)
      ..lineTo(points.first.dx, chartRect.bottom)
      ..close();
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
    final lastPoint = points.last;
    canvas.drawCircle(lastPoint, 7, Paint()..color = lineColor.withValues(alpha: 0.22));
    canvas.drawCircle(lastPoint, 3.5, Paint()..color = lineColor);

    // --- Nhãn giá trị hiện tại + đỉnh (góc trên) ---
    // [FIX] Don vi DUNG la m³/h (khop cong thuc cal_flow_sensor() ben firmware
    // - xem chu thich trong monitor_tab.dart), khong phai "L/h" nhu truoc day.
    _drawLabel(canvas, '${lastV.toStringAsFixed(2)} m³/h (hiện tại)', Offset(chartRect.left, 0), lineColor, bold: true);
    final peakText = '${maxV.toStringAsFixed(2)} m³/h (đỉnh)';
    final peakWidth = _textWidth(peakText, labelColor, 10);
    _drawLabel(canvas, peakText, Offset(chartRect.right - peakWidth, 0), labelColor, size: 10);

    // --- Nhãn thời gian: dau/giua/cuoi truc duoi (truoc day chi co dau/cuoi) ---
    _drawLabel(canvas, _fmtTime(samples.first.time), Offset(chartRect.left, chartRect.bottom + 4), labelColor);
    final midIdx = samples.length ~/ 2;
    final midText = _fmtTime(samples[midIdx].time);
    final midWidth = _textWidth(midText, labelColor, 10.5);
    _drawLabel(canvas, midText, Offset(chartRect.left + chartRect.width / 2 - midWidth / 2, chartRect.bottom + 4), labelColor);
    final endText = _fmtTime(samples.last.time);
    final endWidth = _textWidth(endText, labelColor, 10.5);
    _drawLabel(canvas, endText, Offset(chartRect.right - endWidth, chartRect.bottom + 4), labelColor);
  }

  /// Catmull-Rom -> Bezier: noi tung cap diem lien tiep bang 1 doan cubic,
  /// dung 2 diem lang gieng (truoc/sau) de uoc luong tiep tuyen tai moi diem
  /// - cho duong cong di QUA DUNG tat ca cac mau (khong xap xi/lam sai lech
  /// so lieu thuc), chi lam MUOT phan noi giua 2 mau thay vi goc nhon.
  Path _smoothPath(List<Offset> pts) {
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
      return path;
    }
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = (i + 2 < pts.length) ? pts[i + 2] : p2;
      final cp1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final cp2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  TextPainter _layout(String text, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  double _textWidth(String text, Color color, double size) => _layout(text, color, size).width;

  void _drawLabel(Canvas canvas, String text, Offset offset, Color color, {double size = 10.5, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : null)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _FlowChartPainter oldDelegate) => true;
}
