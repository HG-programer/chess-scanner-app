/// Adaptive Device Sentinel Configuration for Chess Scanner.
/// Dynamically toggles between Lite Mode and Pro Mode based on hardware specs,
/// battery level, and thermal limits to prevent ANRs and overheating.

class EngineConfig {
  final int maxDepth;
  final int threads;
  final bool useNNUE;
  final Duration timeout;
  final bool isLiteMode;

  const EngineConfig({
    required this.maxDepth,
    required this.threads,
    required this.useNNUE,
    required this.timeout,
    required this.isLiteMode,
  });

  /// Factory resolving the optimal profile based on current hardware metrics.
  factory EngineConfig.resolve({
    required int batteryLevel,
    required bool isCharging,
    required int totalRamMb,
    required bool is64Bit,
  }) {
    // Low Battery / Thermal Safeguard:
    // If battery <= 15% (unplugged) or device has <3GB RAM or 32-bit architecture:
    // Switch to Lite Mode (Stockfish Classic, Depth 11, 1 thread, 800ms cap)
    final bool triggerLite = (!isCharging && batteryLevel <= 15) ||
        totalRamMb < 3000 ||
        !is64Bit;

    if (triggerLite) {
      return const EngineConfig(
        maxDepth: 11,
        threads: 1,
        useNNUE: false,
        timeout: Duration(milliseconds: 800),
        isLiteMode: true,
      );
    }

    // Default Pro Mode: Multi-threaded Stockfish NNUE at Depth 18
    return const EngineConfig(
      maxDepth: 18,
      threads: 2,
      useNNUE: true,
      timeout: Duration(milliseconds: 2500),
      isLiteMode: false,
    );
  }
}
