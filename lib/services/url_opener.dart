import 'dart:io';

/// Native macOS URL opener with strict HTTPS scheme validation.
class UrlOpener {
  const UrlOpener._();

  /// Returns true if [url] is a well-formed `https://` URL with a non-empty host.
  static bool isValidHttpsUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    return uri != null &&
        uri.scheme.toLowerCase() == 'https' &&
        uri.host.isNotEmpty;
  }

  /// Opens [url] in the user's default macOS browser using `/usr/bin/open`.
  /// Rejects any URL that does not use the `https://` scheme.
  static Future<bool> openUrl(String url) async {
    if (!isValidHttpsUrl(url)) {
      return false;
    }
    final normalized = Uri.parse(url.trim()).toString();
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('open', [normalized]);
        return result.exitCode == 0;
      }
      if (Platform.isLinux) {
        final result = await Process.run('xdg-open', [normalized]);
        return result.exitCode == 0;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Canonical Garmin Connect web URL for an activity.
  static String garminActivityUrl(String activityId) =>
      'https://connect.garmin.com/modern/activity/$activityId';

  /// Canonical Strava web URL for an activity.
  static String stravaActivityUrl(String stravaId) =>
      'https://www.strava.com/activities/$stravaId';
}
