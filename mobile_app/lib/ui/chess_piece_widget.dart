import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Professional Tournament-Grade Vector Chess Piece Widget.
/// Uses 100% pure Flutter Canvas vector paths (NO font glyphs, NO FreeType text strokes),
/// completely eliminating horizontal line artifacts, missing font glyphs, or emoji bugs.
class ChessPieceWidget extends StatelessWidget {
  final String pieceChar; // 'P', 'p', 'R', 'r', 'N', 'n', 'B', 'b', 'Q', 'q', 'K', 'k'
  final double size;
  final bool isDragging;

  const ChessPieceWidget({
    Key? key,
    required this.pieceChar,
    this.size = 40.0,
    this.isDragging = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isWhite = pieceChar == pieceChar.toUpperCase();
    final type = pieceChar.toLowerCase();

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _VectorPiecePainter(
          type: type,
          isWhite: isWhite,
          isDragging: isDragging,
        ),
      ),
    );
  }
}

class _VectorPiecePainter extends CustomPainter {
  final String type;
  final bool isWhite;
  final bool isDragging;

  _VectorPiecePainter({
    required this.type,
    required this.isWhite,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Draw drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(isDragging ? 0.6 : 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, isDragging ? 6.0 : 2.5);
    canvas.save();
    canvas.translate(0, isDragging ? 4.0 : 1.8);
    _drawPieceSilhouette(canvas, w, h, shadowPaint);
    canvas.restore();

    // Fill Paint (Gradient porcelain for White, gradient obsidian for Black)
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isWhite
            ? [const Color(0xFFFFFFFF), const Color(0xFFEBE6DC)]
            : [const Color(0xFF383A44), const Color(0xFF16171B)],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    // Stroke Paint (Crisp dark contour for White, crisp pearl-white contour for Black)
    final strokePaint = Paint()
      ..color = isWhite ? const Color(0xFF1E1E22) : const Color(0xFFF4F4F5)
      ..strokeWidth = math.max(1.6, w * 0.045)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Detail Stroke Paint (Inner lines, cuts, crowns)
    final detailPaint = Paint()
      ..color = isWhite ? const Color(0xFF323238) : const Color(0xFFE4E4E7)
      ..strokeWidth = math.max(1.2, w * 0.035)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw main piece body
    _drawPieceBody(canvas, w, h, fillPaint, strokePaint, detailPaint);
  }

  void _drawPieceSilhouette(Canvas canvas, double w, double h, Paint paint) {
    _drawPieceBody(canvas, w, h, paint, paint, paint);
  }

  void _drawPieceBody(
    Canvas canvas,
    double w,
    double h,
    Paint fill,
    Paint stroke,
    Paint detail,
  ) {
    switch (type) {
      case 'p':
        _drawPawn(canvas, w, h, fill, stroke, detail);
        break;
      case 'r':
        _drawRook(canvas, w, h, fill, stroke, detail);
        break;
      case 'n':
        _drawKnight(canvas, w, h, fill, stroke, detail);
        break;
      case 'b':
        _drawBishop(canvas, w, h, fill, stroke, detail);
        break;
      case 'q':
        _drawQueen(canvas, w, h, fill, stroke, detail);
        break;
      case 'k':
        _drawKing(canvas, w, h, fill, stroke, detail);
        break;
      default:
        _drawPawn(canvas, w, h, fill, stroke, detail);
    }
  }

  // --- 1. PAWN ---
  void _drawPawn(Canvas canvas, double w, double h, Paint fill, Paint stroke, Paint detail) {
    // Pedestal Base
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.22, h * 0.80, w * 0.56, h * 0.11),
      Radius.circular(w * 0.05),
    );
    canvas.drawRRect(baseRect, fill);
    canvas.drawRRect(baseRect, stroke);

    // Tapered Body & Collar
    final bodyPath = Path()
      ..moveTo(w * 0.28, h * 0.80)
      ..quadraticBezierTo(w * 0.38, h * 0.60, w * 0.38, h * 0.44)
      ..lineTo(w * 0.62, h * 0.44)
      ..quadraticBezierTo(w * 0.62, h * 0.60, w * 0.72, h * 0.80)
      ..close();
    canvas.drawPath(bodyPath, fill);
    canvas.drawPath(bodyPath, stroke);

    // Collar Ring
    final collarRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.32, h * 0.40, w * 0.36, h * 0.07),
      Radius.circular(w * 0.035),
    );
    canvas.drawRRect(collarRect, fill);
    canvas.drawRRect(collarRect, stroke);

    // Head Sphere
    final headCenter = Offset(w * 0.50, h * 0.26);
    final headRadius = w * 0.155;
    canvas.drawCircle(headCenter, headRadius, fill);
    canvas.drawCircle(headCenter, headRadius, stroke);
  }

  // --- 2. ROOK ---
  void _drawRook(Canvas canvas, double w, double h, Paint fill, Paint stroke, Paint detail) {
    // Pedestal Base
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, h * 0.81, w * 0.64, h * 0.11),
      Radius.circular(w * 0.04),
    );
    canvas.drawRRect(baseRect, fill);
    canvas.drawRRect(baseRect, stroke);

    // Tower Body
    final towerPath = Path()
      ..moveTo(w * 0.24, h * 0.81)
      ..lineTo(w * 0.28, h * 0.36)
      ..lineTo(w * 0.72, h * 0.36)
      ..lineTo(w * 0.76, h * 0.81)
      ..close();
    canvas.drawPath(towerPath, fill);
    canvas.drawPath(towerPath, stroke);

    // Crenellated Battlements (3 Turrets)
    final crenelPath = Path()
      ..moveTo(w * 0.22, h * 0.36)
      ..lineTo(w * 0.22, h * 0.18) // Left turret
      ..lineTo(w * 0.35, h * 0.18)
      ..lineTo(w * 0.35, h * 0.26) // Left embrasure
      ..lineTo(w * 0.43, h * 0.26)
      ..lineTo(w * 0.43, h * 0.18) // Center turret
      ..lineTo(w * 0.57, h * 0.18)
      ..lineTo(w * 0.57, h * 0.26) // Right embrasure
      ..lineTo(w * 0.65, h * 0.26)
      ..lineTo(w * 0.65, h * 0.18) // Right turret
      ..lineTo(w * 0.78, h * 0.18)
      ..lineTo(w * 0.78, h * 0.36)
      ..close();
    canvas.drawPath(crenelPath, fill);
    canvas.drawPath(crenelPath, stroke);

    // Arrow slit detail
    final slitRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.46, h * 0.48, w * 0.08, h * 0.18),
      Radius.circular(w * 0.03),
    );
    canvas.drawRRect(slitRect, detail);
  }

  // --- 3. KNIGHT ---
  void _drawKnight(Canvas canvas, double w, double h, Paint fill, Paint stroke, Paint detail) {
    // Pedestal Base
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.20, h * 0.82, w * 0.60, h * 0.10),
      Radius.circular(w * 0.04),
    );
    canvas.drawRRect(baseRect, fill);
    canvas.drawRRect(baseRect, stroke);

    // Iconic Horse Head Silhouette
    final horsePath = Path()
      ..moveTo(w * 0.26, h * 0.82)
      ..quadraticBezierTo(w * 0.22, h * 0.65, w * 0.32, h * 0.52) // Breast curve
      ..lineTo(w * 0.20, h * 0.48) // Snout / Muzzle
      ..quadraticBezierTo(w * 0.18, h * 0.38, w * 0.30, h * 0.34) // Chin & Nostril
      ..lineTo(w * 0.44, h * 0.22) // Forehead
      ..lineTo(w * 0.48, h * 0.12) // Ear point
      ..lineTo(w * 0.56, h * 0.20) // Back of ear
      ..quadraticBezierTo(w * 0.76, h * 0.32, w * 0.74, h * 0.54) // Arched crest & mane
      ..quadraticBezierTo(w * 0.75, h * 0.68, w * 0.74, h * 0.82) // Back neck to base
      ..close();

    canvas.drawPath(horsePath, fill);
    canvas.drawPath(horsePath, stroke);

    // Eye Detail
    final eyeCenter = Offset(w * 0.38, h * 0.32);
    canvas.drawCircle(eyeCenter, w * 0.035, detail);

    // Mane Flutes
    canvas.drawLine(Offset(w * 0.62, h * 0.32), Offset(w * 0.52, h * 0.42), detail);
    canvas.drawLine(Offset(w * 0.68, h * 0.46), Offset(w * 0.56, h * 0.54), detail);
    canvas.drawLine(Offset(w * 0.70, h * 0.60), Offset(w * 0.58, h * 0.66), detail);
  }

  // --- 4. BISHOP ---
  void _drawBishop(Canvas canvas, double w, double h, Paint fill, Paint stroke, Paint detail) {
    // Base
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.20, h * 0.81, w * 0.60, h * 0.11),
      Radius.circular(w * 0.04),
    );
    canvas.drawRRect(baseRect, fill);
    canvas.drawRRect(baseRect, stroke);

    // Body
    final bodyPath = Path()
      ..moveTo(w * 0.26, h * 0.81)
      ..quadraticBezierTo(w * 0.36, h * 0.62, w * 0.38, h * 0.45)
      ..lineTo(w * 0.62, h * 0.45)
      ..quadraticBezierTo(w * 0.64, h * 0.62, w * 0.74, h * 0.81)
      ..close();
    canvas.drawPath(bodyPath, fill);
    canvas.drawPath(bodyPath, stroke);

    // Collar Bead
    final collarRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.34, h * 0.42, w * 0.32, h * 0.07),
      Radius.circular(w * 0.035),
    );
    canvas.drawRRect(collarRect, fill);
    canvas.drawRRect(collarRect, stroke);

    // Mitre Dome
    final mitrePath = Path()
      ..moveTo(w * 0.32, h * 0.42)
      ..cubicTo(w * 0.24, h * 0.30, w * 0.42, h * 0.17, w * 0.50, h * 0.16)
      ..cubicTo(w * 0.58, h * 0.17, w * 0.76, h * 0.30, w * 0.68, h * 0.42)
      ..close();
    canvas.drawPath(mitrePath, fill);
    canvas.drawPath(mitrePath, stroke);

    // Top Finial Ball
    canvas.drawCircle(Offset(w * 0.50, h * 0.12), w * 0.05, fill);
    canvas.drawCircle(Offset(w * 0.50, h * 0.12), w * 0.05, stroke);

    // Mitre Slash Cut (Iconic Bishop cross-slit)
    canvas.drawLine(Offset(w * 0.42, h * 0.26), Offset(w * 0.56, h * 0.34), detail);
  }

  // --- 5. QUEEN ---
  void _drawQueen(Canvas canvas, double w, double h, Paint fill, Paint stroke, Paint detail) {
    // Base
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, h * 0.82, w * 0.64, h * 0.10),
      Radius.circular(w * 0.04),
    );
    canvas.drawRRect(baseRect, fill);
    canvas.drawRRect(baseRect, stroke);

    // Robe Waist
    final waistPath = Path()
      ..moveTo(w * 0.24, h * 0.82)
      ..quadraticBezierTo(w * 0.38, h * 0.66, w * 0.36, h * 0.46)
      ..lineTo(w * 0.64, h * 0.46)
      ..quadraticBezierTo(w * 0.62, h * 0.66, w * 0.76, h * 0.82)
      ..close();
    canvas.drawPath(waistPath, fill);
    canvas.drawPath(waistPath, stroke);

    // Coronet Peaks (5 Peaks)
    final crownPath = Path()
      ..moveTo(w * 0.24, h * 0.46)
      ..lineTo(w * 0.18, h * 0.25) // Peak 1
      ..lineTo(w * 0.32, h * 0.36)
      ..lineTo(w * 0.36, h * 0.20) // Peak 2
      ..lineTo(w * 0.46, h * 0.32)
      ..lineTo(w * 0.50, h * 0.15) // Peak 3 (Center)
      ..lineTo(w * 0.54, h * 0.32)
      ..lineTo(w * 0.64, h * 0.20) // Peak 4
      ..lineTo(w * 0.68, h * 0.36)
      ..lineTo(w * 0.82, h * 0.25) // Peak 5
      ..lineTo(w * 0.76, h * 0.46)
      ..close();
    canvas.drawPath(crownPath, fill);
    canvas.drawPath(crownPath, stroke);

    // 5 Pearls on Coronet
    final pearls = [
      Offset(w * 0.18, h * 0.24),
      Offset(w * 0.36, h * 0.19),
      Offset(w * 0.50, h * 0.14),
      Offset(w * 0.64, h * 0.19),
      Offset(w * 0.82, h * 0.24),
    ];
    for (final p in pearls) {
      canvas.drawCircle(p, w * 0.038, fill);
      canvas.drawCircle(p, w * 0.038, stroke);
    }
  }

  // --- 6. KING ---
  void _drawKing(Canvas canvas, double w, double h, Paint fill, Paint stroke, Paint detail) {
    // Base
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, h * 0.82, w * 0.64, h * 0.10),
      Radius.circular(w * 0.04),
    );
    canvas.drawRRect(baseRect, fill);
    canvas.drawRRect(baseRect, stroke);

    // Regal Shoulders
    final shouldersPath = Path()
      ..moveTo(w * 0.24, h * 0.82)
      ..quadraticBezierTo(w * 0.36, h * 0.65, w * 0.32, h * 0.46)
      ..lineTo(w * 0.68, h * 0.46)
      ..quadraticBezierTo(w * 0.64, h * 0.65, w * 0.76, h * 0.82)
      ..close();
    canvas.drawPath(shouldersPath, fill);
    canvas.drawPath(shouldersPath, stroke);

    // Imperial Crown Dome (Arched Triple Crest)
    final crownPath = Path()
      ..moveTo(w * 0.26, h * 0.46)
      ..cubicTo(w * 0.18, h * 0.30, w * 0.34, h * 0.24, w * 0.50, h * 0.24)
      ..cubicTo(w * 0.66, h * 0.24, w * 0.82, h * 0.30, w * 0.74, h * 0.46)
      ..close();
    canvas.drawPath(crownPath, fill);
    canvas.drawPath(crownPath, stroke);

    // Imperial Cross Finial at the Apex
    // Vertical stem
    final crossV = Rect.fromLTWH(w * 0.46, h * 0.08, w * 0.08, h * 0.16);
    canvas.drawRRect(RRect.fromRectAndRadius(crossV, Radius.circular(w * 0.015)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(crossV, Radius.circular(w * 0.015)), stroke);

    // Horizontal arm
    final crossH = Rect.fromLTWH(w * 0.39, h * 0.12, w * 0.22, h * 0.07);
    canvas.drawRRect(RRect.fromRectAndRadius(crossH, Radius.circular(w * 0.015)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(crossH, Radius.circular(w * 0.015)), stroke);
  }

  @override
  bool shouldRepaint(covariant _VectorPiecePainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.isWhite != isWhite ||
        oldDelegate.isDragging != isDragging;
  }
}
