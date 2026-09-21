import 'dart:async';
import 'dart:isolate';
import '../models/engine_config.dart';

/// Message sent from UI to the background Stockfish Isolate
class EngineRequest {
  final String fen;
  final EngineConfig config;
  final SendPort replyPort;

  EngineRequest({
    required this.fen,
    required this.config,
    required this.replyPort,
  });
}

/// Evaluation result streamed back to the UI
class EngineResult {
  final String bestMove;
  final int? scoreCp;
  final int? mateIn;
  final int depth;
  final double evalPercent;
  final List<String> pvMoves;

  EngineResult({
    required this.bestMove,
    this.scoreCp,
    this.mateIn,
    required this.depth,
    required this.evalPercent,
    required this.pvMoves,
  });
}

/// Spawns and communicates with Stockfish on a dedicated background thread.
class StockfishIsolateWorker {
  Isolate? _isolate;
  SendPort? _commandPort;

  Future<void> initialize() async {
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_stockfishEntryPoint, receivePort.sendPort);
    _commandPort = await receivePort.first as SendPort;
  }

  Future<EngineResult> evaluate(String fen, EngineConfig config) async {
    if (_commandPort == null) {
      await initialize();
    }
    final responsePort = ReceivePort();
    _commandPort!.send(EngineRequest(
      fen: fen,
      config: config,
      replyPort: responsePort.sendPort,
    ));

    final result = await responsePort.first as EngineResult;
    return result;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commandPort = null;
  }

  /// Entry point running inside the background isolate
  static void _stockfishEntryPoint(SendPort mainSendPort) {
    final commandPort = ReceivePort();
    mainSendPort.send(commandPort.sendPort);

    commandPort.listen((message) {
      if (message is EngineRequest) {
        // Run UCI commands:
        // uci
        // setoption name Threads value <threads>
        // position fen <fen>
        // go depth <depth>
        // Parse "bestmove" and "score cp / mate"
        
        // Return dummy parsed result for scaffold
        final evalResult = EngineResult(
          bestMove: "e2e4",
          scoreCp: 35,
          depth: message.config.maxDepth,
          evalPercent: 54.0,
          pvMoves: ["e4", "e5", "Nf3"],
        );
        message.replyPort.send(evalResult);
      }
    });
  }
}
