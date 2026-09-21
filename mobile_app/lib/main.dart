import 'package:flutter/material.dart';
import 'models/engine_config.dart';
import 'services/retention_service.dart';
import 'services/stockfish_isolate.dart';
import 'services/telemetry_service.dart';
import 'ui/calibration_sheet.dart';
import 'ui/daily_puzzle_view.dart';
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
  final StockfishIsolateWorker _engineWorker = StockfishIsolateWorker();

  String _currentFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  double _evalPercent = 50.0;
  String _scoreText = "0.00";
  String _bestMove = "e2e4";
  bool _isLiteMode = false;
  int _depthBoost = 0;

  @override
  void initState() {
    super.initState();
    _checkDeviceSentinel();
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

  void _onMoveMade(String from, String to, String newFen) {
    setState(() {
      _currentFen = newFen;
      // In a real match, simulate AI responding with a new best move
      if (_bestMove == '$from$to') {
        _bestMove = "e7e5";
        _scoreText = "+0.25";
        _evalPercent = 52.5;
      } else {
        _bestMove = "g1f3";
        _scoreText = "+0.45";
        _evalPercent = 54.5;
      }
    });
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Animated Evaluation Bar
          ChessEvalBar(evalPercent: _evalPercent, scoreText: _scoreText),
          const SizedBox(height: 12),

          // 2. Interactive 8x8 Chessboard with Best-Move Arrow
          InteractiveChessboard(
            fen: _currentFen,
            bestMove: _bestMove,
            isWhiteOrientation: true,
            onMoveMade: _onMoveMade,
          ),
          const SizedBox(height: 14),

          // 3. Engine Best Move & Boost Bar
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
                  onPressed: () {
                    setState(() {
                      _depthBoost += 6;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('🎬 Rewarded Boost Active! Depth: ${14 + _depthBoost}')),
                    );
                  },
                  icon: const Icon(Icons.play_circle_fill, size: 18),
                  label: Text('Deep Boost (+${6 + _depthBoost})'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber[800],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. Camera Scan CTA (Deferred Permission Flow)
          Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Icon(Icons.camera_alt, size: 40, color: Colors.amber),
                  const SizedBox(height: 6),
                  const Text(
                    'Scan Physical Chess Board',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Point camera at any 2D diagram or physical 3D board.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      _retentionService.onSuccessfulScan(confidence: 0.95);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Camera scanner ready! Point at board.')),
                      );
                    },
                    icon: const Icon(Icons.photo_camera),
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
          ),
          const SizedBox(height: 12),

          // 5. Quick Calibration Sheet Trigger
          OutlinedButton.icon(
            onPressed: _openCalibrationSheet,
            icon: const Icon(Icons.tune, color: Colors.amber),
            label: const Text('Calibrate Ambiguous Squares (Fast UX)', style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.amber),
              padding: const EdgeInsets.symmetric(vertical: 10),
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
          if (_isLiteMode)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.0),
              child: Center(
                child: Chip(
                  label: Text('🔋 Lite Mode', style: TextStyle(fontSize: 10)),
                  backgroundColor: Colors.orangeAccent,
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
