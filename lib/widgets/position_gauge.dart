import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants.dart';

/// Vong tron N doan (1 doan/vi tri) hien thi truc quan vi tri hien tai cua
/// van trong cac buoc xu ly nuoc - thay cho vong tron so don gian truoc day.
/// [FIX] So doan (N) va nhan/mau doan phai theo DUNG model - van 3 cua
/// (F041/F043) chi co 3 buoc THAT SU (motor3.c ben firmware), ve 5 doan cho
/// model nay se gay hieu nham co 5 buoc. Xem modeForPosition()/
/// maxPositionsForModel() trong constants.dart.
class PositionGauge extends StatelessWidget {
  final int? position;
  final bool isMoving;
  final double size;
  final String? modelCode;

  const PositionGauge({super.key, required this.position, required this.isMoving, this.size = 132, this.modelCode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = modeForPosition(modelCode, position);
    final totalSegments = maxPositionsForModel(modelCode);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GaugePainter(
              position: position,
              totalSegments: totalSegments,
              trackColor: theme.colorScheme.surfaceContainerHighest,
              activeColor: mode?.color ?? theme.colorScheme.primary,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMoving)
                SizedBox(
                  width: size * 0.2,
                  height: size * 0.2,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: mode?.color ?? theme.colorScheme.primary),
                )
              else
                // [FIX] Icon che do (1-5) to ro rang hon - truoc day co dinh
                // 22px, khong theo kich thuoc vong tron nen nhin nho/mo nhat
                // khi vong tron duoc phong to. Ty le theo [size] de luon can
                // doi, du goi voi kich thuoc nao.
                Text(mode?.icon ?? '•', style: TextStyle(fontSize: size * 0.34)),
              SizedBox(height: size * 0.02),
              Text(
                position?.toString() ?? '--',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: mode?.color ?? theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final int? position;
  final int totalSegments;
  final Color trackColor;
  final Color activeColor;

  _GaugePainter({required this.position, required this.totalSegments, required this.trackColor, required this.activeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 20) / 2;
    const gapDeg = 9.0;
    final segDeg = 360 / totalSegments - gapDeg;
    const startOffset = -90.0; // bat dau tu dinh (12 gio)

    for (var i = 1; i <= totalSegments; i++) {
      final active = position == i;
      final startAngle = (startOffset + (i - 1) * 360 / totalSegments + gapDeg / 2) * math.pi / 180;
      final sweepAngle = segDeg * math.pi / 180;
      final rect = Rect.fromCircle(center: center, radius: radius);

      if (active) {
        // [FIX] "Vong tron net dep hon" - them lop hao quang (glow) mo phia
        // sau doan dang active, tao cam giac noi khoi/trau chuot hon 1 net
        // ke tron truoc day.
        final glowPaint = Paint()
          ..color = activeColor.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 20
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);
      }

      final paint = Paint()
        ..color = active ? activeColor : trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 12 : 7
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.totalSegments != totalSegments;
}
