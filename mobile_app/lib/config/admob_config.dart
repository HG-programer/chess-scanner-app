/// Centralized AdMob & Monetization Configuration for ChessSnap.
///
/// To monetize on Google Play:
/// 1. Create your app on Google AdMob (https://apps.admob.com).
/// 2. Set your AdMob Application ID in GitHub Secrets (ADMOB_APP_ID)
///    or update [productionAppId] below.
/// 3. Create your Ad Units (Banner, Rewarded, Interstitial) in AdMob
///    and set their IDs below.
class AdMobConfig {
  // Test IDs (Google's standard sample IDs for safe local testing)
  static const String testAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const String testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String testRewardedId = 'ca-app-pub-3940256099942544/5224354917';
  static const String testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';

  // Production IDs: Place your real AdMob IDs here when ready for Google Play release
  static const String productionAppId = '';
  static const String productionBannerId = '';
  static const String productionRewardedId = '';
  static const String productionInterstitialId = '';

  /// Returns true if production AdMob IDs have been supplied
  static bool get isProductionConfigured =>
      productionAppId.isNotEmpty &&
      productionBannerId.isNotEmpty &&
      productionRewardedId.isNotEmpty &&
      productionInterstitialId.isNotEmpty;

  static String get bannerId =>
      productionBannerId.isNotEmpty ? productionBannerId : testBannerId;

  static String get rewardedId =>
      productionRewardedId.isNotEmpty ? productionRewardedId : testRewardedId;

  static String get interstitialId =>
      productionInterstitialId.isNotEmpty ? productionInterstitialId : testInterstitialId;
}
