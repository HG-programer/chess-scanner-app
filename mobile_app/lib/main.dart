import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess_logic;

import 'models/engine_config.dart';
import 'models/engine_profile.dart';
import 'services/chess_engine_service.dart';
import 'services/retention_service.dart';
import 'services/telemetry_service.dart';
import 'ui/calibration_sheet.dart';
import 'ui/camera_scanner_screen.dart';
import 'ui/daily_puzzle_view.dart';
import 'ui/engine_selector_sheet.dart';
import 'ui/eval_bar.dart';
import 'ui/interactive_chessboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      _evalPercent = result.evalPercent;
      _scoreText = result.evalText;
      _coachAdvice = result.coachAdvice;
    });
  }

  void _onMoveMade(String from, String to, String newFen) {
    _fenHistory.add(_currentFen);
    _moveCount++;

    setState(() {
      _currentFen = newFen;
    });

    _calculateEngineEvaluation(newFen);

    // AI Auto-Response in "Play vs AI" mode
    if (_isPlayVsAi && newFen.contains(' b ')) {
      setState(() => _isAiThinking = true);

      Timer(const Duration(milliseconds: 550), () {
        if (!mounted) return;
        _makeAiMove(newFen);
      });
    }
  }

  Future<void> _makeAiMove(String currentFen) async {
    try {
      final result = await _engineService.analyzePosition(
        currentFen,
        engineId: _currentEngine.id,
        maxDepth: _currentEngine.defaultDepth,
      );

      if (result.bestMove.length >= 4) {
        final from = result.bestMove.substring(0, 2);
        final to = result.bestMove.substring(2, 4);

        final chess = chess_logic.Chess.fromFEN(currentFen);
        if (chess.move({'from': from, 'to': to, 'promotion': 'q'})) {
          setState(() {
            _fenHistory.add(_currentFen);
            _currentFen = chess.fen;
            _isAiThinking = false;
            _moveCount++;
          });

          _calculateEngineEvaluation(chess.fen);
          return;
        }
      }
    } catch (_) {}

    setState(() => _isAiThinking = false);
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
    setState(() {
      _fenHistory.clear();
      _currentFen = _startFen;
      _moveCount = 0;
      _isAiThinking = false;
      _bestMove = "e2e4";
      _evalPercent = 50.0;
      _scoreText = "0.00";
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Board reset to standard starting position.')),
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
        isPremium: _isPremium,
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
        onWatchAdForTempUnlock: () {
          setState(() {
            _isPremium = true; // Temporary 30m unlock
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.amber,
              content: Text('🎬 Rewarded Ad Watched! Pro Engines unlocked for 30 minutes!'),
            ),
          );
        },
      ),
    );
  }

  void _openPaywallSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF181818),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.workspace_premium, color: Colors.amber, size: 26),
                SizedBox(width: 8),
                Text('Upgrade to Chess Scanner Pro', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Unlock all 3 superhuman engines (Stockfish 19 NNUE 3500 ELO, Blitz, and Lichess Cloud) plus unlimited camera scans.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Regional Pricing Cards
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
                setState(() => _isPremium = true);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(backgroundColor: Colors.amber, content: Text('🎬 Ad Completed! Pro Pass active for 30 min.')),
                );
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

  Widget _buildScannerTab() {
    final coachAdvice = _coachAdvice;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Animated Evaluation Bar
          ChessEvalBar(evalPercent: _evalPercent, scoreText: _scoreText),
          const SizedBox(height: 10),

          // 2. Active Engine Selector Card
          InkWell(
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
                                _currentEngine.isPro ? 'PRO' : 'BASE FREE',
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
          ),
          const SizedBox(height: 10),

          // 3. Coach Tactical Advice Card (shown for Base Coach Engine)
          if (_currentEngine.id == 'coach')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
              ),
              child: Text(
                coachAdvice,
                style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12),
              ),
            ),

          // 4. Interactive 8x8 Chessboard with Piece Movement & Best Move Arrow
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

          // 5. Engine Best Move & Boost Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF333333)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('BEST MOVE (AI)', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    Text(
                      _bestMove.toUpperCase(),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _openEngineSelector,
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('Change Engine'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF333333),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 6. Camera Scan CTA (Opens real CameraScannerScreen)
          Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Icon(Icons.camera_alt, size: 38, color: Colors.amber),
                  const SizedBox(height: 6),
                  const Text(
                    'Scan Physical Chess Board',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Point camera at physical boards, books, screens, or test sample diagrams.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _openCameraScanner,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Open Camera Scanner'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 7. Quick Calibration Sheet Trigger
          OutlinedButton.icon(
            onPressed: _openCalibrationSheet,
            icon: const Icon(Icons.tune, color: Colors.amber, size: 18),
            label: const Text('Calibrate Ambiguous Squares (Fast UX)', style: TextStyle(color: Colors.white, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.amber),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
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
                  label: Text(_isPremium ? '💎 PRO' : '⭐ FREE', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  backgroundColor: _isPremium ? Colors.teal : Colors.amber[900],
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
