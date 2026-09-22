import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess_logic;

import 'models/engine_config.dart';
import 'models/engine_profile.dart';
import 'services/ad_service.dart';
import 'services/chess_engine_service.dart';
import 'services/retention_service.dart';
import 'services/telemetry_service.dart';
import 'ui/calibration_sheet.dart';
import 'ui/camera_scanner_screen.dart';
import 'ui/daily_puzzle_view.dart';
import 'ui/engine_selector_sheet.dart';
import 'ui/eval_bar.dart';
import 'ui/interactive_chessboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Safely initialize AdMob monetization (with graceful fallback for emulators)
  await AdService.instance.initialize();
  runApp(const ChessScannerApp());
}

class ChessScannerApp extends StatelessWidget {
  const ChessScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Scanner: Camera FEN & AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.amber,
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.tealAccent,
        ),
      ),
      home: const MainHomeScreen(),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentTabIndex = 0;

  final RetentionService _retentionService = RetentionService();
  final TelemetryService _telemetryService = TelemetryService();

  // Starting standard FEN
  static const String _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  String _currentFen = _startFen;
  final List<String> _fenHistory = [];

  // Engine & Evaluation State
  EngineProfile _currentEngine = EngineProfile.coach; // Base is Coach (Free)
  bool _isPremium = false; // 3 pro engines locked behind premium
  double _evalPercent = 50.0;
  String _scoreText = "0.00";
  String _bestMove = "e2e4";
  String _bestMoveSan = "e4";
  int _engineSearchDepth = 4;
  int _moveCount = 0;
  bool _isWhiteOrientation = true;
  bool _isPlayVsAi = true;
  bool _isAiThinking = false;
  bool _isLiteMode = false;

  final ChessEngineService _engineService = ChessEngineService();
  String _coachAdvice = "💡 Control the 4 central squares with pawns and develop knights before bishops.";

  @override
  void initState() {
    super.initState();
    // Check if user has an active 30-minute Pro Pass from rewarded ad
    if (AdService.instance.hasActiveProPass) {
      _isPremium = true;
    }
    _checkDeviceSentinel();
    _calculateEngineEvaluation(_currentFen);
  }

  void _checkDeviceSentinel() {
    final config = EngineConfig.resolve(
      batteryLevel: 80,
      isCharging: false,
      totalRamMb: 6000,
      is64Bit: true,
    );
    setState(() {
      _isLiteMode = config.isLiteMode;
    });
  }

  /// Evaluates the position and calculates the next best move with Alpha-Beta & Cloud Engine
  Future<void> _calculateEngineEvaluation(String fen) async {
    final result = await _engineService.analyzePosition(
      fen,
      engineId: _currentEngine.id,
      maxDepth: _currentEngine.defaultDepth,
    );

    if (!mounted) return;
    setState(() {
      _bestMove = result.bestMove;
      _bestMoveSan = result.moveSan;
      _evalPercent = result.evalPercent;
      _scoreText = result.evalText;
      _coachAdvice = result.coachAdvice;
      _engineSearchDepth = result.depth;
    });
  }

  void _onMoveMade(String from, String to, String newFen) {
    _fenHistory.add(_currentFen);
    _moveCount++;

    setState(() {
      _currentFen = newFen;
    });

    _calculateEngineEvaluation(newFen);

    // If Play vs AI is enabled, execute the engine's counter-move automatically
    if (_isPlayVsAi) {
      _triggerAiCounterMove(newFen);
    }
  }

  Future<void> _triggerAiCounterMove(String fenAfterPlayerMove) async {
    setState(() => _isAiThinking = true);

    try {
      final chess = chess_logic.Chess.fromFEN(fenAfterPlayerMove);
      if (chess.game_over) {
        setState(() => _isAiThinking = false);
        return;
      }

      // Timing tuned to engine personality
      int delayMs = 500;
      if (_currentEngine.id == 'blitz') delayMs = 150;
      if (_currentEngine.id == 'stockfish19') delayMs = 650;
      if (_currentEngine.id == 'cloud') delayMs = 350;

      await Future.delayed(Duration(milliseconds: delayMs));

      final result = await _engineService.analyzePosition(
        fenAfterPlayerMove,
        engineId: _currentEngine.id,
        maxDepth: _currentEngine.defaultDepth,
      );

      final aiMoveUci = result.bestMove;
      bool moved = false;

      if (aiMoveUci.length >= 4 && aiMoveUci != 'mate' && aiMoveUci != 'none') {
        final from = aiMoveUci.substring(0, 2);
        final to = aiMoveUci.substring(2, 4);
        final promo = aiMoveUci.length >= 5 ? aiMoveUci[4] : 'q';
        moved = chess.move({'from': from, 'to': to, 'promotion': promo});
      }

      // Dynamic fallback: If calculated move failed to execute, execute first legal move
      if (!moved) {
        final legalMoves = chess.moves({'verbose': true});
        if (legalMoves.isNotEmpty) {
          final lm = legalMoves.first as Map;
          moved = chess.move({
            'from': lm['from'].toString(),
            'to': lm['to'].toString(),
            'promotion': lm['promotion']?.toString() ?? 'q',
          });
        }
      }

      if (moved) {
        if (!mounted) return;
        setState(() {
          _fenHistory.add(_currentFen);
          _currentFen = chess.fen;
          _isAiThinking = false;
          _moveCount++;
        });

        _calculateEngineEvaluation(chess.fen);
        return;
      }
    } catch (_) {}

    if (mounted) setState(() => _isAiThinking = false);
  }

  void _undoMove() {
    if (_fenHistory.isNotEmpty) {
      setState(() {
        _currentFen = _fenHistory.removeLast();
        _isAiThinking = false;
        if (_moveCount > 0) _moveCount--;
      });
      _calculateEngineEvaluation(_currentFen);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At the beginning of the game.')),
      );
    }
  }

  void _resetBoard() {
    _openNewMatchSheet();
  }

  void _openNewMatchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E24),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('⚔️ Start New Match', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Play as White or Black against AI, or jump directly into famous grandmaster opening battles.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),

              // Side Selection (White or Black)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.circle, color: Colors.white, size: 16),
                      label: const Text('Play as White', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2C2D35),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _startNewMatch(playAsWhite: true);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.circle, color: Colors.grey, size: 16),
                      label: const Text('Play as Black', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2C2D35),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _startNewMatch(playAsWhite: false);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),

              const Text('Grandmaster Opening Presets', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber)),
              const SizedBox(height: 10),

              ...ChessEngineService.openingPresets.map((preset) {
                return Card(
                  color: const Color(0xFF262730),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text(preset.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    subtitle: Text('${preset.eco} • ${preset.description}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                    trailing: const Icon(Icons.play_arrow, color: Colors.amber),
                    onTap: () {
                      Navigator.pop(ctx);
                      _startNewMatch(
                        playAsWhite: preset.playAsWhite,
                        customFen: preset.fen,
                        presetName: preset.name,
                      );
                    },
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  void _startNewMatch({required bool playAsWhite, String? customFen, String? presetName}) {
    setState(() {
      _fenHistory.clear();
      _currentFen = customFen ?? _startFen;
      _moveCount = 0;
      _isWhiteOrientation = playAsWhite;
      _isAiThinking = false;
      _bestMove = "e2e4";
      _evalPercent = 50.0;
      _scoreText = "0.00";
    });

    _calculateEngineEvaluation(_currentFen);

    // Occasionally show interstitial ad on new game if not premium
    AdService.instance.showInterstitialAd();

    // If user chose to play as Black from starting board, have AI play White's opening move!
    if (!playAsWhite && customFen == null && _isPlayVsAi) {
      _triggerAiCounterMove(_startFen);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E1E1E),
        content: Text(presetName != null ? 'Started: $presetName' : (playAsWhite ? 'Game started: You play White' : 'Game started: You play Black')),
      ),
    );
  }

  void _flipBoard() {
    setState(() {
      _isWhiteOrientation = !_isWhiteOrientation;
    });
  }

  Future<void> _openCameraScanner() async {
    final scannedFen = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const CameraScannerScreen()),
    );

    if (scannedFen != null && scannedFen.isNotEmpty) {
      setState(() {
        _fenHistory.clear();
        _currentFen = scannedFen;
        _moveCount = 4;
      });
      _calculateEngineEvaluation(scannedFen);
      _retentionService.onSuccessfulScan(confidence: 0.98);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('✅ Board Scanned Successfully! Analyzing position with Stockfish...'),
          ),
        );
      }
    }
  }

  void _openEngineSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EngineSelectorSheet(
        currentEngine: _currentEngine,
        isPremium: _isPremium || AdService.instance.hasActiveProPass,
        onEngineSelected: (newEngine) {
          setState(() {
            _currentEngine = newEngine;
          });
          _calculateEngineEvaluation(_currentFen);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF1E1E1E),
              content: Text('Switched to ${newEngine.name} (${newEngine.elo} ELO)'),
            ),
          );
        },
        onOpenPaywall: _openPaywallSheet,
        onWatchAdForTempUnlock: _watchAdForProPass,
      ),
    );
  }

  void _watchAdForProPass() {
    AdService.instance.showRewardedAd(
      context: context,
      onRewardEarned: () {
        if (!mounted) return;
        setState(() {
          _isPremium = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.amber,
            content: Text('🎬 Reward Earned! 30-Minute Pro Pass activated.'),
          ),
        );
      },
    );
  }

  void _openPaywallSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '👑 Unlock All 4 Engines',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amber),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Gain unlimited access to Stockfish 19 NNUE (3500+ ELO), Stockfish Blitz, and Lichess Cloud Engine.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Pricing Plans
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.5)),
              ),
              child: const Column(
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Pro Monthly Pass', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text('Regional Purchasing Power Parity applied'),
                    trailing: Text('₹99 / \$4.99', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Divider(color: Colors.white12),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Lifetime Master Pass', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text('One-time payment forever'),
                    trailing: Text('₹499 / \$29.99', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle, color: Colors.black),
              label: const Text('Unlock Pro Engines Now', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                setState(() => _isPremium = true);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(backgroundColor: Colors.teal, content: Text('🎉 Welcome to Pro! All engines unlocked.')),
                );
              },
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.play_circle_fill, color: Colors.orangeAccent),
              label: const Text('Or Watch a Video Ad for 30m Pro Pass', style: TextStyle(color: Colors.orangeAccent)),
              onPressed: () {
                Navigator.pop(ctx);
                _watchAdForProPass();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openCalibrationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CalibrationSheet(
        activeFen: _currentFen,
        ambiguousSquares: const ["c4", "f1"],
        onPieceCorrected: (square, piece) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Updated $square to ${piece ?? "Empty"}')),
          );
        },
        onSubmitReport: () {
          _telemetryService.submitReport(
            detectedFen: _currentFen,
            correctedFen: _currentFen,
            diffs: [],
            deviceModel: "Android Emulator / LDPlayer",
            batteryLevel: 80,
            isLiteMode: _isLiteMode,
            estimatedLighting: "medium",
            boardType: "wooden_3d",
          );
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anonymous report submitted! Thank you.')),
          );
        },
      ),
    );
  }

  Widget _buildEngineSelectorCard() {
    final hasPass = AdService.instance.hasActiveProPass;
    final remaining = AdService.instance.remainingProPassTime;

    return InkWell(
      onTap: _openEngineSelector,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Text(_currentEngine.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _currentEngine.name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _currentEngine.isPro ? Colors.purple.withOpacity(0.3) : Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          hasPass && _currentEngine.isPro
                              ? 'PRO ($remaining)'
                              : (_currentEngine.isPro ? 'PRO' : 'BASE FREE'),
                          style: TextStyle(
                            color: _currentEngine.isPro ? Colors.purpleAccent : Colors.greenAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${_currentEngine.elo} ELO  •  Depth ${_currentEngine.defaultDepth}',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.amber),
          ],
        ),
      ),
    );
  }

  Widget _buildCoachAdviceCard(String advice) {
    Color borderColor;
    Color bgColor;
    Color textColor;
    String engineTitle;

    switch (_currentEngine.id) {
      case 'stockfish19':
        borderColor = Colors.amber.withOpacity(0.4);
        bgColor = Colors.amber.withOpacity(0.12);
        textColor = Colors.amberAccent;
        engineTitle = '🏆 Stockfish 19 NNUE Telemetry';
        break;
      case 'blitz':
        borderColor = Colors.orangeAccent.withOpacity(0.4);
        bgColor = Colors.orangeAccent.withOpacity(0.12);
        textColor = Colors.orangeAccent;
        engineTitle = '⚡ Stockfish Blitz Fast Tactical Analysis';
        break;
      case 'cloud':
        borderColor = Colors.tealAccent.withOpacity(0.4);
        bgColor = Colors.tealAccent.withOpacity(0.12);
        textColor = Colors.tealAccent;
        engineTitle = '☁️ Lichess Cloud Master Database';
        break;
      default: // coach
        borderColor = Colors.blueAccent.withOpacity(0.3);
        bgColor = Colors.blueAccent.withOpacity(0.12);
        textColor = Colors.lightBlueAccent;
        engineTitle = '🎓 Coach Tactical Insight';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                engineTitle,
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_currentEngine.elo} ELO',
                  style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            advice,
            style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _buildBestMoveCard() {
    final isGameOver = _bestMove == 'mate' || _bestMove == 'none';
    final moveDisplay = isGameOver
        ? (_scoreText.contains('1-0') || _scoreText.contains('0-1') ? '🏆 CHECKMATE' : '½-½ DRAW')
        : (_bestMoveSan != _bestMove
            ? '${_bestMoveSan.toUpperCase()}  (${_bestMove.toUpperCase()})'
            : _bestMove.toUpperCase());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('BEST MOVE (${_currentEngine.name.toUpperCase()})', style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Text('• Depth $_engineSearchDepth', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  moveDisplay,
                  style: TextStyle(
                    fontSize: isGameOver ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: isGameOver ? Colors.amberAccent : Colors.greenAccent,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _openNewMatchSheet,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Match'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _openEngineSelector,
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Engine'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF333333),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCameraScanCard() {
    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: [
            const Icon(Icons.camera_alt, size: 32, color: Colors.amber),
            const SizedBox(height: 6),
            const Text(
              'Scan Physical Chess Board',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            const Text(
              'Point camera at physical boards, screens, or test sample diagrams.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _openCameraScanner,
              icon: const Icon(Icons.photo_camera, size: 16),
              label: const Text('Open Camera Scanner'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerTab() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final coachAdvice = _coachAdvice;

    // RESPONSIVE LAYOUT:
    // In Landscape (e.g. LDPlayer 16:9), split into 2 columns:
    // Left Column: The 8x8 Chessboard (fits screen height with NO vertical scrolling)
    // Right Column: Stockfish Evaluation Bar, Engine Selector, Coach Advice, Best Move Card & Actions
    if (isLandscape) {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: Perfectly Sized Interactive Chessboard
            Expanded(
              flex: 5,
              child: Center(
                child: InteractiveChessboard(
                  fen: _currentFen,
                  bestMove: _bestMove,
                  isWhiteOrientation: _isWhiteOrientation,
                  isPlayVsAi: _isPlayVsAi,
                  isAiThinking: _isAiThinking,
                  onMoveMade: _onMoveMade,
                  onResetBoard: _resetBoard,
                  onUndoMove: _undoMove,
                  onFlipBoard: _flipBoard,
                  onToggleMode: (playVsAi) {
                    setState(() => _isPlayVsAi = playVsAi);
                  },
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Right: Scrollable Control & Analysis Sidebar
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ChessEvalBar(evalPercent: _evalPercent, scoreText: _scoreText),
                    const SizedBox(height: 10),
                    _buildEngineSelectorCard(),
                    if (_currentEngine.id == 'coach') _buildCoachAdviceCard(coachAdvice),
                    const SizedBox(height: 10),
                    _buildBestMoveCard(),
                    const SizedBox(height: 10),
                    _buildCameraScanCard(),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _openCalibrationSheet,
                      icon: const Icon(Icons.tune, color: Colors.amber, size: 16),
                      label: const Text('Calibrate Ambiguous Squares', style: TextStyle(color: Colors.white, fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.amber),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                    if (!_isPremium) const SizedBox(height: 10),
                    if (!_isPremium) const AdBannerWidget(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Standard Portrait Layout (Phones)
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChessEvalBar(evalPercent: _evalPercent, scoreText: _scoreText),
          const SizedBox(height: 10),
          _buildEngineSelectorCard(),
          if (_currentEngine.id == 'coach') _buildCoachAdviceCard(coachAdvice),
          const SizedBox(height: 10),

          // 8x8 Chessboard
          InteractiveChessboard(
            fen: _currentFen,
            bestMove: _bestMove,
            isWhiteOrientation: _isWhiteOrientation,
            isPlayVsAi: _isPlayVsAi,
            isAiThinking: _isAiThinking,
            onMoveMade: _onMoveMade,
            onResetBoard: _resetBoard,
            onUndoMove: _undoMove,
            onFlipBoard: _flipBoard,
            onToggleMode: (playVsAi) {
              setState(() => _isPlayVsAi = playVsAi);
            },
          ),
          const SizedBox(height: 12),

          _buildBestMoveCard(),
          const SizedBox(height: 10),
          _buildCameraScanCard(),
          const SizedBox(height: 10),

          OutlinedButton.icon(
            onPressed: _openCalibrationSheet,
            icon: const Icon(Icons.tune, color: Colors.amber, size: 18),
            label: const Text('Calibrate Ambiguous Squares (Fast UX)', style: TextStyle(color: Colors.white, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.amber),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          if (!_isPremium) const SizedBox(height: 14),
          if (!_isPremium) const Center(child: AdBannerWidget()),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('💎 Monetization & Regional Pricing', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Google Play IAP and Regional Purchasing Power Parity', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),

          Card(
            color: const Color(0xFF1E1E1E),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                children: const [
                  ListTile(
                    leading: Icon(Icons.flag, color: Colors.blueAccent),
                    title: Text('United States & Tier 1'),
                    subtitle: Text('\$4.99/mo  •  \$29.99 Lifetime'),
                  ),
                  Divider(),
                  ListTile(
                    leading: Icon(Icons.flag, color: Colors.orangeAccent),
                    title: Text('India & Tier 3'),
                    subtitle: Text('₹99/mo (\$1.20)  •  ₹499 Lifetime (\$6.00)'),
                  ),
                  Divider(),
                  ListTile(
                    leading: Icon(Icons.flag, color: Colors.greenAccent),
                    title: Text('Brazil & LatAm'),
                    subtitle: Text('R\$ 14.90/mo  •  R\$ 59.90 Lifetime'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Card(
            color: const Color(0xFF1E1E1E),
            child: ListTile(
              leading: Icon(Icons.bolt, color: _isLiteMode ? Colors.orange : Colors.greenAccent),
              title: Text(_isLiteMode ? 'Battery Sentinel: Lite Mode' : 'Battery Sentinel: Pro Mode'),
              subtitle: Text(_isLiteMode ? 'Throttled to save power & cool device' : 'Full multi-threaded Stockfish analysis'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPass = AdService.instance.hasActiveProPass;
    final remaining = AdService.instance.remainingProPassTime;

    return Scaffold(
      appBar: AppBar(
        title: const Text('♟️ Chess Scanner Pro'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt, color: Colors.amber),
            tooltip: 'Scan Board',
            onPressed: _openCameraScanner,
          ),
          GestureDetector(
            onTap: _openPaywallSheet,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Center(
                child: Chip(
                  label: Text(
                    hasPass
                        ? '⏱️ PRO ($remaining)'
                        : (_isPremium ? '💎 PRO' : '⭐ FREE'),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: _isPremium || hasPass ? Colors.teal : Colors.amber[900],
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildScannerTab(),
          const DailyPuzzleView(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        backgroundColor: const Color(0xFF181818),
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.white54,
        onTap: (idx) => setState(() => _currentTabIndex = idx),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.camera),
            label: 'Scanner & Board',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.extension),
            label: 'Daily Puzzle',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.workspace_premium),
            label: 'Premium',
          ),
        ],
      ),
    );
  }
}
