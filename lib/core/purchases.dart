import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'app_settings.dart';

/// The one-off £2.99 full-game unlock: a non-consumable in-app purchase.
/// No account, no server — the store's receipt (restorable on any phone with
/// the same Apple ID / Google account) is the record.
class Purchases extends ChangeNotifier {
  Purchases(this._settings);

  /// Must match the product created in App Store Connect / Play Console.
  static const productId = 'com.littlefortstudios.quizinho.fullgame';

  final AppSettings _settings;
  InAppPurchase? _store;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Timer? _restoreTimeout;

  /// The store's listing (localised price), once loaded.
  ProductDetails? product;

  /// A purchase or restore is in progress.
  bool busy = false;

  /// Last problem to show on the paywall, if any.
  String? error;

  /// Phones only; the web preview is the full game.
  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  bool get unlocked => !supported || _settings.unlocked;

  /// Shown before the store answers.
  String get price => product?.price ?? '£2.99';

  /// Starts listening for purchases (including ones finished while the app
  /// was closed) and loads the price. Safe to call again.
  Future<void> init() async {
    if (!supported) return;
    try {
      final store = _store ??= InAppPurchase.instance;
      _sub ??= store.purchaseStream.listen(_onUpdates, onError: (Object e) {
        busy = false;
        error = 'Something went wrong — try again.';
        notifyListeners();
      });
      if (product != null || !await store.isAvailable()) return;
      final r = await store.queryProductDetails({productId});
      if (r.productDetails.isNotEmpty) {
        product = r.productDetails.first;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Store unavailable: $e');
    }
  }

  Future<void> buy() async {
    if (busy) return;
    await init();
    final store = _store;
    final p = product;
    if (store == null || p == null) {
      error = 'Can’t reach the App Store right now — check your connection and try again.';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      await store.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
    } catch (e) {
      busy = false;
      error = 'Purchase didn’t start — try again.';
      notifyListeners();
    }
  }

  /// Already bought on another phone, or reinstalled.
  Future<void> restore() async {
    if (busy) return;
    await init();
    final store = _store;
    if (store == null) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await store.restorePurchases();
    } catch (e) {
      busy = false;
      error = 'Couldn’t restore — try again.';
      notifyListeners();
      return;
    }
    // The store only reports purchases it finds; silence means none.
    _restoreTimeout?.cancel();
    _restoreTimeout = Timer(const Duration(seconds: 8), () {
      if (!busy) return;
      busy = false;
      if (!unlocked) error = 'No previous purchase found for this account.';
      notifyListeners();
    });
  }

  Future<void> _onUpdates(List<PurchaseDetails> updates) async {
    for (final p in updates) {
      if (p.productID == productId) {
        switch (p.status) {
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            _settings.unlocked = true;
            busy = false;
            error = null;
            _restoreTimeout?.cancel();
          case PurchaseStatus.pending:
            busy = true; // e.g. Ask to Buy — finishes later
          case PurchaseStatus.canceled:
            busy = false;
          case PurchaseStatus.error:
            busy = false;
            error = p.error?.message ?? 'Purchase failed — you haven’t been charged.';
        }
      }
      if (p.pendingCompletePurchase) await _store?.completePurchase(p);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _restoreTimeout?.cancel();
    super.dispose();
  }
}
