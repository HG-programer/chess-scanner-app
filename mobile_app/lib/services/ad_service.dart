import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/admob_config.dart';

/// Production-ready AdMob Monetization Service.
/// Handles initialization, pre-loading, rewarded video ads, banner ads,
/// and offline/emulator fallback mechanics.
class AdService {
  static final AdService instance = AdService._internal();
  AdService._internal();

  // Dynamic Ad Unit IDs from AdMobConfig
  static String get bannerAdUnitId => AdMobConfig.bannerId;
  static String get rewardedAdUnitId => AdMobConfig.rewardedId;
  static String get interstitialAdUnitId => AdMobConfig.interstitialId;

  bool _isInitialized = false;
  RewardedAd? _rewardedAd;
  bool _isRewardedAdLoading = false;
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoading = false;

  DateTime? _proPassExpiry;
  static const String _prefKeyProExpiry = 'pro_pass_expiry_ms';

  /// Initialize Google Mobile Ads SDK safely
  Future<void> initialize() async {
    try {
      await MobileAds.instance.initialize();
      _isInitialized = true;
      debugPrint('[AdService] Google Mobile Ads SDK initialized successfully.');
      _loadRewardedAd();
      _loadInterstitialAd();
    } catch (e) {
      debugPrint('[AdService] MobileAds initialize failed or running in emulator: $e');
      _isInitialized = false;
    }

    // Load saved Pro Pass expiry
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_prefKeyProExpiry);
      if (ms != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(ms);
        if (expiry.isAfter(DateTime.now())) {
          _proPassExpiry = expiry;
        }
      }
    } catch (_) {}
  }

  /// Check if user has an active 30-minute Pro Pass
  bool get hasActiveProPass {
    if (_proPassExpiry == null) return false;
    return _proPassExpiry!.isAfter(DateTime.now());
  }

  /// Formatted string of remaining Pro Pass time (e.g. "24m")
  String get remainingProPassTime {
    if (!hasActiveProPass) return '';
    final diff = _proPassExpiry!.difference(DateTime.now());
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return '${diff.inSeconds}s';
  }

  /// Activate 30-minute Pro Pass after rewarded ad
  Future<void> grantProPass({int durationMinutes = 30}) async {
    _proPassExpiry = DateTime.now().add(Duration(minutes: durationMinutes));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKeyProExpiry, _proPassExpiry!.millisecondsSinceEpoch);
    } catch (_) {}
  }

  // --- REWARDED ADS ---

  void _loadRewardedAd() {
    if (!_isInitialized || _isRewardedAdLoading || _rewardedAd != null) return;
    _isRewardedAdLoading = true;

    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdLoading = false;
          debugPrint('[AdService] RewardedAd loaded successfully.');
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          _isRewardedAdLoading = false;
          debugPrint('[AdService] RewardedAd failed to load: ${error.message}');
        },
      ),
    );
  }

  /// Show Rewarded Video Ad for 30m Pro Pass.
  /// If real AdMob ad is ready -> shows it.
  /// If offline or on emulator -> shows simulated test ad dialog so user is never blocked.
  Future<void> showRewardedAd({
    required BuildContext context,
    required VoidCallback onRewardEarned,
  }) async {
    if (_rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _rewardedAd = null;
          _loadRewardedAd(); // Pre-load next
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _rewardedAd = null;
          _loadRewardedAd();
          // Fallback to simulated ad on failure
          _showSimulatedAdDialog(context, onRewardEarned);
        },
      );

      _rewardedAd!.show(onUserEarnedReward: (ad, reward) {
        grantProPass();
        onRewardEarned();
      });
    } else {
      // Fallback for emulators (LDPlayer), test devices, or offline mode
      _loadRewardedAd();
      await _showSimulatedAdDialog(context, onRewardEarned);
    }
  }

  /// User-friendly test ad dialog for emulators and offline testing
  Future<void> _showSimulatedAdDialog(BuildContext context, VoidCallback onRewardEarned) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _SimulatedAdCountdownDialog(
          onComplete: () {
            grantProPass();
            onRewardEarned();
          },
        );
      },
    );
  }

  // --- INTERSTITIAL ADS ---

  void _loadInterstitialAd() {
    if (!_isInitialized || _isInterstitialAdLoading || _interstitialAd != null) return;
    _isInterstitialAdLoading = true;

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoading = false;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          _isInterstitialAdLoading = false;
        },
      ),
    );
  }

  int _matchesPlayedSinceAd = 0;
  DateTime? _lastInterstitialTime;

  /// Shows interstitial ad responsibly without annoying the user:
  /// - Only shows after every 4 matches (not every match!)
  /// - Enforces at least 4 minutes between full-screen ads
  /// - Never interrupts users with an active Pro Pass
  void showInterstitialWithCooldown({int matchesThreshold = 4, int minMinutesCooldown = 4}) {
    if (hasActiveProPass) return;
    _matchesPlayedSinceAd++;
    if (_matchesPlayedSinceAd < matchesThreshold) return;

    if (_lastInterstitialTime != null) {
      final elapsedMinutes = DateTime.now().difference(_lastInterstitialTime!).inMinutes;
      if (elapsedMinutes < minMinutesCooldown) return;
    }

    _matchesPlayedSinceAd = 0;
    _lastInterstitialTime = DateTime.now();
    showInterstitialAd();
  }

  /// Show Interstitial ad (e.g. after board scan or game reset)
  void showInterstitialAd() {
    if (_interstitialAd != null && !hasActiveProPass) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitialAd();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitialAd();
        },
      );
      _interstitialAd!.show();
    } else {
      _loadInterstitialAd();
    }
  }
}

/// Simulated ad video player dialog for emulator & offline testing
class _SimulatedAdCountdownDialog extends StatefulWidget {
  final VoidCallback onComplete;
  const _SimulatedAdCountdownDialog({Key? key, required this.onComplete}) : super(key: key);

  @override
  State<_SimulatedAdCountdownDialog> createState() => _SimulatedAdCountdownDialogState();
}

class _SimulatedAdCountdownDialogState extends State<_SimulatedAdCountdownDialog> {
  int _secondsLeft = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
      } else {
        _timer?.cancel();
        Navigator.pop(context);
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.amber.withOpacity(0.15),
            ),
            child: const Icon(Icons.play_circle_filled, size: 48, color: Colors.amber),
          ),
          const SizedBox(height: 16),
          const Text(
            'Rewarded Ad in Progress',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Watching sponsored message...\nUnlocking 30m Pro Pass in $_secondsLeft s',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: (5 - _secondsLeft) / 5.0,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
          ),
        ],
      ),
    );
  }
}

/// Responsive Banner Ad Widget
class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({Key? key}) : super(key: key);

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  void _loadBanner() {
    try {
      _bannerAd = BannerAd(
        adUnitId: AdService.bannerAdUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) setState(() => _isLoaded = true);
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            _bannerAd = null;
          },
        ),
      )..load();
    } catch (_) {}
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
