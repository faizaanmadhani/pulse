import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/url_opener.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'macos_ui.dart';

typedef StravaOAuthConnectCallback = Future<bool> Function({
  required String clientId,
  required String clientSecret,
});

typedef StravaTokenConnectCallback = Future<bool> Function(String accessToken);

Future<bool?> showStravaConnectDialog(
  BuildContext context, {
  required StravaOAuthConnectCallback onConnectOAuth,
  required StravaTokenConnectCallback onConnectAccessToken,
  String? initialClientId,
  String? initialError,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => StravaConnectDialog(
      onConnectOAuth: onConnectOAuth,
      onConnectAccessToken: onConnectAccessToken,
      initialClientId: initialClientId,
      initialError: initialError,
    ),
  );
}

class StravaConnectDialog extends StatefulWidget {
  static const String stravaApiSettingsUrl =
      'https://www.strava.com/settings/api';
  static const Color stravaOrange = Color(0xFFFC4C02);

  final StravaOAuthConnectCallback onConnectOAuth;
  final StravaTokenConnectCallback onConnectAccessToken;
  final String? initialClientId;
  final String? initialError;

  const StravaConnectDialog({
    super.key,
    required this.onConnectOAuth,
    required this.onConnectAccessToken,
    this.initialClientId,
    this.initialError,
  });

  @override
  State<StravaConnectDialog> createState() => _StravaConnectDialogState();
}

class _StravaConnectDialogState extends State<StravaConnectDialog> {
  late final TextEditingController _clientIdController;
  final _clientSecretController = TextEditingController();
  final _accessTokenController = TextEditingController();

  bool _obscureSecret = true;
  bool _obscureToken = true;
  bool _isConnectingOAuth = false;
  bool _isConnectingToken = false;
  String? _errorMessage;

  bool get _isBusy => _isConnectingOAuth || _isConnectingToken;

  @override
  void initState() {
    super.initState();
    _clientIdController = TextEditingController(text: widget.initialClientId ?? '');
    _errorMessage = widget.initialError;
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _accessTokenController.dispose();
    super.dispose();
  }

  Future<void> _handleOpenStravaApiSettings() async {
    final opened = await UrlOpener.openUrl(StravaConnectDialog.stravaApiSettingsUrl);
    if (!opened && mounted) {
      setState(() {
        _errorMessage =
            'Could not open browser. Visit https://www.strava.com/settings/api manually.';
      });
    }
  }

  Future<void> _handleOAuthConnect() async {
    final clientId = _clientIdController.text.trim();
    final clientSecret = _clientSecretController.text.trim();

    if (clientId.isEmpty || clientSecret.isEmpty) {
      setState(() {
        _errorMessage = 'Enter both your Strava Client ID and Client Secret.';
      });
      return;
    }

    setState(() {
      _isConnectingOAuth = true;
      _errorMessage = null;
    });

    try {
      final ok = await widget.onConnectOAuth(
        clientId: clientId,
        clientSecret: clientSecret,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isConnectingOAuth = false;
          _errorMessage =
              'Could not complete Strava OAuth. Check your credentials and callback domain.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnectingOAuth = false;
        _errorMessage = e.toString().replaceFirst('StravaAuthException: ', '');
      });
    }
  }

  Future<void> _handleTokenConnect() async {
    final token = _accessTokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _errorMessage = 'Paste a Strava Access Token to connect directly.';
      });
      return;
    }

    setState(() {
      _isConnectingToken = true;
      _errorMessage = null;
    });

    try {
      final ok = await widget.onConnectAccessToken(token);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isConnectingToken = false;
          _errorMessage =
              'Strava rejected this Access Token. Verify it has activity:read_all scope.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnectingToken = false;
        _errorMessage = e.toString().replaceFirst('StravaAuthException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.borderSubtle),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: StravaConnectDialog.stravaOrange.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      CupertinoIcons.flame_fill,
                      size: 21,
                      color: StravaConnectDialog.stravaOrange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Connect Strava', style: AppTypography.headlineMd),
                        const SizedBox(height: 2),
                        Text(
                          'Sync kudos, comments, segments, and PRs onto your Garmin activities.',
                          style: AppTypography.bodySm,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withOpacity(0.35)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        CupertinoIcons.exclamationmark_circle_fill,
                        size: 16,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppTypography.bodySm.copyWith(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              MacCard(
                color: AppColors.surfaceLowest,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.globe,
                          size: 15,
                          color: StravaConnectDialog.stravaOrange,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'OAuth Browser Connect (Recommended)',
                            style: AppTypography.headlineSm,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Create or view your Strava API app and set Authorization Callback Domain to 127.0.0.1. Clicking Connect opens Strava in your browser and captures the callback automatically.',
                      style: AppTypography.bodySm.copyWith(fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: MacPushButton(
                        label: 'Open Strava API Settings',
                        icon: CupertinoIcons.arrow_up_right_square,
                        onPressed: _isBusy ? null : _handleOpenStravaApiSettings,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Client ID', style: AppTypography.headlineSm),
                    const SizedBox(height: 5),
                    TextField(
                      controller: _clientIdController,
                      enabled: !_isBusy,
                      keyboardType: TextInputType.number,
                      style: AppTypography.bodyLg,
                      decoration: _inputDecoration('e.g. 123456'),
                      onSubmitted: (_) => _handleOAuthConnect(),
                    ),
                    const SizedBox(height: 10),
                    Text('Client Secret', style: AppTypography.headlineSm),
                    const SizedBox(height: 5),
                    TextField(
                      controller: _clientSecretController,
                      enabled: !_isBusy,
                      obscureText: _obscureSecret,
                      style: AppTypography.bodyLg,
                      decoration: _inputDecoration('Strava Client Secret').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureSecret
                                ? CupertinoIcons.eye
                                : CupertinoIcons.eye_slash,
                            size: 16,
                            color: AppColors.outline,
                          ),
                          onPressed: () =>
                              setState(() => _obscureSecret = !_obscureSecret),
                        ),
                      ),
                      onSubmitted: (_) => _handleOAuthConnect(),
                    ),
                    const SizedBox(height: 12),
                    MacPushButton(
                      label: _isConnectingOAuth
                          ? 'Waiting for Browser Callback…'
                          : 'Connect with Strava',
                      icon: CupertinoIcons.arrow_up_right_square,
                      isPrimary: true,
                      isLoading: _isConnectingOAuth,
                      onPressed: _isBusy ? null : _handleOAuthConnect,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Divider(color: AppColors.borderSubtle, height: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'OR PASTE ACCESS TOKEN',
                      style: AppTypography.labelCaps.copyWith(fontSize: 10),
                    ),
                  ),
                  Expanded(child: Divider(color: AppColors.borderSubtle, height: 1)),
                ],
              ),
              const SizedBox(height: 12),
              Text('Strava Access Token', style: AppTypography.headlineSm),
              const SizedBox(height: 5),
              TextField(
                controller: _accessTokenController,
                enabled: !_isBusy,
                obscureText: _obscureToken,
                style: AppTypography.bodyLg,
                decoration:
                    _inputDecoration('Paste bearer token with activity:read_all')
                        .copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureToken ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                      size: 16,
                      color: AppColors.outline,
                    ),
                    onPressed: () => setState(() => _obscureToken = !_obscureToken),
                  ),
                ),
                onSubmitted: (_) => _handleTokenConnect(),
              ),
              const SizedBox(height: 14),
              Text(
                'Tokens are persisted locally in ~/Library/Application Support/pulse_training_hub with owner-only permissions (0600).',
                style: AppTypography.bodySm.copyWith(fontSize: 11),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MacPushButton(
                    label: 'Cancel',
                    onPressed: _isBusy ? null : () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  MacPushButton(
                    label: 'Connect with Token',
                    isLoading: _isConnectingToken,
                    onPressed: _isBusy ? null : _handleTokenConnect,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.outline),
      filled: true,
      fillColor: AppColors.surfaceContainer,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: AppColors.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: AppColors.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: AppColors.accent, width: 1.5),
      ),
    );
  }
}
