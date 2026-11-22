import 'package:flutter/services.dart';
import 'garmin_service.dart';

/// Invokes the native macOS WKWebView Garmin Connect sign-in window.
/// Using Apple's real WebKit engine avoids Cloudflare blocks on sso.garmin.com
/// and handles 2FA/MFA prompts natively.
class GarminWebAuth {
  static const MethodChannel _channel = MethodChannel('com.pulse.training/garmin_auth');

  const GarminWebAuth();

  /// Opens the native Garmin Connect sign-in window and returns the CAS service
  /// ticket (`ST-...`), or `null` if the user closed/cancelled the window.
  Future<String?> signInWithWebView({String domain = 'garmin.com'}) async {
    try {
      final ticket = await _channel.invokeMethod<String>(
        'signInWithWebView',
        {'domain': domain},
      );
      if (ticket == null || ticket.trim().isEmpty) {
        return null;
      }
      return ticket.trim();
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED') {
        return null;
      }
      throw GarminAuthException(e.message ?? 'Garmin browser sign-in failed.');
    } on MissingPluginException {
      throw const GarminAuthException(
        'Browser sign-in is only available on the native macOS desktop app.',
      );
    }
  }
}
