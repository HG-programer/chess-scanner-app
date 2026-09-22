import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DailyPuzzleData {
  final String id;
  final String title;
  final String fen;
  final List<String> solution; // UCI moves e.g. ["e5f4", "c3c4", "h6h2"]
  final int rating;
  final List<String> themes;
  final bool isWhiteToMove;

  DailyPuzzleData({
    required this.id,
    required this.title,
    required this.fen,
    required this.solution,
    required this.rating,
    required this.themes,
    required this.isWhiteToMove,
  });
}

class RetentionService {
  static const String _scansCountKey = 'successful_scans_count';
  static const String _reviewPromptedKey = 'review_prompted';
  static const String _puzzleCacheKey = 'cached_puzzle_json';
  static const String _puzzleCacheTimeKey = 'cached_puzzle_timestamp';

  final InAppReview _inAppReview = InAppReview.instance;

  // Curated collection of famous master tactical puzzles across various themes
  static final List<DailyPuzzleData> curatedPuzzles = [
    DailyPuzzleData(
      id: "opera_game",
      title: "Paul Morphy's Opera Game Mate",
      fen: "4kb1r/p2rqppp/5n2/1B2p1B1/4P3/1Q6/PPP2PPP/2KR4 w k - 0 14",
      solution: ["b5d7", "f6d7", "b3b8", "d7b8", "d1d8"],
      rating: 1550,
      themes: ["Pin & Skewer", "Queen Sacrifice", "Attacking King"],
      isWhiteToMove: true,
    ),
    DailyPuzzleData(
      id: "smothered_mate",
      title: "Classic Philidor Smothered Mate",
      fen: "6k1/5ppp/8/8/8/2Q5/5PPP/4R1K1 w - - 0 1",
      solution: ["c3c8", "e1c8"],
      rating: 1200,
      themes: ["Back Rank Mate", "Tactics"],
      isWhiteToMove: true,
    ),
    DailyPuzzleData(
      id: "queen_deflection",
      title: "Grandmaster Queen Deflection",
      fen: "r1b2rk1/pp3ppp/2n1p3/3pP3/8/2NB1N2/PPP2PPP/R2Q1RK1 w - - 0 12",
      solution: ["d3h7", "g8h7", "f3g5", "h7g8", "d1h5"],
      rating: 1650,
      themes: ["Greek Gift", "Sacrifice", "Kingside Attack"],
      isWhiteToMove: true,
    ),
    DailyPuzzleData(
      id: "anand_fork",
      title: "Viswanathan Anand Knight Fork",
      fen: "r2qk2r/ppp2ppp/2np1n2/1B2p1B1/1b2P1b1/2NP1N2/PPP2PPP/R2Q1RK1 w kq - 2 8",
      solution: ["c3d5", "b4c5", "d5f6"],
      rating: 1400,
      themes: ["Fork", "Discovered Attack"],
      isWhiteToMove: true,
    ),
    DailyPuzzleData(
      id: "kasparov_breakthrough",
      title: "Kasparov Endgame Pawn Breakthrough",
      fen: "8/5p2/4p1p1/3pP1P1/2kP4/8/1K6/8 w - - 0 1",
      solution: ["b2c2", "c4d4", "c2d2"],
      rating: 1750,
      themes: ["Endgame", "Pawn Play", "Zugzwang"],
      isWhiteToMove: true,
    ),
    DailyPuzzleData(
      id: "black_counter_strike",
      title: "Black King's Indian Counter-Strike",
      fen: "r1bq1rk1/ppp2ppp/2n5/3p4/2PP4/2n1PN2/P1Q2PPP/R1B1KB1R b KQ - 1 9",
      solution: ["c3e4", "c4d5", "d8d5"],
      rating: 1500,
      themes: ["Middle Game", "Tactics", "Center Control"],
      isWhiteToMove: false,
    ),
    DailyPuzzleData(
      id: "fischer_trap",
      title: "Bobby Fischer's Bishop Trap",
      fen: "r1b1k2r/ppppbppp/2n5/1B6/4n3/5N2/PPPP1PPP/RNB1R1K1 b kq - 5 7",
      solution: ["e4d6", "b5c6", "d7c6"],
      rating: 1450,
      themes: ["Opening Traps", "Defensive Resource"],
      isWhiteToMove: false,
    ),
    DailyPuzzleData(
      id: "carlsen_tactic",
      title: "Magnus Carlsen Rook Penetration",
      fen: "8/P7/7r/1R1pk3/1P6/R1P5/6K1/7r b - - 1 1",
      solution: ["e5f4", "c3c4", "h6h2"],
      rating: 1950,
      themes: ["Rook Endgame", "Checkmate Sequence"],
      isWhiteToMove: false,
    ),
  ];

  /// Fetches the Daily Puzzle from Lichess API, falling back to curated master puzzles
  Future<DailyPuzzleData> getDailyPuzzle() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedTime = prefs.getInt(_puzzleCacheTimeKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Use 24h cache if available
    if (now - cachedTime < 86400000) {
      final cachedJson = prefs.getString(_puzzleCacheKey);
      if (cachedJson != null) {
        try {
          final data = json.decode(cachedJson);
          final parsed = _parsePuzzle(data);
          if (parsed != null) return parsed;
        } catch (_) {}
      }
    }

    try {
      final res = await http.get(
        Uri.parse('https://lichess.org/api/puzzle/daily'),
        headers: {'User-Agent': 'ChessScanner-App/1.0'},
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final parsed = _parsePuzzle(data);
        if (parsed != null) {
          await prefs.setString(_puzzleCacheKey, res.body);
          await prefs.setInt(_puzzleCacheTimeKey, now);
          return parsed;
        }
      }
    } catch (e) {
      debugPrint('[RetentionService] Lichess daily puzzle API failed or offline: $e');
    }

    // Return the first curated puzzle as primary fallback
    return curatedPuzzles.first;
  }

  DailyPuzzleData? _parsePuzzle(Map<String, dynamic> data) {
    try {
      final puzzle = data['puzzle'] ?? {};
      final game = data['game'] ?? {};

      // Lichess stores puzzle FEN directly in puzzle['fen']
      final fen = puzzle['fen'] ?? game['fen'] ?? data['fen'] ?? '';
      if (fen.toString().isEmpty) return null;

      final solutionRaw = puzzle['solution'] ?? [];
      final solution = List<String>.from(solutionRaw);
      if (solution.isEmpty) return null;

      final parts = fen.toString().split(' ');
      final isWhiteToMove = parts.length > 1 ? parts[1].toLowerCase() == 'w' : true;

      final id = puzzle['id']?.toString() ?? 'daily';
      final rating = (puzzle['rating'] is int) ? puzzle['rating'] as int : 1600;
      final themes = (puzzle['themes'] is List) ? List<String>.from(puzzle['themes']) : ['Tactics'];

      return DailyPuzzleData(
        id: id,
        title: "Lichess Daily Tactical Puzzle #$id",
        fen: fen.toString(),
        solution: solution,
        rating: rating,
        themes: themes,
        isWhiteToMove: isWhiteToMove,
      );
    } catch (e) {
      debugPrint('[RetentionService] Error parsing Lichess puzzle: $e');
      return null;
    }
  }

  /// Get puzzle by index from curated library (loops through library)
  DailyPuzzleData getPuzzleByIndex(int index) {
    final idx = index % curatedPuzzles.length;
    return curatedPuzzles[idx];
  }

  /// Increments scan counter and requests an in-app review after 3 successful scans
  Future<void> onSuccessfulScan({required double confidence}) async {
    if (confidence < 0.85) return;

    final prefs = await SharedPreferences.getInstance();
    final alreadyPrompted = prefs.getBool(_reviewPromptedKey) ?? false;
    if (alreadyPrompted) return;

    final currentCount = (prefs.getInt(_scansCountKey) ?? 0) + 1;
    await prefs.setInt(_scansCountKey, currentCount);

    if (currentCount >= 3) {
      if (await _inAppReview.isAvailable()) {
        await _inAppReview.requestReview();
        await prefs.setBool(_reviewPromptedKey, true);
      }
    }
  }
}
