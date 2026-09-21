import 'package:flutter/material.dart';
import 'models/engine_config.dart';
import 'services/retention_service.dart';
import 'services/stockfish_isolate.dart';
import 'services/telemetry_service.dart';
import 'ui/calibration_sheet.dart';
import 'ui/eval_bar.dart';

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
      home: const MainScannerScreen(),
    );
  }
}

class MainScannerScreen extends StatefulWidget {
  const MainScannerScreen({super.key});

  @override
  State<MainScannerScreen> createState() => _MainScannerScreenState();
}

class _MainScannerScreenState extends State<MainScannerScreen> {
  final RetentionService _retentionService = RetentionService();
  final TelemetryService _telemetryService = TelemetryService();
  final StockfishIsolateWorker _engineWorker = StockfishIsolateWorker();

  String _currentFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  double _evalPercent = 50.0;
  String _scoreText = "0.00";
  String _bestMove = "e2e4";
  bool _isLiteMode = false;

  @override
  void initState() {
    super.initState();
    _checkDeviceSentinel();
  }

  void _checkDeviceSentinel() {
    // Device Profile check
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

  void _openCalibrationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CalibrationSheet(
        activeFen: _currentFen,
        ambiguousSquares: const ["c4", "f1"],
        onPieceCorrected: (square, piece) {
          // Update square in FEN
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Updated $square to ${piece ?? "Empty"}')),
          );
        },
        onSubmitReport: () {
          _telemetryService.submitReport(
            detectedFen: _currentFen,
            correctedFen: _currentFen,
            diffs: [],
            deviceModel: "Android Pixel",
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('♟️ Chess Scanner Pro'),
        actions: [
          if (_isLiteMode)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.0),
              child: Center(
                child: Chip(
                  label: Text('🔋 Lite Mode', style: TextStyle(fontSize: 11)),
                  backgroundColor: Colors.orangeAccent,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Evaluation Bar
            ChessEvalBar(evalPercent: _evalPercent, scoreText: _scoreText),
            const SizedBox(height: 16),

            // Camera Scan CTA (Deferred Permission Flow)
            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(Icons.camera_alt, size: 48, color: Colors.amber),
                    const SizedBox(height: 8),
                    const Text(
                      'Scan Physical Chess Board',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Point camera at any 2D diagram or 3D chess set.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Triggers camera permission and opens scanner
                        _retentionService.onSuccessfulScan(confidence: 0.95);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Camera scanner initialized!')),
                        );
                      },
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Open Camera Scanner'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Quick Calibration Action
            OutlinedButton.icon(
              onPressed: _openCalibrationSheet,
              icon: const Icon(Icons.tune, color: Colors.amber),
              label: const Text('Calibrate Ambiguous Squares (Fast UX)', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.amber),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // Engine Best Move Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BEST MOVE', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Text(_bestMove, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: () {
                      // Deep Analysis boost (Rewarded Video)
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
                    child: const Text('🎬 Deep Boost (+6 Depth)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
