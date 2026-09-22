import 'package:flutter/material.dart';
import '../models/engine_profile.dart';

class EngineSelectorSheet extends StatefulWidget {
  final EngineProfile currentEngine;
  final bool isPremium;
  final Function(EngineProfile newEngine) onEngineSelected;
  final VoidCallback onOpenPaywall;
  final Function(EngineProfile intendedEngine) onWatchAdForTempUnlock;

  const EngineSelectorSheet({
    Key? key,
    required this.currentEngine,
    required this.isPremium,
    required this.onEngineSelected,
    required this.onOpenPaywall,
    required this.onWatchAdForTempUnlock,
  }) : super(key: key);

  @override
  State<EngineSelectorSheet> createState() => _EngineSelectorSheetState();
}

class _EngineSelectorSheetState extends State<EngineSelectorSheet> {
  late EngineProfile _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentEngine;
  }

  void _handleEngineTap(EngineProfile engine) {
    if (engine.isPro && !widget.isPremium) {
      // Prompt paywall / unlock dialog
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Text(engine.icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Text(engine.name, style: const TextStyle(fontSize: 18, color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('🔒 PRO ENGINE', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              const SizedBox(height: 10),
              Text(
                '${engine.name} is a high-performance tournament engine (${engine.elo} ELO).\n\n${engine.description}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              const Text('Unlock Option:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.play_circle_fill, color: Colors.orangeAccent),
              label: const Text('Watch Ad (30m Pass)', style: TextStyle(color: Colors.orangeAccent)),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
                widget.onWatchAdForTempUnlock(engine);
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.workspace_premium, color: Colors.black),
              label: const Text('Upgrade Pro', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
                widget.onOpenPaywall();
              },
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _selected = engine);
    widget.onEngineSelected(engine);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF181818),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar Handle
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '⚙️ Select AI Engine',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              if (!widget.isPremium)
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    widget.onOpenPaywall();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.amber, Colors.orangeAccent]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, size: 14, color: Colors.black),
                        SizedBox(width: 4),
                        Text('Get Pro Pass', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Base engine is Stockfish Coach. Pro engines offer superhuman tactical depth.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),

          // Engine List
          ...EngineProfile.all.map((engine) {
            final isCurrent = _selected.id == engine.id;
            final isLocked = engine.isPro && !widget.isPremium;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: isCurrent
                    ? Colors.amber.withOpacity(0.12)
                    : const Color(0xFF222222),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => _handleEngineTap(engine),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent ? Colors.amber : Colors.white10,
                        width: isCurrent ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Engine Icon / Avatar
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isCurrent ? Colors.amber.withOpacity(0.2) : Colors.black26,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(engine.icon, style: const TextStyle(fontSize: 22)),
                        ),
                        const SizedBox(width: 12),

                        // Title & Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    engine.name,
                                    style: TextStyle(
                                      color: isCurrent ? Colors.amber : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: engine.isPro
                                          ? (widget.isPremium ? Colors.tealAccent.withOpacity(0.2) : Colors.purple.withOpacity(0.25))
                                          : Colors.green.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      engine.tag,
                                      style: TextStyle(
                                        color: engine.isPro
                                            ? (widget.isPremium ? Colors.tealAccent : Colors.purpleAccent)
                                            : Colors.greenAccent,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${engine.elo} ELO  •  Depth ${engine.defaultDepth}',
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                engine.description,
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        // Trailing State (Radio / Lock)
                        if (isLocked)
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF2E2E2E),
                            ),
                            child: const Icon(Icons.lock, color: Colors.amber, size: 18),
                          )
                        else if (isCurrent)
                          const Icon(Icons.check_circle, color: Colors.amber, size: 22)
                        else
                          const Icon(Icons.radio_button_unchecked, color: Colors.white30, size: 22),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
