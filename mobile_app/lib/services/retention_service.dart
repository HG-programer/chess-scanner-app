import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DailyPuzzleData {
  final String id;
  final String fen;
  final List<String> solution;
  final int rating;
  final List<String> themes;

  DailyPuzzleData({
    required this.id,
    required this.fen,
    required this.solution,
    required this.rating,
    required this.themes,
  });
}

class RetentionService {
  static const String _scansCountKey = 'successful_scans_count';
  static const String _reviewPromptedKey = 'review_prompted';
  static const String _puzzleCacheKey = 'cached_puzzle_json';
  static const String _puzzleCacheTimeKey = 'cached_puzzle_timestamp';

  final InAppReview _inAppReview = InAppReview.instance;

  /// Fetches the Daily Puzzle from Lichess API with 24-hour local caching
  Future<DailyPuzzleData> getDailyPuzzle() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedTime = prefs.getInt(_puzzleCacheTimeKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Use 24h cache if available
    if (now - cachedTime < 86400000) {
      final cachedJson = prefs.getString(_puzzleCacheKey);
      if (cachedJson != null) {
        final data = json.decode(cachedJson);
        return _parsePuzzle(data);
      }
    }

    try {
      final res = await http.get(
        Uri.parse('https://lichess.org/api/puzzle/daily'),
        headers: {'User-Agent': 'ChessScanner-App/1.0'},
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        await prefs.setString(_puzzleCacheKey, res.body);
        await prefs.setInt(_puzzleCacheTimeKey, now);
        return _parsePuzzle(data);
      }
    } catch (_) {}

    // Fallback offline tactical puzzle
    return DailyPuzzleData(
      id: "offline_opera",
      fen: "4kb1r/p2rqppp/5n2/1B2p1B1/4P3/1Q6/PPP2PPP/2KR4 w k - 0 14",
      solution: ["b5d7", "f6d7", "b3b8"],
      rating: 1600,
      themes: ["mateIn3", "tactics"],
    );
  }

  DailyPuzzleData _parsePuzzle(Map<String, dynamic> data) {
    final puzzle = data['puzzle'] ?? {};
    final game = data['game'] ?? {};
    final fen = (game['tree'] != null && game['tree'].isNotEmpty)
        ? game['tree'][0]['fen'] ?? ""
        : game['fen'] ?? "";

    return DailyPuzzleData(
      id: puzzle['id'] ?? "daily",
      fen: fen,
      solution: List<String>.from(puzzle['solution'] ?? []),
      rating: puzzle['rating'] ?? 1500,
      themes: List<String>.from(puzzle['themes'] ?? []),
    );
  }

  /// The Delight Review Trigger:
  /// Increments scan counter and requests an in-app review ONLY after 3 successful scans.
  Future<void> onSuccessfulScan({required double confidence}) async {
    if (confidence < 0.85) return; // Don't ask if scan required heavy manual editing

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
