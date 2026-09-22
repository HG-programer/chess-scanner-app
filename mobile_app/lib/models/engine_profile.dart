enum EngineTier {
  free,
  pro,
}

class EngineProfile {
  final String id;
  final String name;
  final String tag;
  final int elo;
  final String description;
  final EngineTier tier;
  final int defaultDepth;
  final String icon;

  const EngineProfile({
    required this.id,
    required this.name,
    required this.tag,
    required this.elo,
    required this.description,
    required this.tier,
    required this.defaultDepth,
    required this.icon,
  });

  bool get isPro => tier == EngineTier.pro;

  static const EngineProfile coach = EngineProfile(
    id: 'coach',
    name: 'Stockfish Coach',
    tag: 'BASE FREE',
    elo: 1500,
    description: 'Club Master & Tactician. Explains positional ideas, tactics, and blunders in plain English.',
    tier: EngineTier.free,
    defaultDepth: 8,
    icon: '🎓',
  );

  static const EngineProfile stockfish19 = EngineProfile(
    id: 'stockfish19',
    name: 'Stockfish NNUE Grandmaster',
    tag: 'PRO ONLY',
    elo: 3500,
    description: 'Superhuman NNUE neural heuristics. Unbeatable depth 20+ multi-pv tournament analysis.',
    tier: EngineTier.pro,
    defaultDepth: 22,
    icon: '🏆',
  );

  static const EngineProfile blitz = EngineProfile(
    id: 'blitz',
    name: 'Stockfish Blitz',
    tag: 'PRO ONLY',
    elo: 2200,
    description: 'Lightning-fast 100ms move generator tuned for speed and practical blitz tactics.',
    tier: EngineTier.pro,
    defaultDepth: 12,
    icon: '⚡',
  );

  static const EngineProfile cloud = EngineProfile(
    id: 'cloud',
    name: 'Lichess Cloud Master',
    tag: 'PRO ONLY',
    elo: 3800,
    description: 'Instant grandmaster opening book and 10-million game cloud database evaluation.',
    tier: EngineTier.pro,
    defaultDepth: 40,
    icon: '☁️',
  );

  static const List<EngineProfile> all = [coach, stockfish19, blitz, cloud];

  /// Generates contextual coaching advice based on move and evaluation
  static String getCoachAdvice(String bestMove, double evalPercent, int moveCount) {
    if (moveCount <= 2) {
      return "💡 Opening Stage: Control the 4 central squares (e4, d4, e5, d5) and develop minor pieces.";
    }
    if (evalPercent > 60.0) {
      return "💡 White holds a strong advantage. Look for active piece infiltration or king-side attack.";
    } else if (evalPercent < 40.0) {
      return "⚠️ Black has counter-play. Tighten king defense and avoid rushing pawn pushes.";
    } else {
      return "⚖️ Balanced position. Focus on piece coordination, controlling open files, and rooks to center.";
    }
  }
}
