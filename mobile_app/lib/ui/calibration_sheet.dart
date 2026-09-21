import 'package:flutter/material.dart';

/// Fast-response calibration widget for correcting misidentified squares in < 1 second.
class CalibrationSheet extends StatefulWidget {
  final String activeFen;
  final List<String> ambiguousSquares; // e.g. ["c4", "f1"]
  final Function(String square, String? piece) onPieceCorrected;
  final VoidCallback onSubmitReport;

  const CalibrationSheet({
    Key? key,
    required this.activeFen,
    required this.ambiguousSquares,
    required this.onPieceCorrected,
    required this.onSubmitReport,
  }) : super(key: key);

  @override
  State<CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends State<CalibrationSheet> {
  String? _selectedSquare;

  final List<String> _pieces = [
    'P', 'N', 'B', 'R', 'Q', 'K',
    'p', 'n', 'b', 'r', 'q', 'k'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.ambiguousSquares.isNotEmpty) {
      _selectedSquare = widget.ambiguousSquares.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '✏️ Confirm & Calibrate Pieces',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              TextButton.icon(
                onPressed: widget.onSubmitReport,
                icon: const Icon(Icons.bug_report, size: 16, color: Colors.amber),
                label: const Text('Report Error', style: TextStyle(color: Colors.amber, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.ambiguousSquares.isNotEmpty)
            Text(
              'Ambiguous squares detected: ${widget.ambiguousSquares.join(", ")}',
              style: const TextStyle(color: Colors.amber, fontSize: 13),
            ),
          const SizedBox(height: 12),
          // Quick piece palette
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('Empty'),
                backgroundColor: Colors.grey[800],
                onPressed: () {
                  if (_selectedSquare != null) {
                    widget.onPieceCorrected(_selectedSquare!, null);
                  }
                },
              ),
              ..._pieces.map((p) {
                final bool isWhite = p == p.toUpperCase();
                return ActionChip(
                  label: Text(
                    p,
                    style: TextStyle(
                      color: isWhite ? Colors.white : Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: isWhite ? Colors.blueGrey[800] : Colors.grey[900],
                  onPressed: () {
                    if (_selectedSquare != null) {
                      widget.onPieceCorrected(_selectedSquare!, p);
                    }
                  },
                );
              }).toList(),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () => Navigator.pop(context),
              child: const Text('Confirm & Analyze', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
