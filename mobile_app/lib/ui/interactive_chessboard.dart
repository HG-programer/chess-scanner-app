import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess_logic;
import 'chess_piece_widget.dart';

/// Interactive 8x8 Chessboard supporting Drag & Drop, Tap to Move,
/// legal move dots, check indicator, takeback, board flip, and AI best-move arrow.
class InteractiveChessboard extends StatefulWidget {
  final String fen;
  final String? bestMove; // UCI e.g. "e2e4"
  final bool isWhiteOrientation;
  final bool isPlayVsAi;
  final bool isAiThinking;
  final Function(String from, String to, String newFen) onMoveMade;
  final VoidCallback? onResetBoard;
  final VoidCallback? onUndoMove;
  final VoidCallback? onFlipBoard;
  final Function(bool playVsAi)? onToggleMode;

  const InteractiveChessboard({
    Key? key,
    required this.fen,
    this.bestMove,
    this.isWhiteOrientation = true,
    this.isPlayVsAi = true,
    this.isAiThinking = false,
    required this.onMoveMade,
    this.onResetBoard,
    this.onUndoMove,
    this.onFlipBoard,
    this.onToggleMode,
  }) : super(key: key);

  @override
  State<InteractiveChessboard> createState() => _InteractiveChessboardState();
}

class _BoardCoord {
  final int row;
  final int col;
  const _BoardCoord(this.row, this.col);
}

class _InteractiveChessboardState extends State<InteractiveChessboard> {
  String? _selectedSquare;
  List<String> _legalDestinations = [];
  String? _lastFrom;
  String? _lastTo;
  late chess_logic.Chess _chess;

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
      _legalDestinations = [];
    }
  }

  void _loadChess() {
    try {
      _chess = chess_logic.Chess.fromFEN(widget.fen);
    } catch (_) {
      _chess = chess_logic.Chess();
    }
  }

  /// Parses the 8x8 piece grid directly from FEN string for 100% reliability
  List<List<String?>> _parseFenGrid(String fen) {
    final grid = List.generate(8, (_) => List<String?>.filled(8, null));
    final parts = fen.split(' ');
    final rows = parts[0].split('/');

    for (int r = 0; r < 8 && r < rows.length; r++) {
      int c = 0;
      for (int i = 0; i < rows[r].length; i++) {
        final ch = rows[r][i];
        final digit = int.tryParse(ch);
        if (digit != null) {
          c += digit;
        } else {
          if (c < 8) {
            grid[r][c] = ch;
            c++;
          }
        }
      }
    }
    return grid;
  }

  /// Converts board (row, col) into algebraic square e.g. "e4"
  String _coordsToSquare(int row, int col) {
    final file = String.fromCharCode('a'.codeUnitAt(0) + (widget.isWhiteOrientation ? col : 7 - col));
    final rank = widget.isWhiteOrientation ? (8 - row).toString() : (row + 1).toString();
    return '$file$rank';
  }

  /// Converts algebraic square e.g. "e4" to (row, col)
  _BoardCoord _squareToCoords(String sq) {
    if (sq.length < 2) return const _BoardCoord(0, 0);
    final file = sq[0].toLowerCase().codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.tryParse(sq[1]) ?? 1;
    final row = widget.isWhiteOrientation ? 8 - rank : rank - 1;
    final col = widget.isWhiteOrientation ? file : 7 - file;
    return _BoardCoord(row, col);
  }

  /// Finds all legal destination squares for a piece on [fromSquare]
  List<String> _getLegalMovesForSquare(String fromSquare) {
    try {
      final verboseMoves = _chess.moves({'verbose': true});
      final destinations = <String>[];
      for (final m in verboseMoves) {
        if (m is Map) {
          if (m['from'] == fromSquare) {
            destinations.add(m['to'].toString());
          }
        }
      }
      return destinations;
    } catch (_) {
      return [];
    }
  }

  /// Execute move from [from] to [to]
  void _executeMove(String from, String to) {
    if (widget.isAiThinking) return;

    setState(() {
      _lastFrom = from;
      _lastTo = to;
    });

    try {
      final success = _chess.move({'from': from, 'to': to, 'promotion': 'q'});
      if (success) {
        final newFen = _chess.fen;
        setState(() {
          _selectedSquare = null;
          _legalDestinations = [];
        });
        widget.onMoveMade(from, to, newFen);
        return;
      }
    } catch (_) {}

    // Fallback: If strict chess.dart move check failed in analysis mode, allow move directly
    if (!widget.isPlayVsAi) {
      _forceMoveInFen(from, to);
    }
  }

  void _forceMoveInFen(String from, String to) {
    // In free analysis mode, fallback move
    final grid = _parseFenGrid(widget.fen);
    final pFrom = _squareToCoords(from);
    final pTo = _squareToCoords(to);
    final piece = grid[pFrom.row][pFrom.col];
    if (piece != null) {
      grid[pFrom.row][pFrom.col] = null;
      grid[pTo.row][pTo.col] = piece;
      // Rebuild FEN rows
      final rowStrs = <String>[];
      for (int r = 0; r < 8; r++) {
        int empty = 0;
        String rowStr = '';
        for (int c = 0; c < 8; c++) {
          if (grid[r][c] == null) {
            empty++;
          } else {
            if (empty > 0) {
              rowStr += empty.toString();
              empty = 0;
            }
            rowStr += grid[r][c]!;
          }
        }
        if (empty > 0) rowStr += empty.toString();
        rowStrs.add(rowStr);
      }
      final turn = widget.fen.contains(' w ') ? 'b' : 'w';
      final newFen = '${rowStrs.join('/')} $turn - - 0 1';
      widget.onMoveMade(from, to, newFen);
    }
  }

  void _onSquareTap(String sq, String? pieceChar) {
    if (widget.isAiThinking) return;

    if (_selectedSquare == null) {
      if (pieceChar == null) return;
      // In vs AI mode, only allow moving White if user is White
      final isWhitePiece = pieceChar == pieceChar.toUpperCase();
      final isWhiteTurn = _chess.turn == chess_logic.Color.WHITE;
      if (widget.isPlayVsAi && (isWhitePiece != isWhiteTurn)) {
        return;
      }

      setState(() {
        _selectedSquare = sq;
        _legalDestinations = _getLegalMovesForSquare(sq);
      });
    } else {
      if (_legalDestinations.contains(sq) || (!widget.isPlayVsAi && _selectedSquare != sq)) {
        _executeMove(_selectedSquare!, sq);
      } else {
        // Deselect or select another piece of current turn
        if (pieceChar != null) {
          setState(() {
            _selectedSquare = sq;
            _legalDestinations = _getLegalMovesForSquare(sq);
          });
        } else {
          setState(() {
            _selectedSquare = null;
            _legalDestinations = [];
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final grid = _parseFenGrid(widget.fen);
    final isWhiteTurn = _chess.turn == chess_logic.Color.WHITE;

    return Column(
      children: [
        // 1. Status / Turn Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isWhiteTurn ? Colors.white : Colors.grey[800],
                      border: Border.all(color: Colors.white70, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isAiThinking
                        ? '🤖 Engine is thinking...'
                        : (isWhiteTurn ? 'White to Move' : 'Black to Move'),
                    style: TextStyle(
                      color: widget.isAiThinking ? Colors.amber : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              // Play vs AI Toggle
              GestureDetector(
                onTap: () {
                  if (widget.onToggleMode != null) {
                    widget.onToggleMode!(!widget.isPlayVsAi);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.isPlayVsAi ? Colors.amber.withOpacity(0.2) : Colors.blueAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: widget.isPlayVsAi ? Colors.amber : Colors.blueAccent, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isPlayVsAi ? Icons.smart_toy : Icons.people,
                        size: 14,
                        color: widget.isPlayVsAi ? Colors.amber : Colors.blueAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.isPlayVsAi ? 'Vs Engine' : 'Analysis',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: widget.isPlayVsAi ? Colors.amber : Colors.blueAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // 2. The 8x8 Board
        AspectRatio(
          aspectRatio: 1.0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Column(
                    children: List.generate(8, (r) {
                      return Expanded(
                        child: Row(
                          children: List.generate(8, (c) {
                            final sq = _coordsToSquare(r, c);
                            final isLight = (r + c) % 2 == 0;
                            final isSelected = sq == _selectedSquare;
                            final isLegal = _legalDestinations.contains(sq);

                            // Get piece from parsed grid directly
                            final pieceChar = grid[r][c];

                            final isWhitePiece = pieceChar != null && pieceChar == pieceChar.toUpperCase();
                            final bgColor = isLight ? const Color(0xFFF0D9B5) : const Color(0xFFB58863);

                            return Expanded(
                              child: DragTarget<String>(
                                onWillAccept: (fromSq) => fromSq != null && fromSq != sq,
                                onAccept: (fromSq) {
                                  _executeMove(fromSq, sq);
                                },
                                builder: (ctx, candidateData, rejectedData) {
                                    final isTrail = sq == _lastFrom || sq == _lastTo;
                                    final tileColor = isSelected
                                        ? const Color(0xFFBBCB44)
                                        : (candidateData.isNotEmpty
                                            ? const Color(0xFF769656)
                                            : (isTrail ? const Color(0xFFCED56A) : bgColor));

                                    return GestureDetector(
                                      onTap: () => _onSquareTap(sq, pieceChar),
                                      child: Container(
                                        color: tileColor,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // Coordinate Rank/File indicators on edges
                                            if (c == 0)
                                              Positioned(
                                                top: 2,
                                                left: 2,
                                                child: Text(
                                                  sq[1],
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    color: isLight ? const Color(0xFFB58863) : const Color(0xFFF0D9B5),
                                                  ),
                                                ),
                                              ),
                                            if (r == 7)
                                              Positioned(
                                                bottom: 2,
                                                right: 2,
                                                child: Text(
                                                  sq[0],
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    color: isLight ? const Color(0xFFB58863) : const Color(0xFFF0D9B5),
                                                  ),
                                                ),
                                              ),

                                            // Legal Destination Dot
                                            if (isLegal)
                                              Container(
                                                width: pieceChar == null ? 14 : 32,
                                                height: pieceChar == null ? 14 : 32,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: pieceChar == null
                                                      ? Colors.black.withOpacity(0.28)
                                                      : Colors.transparent,
                                                  border: pieceChar != null
                                                      ? Border.all(color: Colors.black.withOpacity(0.35), width: 4)
                                                      : null,
                                                ),
                                              ),

                                            // Piece Widget (Draggable) with touch scale animation
                                            if (pieceChar != null)
                                              Draggable<String>(
                                                data: sq,
                                                dragAnchorStrategy: pointerDragAnchorStrategy,
                                                onDragStarted: () {
                                                  setState(() {
                                                    _selectedSquare = sq;
                                                    _legalDestinations = _getLegalMovesForSquare(sq);
                                                  });
                                                },
                                                feedback: Material(
                                                  color: Colors.transparent,
                                                  child: Transform.translate(
                                                    offset: const Offset(-26, -26),
                                                    child: ChessPieceWidget(
                                                      pieceChar: pieceChar,
                                                      size: 52,
                                                      isDragging: true,
                                                    ),
                                                  ),
                                                ),
                                                childWhenDragging: Opacity(
                                                  opacity: 0.20,
                                                  child: ChessPieceWidget(
                                                    pieceChar: pieceChar,
                                                    size: 38,
                                                  ),
                                                ),
                                                child: AnimatedScale(
                                                  scale: isSelected ? 1.14 : 1.0,
                                                  duration: const Duration(milliseconds: 140),
                                                  curve: Curves.easeOutBack,
                                                  child: ChessPieceWidget(
                                                    pieceChar: pieceChar,
                                                    size: 38,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            }),
                          ),
                        );
                      }),
                    ),

                  // Best Move Arrow Layer (e.g. e2e4)
                  if (widget.bestMove != null && widget.bestMove!.length >= 4)
                    IgnorePointer(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: ArrowPainter(
                          bestMove: widget.bestMove!,
                          isWhite: widget.isWhiteOrientation,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // 3. Quick Board Actions Bar (Flip, Undo, Reset)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: widget.onFlipBoard,
              icon: const Icon(Icons.swap_vert, size: 18, color: Colors.white70),
              label: const Text('Flip', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            TextButton.icon(
              onPressed: widget.onUndoMove,
              icon: const Icon(Icons.undo, size: 18, color: Colors.white70),
              label: const Text('Takeback', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            TextButton.icon(
              onPressed: widget.onResetBoard,
              icon: const Icon(Icons.refresh, size: 18, color: Colors.amber),
              label: const Text('New Game', style: TextStyle(color: Colors.amber, fontSize: 12)),
            ),
          ],
        ),
      ],
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
      ..color = const Color(0xC822C55E) // Semi-transparent bright emerald green
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw line shaft
    canvas.drawLine(start, end, paint);

    // Draw arrowhead
    final angle = (end - start).direction;
    const arrowSize = 16.0;
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

    final fillPaint = Paint()
      ..color = const Color(0xC822C55E)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant ArrowPainter oldDelegate) {
    return oldDelegate.bestMove != bestMove || oldDelegate.isWhite != isWhite;
  }
}
