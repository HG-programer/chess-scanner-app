import 'package:flutter/material.dart';

/// Tournament-grade Chess Piece Widget that renders solid, filled, high-contrast
/// pieces with dual-stroke outlines and drop shadows, ensuring flawless visibility
/// on both light and dark squares without relying on external image asset bundles.
class ChessPieceWidget extends StatelessWidget {
  final String pieceChar; // e.g. 'P', 'p', 'N', 'n', etc.
  final double size;
  final bool isDragging;

  const ChessPieceWidget({
    Key? key,
    required this.pieceChar,
    this.size = 38.0,
    this.isDragging = false,
  }) : super(key: key);

  // Always use solid silhouette glyphs for consistent, filled piece anatomy
  static const Map<String, String> _solidGlyphs = {
    'k': '♚',
    'q': '♛',
    'r': '♜',
    'b': '♝',
    'n': '♞',
    'p': '♟',
  };

  @override
  Widget build(BuildContext context) {
    final isWhite = pieceChar == pieceChar.toUpperCase();
    final lower = pieceChar.toLowerCase();
    final glyph = _solidGlyphs[lower] ?? pieceChar;

    // Palette:
    // White pieces: Pure porcelain white with dark charcoal outline
    // Black pieces: Rich obsidian charcoal with crisp pearl white outline
    final fillColor = isWhite ? const Color(0xFFFFFFFF) : const Color(0xFF1C1C21);
    final strokeColor = isWhite ? const Color(0xFF141416) : const Color(0xFFFFFFFF);
    final strokeWidth = size * 0.085; // Proportional outline thickness

    return FittedBox(
      fit: BoxFit.contain,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Soft Ambient Depth Shadow
          Text(
            glyph,
            style: TextStyle(
              fontSize: size,
              height: 1.0,
              fontFamily: 'sans-serif',
              color: Colors.transparent,
              shadows: [
                Shadow(
                  blurRadius: isDragging ? 10.0 : 4.0,
                  color: Colors.black.withOpacity(isDragging ? 0.75 : 0.5),
                  offset: Offset(0, isDragging ? 6.0 : 2.5),
                ),
              ],
            ),
          ),

          // 2. Crisp Outer Stroke / Border (Guarantees contrast on all board squares)
          Text(
            glyph,
            style: TextStyle(
              fontSize: size,
              height: 1.0,
              fontFamily: 'sans-serif',
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeWidth
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round
                ..color = strokeColor,
            ),
          ),

          // 3. Solid Opaque Body Fill
          Text(
            glyph,
            style: TextStyle(
              fontSize: size,
              height: 1.0,
              fontFamily: 'sans-serif',
              color: fillColor,
            ),
          ),

          // 4. Subtle Inner Specular Highlight for White pieces (3D Porcelain Finish)
          if (isWhite)
            Positioned(
              top: 1,
              child: Opacity(
                opacity: 0.25,
                child: Text(
                  glyph,
                  style: TextStyle(
                    fontSize: size * 0.94,
                    height: 1.0,
                    fontFamily: 'sans-serif',
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
