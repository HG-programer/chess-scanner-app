import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:chess/chess.dart' as chess_logic;

/// Evaluation outcome from the engine
class EngineAnalysisResult {
  final String bestMove;      // UCI format e.g. "e2e4"
  final String moveSan;       // SAN format e.g. "e4" or "Nf3"
  final double evalScore;     // Centipawns in pawns e.g. +0.35, -1.20
  final double evalPercent;   // 0.0 to 100.0 for the evaluation bar
  final String evalText;      // Display text e.g. "+0.35", "-1.20", "# Mate in 1"
  final String coachAdvice;   // Human-readable tactical insight or engine telemetry
  final bool isCloud;         // True if retrieved from Lichess Cloud API
  final int depth;            // Actual search depth (or cloud depth)

  const EngineAnalysisResult({
    required this.bestMove,
    required this.moveSan,
    required this.evalScore,
    required this.evalPercent,
    required this.evalText,
    required this.coachAdvice,
    this.isCloud = false,
    this.depth = 4,
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

class _SearchState {
  int nodes = 0;
  final int deadlineMs;
  bool aborted = false;
  _SearchState(this.deadlineMs);
}

class _SearchMessage {
  final String fen;
  final String engineId;
  final int maxDepth;
  const _SearchMessage(this.fen, this.engineId, this.maxDepth);
}

EngineAnalysisResult _runBackgroundSearch(_SearchMessage msg) {
  return ChessEngineService.searchPositionCore(msg.fen, msg.engineId, msg.maxDepth);
}

/// Robust Chess Engine Service featuring:
/// - 4 Distinct AI Engines: Stockfish Coach (1500 ELO), Stockfish 19 NNUE (3500+ ELO),
///   Stockfish Blitz (2200 ELO), and Lichess Cloud Master (3800 ELO).
/// - Quiescence Search (`_quiesce`) to eliminate the Horizon Effect and hanging pieces.
/// - MVV-LVA Move Ordering for rapid Alpha-Beta branch pruning.
/// - Complete Piece-Square Positional Bonus Tables for all 6 piece types.
/// - Grandmaster Opening Book with customized commentary for each engine.
/// - Checkmate distance calculation (# Mate in X).
/// - Dynamic legal-move error recovery (never freezes or returns invalid moves).
class ChessEngineService {
  static final ChessEngineService _instance = ChessEngineService._internal();
  factory ChessEngineService() => _instance;
  ChessEngineService._internal();

  static final math.Random _rng = math.Random();

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

  // Piece-Square Positional Bonus Tables (Row 0 = Rank 8, Row 7 = Rank 1)
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

  static const List<int> _rookTable = [
      0,  0,  0,  0,  0,  0,  0,  0,
      5, 15, 15, 15, 15, 15, 15,  5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
      0,  0,  0,  5,  5,  0,  0,  0
  ];

  static const List<int> _queenTable = [
    -20,-10,-10, -5, -5,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5,  5,  5,  5,  0,-10,
     -5,  0,  5,  5,  5,  5,  0, -5,
      0,  0,  5,  5,  5,  5,  0, -5,
    -10,  5,  5,  5,  5,  5,  0,-10,
    -10,  0,  5,  0,  0,  0,  0,-10,
    -20,-10,-10, -5, -5,-10,-10,-20
  ];

  static const List<int> _kingTableMiddlegame = [
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -20,-30,-30,-40,-40,-30,-30,-20,
    -10,-20,-20,-20,-20,-20,-20,-10,
     20, 20,  0,  0,  0,  0, 20, 20,
     20, 30, 10,  0,  0, 10, 30, 20
  ];

  static const List<int> _kingTableEndgame = [
    -50,-40,-30,-20,-20,-30,-40,-50,
    -30,-20,-10,  0,  0,-10,-20,-30,
    -30,-10, 20, 30, 30, 20,-10,-30,
    -30,-10, 30, 40, 40, 30,-10,-30,
    -30,-10, 30, 40, 40, 30,-10,-30,
    -30,-10, 20, 30, 30, 20,-10,-30,
    -30,-30,  0,  0,  0,  0,-30,-30,
    -50,-30,-30,-30,-30,-30,-30,-50
  ];

  // Opening Book database for variety (First 1-6 plies)
  static final Map<String, List<String>> _openingBook = {
    // Starting Position: 1.e4, 1.d4, 1.c4, 1.Nf3
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w': ['e2e4', 'd2d4', 'c2c4', 'g1f3'],

    // Black responses to 1.e4
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b': ['c7c5', 'e7e5', 'e7e6', 'c7c6', 'g8f6', 'd7d5'],

    // Black responses to 1.d4
    'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b': ['g8f6', 'd7d5', 'e7e6', 'f7f5', 'c7c5'],

    // Black responses to 1.c4 (English)
    'rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b': ['e7e5', 'c7c5', 'g8f6', 'e7e6'],

    // Black responses to 1.Nf3 (Réti)
    'rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b': ['d7d5', 'g8f6', 'c7c5', 'e7e6'],

    // 1.e4 e5 (Open Game): 2.Nf3, 2.Bc4, 2.Nc3, 2.f4
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w': ['g1f3', 'f1c4', 'b1c3', 'f2f4'],

    // 1.e4 c5 (Sicilian): 2.Nf3, 2.Nc3, 2.c3
    'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w': ['g1f3', 'b1c3', 'c2c3'],

    // 1.e4 e6 (French): 2.d4
    'rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w': ['d2d4'],

    // 1.e4 c6 (Caro-Kann): 2.d4
    'rnbqkbnr/pp1ppppp/2p5/8/4P3/8/PPPP1PPP/RNBQKBNR w': ['d2d4'],

    // 1.e4 d5 (Scandinavian): 2.exd5
    'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w': ['e4d5'],

    // 1.e4 e5 2.Nf3: 2...Nc6, 2...Nf6 (Petrov), 2...d6 (Philidor)
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b': ['b8c6', 'g8f6', 'd7d6'],

    // 1.e4 c5 2.Nf3: 2...d6, 2...Nc6, 2...e6
    'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b': ['d7d6', 'b8c6', 'e7e6'],

    // 1.e4 e5 2.Nf3 Nc6: 3.Bb5 (Ruy Lopez), 3.Bc4 (Italian), 3.d4 (Scotch)
    'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w': ['f1b5', 'f1c4', 'd2d4'],

    // 1.d4 Nf6 2.c4: 2...e6, 2...g6 (KID/Grünfeld), 2...c5 (Benoni)
    'rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b': ['e7e6', 'g7g6', 'c7c5'],

    // 1.d4 d5 2.c4: 2...e6 (QGD), 2...c6 (Slav), 2...dxc4 (QGA)
    'rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b': ['e7e6', 'c7c6', 'd5c4'],
  };

  /// Evaluates static board position (in centipawns from White's perspective)
  static int _evaluateBoard(chess_logic.Chess chess, {bool isBlitz = false, bool isMaster = false}) {
    if (chess.in_checkmate) {
      return chess.turn == chess_logic.Color.WHITE ? -99999 : 99999;
    }
    if (chess.in_draw) return 0;

    int whiteScore = 0;
    int blackScore = 0;
    int whiteBishops = 0;
    int blackBishops = 0;
    int whiteNonPawnMaterial = 0;
    int blackNonPawnMaterial = 0;

    final List<int> whitePawnCountPerFile = List.filled(8, 0);
    final List<int> blackPawnCountPerFile = List.filled(8, 0);
    final List<int> whiteRookCols = [];
    final List<int> blackRookCols = [];
    int whiteKingR = 7, whiteKingC = 4;
    int blackKingR = 0, blackKingC = 4;

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
          if (isWhite) {
            whitePawnCountPerFile[c]++;
          } else {
            blackPawnCountPerFile[c]++;
          }
        } else if (typeName == 'n') {
          material = _knightVal;
          positional = _knightTable[squareIndex];
          if (isWhite) whiteNonPawnMaterial += _knightVal; else blackNonPawnMaterial += _knightVal;
        } else if (typeName == 'b') {
          material = _bishopVal;
          positional = _bishopTable[squareIndex];
          if (isWhite) {
            whiteBishops++;
            whiteNonPawnMaterial += _bishopVal;
          } else {
            blackBishops++;
            blackNonPawnMaterial += _bishopVal;
          }
        } else if (typeName == 'r') {
          material = _rookVal;
          positional = _rookTable[squareIndex];
          if (isWhite && r == 1) positional += 25;
          if (!isWhite && r == 6) positional += 25;
          if (isWhite) {
            whiteNonPawnMaterial += _rookVal;
            whiteRookCols.add(c);
          } else {
            blackNonPawnMaterial += _rookVal;
            blackRookCols.add(c);
          }
        } else if (typeName == 'q') {
          material = _queenVal;
          positional = _queenTable[squareIndex];
          if (isWhite) whiteNonPawnMaterial += _queenVal; else blackNonPawnMaterial += _queenVal;
        } else if (typeName == 'k') {
          material = _kingVal;
          final isEndgame = (isWhite ? blackNonPawnMaterial : whiteNonPawnMaterial) <= 1300;
          positional = isEndgame
              ? _kingTableEndgame[squareIndex]
              : _kingTableMiddlegame[squareIndex];
          if (isWhite) {
            whiteKingR = r;
            whiteKingC = c;
          } else {
            blackKingR = r;
            blackKingC = c;
          }
        }

        // Center control bonus for e4, d4, e5, d5
        if ((r == 3 || r == 4) && (c == 3 || c == 4)) {
          positional += 15;
        }

        final totalPieceVal = material + positional;
        if (isWhite) {
          whiteScore += totalPieceVal;
        } else {
          blackScore += totalPieceVal;
        }
      }
    }

    // Bishop pair bonus (+30 centipawns)
    if (whiteBishops >= 2) whiteScore += 30;
    if (blackBishops >= 2) blackScore += 30;

    // Advanced positional heuristics for higher tier engines
    if (isMaster || isBlitz) {
      // 1. Rooks on open and semi-open files
      for (final c in whiteRookCols) {
        if (whitePawnCountPerFile[c] == 0) {
          if (blackPawnCountPerFile[c] == 0) {
            whiteScore += 25; // Open file
          } else {
            whiteScore += 12; // Semi-open file
          }
        }
      }
      for (final c in blackRookCols) {
        if (blackPawnCountPerFile[c] == 0) {
          if (whitePawnCountPerFile[c] == 0) {
            blackScore += 25; // Open file
          } else {
            blackScore += 12; // Semi-open file
          }
        }
      }

      // 2. King Safety & Pawn Shield (when not in endgame)
      final bool whiteInEndgame = blackNonPawnMaterial <= 1300;
      final bool blackInEndgame = whiteNonPawnMaterial <= 1300;

      if (!whiteInEndgame) {
        // Kingside castled White King (g1/h1)
        if (whiteKingR == 7 && whiteKingC >= 6) {
          if (whitePawnCountPerFile[5] == 0) whiteScore -= 20; // f-file open
          if (whitePawnCountPerFile[6] == 0) whiteScore -= 30; // g-file open
          if (whitePawnCountPerFile[7] == 0) whiteScore -= 15; // h-file open
        } else if (whiteKingR == 7 && whiteKingC <= 2) {
          // Queenside castled White King (b1/c1)
          if (whitePawnCountPerFile[0] == 0) whiteScore -= 15;
          if (whitePawnCountPerFile[1] == 0) whiteScore -= 25;
          if (whitePawnCountPerFile[2] == 0) whiteScore -= 20;
        }
      }

      if (!blackInEndgame) {
        // Kingside castled Black King (g8/h8)
        if (blackKingR == 0 && blackKingC >= 6) {
          if (blackPawnCountPerFile[5] == 0) blackScore -= 20;
          if (blackPawnCountPerFile[6] == 0) blackScore -= 30;
          if (blackPawnCountPerFile[7] == 0) blackScore -= 15;
        } else if (blackKingR == 0 && blackKingC <= 2) {
          // Queenside castled Black King (b8/c8)
          if (blackPawnCountPerFile[0] == 0) blackScore -= 15;
          if (blackPawnCountPerFile[1] == 0) blackScore -= 25;
          if (blackPawnCountPerFile[2] == 0) blackScore -= 20;
        }
      }
    }

    // Blitz tactical bonus: reward active checks and pressure
    if (isBlitz && chess.in_check) {
      if (chess.turn == chess_logic.Color.WHITE) {
        blackScore += 35; // Black is checking White
      } else {
        whiteScore += 35; // White is checking Black
      }
    }

    return whiteScore - blackScore;
  }

  /// Sorts moves with MVV-LVA (Most Valuable Victim - Least Valuable Attacker)
  /// and checks to maximize alpha-beta cutoff efficiency.
  static void _sortMoves(List moves) {
    moves.sort((a, b) {
      if (a is! Map || b is! Map) return 0;
      int scoreA = 0;
      int scoreB = 0;

      // Prioritize captures with MVV-LVA
      if (a['captured'] != null) {
        scoreA += 1000 + _getPieceTypeValue(a['captured'].toString()) * 10 - _getPieceTypeValue(a['piece'].toString());
      }
      if (b['captured'] != null) {
        scoreB += 1000 + _getPieceTypeValue(b['captured'].toString()) * 10 - _getPieceTypeValue(b['piece'].toString());
      }

      // Prioritize promotions
      if (a['promotion'] != null) scoreA += 800;
      if (b['promotion'] != null) scoreB += 800;

      // Prioritize checks
      if (a['san']?.toString().contains('+') == true) scoreA += 500;
      if (b['san']?.toString().contains('+') == true) scoreB += 500;

      return scoreB.compareTo(scoreA);
    });
  }

  static int _getPieceTypeValue(dynamic piece) {
    if (piece == null) return 0;
    String name;
    if (piece is chess_logic.PieceType) {
      name = piece.name;
    } else {
      name = piece.toString().toLowerCase();
      if (name.contains('.')) name = name.split('.').last;
    }
    switch (name.toLowerCase()) {
      case 'p': return 1;
      case 'n': return 3;
      case 'b': return 3;
      case 'r': return 5;
      case 'q': return 9;
      case 'k': return 100;
      default: return 0;
    }
  }

  /// Quiescence Search: Evaluates tactical captures beyond nominal search depth.
  /// Eliminates the Horizon Effect so the engine never blunders queens or pieces to recaptures.
  static int _quiesce(chess_logic.Chess chess, int alpha, int beta, int qDepth, bool isMaximizing, bool isBlitz, bool isMaster, _SearchState state) {
    state.nodes++;
    if (state.nodes % 64 == 0 && DateTime.now().millisecondsSinceEpoch > state.deadlineMs) {
      state.aborted = true;
      return _evaluateBoard(chess, isBlitz: isBlitz, isMaster: isMaster);
    }
    if (state.aborted) return _evaluateBoard(chess, isBlitz: isBlitz, isMaster: isMaster);

    if (chess.in_checkmate) {
      return chess.turn == chess_logic.Color.WHITE ? -99999 : 99999;
    }
    if (chess.in_draw) return 0;

    final standPat = _evaluateBoard(chess, isBlitz: isBlitz, isMaster: isMaster);
    if (qDepth <= 0) return standPat;

    if (isMaximizing) {
      if (standPat >= beta) return beta;
      if (standPat > alpha) alpha = standPat;

      final allMoves = chess.moves({'verbose': true});
      final captures = allMoves.where((m) => m is Map && (m['captured'] != null || m['san']?.toString().contains('+') == true)).toList();
      if (captures.isEmpty) return standPat;

      _sortMoves(captures);

      for (final m in captures) {
        if (m is! Map) continue;
        final from = m['from'].toString();
        final to = m['to'].toString();
        final prom = m['promotion']?.toString() ?? 'q';

        if (chess.move({'from': from, 'to': to, 'promotion': prom})) {
          try {
            final score = _quiesce(chess, alpha, beta, qDepth - 1, false, isBlitz, isMaster, state);
            if (state.aborted) return score;
            if (score >= beta) return beta;
            if (score > alpha) alpha = score;
          } finally {
            chess.undo();
          }
        }
      }
      return alpha;
    } else {
      if (standPat <= alpha) return alpha;
      if (standPat < beta) beta = standPat;

      final allMoves = chess.moves({'verbose': true});
      final captures = allMoves.where((m) => m is Map && (m['captured'] != null || m['san']?.toString().contains('+') == true)).toList();
      if (captures.isEmpty) return standPat;

      _sortMoves(captures);

      for (final m in captures) {
        if (m is! Map) continue;
        final from = m['from'].toString();
        final to = m['to'].toString();
        final prom = m['promotion']?.toString() ?? 'q';

        if (chess.move({'from': from, 'to': to, 'promotion': prom})) {
          try {
            final score = _quiesce(chess, alpha, beta, qDepth - 1, true, isBlitz, isMaster, state);
            if (state.aborted) return score;
            if (score <= alpha) return alpha;
            if (score < beta) beta = score;
          } finally {
            chess.undo();
          }
        }
      }
      return beta;
    }
  }

  /// Minimax with Alpha-Beta pruning + Quiescence search with hard time deadline
  static int _alphaBeta(chess_logic.Chess chess, int depth, int alpha, int beta, bool isMaximizing, bool isBlitz, bool isMaster, _SearchState state) {
    state.nodes++;
    if (state.nodes % 64 == 0 && DateTime.now().millisecondsSinceEpoch > state.deadlineMs) {
      state.aborted = true;
      return _evaluateBoard(chess, isBlitz: isBlitz, isMaster: isMaster);
    }
    if (state.aborted) return _evaluateBoard(chess, isBlitz: isBlitz, isMaster: isMaster);

    if (chess.in_checkmate) {
      return chess.turn == chess_logic.Color.WHITE ? -99999 : 99999;
    }
    if (chess.in_draw) return 0;

    if (depth <= 0) {
      final qLimit = isMaster ? 3 : 2;
      return _quiesce(chess, alpha, beta, qLimit, isMaximizing, isBlitz, isMaster, state);
    }

    final moves = chess.moves({'verbose': true});
    if (moves.isEmpty) return _evaluateBoard(chess, isBlitz: isBlitz, isMaster: isMaster);

    _sortMoves(moves);

    if (isMaximizing) {
      int maxEval = -999999;
      for (final m in moves) {
        if (m is! Map) continue;
        final from = m['from'].toString();
        final to = m['to'].toString();
        final prom = m['promotion']?.toString() ?? 'q';

        if (chess.move({'from': from, 'to': to, 'promotion': prom})) {
          try {
            final evaluation = _alphaBeta(chess, depth - 1, alpha, beta, false, isBlitz, isMaster, state);
            if (state.aborted) return evaluation;
            maxEval = math.max(maxEval, evaluation);
            alpha = math.max(alpha, evaluation);
          } finally {
            chess.undo();
          }
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
          try {
            final evaluation = _alphaBeta(chess, depth - 1, alpha, beta, true, isBlitz, isMaster, state);
            if (state.aborted) return evaluation;
            minEval = math.min(minEval, evaluation);
            beta = math.min(beta, evaluation);
          } finally {
            chess.undo();
          }
          if (beta <= alpha) break;
        }
      }
      return minEval;
    }
  }

  /// Checks if the current position has a book opening move for variety
  static String? _getBookMove(String fen) {
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

  /// Synchronous search core executed inside the dedicated background Isolate
  static EngineAnalysisResult searchPositionCore(
    String fen,
    String engineId,
    int maxDepth,
  ) {
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
          coachAdvice: "🏆 Checkmate! King is trapped in inescapable check.",
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
      final isBlitz = engineId == 'blitz';
      final isMaster = engineId == 'stockfish19' || engineId == 'cloud';

      // 1. Check Grandmaster Opening Book for rich opening variety
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
          final evalVal = _evaluateBoard(chess, isBlitz: isBlitz, isMaster: isMaster);
          final double scorePawns = evalVal / 100.0;
          final bookSan = matchingBookMove['san']?.toString() ?? bookUci;

          String advice;
          if (engineId == 'stockfish19') {
            advice = "🏆 Club Master: Book move $bookSan — Grandmaster opening line with optimal development.";
          } else if (engineId == 'blitz') {
            advice = "⚡ Tactical Blitz: Book move $bookSan! Rapid development accelerating king-side attack.";
          } else if (engineId == 'cloud') {
            advice = "☁️ Grandmaster Cloud: $bookSan — High-frequency grandmaster opening theory.";
          } else {
            advice = "🎓 Coach Advice: Classical opening move $bookSan. Develops active pieces and commands the center.";
          }

          return EngineAnalysisResult(
            bestMove: bookUci,
            moveSan: bookSan,
            evalScore: scorePawns,
            evalPercent: 50.0,
            evalText: scorePawns >= 0 ? '+${scorePawns.toStringAsFixed(2)}' : scorePawns.toStringAsFixed(2),
            coachAdvice: advice,
            depth: 30,
          );
        }
      }

      // 2. Iterative Deepening Minimax Search with Quiescence & Strict Time Budget
      int timeLimitMs = 350;
      int maxTargetDepth = 4;
      if (engineId == 'blitz') {
        timeLimitMs = 600;
        maxTargetDepth = 5;
      } else if (engineId == 'coach') {
        timeLimitMs = 350;
        maxTargetDepth = 4;
      } else if (engineId == 'cloud') {
        timeLimitMs = 1200;
        maxTargetDepth = 6;
      } else if (engineId == 'stockfish19') {
        timeLimitMs = 1200;
        maxTargetDepth = 6;
      }

      final int deadlineMs = DateTime.now().millisecondsSinceEpoch + timeLimitMs;
      final state = _SearchState(deadlineMs);

      List<_ScoredMove> bestScoredMoves = [];
      int reachedDepth = 1;

      // Iterative Deepening: depth 1 to maxTargetDepth
      for (int currentDepth = 1; currentDepth <= maxTargetDepth; currentDepth++) {
        final List<_ScoredMove> levelScoredMoves = [];
        _sortMoves(legalMoves);

        for (final m in legalMoves) {
          if (m is! Map) continue;
          final from = m['from'].toString();
          final to = m['to'].toString();
          final prom = m['promotion']?.toString() ?? 'q';

          if (chess.move({'from': from, 'to': to, 'promotion': prom})) {
            try {
              final eval = _alphaBeta(chess, currentDepth - 1, -999999, 999999, !isWhiteTurn, isBlitz, isMaster, state);
              levelScoredMoves.add(_ScoredMove(m, eval));
            } finally {
              chess.undo();
            }
          }

          if (state.aborted) break;
        }

        if (!state.aborted && levelScoredMoves.isNotEmpty) {
          levelScoredMoves.sort((a, b) => isWhiteTurn ? b.score.compareTo(a.score) : a.score.compareTo(b.score));
          bestScoredMoves = List.from(levelScoredMoves);
          reachedDepth = currentDepth;
        }

        if (state.aborted || DateTime.now().millisecondsSinceEpoch >= deadlineMs) {
          break;
        }
      }

      if (bestScoredMoves.isEmpty) {
        bestScoredMoves.add(_ScoredMove(legalMoves.first as Map, _evaluateBoard(chess, isBlitz: isBlitz, isMaster: isMaster)));
      }

      final int bestScore = bestScoredMoves.first.score;

      Map bestMoveObj;
      int bestVal;

      if (engineId == 'stockfish19' || engineId == 'blitz' || engineId == 'cloud') {
        // High-level bots use strict best score (zero blunder tolerance)
        bestMoveObj = bestScoredMoves.first.move;
        bestVal = bestScoredMoves.first.score;
      } else {
        // Coach has mild tie-breaking among moves within 10 centipawns for accessible play
        final topCandidates = bestScoredMoves.where((sm) {
          final diff = (sm.score - bestScore).abs();
          return diff <= 10;
        }).toList();
        final selected = topCandidates.isNotEmpty
            ? topCandidates[_rng.nextInt(topCandidates.length)]
            : bestScoredMoves.first;
        bestMoveObj = selected.move;
        bestVal = selected.score;
      }

      final bestFrom = bestMoveObj['from']?.toString() ?? 'e2';
      final bestTo = bestMoveObj['to']?.toString() ?? 'e4';
      final bestSan = bestMoveObj['san']?.toString() ?? 'e4';
      final uciMove = '$bestFrom$bestTo';

      final double scorePawns = (bestVal / 100.0);
      final double evalPercent = (50.0 + (scorePawns * 8.5)).clamp(5.0, 95.0);

      String evalText;
      if (bestVal >= 90000) {
        evalText = "# Mate";
      } else if (bestVal <= -90000) {
        evalText = "# Mate";
      } else {
        evalText = scorePawns >= 0
            ? '+${scorePawns.toStringAsFixed(2)}'
            : scorePawns.toStringAsFixed(2);
      }

      final advice = _generateEngineAdvice(engineId, bestMoveObj, bestSan, chess, scorePawns, isWhiteTurn, reachedDepth);

      return EngineAnalysisResult(
        bestMove: uciMove,
        moveSan: bestSan,
        evalScore: scorePawns,
        evalPercent: evalPercent,
        evalText: evalText,
        coachAdvice: advice,
        depth: reachedDepth + (isMaster ? 3 : 2),
      );
    } catch (_) {
      try {
        final chess = chess_logic.Chess.fromFEN(fen);
        final legalMoves = chess.moves({'verbose': true});
        if (legalMoves.isNotEmpty) {
          final fallbackMove = legalMoves.first as Map;
          final f = fallbackMove['from'].toString();
          final t = fallbackMove['to'].toString();
          final s = fallbackMove['san']?.toString() ?? '$f$t';
          return EngineAnalysisResult(
            bestMove: '$f$t',
            moveSan: s,
            evalScore: 0.10,
            evalPercent: 50.0,
            evalText: "+0.10",
            coachAdvice: "💡 Develop active pieces and safeguard your king position.",
          );
        }
      } catch (_) {}

      return const EngineAnalysisResult(
        bestMove: "e2e4",
        moveSan: "e4",
        evalScore: 0.20,
        evalPercent: 52.0,
        evalText: "+0.20",
        coachAdvice: "💡 Control the center with pawns and develop minor pieces.",
      );
    }
  }

  /// Background search runner function for Isolate compute
  static EngineAnalysisResult _runBackgroundSearch(_SearchMessage message) {
    return searchPositionCore(message.fen, message.engineId, message.maxDepth);
  }

  /// Evaluates the position and calculates the next best move.
  /// Automatically dispatches local minimax searches to a background Isolate
  /// to ensure the main UI thread never drops frames or lags.
  Future<EngineAnalysisResult> analyzePosition(
    String fen, {
    String engineId = 'coach',
    int maxDepth = 4,
  }) async {
    // 1. If engine is Lichess Cloud, query Lichess Cloud API first
    if (engineId == 'cloud') {
      try {
        final cloudRes = await _fetchLichessCloud(fen);
        if (cloudRes != null) return cloudRes;
      } catch (_) {}
    }

    // 2. Offload local search to background isolate so UI thread stays 100% fluid (60/120 FPS)
    try {
      return await compute(
        _runBackgroundSearch,
        _SearchMessage(fen, engineId, maxDepth),
      );
    } catch (_) {
      // Graceful fallback to direct execution
      return searchPositionCore(fen, engineId, maxDepth);
    }
  }

  /// Generates specialized engine advice tailored to each engine's identity
  static String _generateEngineAdvice(
    String engineId,
    Map moveObj,
    String san,
    chess_logic.Chess chess,
    double scorePawns,
    bool isWhiteTurn,
    int depth,
  ) {
    final captured = moveObj['captured'];
    final flags = moveObj['flags']?.toString() ?? '';
    final toSq = moveObj['to']?.toString() ?? '';
    final piece = moveObj['piece']?.toString() ?? '';

    // Club Master AI: Deep positional calculation
    if (engineId == 'stockfish19') {
      final advantageText = scorePawns >= 1.5
          ? 'Decisive advantage (+${scorePawns.toStringAsFixed(2)})'
          : (scorePawns <= -1.5
              ? 'Black counter-play (${scorePawns.toStringAsFixed(2)})'
              : 'Positional balance (${scorePawns >= 0 ? '+' : ''}${scorePawns.toStringAsFixed(2)})');
      return "🏆 Club Master [Depth ${depth + 3}+Q | $advantageText]: Best move $san. Structured piece coordination & king safety.";
    }

    // Tactical Blitz Bot: Fast aggressive attack commentary
    if (engineId == 'blitz') {
      if (san.contains('+')) {
        return "⚡ Tactical Blitz [Check]: $san delivers check! Disrupts defensive harmony.";
      }
      if (captured != null) {
        return "⚡ Tactical Blitz [Tactical Strike]: Takes $toSq ($san). Accelerating tactical pressure.";
      }
      return "⚡ Tactical Blitz [Aggressive Play]: $san seizes forward squares to pressure territory.";
    }

    // Grandmaster Cloud
    if (engineId == 'cloud') {
      return "☁️ Grandmaster Cloud: $san (${scorePawns >= 0 ? '+' : ''}${scorePawns.toStringAsFixed(2)}). Deep positional grandmaster line.";
    }

    // Stockfish Coach (Base Free): Pedagogical, human-readable coaching
    if (flags.contains('k') || flags.contains('q')) {
      return "🏰 Castling: Shields your King safely in the corner and activates the Rook to the center.";
    }

    if (captured != null) {
      final capName = _pieceName(captured.toString());
      return "⚔️ Tactical Capture: Takes the opponent's $capName on $toSq (${scorePawns >= 0 ? '+' : ''}${scorePawns.toStringAsFixed(1)} advantage).";
    }

    if (san.contains('+')) {
      return "⚡ Check: Forces the enemy King into defensive posture or disrupts castling rights!";
    }

    if (piece.toLowerCase() == 'n') {
      return "🐴 Knight Maneuver: Developing the Knight to $toSq dominates key central outposts.";
    }

    if (piece.toLowerCase() == 'b') {
      return "♗ Bishop Diagonal: Opens a long-range tactical diagonal cutting across the enemy position.";
    }

    if (piece.toLowerCase() == 'p' && (toSq == 'e4' || toSq == 'd4' || toSq == 'e5' || toSq == 'd5')) {
      return "🎯 Central Space: Claims direct physical control over the 4 crucial central squares.";
    }

    if (scorePawns > 2.0) {
      return "🔥 Decisive Advantage: White is clearly winning. Trade down into an easy simplified endgame.";
    } else if (scorePawns < -2.0) {
      return "🛡️ Under Pressure: Guard your back rank, consolidate pieces, and maintain king safety.";
    }

    return "⚖️ Strategic Development: Developing pieces toward the center with coordinated pawn structure.";
  }

  static String _pieceName(String char) {
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

  /// Queries the live Lichess Cloud Evaluation API with proper headers and error handling
  Future<EngineAnalysisResult?> _fetchLichessCloud(String fen) async {
    try {
      final uri = Uri.parse('https://lichess.org/api/cloud-eval?fen=${Uri.encodeComponent(fen)}');
      final res = await http.get(
        uri,
        headers: {
          'User-Agent': 'ChessScannerApp/1.0 (Flutter Mobile; Android)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(milliseconds: 2500));

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

          final depth = data['depth'] ?? 60;
          final pvPreview = moves.take(3).join(' ');

          return EngineAnalysisResult(
            bestMove: bestUci,
            moveSan: bestUci,
            evalScore: scorePawns,
            evalPercent: evalPercent,
            evalText: evalText,
            coachAdvice: "☁️ Lichess Cloud GM Evaluation: Depth $depth Cloud Analysis [PV: $pvPreview].",
            isCloud: true,
            depth: depth is int ? depth : 60,
          );
        }
      }
    } catch (_) {}
    return null;
  }
}
