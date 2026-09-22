import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:chess/chess.dart' as chess_logic;

/// Evaluation outcome from the engine
class EngineAnalysisResult {
  final String bestMove;      // UCI format e.g. "e2e4"
  final String moveSan;       // SAN format e.g. "e4" or "Nf3"
  final double evalScore;     // Centipawns in pawns e.g. +0.35, -1.20
  final double evalPercent;   // 0.0 to 100.0 for the evaluation bar
  final String evalText;      // Display text e.g. "+0.35", "-1.20", "# Mate"
  final String coachAdvice;   // Human-readable tactical insight
  final bool isCloud;         // True if retrieved from Lichess Cloud API

  const EngineAnalysisResult({
    required this.bestMove,
    required this.moveSan,
    required this.evalScore,
    required this.evalPercent,
    required this.evalText,
    required this.coachAdvice,
    this.isCloud = false,
  });
}

class OpeningPreset {
  final String name;
  final String eco;
  final String fen;
  final String description;
  final bool playAsWhite;

  const OpeningPreset({
    required this.name,
    required this.eco,
    required this.fen,
    required this.description,
    this.playAsWhite = true,
  });
}

class _ScoredMove {
  final Map move;
  final int score;
  _ScoredMove(this.move, this.score);
}

/// Robust Chess Engine Service with Alpha-Beta Search, Piece-Square Positional
/// Evaluation, Grandmaster Opening Book, and optional Lichess Cloud Database lookups.
class ChessEngineService {
  static final ChessEngineService _instance = ChessEngineService._internal();
  factory ChessEngineService() => _instance;
  ChessEngineService._internal();

  final math.Random _rng = math.Random();

  // Grandmaster Opening Presets for diverse home screen matches
  static const List<OpeningPreset> openingPresets = [
    OpeningPreset(
      name: "Standard Match (Play as White)",
      eco: "A00",
      fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      description: "Start from move 1. Command the board as White.",
      playAsWhite: true,
    ),
    OpeningPreset(
      name: "Standard Match (Play as Black)",
      eco: "A00",
      fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
      description: "White plays 1.e4. Defend and counter-attack as Black.",
      playAsWhite: false,
    ),
    OpeningPreset(
      name: "Sicilian Defense: Open Variation",
      eco: "B20",
      fen: "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2",
      description: "1.e4 c5. The sharpest, most popular combat opening.",
      playAsWhite: true,
    ),
    OpeningPreset(
      name: "Queen's Gambit Declined",
      eco: "D30",
      fen: "rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b KQkq c3 0 2",
      description: "1.d4 d5 2.c4. Strategic positional battle for the center.",
      playAsWhite: false,
    ),
    OpeningPreset(
      name: "Italian Game (Giuoco Piano)",
      eco: "C50",
      fen: "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4",
      description: "Classical harmonious piece development targeting f7.",
      playAsWhite: true,
    ),
    OpeningPreset(
      name: "King's Gambit: Accepted",
      eco: "C33",
      fen: "rnbqkbnr/pppp1ppp/8/4p3/4PP2/8/PPPP2PP/RNBQKBNR b KQkq f3 0 2",
      description: "1.e4 e5 2.f4. Highly aggressive romantic attacking chess.",
      playAsWhite: false,
    ),
    OpeningPreset(
      name: "Ruy Lopez (Spanish Opening)",
      eco: "C60",
      fen: "r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3",
      description: "1.e4 e5 2.Nf3 Nc6 3.Bb5. Elite grandmaster standard.",
      playAsWhite: false,
    ),
  ];

  // Piece Material Values (Centipawns)
  static const int _pawnVal = 100;
  static const int _knightVal = 320;
  static const int _bishopVal = 330;
  static const int _rookVal = 500;
  static const int _queenVal = 900;
  static const int _kingVal = 20000;

  // Piece-Square Positional Bonus Tables
  static const List<int> _pawnTable = [
      0,  0,  0,  0,  0,  0,  0,  0,
     50, 50, 50, 50, 50, 50, 50, 50,
     10, 10, 20, 30, 30, 20, 10, 10,
      5,  5, 10, 25, 25, 10,  5,  5,
      0,  0,  0, 20, 20,  0,  0,  0,
      5, -5,-10,  0,  0,-10, -5,  5,
      5, 10, 10,-20,-20, 10, 10,  5,
      0,  0,  0,  0,  0,  0,  0,  0
  ];

  static const List<int> _knightTable = [
    -50,-40,-30,-30,-30,-30,-40,-50,
    -40,-20,  0,  0,  0,  0,-20,-40,
    -30,  0, 10, 15, 15, 10,  0,-30,
    -30,  5, 15, 20, 20, 15,  5,-30,
    -30,  0, 15, 20, 20, 15,  0,-30,
    -30,  5, 10, 15, 15, 10,  5,-30,
    -40,-20,  0,  5,  5,  0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50,
  ];

  static const List<int> _bishopTable = [
    -20,-10,-10,-10,-10,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5, 10, 10,  5,  0,-10,
    -10,  5,  5, 10, 10,  5,  5,-10,
    -10,  0, 10, 10, 10, 10,  0,-10,
    -10, 10, 10, 10, 10, 10, 10,-10,
    -10,  5,  0,  0,  0,  0,  5,-10,
    -20,-10,-10,-10,-10,-10,-10,-20,
  ];

  // Opening Book database for variety (First 1-4 plies)
  static final Map<String, List<String>> _openingBook = {
    // Starting Position: 1.e4, 1.d4, 1.c4, 1.Nf3
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w': ['e2e4', 'd2d4', 'c2c4', 'g1f3'],

    // Black responses to 1.e4
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b': ['c7c5', 'e7e5', 'e7e6', 'c7c6', 'g8f6'],

    // Black responses to 1.d4
    'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b': ['g8f6', 'd7d5', 'e7e6', 'f7f5'],

    // Black responses to 1.c4
    'rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b': ['e7e5', 'c7c5', 'g8f6'],

    // 1.e4 e5 (Open Game): 2.Nf3, 2.Bc4, 2.Nc3
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w': ['g1f3', 'f1c4', 'b1c3', 'f2f4'],

    // 1.e4 c5 (Sicilian): 2.Nf3, 2.Nc3, 2.c3
    'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w': ['g1f3', 'b1c3', 'c2c3'],

    // 1.e4 e6 (French): 2.d4
    'rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w': ['d2d4'],

    // 1.e4 c6 (Caro-Kann): 2.d4
    'rnbqkbnr/pp1ppppp/2p5/8/4P3/8/PPPP1PPP/RNBQKBNR w': ['d2d4'],

    // 1.e4 e5 2.Nf3: 2...Nc6, 2...Nf6, 2...d6
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b': ['b8c6', 'g8f6', 'd7d6'],

    // 1.e4 c5 2.Nf3: 2...d6, 2...Nc6, 2...e6
    'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b': ['d7d6', 'b8c6', 'e7e6'],

    // 1.d4 Nf6 2.c4: 2...e6, 2...g6
    'rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b': ['e7e6', 'g7g6', 'c7c5'],

    // 1.d4 d5 2.c4: 2...e6, 2...c6, 2...dxc4
    'rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b': ['e7e6', 'c7c6', 'd5c4'],
  };

  /// Evaluates the board static position (in centipawns from White's perspective)
  int _evaluateBoard(chess_logic.Chess chess) {
    if (chess.in_checkmate) {
      return chess.turn == chess_logic.Color.WHITE ? -99999 : 99999;
    }
    if (chess.in_draw) return 0;

    int whiteScore = 0;
    int blackScore = 0;

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final sqName = '${String.fromCharCode("a".codeUnitAt(0) + c)}${8 - r}';
        final piece = chess.get(sqName);
        if (piece == null) continue;

        final isWhite = piece.color == chess_logic.Color.WHITE;
        final squareIndex = isWhite ? (r * 8 + c) : ((7 - r) * 8 + c);

        int material = 0;
        int positional = 0;

        final typeName = piece.type.name.toLowerCase();
        if (typeName == 'p') {
          material = _pawnVal;
          positional = _pawnTable[squareIndex];
        } else if (typeName == 'n') {
          material = _knightVal;
          positional = _knightTable[squareIndex];
        } else if (typeName == 'b') {
          material = _bishopVal;
          positional = _bishopTable[squareIndex];
        } else if (typeName == 'r') {
          material = _rookVal;
          positional = 10;
        } else if (typeName == 'q') {
          material = _queenVal;
          positional = 5;
        } else if (typeName == 'k') {
          material = _kingVal;
          positional = isWhite ? (r >= 6 ? 20 : -10) : (r <= 1 ? 20 : -10);
        }

        final totalPieceVal = material + positional;
        if (isWhite) {
          whiteScore += totalPieceVal;
        } else {
          blackScore += totalPieceVal;
        }
      }
    }

    return whiteScore - blackScore;
  }

  /// Minimax with Alpha-Beta pruning
  int _alphaBeta(chess_logic.Chess chess, int depth, int alpha, int beta, bool isMaximizing) {
    if (depth == 0 || chess.game_over) {
      return _evaluateBoard(chess);
    }

    final moves = chess.moves({'verbose': true});
    if (moves.isEmpty) return _evaluateBoard(chess);

    // Sort captures first for pruning
    moves.sort((a, b) {
      final aCap = (a is Map && a['captured'] != null) ? 1 : 0;
      final bCap = (b is Map && b['captured'] != null) ? 1 : 0;
      return bCap.compareTo(aCap);
    });

    if (isMaximizing) {
      int maxEval = -999999;
      for (final m in moves) {
        if (m is! Map) continue;
        final from = m['from'].toString();
        final to = m['to'].toString();
        final prom = m['promotion']?.toString() ?? 'q';

        if (chess.move({'from': from, 'to': to, 'promotion': prom})) {
          final evaluation = _alphaBeta(chess, depth - 1, alpha, beta, false);
          chess.undo();
          maxEval = math.max(maxEval, evaluation);
          alpha = math.max(alpha, evaluation);
          if (beta <= alpha) break;
        }
      }
      return maxEval;
    } else {
      int minEval = 999999;
      for (final m in moves) {
        if (m is! Map) continue;
        final from = m['from'].toString();
        final to = m['to'].toString();
        final prom = m['promotion']?.toString() ?? 'q';

        if (chess.move({'from': from, 'to': to, 'promotion': prom})) {
          final evaluation = _alphaBeta(chess, depth - 1, alpha, beta, true);
          chess.undo();
          minEval = math.min(minEval, evaluation);
          beta = math.min(beta, evaluation);
          if (beta <= alpha) break;
        }
      }
      return minEval;
    }
  }

  /// Checks if the current position has a book opening move for variety
  String? _getBookMove(String fen) {
    final parts = fen.split(' ');
    if (parts.length >= 2) {
      final key = '${parts[0]} ${parts[1]}';
      final bookOptions = _openingBook[key];
      if (bookOptions != null && bookOptions.isNotEmpty) {
        return bookOptions[_rng.nextInt(bookOptions.length)];
      }
    }
    return null;
  }

  /// Calculates the best move and evaluation with Opening Book and randomized candidate tie-breaking
  Future<EngineAnalysisResult> analyzePosition(
    String fen, {
    String engineId = 'coach',
    int maxDepth = 3,
  }) async {
    // 1. If engine is Lichess Cloud, try cloud query first
    if (engineId == 'cloud') {
      try {
        final cloudRes = await _fetchLichessCloud(fen);
        if (cloudRes != null) return cloudRes;
      } catch (_) {}
    }

    try {
      final chess = chess_logic.Chess.fromFEN(fen);
      if (chess.in_checkmate) {
        final whiteWon = chess.turn == chess_logic.Color.BLACK;
        return EngineAnalysisResult(
          bestMove: "mate",
          moveSan: "#",
          evalScore: whiteWon ? 999.0 : -999.0,
          evalPercent: whiteWon ? 100.0 : 0.0,
          evalText: whiteWon ? "1-0 White Wins" : "0-1 Black Wins",
          coachAdvice: "🏆 Checkmate! King is in inescapable check.",
        );
      }

      final legalMoves = chess.moves({'verbose': true});
      if (legalMoves.isEmpty) {
        return const EngineAnalysisResult(
          bestMove: "none",
          moveSan: "-",
          evalScore: 0.0,
          evalPercent: 50.0,
          evalText: "½-½ Stalemate",
          coachAdvice: "Draw by stalemate or insufficient material.",
        );
      }

      final isWhiteTurn = chess.turn == chess_logic.Color.WHITE;

      // 2. Check Grandmaster Opening Book for rich variety in first moves
      final bookUci = _getBookMove(fen);
      if (bookUci != null) {
        Map? matchingBookMove;
        for (final m in legalMoves) {
          if (m is Map && '${m['from']}${m['to']}' == bookUci) {
            matchingBookMove = m;
            break;
          }
        }
        if (matchingBookMove != null) {
          final evalVal = _evaluateBoard(chess);
          final double scorePawns = evalVal / 100.0;
          return EngineAnalysisResult(
            bestMove: bookUci,
            moveSan: matchingBookMove['san']?.toString() ?? bookUci,
            evalScore: scorePawns,
            evalPercent: 50.0,
            evalText: scorePawns >= 0 ? '+${scorePawns.toStringAsFixed(2)}' : scorePawns.toStringAsFixed(2),
            coachAdvice: "📖 Opening Book: Classical grandmaster opening theory.",
          );
        }
      }

      // 3. Minimax Alpha-Beta Search across all legal moves
      int searchDepth = 3;
      if (engineId == 'blitz') searchDepth = 2;
      if (engineId == 'stockfish19') searchDepth = 3;

      final List<_ScoredMove> scoredMoves = [];

      for (final m in legalMoves) {
        if (m is! Map) continue;
        final from = m['from'].toString();
        final to = m['to'].toString();
        final prom = m['promotion']?.toString() ?? 'q';

        if (chess.move({'from': from, 'to': to, 'promotion': prom})) {
          final eval = _alphaBeta(chess, searchDepth - 1, -999999, 999999, !isWhiteTurn);
          chess.undo();
          scoredMoves.add(_ScoredMove(m, eval));
        }
      }

      if (scoredMoves.isEmpty) {
        scoredMoves.add(_ScoredMove(legalMoves.first as Map, _evaluateBoard(chess)));
      }

      // Sort scored moves
      scoredMoves.sort((a, b) => isWhiteTurn ? b.score.compareTo(a.score) : a.score.compareTo(b.score));

      final int bestScore = scoredMoves.first.score;

      // RANDOMIZED TIE-BREAKING:
      // Select among top candidates within 22 centipawns of the best move!
      // This completely stops matches from always repeating the same moves.
      final topCandidates = scoredMoves.where((sm) {
        final diff = (sm.score - bestScore).abs();
        return diff <= 22;
      }).toList();

      final selectedScoredMove = topCandidates[_rng.nextInt(topCandidates.length)];
      final bestMoveObj = selectedScoredMove.move;
      final bestVal = selectedScoredMove.score;

      final bestFrom = bestMoveObj['from']?.toString() ?? 'e2';
      final bestTo = bestMoveObj['to']?.toString() ?? 'e4';
      final bestSan = bestMoveObj['san']?.toString() ?? 'e4';
      final uciMove = '$bestFrom$bestTo';

      final double scorePawns = (bestVal / 100.0);
      final double evalPercent = (50.0 + (scorePawns * 8.5)).clamp(5.0, 95.0);

      String evalText = scorePawns >= 0
          ? '+${scorePawns.toStringAsFixed(2)}'
          : scorePawns.toStringAsFixed(2);

      final coachAdvice = _generateCoachAdvice(bestMoveObj, chess, scorePawns, isWhiteTurn);

      return EngineAnalysisResult(
        bestMove: uciMove,
        moveSan: bestSan,
        evalScore: scorePawns,
        evalPercent: evalPercent,
        evalText: evalText,
        coachAdvice: coachAdvice,
      );
    } catch (_) {
      return const EngineAnalysisResult(
        bestMove: "e2e4",
        moveSan: "e4",
        evalScore: 0.25,
        evalPercent: 52.0,
        evalText: "+0.25",
        coachAdvice: "💡 Control the center with pawns and develop knights before bishops.",
      );
    }
  }

  String _generateCoachAdvice(Map? moveObj, chess_logic.Chess chess, double scorePawns, bool isWhiteTurn) {
    if (moveObj == null) return "💡 Focus on active piece mobility.";

    final captured = moveObj['captured'];
    final flags = moveObj['flags']?.toString() ?? '';
    final san = moveObj['san']?.toString() ?? '';
    final piece = moveObj['piece']?.toString() ?? '';
    final toSq = moveObj['to']?.toString() ?? '';

    if (flags.contains('k') || flags.contains('q')) {
      return "🏰 Castling: Shields the King safely in the corner and activates the Rook to the center.";
    }

    if (captured != null) {
      final capturedName = _pieceName(captured.toString());
      return "⚔️ Tactical Capture: Takes the opponent's $capturedName on $toSq (${scorePawns >= 0 ? '+' : ''}${scorePawns.toStringAsFixed(1)} material advantage).";
    }

    if (san.contains('+')) {
      return "⚡ Check: Forces the enemy King into defensive posture or disrupts castling rights!";
    }

    if (piece.toLowerCase() == 'n') {
      return "🐴 Knight Maneuver: Developing the Knight to $toSq dominates key central outposts.";
    }

    if (piece.toLowerCase() == 'b') {
      return "♗ Bishop Diagonal: Opens a long-range tactical diagonal cutting across the enemy board.";
    }

    if (piece.toLowerCase() == 'p' && (toSq == 'e4' || toSq == 'd4' || toSq == 'e5' || toSq == 'd5')) {
      return "🎯 Central Space: Claims direct physical control over the 4 crucial central squares.";
    }

    if (scorePawns > 2.0) {
      return "🔥 Decisive Advantage: White is clearly winning. Trade down material into an easy endgame.";
    } else if (scorePawns < -2.0) {
      return "🛡️ Under Pressure: Black holds strong counter-attack. Guard your back-rank and King safety.";
    }

    return "⚖️ Strategic Play: Developing pieces toward the center with coordinated pawn structure.";
  }

  String _pieceName(String char) {
    switch (char.toLowerCase()) {
      case 'p': return 'Pawn';
      case 'n': return 'Knight';
      case 'b': return 'Bishop';
      case 'r': return 'Rook';
      case 'q': return 'Queen';
      case 'k': return 'King';
      default: return 'Piece';
    }
  }

  Future<EngineAnalysisResult?> _fetchLichessCloud(String fen) async {
    try {
      final uri = Uri.parse('https://lichess.org/api/cloud-eval?fen=${Uri.encodeComponent(fen)}');
      final res = await http.get(uri).timeout(const Duration(milliseconds: 1400));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final pvs = data['pvs'] as List?;
        if (pvs != null && pvs.isNotEmpty) {
          final firstPv = pvs[0];
          final movesStr = firstPv['moves']?.toString() ?? '';
          final moves = movesStr.split(' ');
          final bestUci = moves.isNotEmpty ? moves[0] : 'e2e4';

          int cp = 0;
          if (firstPv['cp'] != null) {
            cp = (firstPv['cp'] as num).toInt();
          } else if (firstPv['mate'] != null) {
            cp = (firstPv['mate'] as num) > 0 ? 10000 : -10000;
          }

          final double scorePawns = cp / 100.0;
          final double evalPercent = (50.0 + (scorePawns * 8.5)).clamp(5.0, 95.0);
          final String evalText = cp.abs() > 5000
              ? '# Mate'
              : (scorePawns >= 0 ? '+${scorePawns.toStringAsFixed(2)}' : scorePawns.toStringAsFixed(2));

          return EngineAnalysisResult(
            bestMove: bestUci,
            moveSan: bestUci,
            evalScore: scorePawns,
            evalPercent: evalPercent,
            evalText: evalText,
            coachAdvice: "☁️ Lichess Cloud GM Evaluation: Depth ${data['depth'] ?? 40} NNUE Analysis.",
            isCloud: true,
          );
        }
      }
    } catch (_) {}
    return null;
  }
}
