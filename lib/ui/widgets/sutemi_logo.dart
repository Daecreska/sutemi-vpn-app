import 'package:flutter/material.dart';

class SutemiLogo extends StatelessWidget {
  final double size;
  const SutemiLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SutemiLogoPainter(),
    );
  }
}

class _SutemiLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final shieldPath = Path()
      ..moveTo(w * 0.50, h * 0.09)
      ..lineTo(w * 0.83, h * 0.22)
      ..lineTo(w * 0.83, h * 0.48)
      ..cubicTo(w * 0.83, h * 0.69, w * 0.68, h * 0.83, w * 0.50, h * 0.91)
      ..cubicTo(w * 0.32, h * 0.83, w * 0.17, h * 0.69, w * 0.17, h * 0.48)
      ..lineTo(w * 0.17, h * 0.22)
      ..close();

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0x52FFFFFF),
          Color(0x24DBE8FF),
          Color(0x10FFFFFF),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.042
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFCFE6FF),
          Color(0xFFE3D4FF),
          Color(0xFFAEF7EA),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(shieldPath, fillPaint);
    canvas.drawPath(shieldPath, strokePaint);

    // Top inner glass highlight arc
    final arcPath = Path()
      ..moveTo(w * 0.24, h * 0.26)
      ..quadraticBezierTo(w * 0.50, h * 0.16, w * 0.76, h * 0.26);
    canvas.drawPath(
      arcPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.022
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.62),
    );

    // Crown inside shield
    final crownPath = Path()
      ..moveTo(w * 0.31, h * 0.58)
      ..lineTo(w * 0.35, h * 0.37)
      ..lineTo(w * 0.44, h * 0.46)
      ..lineTo(w * 0.50, h * 0.31)
      ..lineTo(w * 0.56, h * 0.46)
      ..lineTo(w * 0.65, h * 0.37)
      ..lineTo(w * 0.69, h * 0.58)
      ..close();

    final crownPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFE6F0FF), Color(0xFFC3F7EC)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(crownPath, crownPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.33, h * 0.63, w * 0.34, h * 0.05),
        Radius.circular(w * 0.025),
      ),
      crownPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
