import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/chatgpt_service.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'macos_ui.dart';

Future<bool?> showChatGptConnectDialog(
  BuildContext context,
  AppState appState, {
  String? initialClientId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => ChatGptConnectDialog(
      appState: appState,
      initialClientId: initialClientId,
    ),
  );
}

class ChatGptConnectDialog extends StatefulWidget {
  static const String defaultCallbackUrl =
      'http://127.0.0.1:${ChatGptService.defaultCallbackPort}/callback';
  static const Color chatGptTeal = Color(0xFF10A37F);

  final AppState appState;
  final String? initialClientId;

  const ChatGptConnectDialog({
    super.key,
    required this.appState,
    this.initialClientId,
  });

  @override
  State<ChatGptConnectDialog> createState() => _ChatGptConnectDialogState();
}

class _ChatGptConnectDialogState extends State<ChatGptConnectDialog> {
  late final TextEditingController _clientIdController;
  final _manualCodeController = TextEditingController();

  bool _copiedCallback = false;
  bool _isSubmittingManual = false;
  bool _didCompleteSuccess = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _clientIdController = TextEditingController(
      text: widget.initialClientId ?? widget.appState.chatGptSession?.clientId ?? '',
    );
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _manualCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleCopyCallbackUrl() async {
    await Clipboard.setData(
      const ClipboardData(text: ChatGptConnectDialog.defaultCallbackUrl),
    );
    if (!mounted) return;
    setState(() {
      _copiedCallback = true;
    });
  }

  Future<void> _handleOAuthConnect() async {
    final clientId = _clientIdController.text.trim();
    if (clientId.isEmpty) {
      setState(() {
        _localError = 'Enter your OpenAI OAuth Client ID (oaiapp_...).';
      });
      return;
    }

    setState(() {
      _localError = null;
    });

    final ok = await widget.appState.connectChatGpt(clientId);
    if (!mounted) return;
    if (ok) {
      _didCompleteSuccess = true;
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _handleManualCodeSubmit() async {
    final clientId = _clientIdController.text.trim();
    final manualInput = _manualCodeController.text.trim();

    if (clientId.isEmpty) {
      setState(() {
        _localError = 'Enter your OpenAI OAuth Client ID (oaiapp_...).';
      });
      return;
    }
    if (manualInput.isEmpty) {
      setState(() {
        _localError = 'Paste the authorization code or callback URL.';
      });
      return;
    }

    setState(() {
      _isSubmittingManual = true;
      _localError = null;
    });

    final ok = await widget.appState.completeChatGptOAuthWithCode(
      manualInput,
      clientId: clientId,
    );
    if (!mounted) return;
    if (ok) {
      _didCompleteSuccess = true;
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmittingManual = false;
      });
    }
  }

  Future<void> _handleCancel() async {
    await widget.appState.cancelChatGptAuth();
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop && !_didCompleteSuccess) {
          widget.appState.cancelChatGptAuth();
        }
      },
      child: ListenableBuilder(
        listenable: widget.appState,
        builder: (context, _) {
          final isAuthenticating = widget.appState.isAuthenticatingChatGpt;
          final isBusy = isAuthenticating || _isSubmittingManual;
          final errorMessage = _localError ?? widget.appState.chatGptError;

          return Dialog(
            backgroundColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.borderSubtle),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
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
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: ChatGptConnectDialog.chatGptTeal
                                .withOpacity(0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            CupertinoIcons.sparkles,
                            size: 20,
                            color: ChatGptConnectDialog.chatGptTeal,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sign in with ChatGPT',
                                style: AppTypography.headlineMd,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Connect with OAuth 2.0 + PKCE to power AI coaching and personalized triathlon plans.',
                                style: AppTypography.bodySm,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (errorMessage != null && errorMessage.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.error.withOpacity(0.35),
                          ),
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
                                errorMessage,
                                style: AppTypography.bodySm
                                    .copyWith(color: AppColors.error),
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
                                CupertinoIcons.lock_shield,
                                size: 15,
                                color: ChatGptConnectDialog.chatGptTeal,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  'OAuth 2.0 + PKCE Browser Flow',
                                  style: AppTypography.headlineSm,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Enter your registered OpenAI OAuth Client ID and ensure your redirect URI matches the local callback address below.',
                            style: AppTypography.bodySm.copyWith(fontSize: 11),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'OpenAI OAuth Client ID',
                            style: AppTypography.headlineSm,
                          ),
                          const SizedBox(height: 5),
                          TextField(
                            controller: _clientIdController,
                            enabled: !isBusy,
                            style: AppTypography.bodyLg,
                            decoration: _inputDecoration('e.g. oaiapp_...'),
                            onSubmitted: (_) => _handleOAuthConnect(),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Local Callback URL',
                            style: AppTypography.headlineSm,
                          ),
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    ChatGptConnectDialog.defaultCallbackUrl,
                                    style: AppTypography.telemetrySm.copyWith(
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                MacPushButton(
                                  label: _copiedCallback ? 'Copied' : 'Copy',
                                  icon: _copiedCallback
                                      ? CupertinoIcons.checkmark
                                      : CupertinoIcons.doc_on_doc,
                                  onPressed: _handleCopyCallbackUrl,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          MacPushButton(
                            label: isAuthenticating && !_isSubmittingManual
                                ? 'Waiting for Browser Callback…'
                                : 'Continue with ChatGPT',
                            icon: CupertinoIcons.arrow_up_right_square,
                            isPrimary: true,
                            isLoading: isAuthenticating && !_isSubmittingManual,
                            onPressed: isBusy ? null : _handleOAuthConnect,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: AppColors.borderSubtle,
                            height: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'OR PASTE CALLBACK URL / CODE',
                            style: AppTypography.labelCaps.copyWith(fontSize: 10),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: AppColors.borderSubtle,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Authorization Code or Callback URL',
                      style: AppTypography.headlineSm,
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      controller: _manualCodeController,
                      enabled: !_isSubmittingManual,
                      style: AppTypography.bodyLg,
                      decoration: _inputDecoration(
                        'Paste http://127.0.0.1:1455/callback?code=... or code',
                      ),
                      onSubmitted: (_) => _handleManualCodeSubmit(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tokens are stored locally in ~/Library/Application Support/pulse_training_hub with owner-only permissions (0600).',
                      style: AppTypography.bodySm.copyWith(fontSize: 11),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        MacPushButton(
                          label: 'Cancel',
                          onPressed: _handleCancel,
                        ),
                        const SizedBox(width: 8),
                        MacPushButton(
                          label: 'Complete Sign-In',
                          isLoading: _isSubmittingManual,
                          onPressed:
                              _isSubmittingManual ? null : _handleManualCodeSubmit,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
