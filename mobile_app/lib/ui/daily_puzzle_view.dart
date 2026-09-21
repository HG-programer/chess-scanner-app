import 'package:flutter/material.dart';
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
  bool _isLoading = true;
  String _currentFen = "";
  int _moveIndex = 0;
  String _statusMessage = "Find the best move!";
  Color _statusColor = Colors.amber;

  @override
  void initState() {
    super.initState();
    _loadPuzzle();
  }

  Future<void> _loadPuzzle() async {
    setState(() => _isLoading = true);
    final puzzle = await _retentionService.getDailyPuzzle();
    setState(() {
      _puzzle = puzzle;
      _currentFen = puzzle.fen;
      _isLoading = false;
      _moveIndex = 0;
      _statusMessage = "Find the best move!";
      _statusColor = Colors.amber;
    });
  }

  void _onMove(String from, String to, String newFen) {
    if (_puzzle == null || _moveIndex >= _puzzle!.solution.length) return;

    final playedMove = '$from$to';
    final expectedMove = _puzzle!.solution[_moveIndex];

    if (playedMove == expectedMove) {
      _moveIndex++;
      if (_moveIndex >= _puzzle!.solution.length) {
        setState(() {
          _currentFen = newFen;
          _statusMessage = "🎉 Puzzle Solved! Brilliant tactic found.";
          _statusColor = Colors.greenAccent;
        });
      } else {
        // Play opponent reply if exists
        setState(() {
          _currentFen = newFen;
          _statusMessage = "Correct! Playing response...";
          _statusColor = Colors.greenAccent;
        });
      }
    } else {
      setState(() {
        _statusMessage = "❌ Incorrect move. Try again!";
        _statusColor = Colors.redAccent;
      });
    }
  }

  void _resetPuzzle() {
    if (_puzzle != null) {
      setState(() {
        _currentFen = _puzzle!.fen;
        _moveIndex = 0;
        _statusMessage = "Find the best move!";
        _statusColor = Colors.amber;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.amber));
    }

    if (_puzzle == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Failed to load today\'s puzzle.'),
            ElevatedButton(onPressed: _loadPuzzle, child: const Text('Retry')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🧩 Daily Tactical Puzzle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Rating: ${_puzzle!.rating} ELO', style: const TextStyle(color: Colors.amber, fontSize: 13)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                onPressed: _resetPuzzle,
                tooltip: 'Reset Puzzle',
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Themes Chips
          Wrap(
            spacing: 6,
            children: _puzzle!.themes.map((t) {
              return Chip(
                label: Text(t, style: const TextStyle(fontSize: 10)),
                backgroundColor: const Color(0xFF262626),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Status message banner
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
          const SizedBox(height: 16),

          // The Board
          InteractiveChessboard(
            fen: _currentFen,
            bestMove: null,
            onMoveMade: _onMove,
          ),
          const SizedBox(height: 16),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _resetPuzzle,
                  child: const Text('Reset', style: TextStyle(color: Colors.white70)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1E1E1E),
                        title: const Text('Solution Moves'),
                        content: Text(
                          _puzzle!.solution.join(' ➔ '),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                        ],
                      ),
                    );
                  },
                  child: const Text('Reveal Solution'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
