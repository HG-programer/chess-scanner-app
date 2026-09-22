import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chess/chess.dart' as chess_logic;
import 'chess_piece_widget.dart';

class _BoardCoord {
  final int row;
  final int col;
  const _BoardCoord(this.row, this.col);
}

/// Interactive 8x8 Chessboard Widget featuring:
/// - Tap-to-move & drag-and-drop dual support
/// - Last move highlighting for both player and AI moves
/// - Red pulse highlight on the King when in Check
/// - Visual best move tactical hint arrow with user toggle
/// - Full pawn underpromotion selection dialog (Queen, Knight, Rook, Bishop)
/// - Haptic feedback on moves, captures, checks, and checkmate
/// - 100% rigid squares with zero black horizontal stripes
/// - Responsive layout for phones and landscape emulators (LDPlayer)
class InteractiveChessboard extends StatefulWidget {
  final String fen;
  final String? bestMove; // e.g. "e2e4"
  final String? lastMoveUci; // e.g. "e7e5" (highlights both player & AI moves)
  final bool isWhiteOrientation;
  final bool isPlayVsAi;
  final bool isAiThinking;
  final void Function(String from, String to, String newFen) onMoveMade;
  final VoidCallback? onResetBoard;
  final VoidCallback? onUndoMove;
  final VoidCallback? onFlipBoard;
  final Function(bool playVsAi)? onToggleMode;

  const InteractiveChessboard({
    Key? key,
    required this.fen,
    this.bestMove,
    this.lastMoveUci,
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

class _InteractiveChessboardState extends State<InteractiveChessboard> {
  late chess_logic.Chess _chess;
  String? _selectedSquare;
  List<String> _legalDestinations = [];
  String? _lastFrom;
  String? _lastTo;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _loadChess();
    _syncLastMove();
  }

  @override
  void didUpdateWidget(covariant InteractiveChessboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fen != widget.fen) {
      _loadChess();
      _selectedSquare = null;
      _legalDestinations = [];
    }
    if (oldWidget.lastMoveUci != widget.lastMoveUci) {
      _syncLastMove();
    }
  }

  void _syncLastMove() {
    if (widget.lastMoveUci != null && widget.lastMoveUci!.length >= 4) {
      _lastFrom = widget.lastMoveUci!.substring(0, 2);
      _lastTo = widget.lastMoveUci!.substring(2, 4);
    } else {
      _lastFrom = null;
      _lastTo = null;
    }
  }

  void _loadChess() {
    try {
      _chess = chess_logic.Chess.fromFEN(widget.fen);
    } catch (_) {
      _chess = chess_logic.Chess();
    }
  }

  /// Directly queries the piece on algebraic square [sq] (e.g. "e4") from the chess state.
  /// Returns uppercase ('P','N','B','R','Q','K') for White, lowercase ('p','n','b','r','q','k') for Black.
  /// 100% resilient across White and Black orientations, flips, and custom FENs.
  String? _getPieceAt(String sq) {
    try {
      final p = _chess.get(sq);
      if (p == null) return null;
      final typeStr = p.type.name.toLowerCase();
      return p.color == chess_logic.Color.WHITE ? typeStr.toUpperCase() : typeStr.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  /// Converts board (row, col) into algebraic square e.g. "e4"
  String _coordsToSquare(int row, int col) {
    final file = String.fromCharCode('a'.codeUnitAt(0) + (widget.isWhiteOrientation ? col : 7 - col));
    final rank = widget.isWhiteOrientation ? (8 - row).toString() : (row + 1).toString();
    return '$file$rank';
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

  /// Prompt user to choose pawn promotion piece (Queen, Knight, Rook, Bishop)
  Future<String?> _showPromotionDialog(bool isWhite) async {
    final pieces = [
      {'char': isWhite ? 'Q' : 'q', 'name': 'Queen', 'val': 'q'},
      {'char': isWhite ? 'N' : 'n', 'name': 'Knight', 'val': 'n'},
      {'char': isWhite ? 'R' : 'r', 'name': 'Rook', 'val': 'r'},
      {'char': isWhite ? 'B' : 'b', 'name': 'Bishop', 'val': 'b'},
    ];

    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Center(
            child: Text(
              'Promote Pawn',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: pieces.map((p) {
              return InkWell(
                onTap: () => Navigator.pop(ctx, p['val']),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B2B36),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withOpacity(0.4)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChessPieceWidget(pieceChar: p['char']!, size: 42),
                      const SizedBox(height: 4),
                      Text(p['name']!, style: const TextStyle(fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// Execute move from [from] to [to]
  Future<void> _executeMove(String from, String to) async {
    if (widget.isAiThinking) return;
    if (from.length < 2 || to.length < 2) return;

    // Check if this move is a pawn promotion
    final pieceChar = _chess.get(from)?.type.name.toLowerCase();
    final isPawn = pieceChar == 'p';
    final isWhite = _chess.turn == chess_logic.Color.WHITE;
    final isPromo = isPawn && ((isWhite && from[1] == '7' && to[1] == '8') || (!isWhite && from[1] == '2' && to[1] == '1'));

    String promoPiece = 'q';
    if (isPromo) {
      final chosen = await _showPromotionDialog(isWhite);
      promoPiece = chosen ?? 'q';
    }

    try {
      final isCapture = _chess.get(to) != null;
      final success = _chess.move({'from': from, 'to': to, 'promotion': promoPiece});
      if (success) {
        // Haptic feedback
        if (_chess.in_checkmate) {
          HapticFeedback.heavyImpact();
        } else if (_chess.in_check) {
          HapticFeedback.mediumImpact();
        } else if (isCapture) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.lightImpact();
        }

        final newFen = _chess.fen;
        setState(() {
          _lastFrom = from;
          _lastTo = to;
          _selectedSquare = null;
          _legalDestinations = [];
        });

        widget.onMoveMade(from, to, newFen);
      } else {
        setState(() {
          _selectedSquare = null;
          _legalDestinations = [];
        });
      }
    } catch (_) {
      setState(() {
        _selectedSquare = null;
        _legalDestinations = [];
      });
    }
  }

  void _onSquareTap(String sq, String? pieceChar) {
    if (widget.isAiThinking) return;

    final isWhiteTurn = _chess.turn == chess_logic.Color.WHITE;

    if (_selectedSquare != null) {
      // 1. If clicking a valid legal destination, execute move immediately
      if (_legalDestinations.contains(sq)) {
        _executeMove(_selectedSquare!, sq);
        return;
      }

      // 2. If tapping the same square, deselect
      if (_selectedSquare == sq) {
        setState(() {
          _selectedSquare = null;
          _legalDestinations = [];
        });
        return;
      }

      // 3. If tapping another friendly piece of the active side, smoothly switch selection
      if (pieceChar != null) {
        final isWhitePiece = pieceChar == pieceChar.toUpperCase();
        if ((isWhiteTurn && isWhitePiece) || (!isWhiteTurn && !isWhitePiece) || !widget.isPlayVsAi) {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedSquare = sq;
            _legalDestinations = _getLegalMovesForSquare(sq);
          });
          return;
        }
      }

      // 4. Otherwise clear selection
      setState(() {
        _selectedSquare = null;
        _legalDestinations = [];
      });
      return;
    }

    // No piece currently selected: select if piece belongs to side to move
    if (pieceChar != null) {
      final isWhitePiece = pieceChar == pieceChar.toUpperCase();
      if ((isWhiteTurn && isWhitePiece) || (!isWhiteTurn && !isWhitePiece) || !widget.isPlayVsAi) {
        HapticFeedback.selectionClick();
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
    } else {
      setState(() {
        _selectedSquare = null;
        _legalDestinations = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWhiteTurn = _chess.turn == chess_logic.Color.WHITE;
    final inCheck = _chess.in_check;

    // Locate the King square of the side to move if in check
    String? checkKingSquare;
    if (inCheck) {
      final targetKing = isWhiteTurn ? 'K' : 'k';
      for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
          final s = _coordsToSquare(r, c);
          if (_getPieceAt(s) == targetKing) {
            checkKingSquare = s;
            break;
          }
        }
        if (checkKingSquare != null) break;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.of(context).size.height;
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

        // In landscape (LDPlayer), constrain board height so it never exceeds screen height.
        final maxAllowedHeight = isLandscape ? math.max(260.0, screenHeight - 160.0) : 540.0;
        final boardSize = math.min(constraints.maxWidth, maxAllowedHeight);
        final squareSize = boardSize / 8.0;
        final pieceSize = squareSize * 0.82;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Status / Turn Bar with Check Indicator & Hint Button
            SizedBox(
              width: boardSize,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: inCheck ? Colors.red.withOpacity(0.18) : const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: inCheck ? Colors.redAccent.withOpacity(0.6) : Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Turn / Status indicator
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: inCheck
                                ? Colors.redAccent
                                : (isWhiteTurn ? Colors.white : Colors.grey[800]),
                            border: Border.all(color: Colors.white70, width: 1.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.isAiThinking
                              ? '🤖 Engine thinking...'
                              : (inCheck
                                  ? '⚠️ ${isWhiteTurn ? "White" : "Black"} in Check!'
                                  : (isWhiteTurn ? 'White to Move' : 'Black to Move')),
                          style: TextStyle(
                            color: inCheck
                                ? Colors.redAccent
                                : (widget.isAiThinking ? Colors.amber : Colors.white),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    // Controls: Hint Toggle + Mode Toggle
                    Row(
                      children: [
                        // Hint Arrow Toggle
                        if (widget.bestMove != null && widget.bestMove!.length >= 4 && widget.bestMove != 'mate' && widget.bestMove != 'none')
                          GestureDetector(
                            onTap: () {
                              setState(() => _showHint = !_showHint);
                              HapticFeedback.selectionClick();
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _showHint ? Colors.green.withOpacity(0.25) : Colors.white10,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _showHint ? Colors.greenAccent : Colors.white24,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lightbulb,
                                    size: 13,
                                    color: _showHint ? Colors.greenAccent : Colors.white70,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Hint',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _showHint ? Colors.greenAccent : Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                              color: widget.isPlayVsAi
                                  ? Colors.amber.withOpacity(0.2)
                                  : Colors.blueAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: widget.isPlayVsAi ? Colors.amber : Colors.blueAccent,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.isPlayVsAi ? Icons.smart_toy : Icons.people,
                                  size: 13,
                                  color: widget.isPlayVsAi ? Colors.amber : Colors.blueAccent,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  widget.isPlayVsAi ? 'Vs AI' : '2-Player',
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // 2. The 8x8 Board (Perfect square, zero black horizontal gaps)
            SizedBox(
              width: boardSize,
              height: boardSize,
              child: AbsorbPointer(
                absorbing: widget.isAiThinking,
                child: Container(
                  decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 14,
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
                              // CRITICAL: stretch prevents vertical collapse of squares!
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: List.generate(8, (c) {
                                final sq = _coordsToSquare(r, c);
                                final isLight = (r + c) % 2 == 0;
                                final isSelected = sq == _selectedSquare;
                                final isLegal = _legalDestinations.contains(sq);
                                final isCheckKing = sq == checkKingSquare;

                                // Get piece directly from chess state for this square
                                final pieceChar = _getPieceAt(sq);
                                final bgColor = isLight ? const Color(0xFFF0D9B5) : const Color(0xFFB58863);

                                return Expanded(
                                  child: DragTarget<String>(
                                    onWillAccept: (fromSq) => fromSq != null && fromSq != sq && _legalDestinations.contains(sq),
                                    onAccept: (fromSq) {
                                      _executeMove(fromSq, sq);
                                    },
                                    builder: (ctx, candidateData, rejectedData) {
                                      final isTrail = sq == _lastFrom || sq == _lastTo;
                                      final isHovered = candidateData.isNotEmpty && _legalDestinations.contains(sq);

                                      Color tileColor;
                                      if (isCheckKing) {
                                        tileColor = const Color(0xFFE53935).withOpacity(0.72);
                                      } else if (isSelected) {
                                        tileColor = const Color(0xFFBBCB44);
                                      } else if (isHovered) {
                                        tileColor = const Color(0xFF769656);
                                      } else if (isTrail) {
                                        tileColor = const Color(0xFFCED56A).withOpacity(0.8);
                                      } else {
                                        tileColor = bgColor;
                                      }

                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _onSquareTap(sq, pieceChar),
                                        child: SizedBox.expand(
                                          child: Container(
                                            color: tileColor,
                                            child: Stack(
                                              fit: StackFit.expand,
                                              alignment: Alignment.center,
                                              children: [
                                                // Coordinate Rank indicator on left edge (file a)
                                                if (c == 0)
                                                  Positioned(
                                                    top: 2,
                                                    left: 3,
                                                    child: Text(
                                                      sq[1],
                                                      style: TextStyle(
                                                        fontSize: math.max(9.0, squareSize * 0.18),
                                                        fontWeight: FontWeight.bold,
                                                        color: isLight
                                                            ? const Color(0xFFB58863)
                                                            : const Color(0xFFF0D9B5),
                                                      ),
                                                    ),
                                                  ),

                                                // Coordinate File indicator on bottom edge (rank 1)
                                                if (r == 7)
                                                  Positioned(
                                                    bottom: 2,
                                                    right: 3,
                                                    child: Text(
                                                      sq[0],
                                                      style: TextStyle(
                                                        fontSize: math.max(9.0, squareSize * 0.18),
                                                        fontWeight: FontWeight.bold,
                                                        color: isLight
                                                            ? const Color(0xFFB58863)
                                                            : const Color(0xFFF0D9B5),
                                                      ),
                                                    ),
                                                  ),

                                                // Legal Destination Marker (Dot for empty, Ring for capture)
                                                if (isLegal)
                                                  Center(
                                                    child: Container(
                                                      width: pieceChar == null
                                                          ? squareSize * 0.28
                                                          : squareSize * 0.82,
                                                      height: pieceChar == null
                                                          ? squareSize * 0.28
                                                          : squareSize * 0.82,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: pieceChar == null
                                                            ? Colors.black.withOpacity(0.28)
                                                            : Colors.transparent,
                                                        border: pieceChar != null
                                                            ? Border.all(
                                                                color: Colors.black.withOpacity(0.40),
                                                                width: math.max(3.2, squareSize * 0.085),
                                                              )
                                                            : null,
                                                      ),
                                                    ),
                                                  ),

                                                // Dynamic Staunton Vector Piece (Dual Tap & Drag)
                                                if (pieceChar != null)
                                                  Center(
                                                    child: Draggable<String>(
                                                      data: sq,
                                                      dragAnchorStrategy: (draggable, context, position) {
                                                        final liftSize = pieceSize * 1.15;
                                                        return Offset(liftSize / 2.0, liftSize / 2.0);
                                                      },
                                                      onDragStarted: () {
                                                        if (widget.isAiThinking) return;
                                                        HapticFeedback.selectionClick();
                                                        setState(() {
                                                          _selectedSquare = sq;
                                                          _legalDestinations = _getLegalMovesForSquare(sq);
                                                        });
                                                      },
                                                      feedback: Material(
                                                        color: Colors.transparent,
                                                        child: ChessPieceWidget(
                                                          pieceChar: pieceChar,
                                                          size: pieceSize * 1.15,
                                                          isDragging: true,
                                                        ),
                                                      ),
                                                      childWhenDragging: Opacity(
                                                        opacity: 0.25,
                                                        child: ChessPieceWidget(
                                                          pieceChar: pieceChar,
                                                          size: pieceSize,
                                                        ),
                                                      ),
                                                      child: GestureDetector(
                                                        behavior: HitTestBehavior.opaque,
                                                        onTap: () => _onSquareTap(sq, pieceChar),
                                                        child: AnimatedScale(
                                                          scale: isSelected ? 1.12 : 1.0,
                                                          duration: const Duration(milliseconds: 130),
                                                          curve: Curves.easeOutBack,
                                                          child: ChessPieceWidget(
                                                            pieceChar: pieceChar,
                                                            size: pieceSize,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
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

                      // Best Move Tactical Arrow Layer (drawn only when hint is enabled)
                      if (_showHint && widget.bestMove != null && widget.bestMove!.length >= 4)
                        IgnorePointer(
                          child: CustomPaint(
                            size: Size(boardSize, boardSize),
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
          ),
          const SizedBox(height: 8),

            // 3. Quick Board Actions Bar (Flip, Undo, Reset)
            if (widget.onFlipBoard != null || widget.onUndoMove != null || widget.onResetBoard != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: boardSize,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (widget.onFlipBoard != null)
                      TextButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          widget.onFlipBoard!();
                        },
                        icon: const Icon(Icons.swap_vert, size: 18, color: Colors.white70),
                        label: const Text('Flip', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                    if (widget.onUndoMove != null)
                      TextButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          widget.onUndoMove!();
                        },
                        icon: const Icon(Icons.undo, size: 18, color: Colors.white70),
                        label: const Text('Takeback', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                    if (widget.onResetBoard != null)
                      TextButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          widget.onResetBoard!();
                        },
                        icon: const Icon(Icons.refresh, size: 18, color: Colors.amber),
                        label: const Text('New Game', style: TextStyle(color: Colors.amber, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Custom painter that draws a clean vector arrow for the AI's best move.
/// Bulletproofed against non-algebraic strings like 'mate' or 'none'.
class ArrowPainter extends CustomPainter {
  final String bestMove; // e.g. "e2e4"
  final bool isWhite;

  ArrowPainter({required this.bestMove, required this.isWhite});

  Offset? _squareToCenter(String sq, double sqSize) {
    if (sq.length < 2) return null;
    final fileChar = sq[0].toLowerCase();
    final rankDigit = int.tryParse(sq[1]);

    if (rankDigit == null || rankDigit < 1 || rankDigit > 8) return null;
    if (fileChar.codeUnitAt(0) < 'a'.codeUnitAt(0) || fileChar.codeUnitAt(0) > 'h'.codeUnitAt(0)) return null;

    final col = fileChar.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final x = (isWhite ? col : 7 - col) * sqSize + sqSize / 2;
    final y = (isWhite ? 8 - rankDigit : rankDigit - 1) * sqSize + sqSize / 2;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (bestMove.length < 4 || bestMove == 'mate' || bestMove == 'none') return;
    final sqSize = size.width / 8.0;

    final fromSq = bestMove.substring(0, 2);
    final toSq = bestMove.substring(2, 4);

    final start = _squareToCenter(fromSq, sqSize);
    final end = _squareToCenter(toSq, sqSize);
    if (start == null || end == null) return;

    final linePaint = Paint()
      ..color = const Color(0xFF43A047).withOpacity(0.82)
      ..strokeWidth = math.max(4.0, sqSize * 0.12)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final headPaint = Paint()
      ..color = const Color(0xFF43A047).withOpacity(0.92)
      ..style = PaintingStyle.fill;

    // Shorten end point so arrowhead looks sharp
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final headLength = math.max(12.0, sqSize * 0.32);
    final adjustedEnd = Offset(
      end.dx - (headLength * 0.5) * math.cos(angle),
      end.dy - (headLength * 0.5) * math.sin(angle),
    );

    // Draw main arrow shaft
    canvas.drawLine(start, adjustedEnd, linePaint);

    // Draw clean triangle arrowhead
    final path = Path();
    path.moveTo(end.dx, end.dy);
    path.lineTo(
      end.dx - headLength * math.cos(angle - math.pi / 6),
      end.dy - headLength * math.sin(angle - math.pi / 6),
    );
    path.lineTo(
      end.dx - headLength * math.cos(angle + math.pi / 6),
      end.dy - headLength * math.sin(angle + math.pi / 6),
    );
    path.close();

    canvas.drawPath(path, headPaint);
  }

  @override
  bool shouldRepaint(covariant ArrowPainter oldDelegate) {
    return oldDelegate.bestMove != bestMove || oldDelegate.isWhite != isWhite;
  }
}
