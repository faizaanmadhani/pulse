import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'macos_ui.dart';

Future<void> showGarminSignInDialog(BuildContext context, AppState appState) {
  appState.clearAuthError();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => GarminSignInDialog(appState: appState),
  );
}

class GarminSignInDialog extends StatefulWidget {
  final AppState appState;

  const GarminSignInDialog({super.key, required this.appState});

  @override
  State<GarminSignInDialog> createState() => _GarminSignInDialogState();
}

class _GarminSignInDialogState extends State<GarminSignInDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mfaController = TextEditingController();
  bool _obscurePassword = true;
  String _domain = 'garmin.com';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _mfaController.dispose();
    super.dispose();
  }

  Future<void> _handleBrowserSignIn() async {
    final ok = await widget.appState.signInWithGarminBrowser(domain: _domain);
    if (ok && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleSignIn() async {
    final ok = await widget.appState.signInWithGarmin(
      email: _emailController.text,
      password: _passwordController.text,
      domain: _domain,
    );
    if (ok && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleSubmitMfa() async {
    final ok = await widget.appState.submitGarminMfa(_mfaController.text);
    if (ok && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final appState = widget.appState;
        final isMfaStep = appState.pendingMfa != null;
        final isBusy = appState.isAuthenticating;

        return Dialog(
          backgroundColor: AppColors.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.borderSubtle),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
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
                          color: AppColors.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isMfaStep
                              ? CupertinoIcons.lock_shield
                              : CupertinoIcons.person_crop_circle,
                          size: 22,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMfaStep ? 'Two-Factor Verification' : 'Sign in to Garmin Connect',
                              style: AppTypography.headlineMd,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isMfaStep
                                  ? 'Enter the 6-digit verification code sent by Garmin.'
                                  : 'Pull your real activities, devices, and health stats.',
                              style: AppTypography.bodySm,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (appState.authError != null) ...[
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
                          Icon(CupertinoIcons.exclamationmark_circle_fill,
                              size: 16, color: AppColors.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              appState.authError!,
                              style: AppTypography.bodySm.copyWith(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!isMfaStep) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLowest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(CupertinoIcons.globe, size: 16, color: AppColors.accent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Browser Sign-In (Recommended)',
                                  style: AppTypography.headlineSm,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Opens Garmin\'s official login page in a secure macOS window. Supports 2FA and avoids Garmin website security blocks.',
                            style: AppTypography.bodySm.copyWith(fontSize: 11),
                          ),
                          const SizedBox(height: 12),
                          MacPushButton(
                            label: 'Open Garmin Sign-In',
                            icon: CupertinoIcons.arrow_up_right_square,
                            isPrimary: true,
                            isLoading: isBusy,
                            onPressed: _handleBrowserSignIn,
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
                            'OR DIRECT SIGN-IN',
                            style: AppTypography.labelCaps.copyWith(fontSize: 10),
                          ),
                        ),
                        Expanded(child: Divider(color: AppColors.borderSubtle, height: 1)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Garmin Email', style: AppTypography.headlineSm),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailController,
                      enabled: !isBusy,
                      keyboardType: TextInputType.emailAddress,
                      style: AppTypography.bodyLg,
                      decoration: _inputDecoration('you@example.com'),
                      onSubmitted: (_) => _handleSignIn(),
                    ),
                    const SizedBox(height: 12),
                    Text('Password', style: AppTypography.headlineSm),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordController,
                      enabled: !isBusy,
                      obscureText: _obscurePassword,
                      style: AppTypography.bodyLg,
                      decoration: _inputDecoration('Garmin Connect password').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                            size: 16,
                            color: AppColors.outline,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      onSubmitted: (_) => _handleSignIn(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Region', style: AppTypography.bodySm),
                        MacSegmentedControl<String>(
                          items: const ['garmin.com', 'garmin.cn'],
                          selected: _domain,
                          labelBuilder: (d) => d == 'garmin.com' ? 'Global' : 'China',
                          onChanged: (val) => setState(() => _domain = val),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text('Verification Code', style: AppTypography.headlineSm),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _mfaController,
                      enabled: !isBusy,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      style: AppTypography.telemetryLg,
                      decoration: _inputDecoration('123456'),
                      onSubmitted: (_) => _handleSubmitMfa(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Credentials are sent directly to Garmin Connect (sso.$_domain) to obtain an OAuth token. Your password is never stored.',
                    style: AppTypography.bodySm.copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      MacPushButton(
                        label: isMfaStep ? 'Back' : 'Cancel',
                        onPressed: isBusy
                            ? null
                            : () {
                                if (isMfaStep) {
                                  appState.cancelMfa();
                                } else {
                                  Navigator.of(context).pop();
                                }
                              },
                      ),
                      const SizedBox(width: 8),
                      MacPushButton(
                        label: isMfaStep ? 'Verify & Sign In' : 'Sign In',
                        isPrimary: isMfaStep,
                        isLoading: isBusy,
                        onPressed: isMfaStep ? _handleSubmitMfa : _handleSignIn,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.outline),
      filled: true,
      fillColor: AppColors.surfaceLowest,
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
