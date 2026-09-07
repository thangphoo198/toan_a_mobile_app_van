import 'package:flutter/material.dart';

/// Minh hoa truc quan luu luong "con lai / da dat" bang 1 cai thung nuoc
/// (gop 2 StatBox rieng le truoc day thanh 1 hinh anh de doc hon).
class WaterTank extends StatelessWidget {
  final double? setValue;
  final double? remainValue;
  final double height;
  final double width;

  const WaterTank({
    super.key,
    required this.setValue,
    required this.remainValue,
    this.height = 140,
    this.width = 84,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = setValue != null && setValue! > 0 && remainValue != null;
    final ratio = hasData ? (remainValue! / setValue!).clamp(0.0, 1.0) : 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _TankPainter(
              ratio: ratio,
              tankColor: theme.colorScheme.outlineVariant,
              waterColor: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${remainValue?.toStringAsFixed(2) ?? '--'} m³',
                style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
              ),
              Text('còn lại', style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.flag_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text('Đã đặt: ${setValue?.toStringAsFixed(2) ?? '--'} m³', style: theme.textTheme.bodyMedium),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                hasData ? '${(ratio * 100).toStringAsFixed(0)}% còn lại' : '--',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TankPainter extends CustomPainter {
  final double ratio;
  final Color tankColor;
  final Color waterColor;

  _TankPainter({required this.ratio, required this.tankColor, required this.waterColor});

  @override
  void paint(Canvas canvas, Size size) {
    final tankRRect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));

    // Nen thung (rong) - mo, phan biet voi phan co nuoc
    canvas.drawRRect(tankRRect.deflate(1.5), Paint()..color = tankColor.withValues(alpha: 0.12));

    // Vien thung
    canvas.drawRRect(
      tankRRect.deflate(1.5),
      Paint()
        ..color = tankColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Ve nuoc ben trong, cat theo hinh thung (bo goc)
    canvas.save();
    canvas.clipRRect(tankRRect.deflate(3));

    final waterHeight = size.height * ratio;
    final waterTop = size.height - waterHeight;

    final wavePath = Path()..moveTo(0, waterTop + 6);
    wavePath.quadraticBezierTo(size.width * 0.25, waterTop - 4, size.width * 0.5, waterTop + 6);
    wavePath.quadraticBezierTo(size.width * 0.75, waterTop + 16, size.width, waterTop + 6);
    wavePath.lineTo(size.width, size.height);
    wavePath.lineTo(0, size.height);
    wavePath.close();

    final waterPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [waterColor.withValues(alpha: 0.7), waterColor],
      ).createShader(Offset.zero & size);
    canvas.drawPath(wavePath, waterPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TankPainter oldDelegate) => oldDelegate.ratio != ratio;
}
