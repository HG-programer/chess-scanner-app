import 'dart:convert';
import 'package:http/http.dart' as http;

class SquareDiffItem {
  final String square;
  final String? detected;
  final String? corrected;
  final double confidence;

  SquareDiffItem({
    required this.square,
    this.detected,
    this.corrected,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'square': square,
        'detected': detected,
        'corrected': corrected,
        'confidence': confidence,
      };
}

class TelemetryService {
  static const String _endpoint = 'https://api.yourbackend.com/reports'; // Replace with Firebase or endpoint

  /// Submits an anonymous misidentified board report for dataset retraining
  Future<bool> submitReport({
    required String detectedFen,
    required String correctedFen,
    required List<SquareDiffItem> diffs,
    required String deviceModel,
    required int batteryLevel,
    required bool isLiteMode,
    required String estimatedLighting,
    required String boardType,
    String appVersion = '1.0.0',
  }) async {
    final reportPayload = {
      'report_id': 'rep_${DateTime.now().millisecondsSinceEpoch}',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'app_version': appVersion,
      'device': {
        'model': deviceModel,
        'battery_level': batteryLevel,
        'is_lite_mode': isLiteMode,
      },
      'environment': {
        'estimated_lighting': estimatedLighting,
        'board_type': boardType,
      },
      'scan_data': {
        'detected_fen': detectedFen,
        'corrected_fen': correctedFen,
        'diff_squares': diffs.map((d) => d.toJson()).toList(),
        'diff_count': diffs.length,
      },
    };

    try {
      // In production, send to backend or Firebase Firestore/Storage
      // final response = await http.post(
      //   Uri.parse(_endpoint),
      //   headers: {'Content-Type': 'application/json'},
      //   body: json.encode(reportPayload),
      // );
      // return response.statusCode == 200 || response.statusCode == 201;
      print('Logged Telemetry Report: ${json.encode(reportPayload)}');
      return true;
    } catch (_) {
      return false;
    }
  }
}
