import 'package:flutter/material.dart';

/// 60 FPS Animated Evaluation Bar showing White vs Black probability.
class ChessEvalBar extends StatelessWidget {
  final double evalPercent; // 0.0 (Black winning) to 100.0 (White winning)
  final String scoreText;   // e.g. "+1.4" or "M2"

  const ChessEvalBar({
    Key? key,
    required this.evalPercent,
    required this.scoreText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF444444), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Stack(
          children: [
            FractionallySizedBox(
              widthFactor: (evalPercent / 100.0).clamp(0.0, 1.0),
              child: Container(
                color: const Color(0xFFF0F0F0),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      scoreText,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const Text(
                      'AI EVAL',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
