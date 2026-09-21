import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess_logic;

/// Interactive 8x8 Chessboard Widget with piece dragging, tap-to-move,
/// legal move highlights, and AI best-move arrow rendering.
class InteractiveChessboard extends StatefulWidget {
  final String fen;
  final String? bestMove; // UCI format e.g. "e2e4"
  final bool isWhiteOrientation;
  final Function(String from, String to, String newFen) onMoveMade;

  const InteractiveChessboard({
    Key? key,
    required this.fen,
    this.bestMove,
    this.isWhiteOrientation = true,
    required this.onMoveMade,
  }) : super(key: key);

  @override
  State<InteractiveChessboard> createState() => _InteractiveChessboardState();
}

class _InteractiveChessboardState extends State<InteractiveChessboard> {
  String? _selectedSquare;
  List<String> _legalMoves = [];
  late chess_logic.Chess _chess;

  final Map<String, String> _glyphs = {
    'K': '♔', 'Q': '♕', 'R': '♖', 'B': '♗', 'N': '♘', 'P': '♙',
    'k': '♚', 'q': '♛', 'r': '♜', 'b': '♝', 'n': '♞', 'p': '♟'
  };

  @override
  void initState() {
    super.initState();
    _loadChess();
  }

  @override
  void didUpdateWidget(covariant InteractiveChessboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fen != widget.fen) {
      _loadChess();
      _selectedSquare = null;
      _legalMoves = [];
    }
  }

  void _loadChess() {
    try {
      _chess = chess_logic.Chess.fromFEN(widget.fen);
    } catch (_) {
      _chess = chess_logic.Chess();
    }
  }

  String _coordsToSquare(int row, int col) {
    // row 0 = rank 8 (if white orientation)
    final file = String.fromCharCode('a'.codeUnitAt(0) + (widget.isWhiteOrientation ? col : 7 - col));
    final rank = widget.isWhiteOrientation ? (8 - row).toString() : (row + 1).toString();
    return '$file$rank';
  }

  String? _getPieceAtSquare(String sq) {
    final piece = _chess.get(sq);
    if (piece == null) return null;
    return piece.color == chess_logic.Color.WHITE
        ? piece.type.name.toUpperCase()
        : piece.type.name.toLowerCase();
  }

  void _onSquareTapped(String sq) {
    if (_selectedSquare == null) {
      final piece = _chess.get(sq);
      if (piece != null && piece.color == _chess.turn) {
        setState(() {
          _selectedSquare = sq;
          final moves = _chess.moves({'square': sq, 'verbose': true});
          _legalMoves = moves.map((m) => m['to'] as String).toList();
        });
      }
    } else {
      if (_legalMoves.contains(sq)) {
        final from = _selectedSquare!;
        final success = _chess.move({'from': from, 'to': sq, 'promotion': 'q'});
        if (success) {
          widget.onMoveMade(from, sq, _chess.fen);
          setState(() {
            _selectedSquare = null;
            _legalMoves = [];
          });
          return;
        }
      }
      // Select another piece or deselect
      final piece = _chess.get(sq);
      setState(() {
        if (piece != null && piece.color == _chess.turn) {
          _selectedSquare = sq;
          final moves = _chess.moves({'square': sq, 'verbose': true});
          _legalMoves = moves.map((m) => m['to'] as String).toList();
        } else {
          _selectedSquare = null;
          _legalMoves = [];
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              // 8x8 Grid
              Column(
                children: List.generate(8, (r) {
                  return Expanded(
                    child: Row(
                      children: List.generate(8, (c) {
                        final sq = _coordsToSquare(r, c);
                        final isLight = (r + c) % 2 == 0;
                        final isSelected = sq == _selectedSquare;
                        final isLegal = _legalMoves.contains(sq);
                        final pieceChar = _getPieceAtSquare(sq);

                        final bgColor = isLight ? const Color(0xFFF0D9B5) : const Color(0xFFB58863);

                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _onSquareTapped(sq),
                            child: Container(
                              color: isSelected ? const Color(0xFFBBCB44) : bgColor,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Legal move dot
                                  if (isLegal)
                                    Container(
                                      width: pieceChar == null ? 14 : null,
                                      height: pieceChar == null ? 14 : null,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black.withOpacity(pieceChar == null ? 0.25 : 0.0),
                                        border: pieceChar != null
                                            ? Border.all(color: Colors.black.withOpacity(0.35), width: 4)
                                            : null,
                                      ),
                                    ),
                                  // Piece Glyph
                                  if (pieceChar != null)
                                    Text(
                                      _glyphs[pieceChar] ?? pieceChar,
                                      style: TextStyle(
                                        fontSize: 34,
                                        height: 1.1,
                                        color: pieceChar == pieceChar.toUpperCase()
                                            ? Colors.white
                                            : const Color(0xFF1E1E1E),
                                        shadows: [
                                          Shadow(
                                            blurRadius: 3.0,
                                            color: Colors.black.withOpacity(0.6),
                                            offset: const Offset(1, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),

              // Arrow Layer for Best Move (e.g. e2e4)
              if (widget.bestMove != null && widget.bestMove!.length >= 4)
                CustomPaint(
                  size: Size.infinite,
                  painter: ArrowPainter(
                    bestMove: widget.bestMove!,
                    isWhite: widget.isWhiteOrientation,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter that draws a clean animated vector arrow for the AI's best move.
class ArrowPainter extends CustomPainter {
  final String bestMove; // e.g. "e2e4"
  final bool isWhite;

  ArrowPainter({required this.bestMove, required this.isWhite});

  Offset _squareToCenter(String sq, double sqSize) {
    final col = sq.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.parse(sq[1]);
    final x = (isWhite ? col : 7 - col) * sqSize + sqSize / 2;
    final y = (isWhite ? 8 - rank : rank - 1) * sqSize + sqSize / 2;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (bestMove.length < 4) return;
    final sqSize = size.width / 8;
    final fromSq = bestMove.substring(0, 2);
    final toSq = bestMove.substring(2, 4);

    final start = _squareToCenter(fromSq, sqSize);
    final end = _squareToCenter(toSq, sqSize);

    final paint = Paint()
      ..color = const Color(0xA622C55E) // Semi-transparent bright emerald green
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw line shaft
    canvas.drawLine(start, end, paint);

    // Draw arrowhead
    final angle = (end - start).direction;
    final arrowSize = 18.0;
    final path = Path();
    path.moveTo(end.dx, end.dy);
    path.lineTo(
      end.dx - arrowSize * math.cos(angle - math.pi / 6),
      end.dy - arrowSize * math.sin(angle - math.pi / 6),
    );
    path.lineTo(
      end.dx - arrowSize * math.cos(angle + math.pi / 6),
      end.dy - arrowSize * math.sin(angle + math.pi / 6),
    );
    path.close();

    final arrowHeadPaint = Paint()
      ..color = const Color(0xA622C55E)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, arrowHeadPaint);
  }

  @override
  bool shouldRepaint(covariant ArrowPainter oldDelegate) =>
      oldDelegate.bestMove != bestMove || oldDelegate.isWhite != isWhite;
}
