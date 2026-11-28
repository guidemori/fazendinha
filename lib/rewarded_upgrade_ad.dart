import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

Future<bool> showRewardedUpgradeAd(String unitId) async {
  final loaded = Completer<RewardedAd?>();
  try {
    await RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (loaded.isCompleted) {
            unawaited(ad.dispose());
          } else {
            loaded.complete(ad);
          }
        },
        onAdFailedToLoad: (_) {
          if (!loaded.isCompleted) loaded.complete(null);
        },
      ),
    );
  } catch (_) {
    if (!loaded.isCompleted) loaded.complete(null);
  }

  final ad =
      await loaded.future.timeout(const Duration(seconds: 20), onTimeout: () {
    if (!loaded.isCompleted) loaded.complete(null);
    return null;
  });
  if (ad == null) return false;

  final closed = Completer<bool>();
  var earned = false;
  void finish(bool rewarded) {
    if (closed.isCompleted) return;
    unawaited(ad.dispose());
    closed.complete(rewarded);
  }

  ad.fullScreenContentCallback = FullScreenContentCallback(
    onAdDismissedFullScreenContent: (_) => finish(earned),
    onAdFailedToShowFullScreenContent: (_, __) => finish(false),
  );
  try {
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
  } catch (_) {
    finish(false);
  }
  return closed.future;
}
