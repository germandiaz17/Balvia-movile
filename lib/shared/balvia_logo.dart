import 'package:flutter/material.dart';

/// Minimal "M" / trend-line logo mark used on splash/login/register.
/// In a real product this would be an SVG asset; a custom painter avoids
/// bundling assets for now.
class BalviaLogoMark extends StatelessWidget {
  const BalviaLogoMark({super.key, required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _LogoPainter(color: color),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    // Stylised "M" / trend line with a dot — echoes the mockup logo
    final path = Path()
      ..moveTo(w * 0.08, h * 0.65)
      ..lineTo(w * 0.30, h * 0.35)
      ..lineTo(w * 0.50, h * 0.55)
      ..lineTo(w * 0.70, h * 0.25)
      ..lineTo(w * 0.92, h * 0.45);

    canvas.drawPath(path, paint);

    // Small dot at the peak
    canvas.drawCircle(
      Offset(w * 0.70, h * 0.25),
      w * 0.07,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
