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
    elo: 1100,
    description: 'Club Apprentice & Tactician. Explains positional ideas, tactics, and blunders in plain English.',
    tier: EngineTier.free,
    defaultDepth: 4,
    icon: '🎓',
  );

  static const EngineProfile blitz = EngineProfile(
    id: 'blitz',
    name: 'Tactical Blitz Bot',
    tag: 'PRO ONLY',
    elo: 1450,
    description: 'Aggressive attacking engine tuned for rapid tactical combinations and counter-punches.',
    tier: EngineTier.pro,
    defaultDepth: 5,
    icon: '⚡',
  );

  static const EngineProfile stockfish19 = EngineProfile(
    id: 'stockfish19',
    name: 'Club Master AI',
    tag: 'PRO ONLY',
    elo: 1750,
    description: 'Deep positional search with king safety, pawn structure, and zero tactical blunders.',
    tier: EngineTier.pro,
    defaultDepth: 6,
    icon: '🏆',
  );

  static const EngineProfile cloud = EngineProfile(
    id: 'cloud',
    name: 'Grandmaster Cloud',
    tag: 'PRO ONLY',
    elo: 3000,
    description: 'Direct queries to Lichess Cloud opening book and 60+ depth Grandmaster evaluation.',
    tier: EngineTier.pro,
    defaultDepth: 60,
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
