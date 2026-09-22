import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess_logic;
import '../services/retention_service.dart';
import 'interactive_chessboard.dart';

class DailyPuzzleView extends StatefulWidget {
  const DailyPuzzleView({Key? key}) : super(key: key);

  @override
  State<DailyPuzzleView> createState() => _DailyPuzzleViewState();
}

class _DailyPuzzleViewState extends State<DailyPuzzleView> {
  final RetentionService _retentionService = RetentionService();
  DailyPuzzleData? _puzzle;
  int _puzzleIndex = 0;
  bool _isLoading = true;

  String _currentFen = "";
  String _lastValidFen = "";
  int _moveIndex = 0;
  String _statusMessage = "Find the best move!";
  Color _statusColor = Colors.amber;
  bool _isResetting = false;

  @override
  void initState() {
    super.initState();
    _loadDailyPuzzle();
  }

  Future<void> _loadDailyPuzzle() async {
    setState(() => _isLoading = true);
    final puzzle = await _retentionService.getDailyPuzzle();
    _applyPuzzle(puzzle);
  }

  void _loadPuzzleByIndex(int index) {
    setState(() {
      _puzzleIndex = index;
      _isLoading = true;
    });
    final puzzle = _retentionService.getPuzzleByIndex(index);
    _applyPuzzle(puzzle);
  }

  void _applyPuzzle(DailyPuzzleData puzzle) {
    setState(() {
      _puzzle = puzzle;
      _currentFen = puzzle.fen;
      _lastValidFen = puzzle.fen;
      _isLoading = false;
      _moveIndex = 0;
      _isResetting = false;
      _statusMessage = puzzle.isWhiteToMove ? "⚪ White to move and win!" : "⚫ Black to move and win!";
      _statusColor = Colors.amber;
    });
  }

  void _onMove(String from, String to, String newFen) {
    if (_puzzle == null || _isResetting || _moveIndex >= _puzzle!.solution.length) return;

    final playedMove = '$from$to'.toLowerCase();
    final expectedMove = _puzzle!.solution[_moveIndex].toLowerCase();

    // Check if played move matches the puzzle solution move
    if (playedMove == expectedMove || playedMove.startsWith(expectedMove.substring(0, 4))) {
      _moveIndex++;
      _lastValidFen = newFen;

      if (_moveIndex >= _puzzle!.solution.length) {
        setState(() {
          _currentFen = newFen;
          _statusMessage = "🎉 Puzzle Solved! Outstanding tactic.";
          _statusColor = Colors.greenAccent;
        });
      } else {
        // Correct move played! Play opponent reply automatically after 450ms
        setState(() {
          _currentFen = newFen;
          _statusMessage = "✅ Good move! Defending reply coming...";
          _statusColor = Colors.greenAccent;
        });

        Timer(const Duration(milliseconds: 450), () {
          if (!mounted || _puzzle == null || _moveIndex >= _puzzle!.solution.length) return;
          final replyUci = _puzzle!.solution[_moveIndex];
          _moveIndex++;
          _playOpponentUci(replyUci);

          setState(() {
            if (_moveIndex >= _puzzle!.solution.length) {
              _statusMessage = "🎉 Puzzle Solved! Outstanding tactic.";
              _statusColor = Colors.greenAccent;
            } else {
              _statusMessage = "Your turn: Find the next move!";
              _statusColor = Colors.amber;
            }
          });
        });
      }
    } else {
      // Incorrect move made! Automatically restore previous valid board state
      setState(() {
        _isResetting = true;
        _statusMessage = "❌ Incorrect move. Resetting...";
        _statusColor = Colors.redAccent;
      });

      Timer(const Duration(milliseconds: 650), () {
        if (!mounted || _puzzle == null) return;
        setState(() {
          _currentFen = _lastValidFen;
          _isResetting = false;
          _statusMessage = _puzzle!.isWhiteToMove ? "⚪ White to move. Try again!" : "⚫ Black to move. Try again!";
          _statusColor = Colors.amber;
        });
      });
    }
  }

  void _playOpponentUci(String uci) {
    if (uci.length < 4) return;
    final from = uci.substring(0, 2);
    final to = uci.substring(2, 4);
    final promo = uci.length >= 5 ? uci[4] : 'q';

    try {
      final chess = chess_logic.Chess.fromFEN(_currentFen);
      final ok = chess.move({'from': from, 'to': to, 'promotion': promo});
      if (ok) {
        setState(() {
          _currentFen = chess.fen;
          _lastValidFen = chess.fen;
        });
      }
    } catch (_) {}
  }

  void _resetPuzzle() {
    if (_puzzle != null) {
      setState(() {
        _currentFen = _puzzle!.fen;
        _lastValidFen = _puzzle!.fen;
        _moveIndex = 0;
        _isResetting = false;
        _statusMessage = _puzzle!.isWhiteToMove ? "⚪ White to move and win!" : "⚫ Black to move and win!";
        _statusColor = Colors.amber;
      });
    }
  }

  void _nextPuzzle() {
    _loadPuzzleByIndex(_puzzleIndex + 1);
  }

  void _prevPuzzle() {
    if (_puzzleIndex > 0) {
      _loadPuzzleByIndex(_puzzleIndex - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.amber),
      );
    }

    if (_puzzle == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Unable to load tactical puzzle.', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadDailyPuzzle,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final isSolved = _puzzle != null && _moveIndex >= _puzzle!.solution.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _puzzle!.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Rating: ${_puzzle!.rating} ELO  •  ${_puzzle!.isWhiteToMove ? "Play as White" : "Play as Black"}',
                      style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                onPressed: _resetPuzzle,
                tooltip: 'Reset Puzzle',
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Theme tags
          Wrap(
            spacing: 6,
            children: _puzzle!.themes.map((t) {
              return Chip(
                label: Text(t, style: const TextStyle(fontSize: 10, color: Colors.white70)),
                backgroundColor: const Color(0xFF262626),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          // Status & Turn Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _statusColor.withOpacity(0.4)),
            ),
            child: Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: _statusColor, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),

          // Interactive Chessboard (with correct orientation for Black / White)
          InteractiveChessboard(
            fen: _currentFen,
            bestMove: null,
            isWhiteOrientation: _puzzle!.isWhiteToMove,
            isPlayVsAi: false,
            onMoveMade: _onMove,
            onResetBoard: _resetPuzzle,
          ),
          const SizedBox(height: 14),

          // Action Navigation Buttons (Prev, Reset, Next Puzzle)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _puzzleIndex > 0 ? _prevPuzzle : null,
                  icon: const Icon(Icons.chevron_left, size: 18),
                  label: const Text('Prev'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetPuzzle,
                  icon: const Icon(Icons.replay, size: 16),
                  label: const Text('Reset'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _nextPuzzle,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text(isSolved ? 'Next Puzzle 🎉' : 'Skip / Next ⏭️'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSolved ? Colors.green : Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
