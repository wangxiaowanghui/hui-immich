import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:url_launcher/url_launcher.dart';

const _amapPrivacyPolicyVersion = 1;

class AmapPrivacyGate extends ConsumerStatefulWidget {
  final Widget Function(BuildContext context, bool useAmap) builder;
  final bool inlinePrompt;

  const AmapPrivacyGate({super.key, required this.builder, this.inlinePrompt = false});

  static void useFallback(BuildContext context) {
    final state = context.findAncestorStateOfType<_AmapPrivacyGateState>();
    state?._useFallback();
  }

  @override
  ConsumerState<AmapPrivacyGate> createState() => _AmapPrivacyGateState();
}

class _AmapPrivacyGateState extends ConsumerState<AmapPrivacyGate> {
  Future<bool>? _isConfigured;
  bool _failed = false;
  bool get _supported => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  bool _requestingConsent = false;

  void _useFallback() {
    if (mounted && !_failed) {
      setState(() => _failed = true);
    }
  }

  @override
  void initState() {
    super.initState();
    if (_supported) {
      _isConfigured ??= const MethodChannel('immich/amap_config')
          .invokeMethod<bool>('isConfigured')
          .timeout(const Duration(seconds: 5))
          .then((value) => value ?? false, onError: (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported || _failed) {
      return widget.builder(context, false);
    }

    return FutureBuilder<bool>(
      future: _isConfigured,
      builder: (context, configured) {
        // 配置判定前不创建备用原生地图，避免它迟到的创建回调覆盖高德控制器。
        if (configured.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (configured.data != true) {
          return widget.builder(context, false);
        }

        final consentVersion = ref.watch(appConfigProvider.select((config) => config.map.amapPrivacyConsentVersion));
        if (consentVersion == _amapPrivacyPolicyVersion) {
          return Builder(builder: (mapContext) => widget.builder(mapContext, true));
        }
        if (consentVersion == -_amapPrivacyPolicyVersion) {
          return widget.builder(context, false);
        }

        if (widget.inlinePrompt) {
          return Stack(
            fit: StackFit.expand,
            children: [
              widget.builder(context, false),
              const ModalBarrier(dismissible: false, color: Colors.black54),
              Center(
                child: SafeArea(
                  minimum: const EdgeInsets.all(24),
                  child: _AmapPrivacyDialog(onSelected: _saveConsent),
                ),
              ),
            ],
          );
        }

        if (!_requestingConsent) {
          _requestingConsent = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _requestConsent());
        }
        return const Center(child: CircularProgressIndicator.adaptive());
      },
    );
  }

  Future<void> _requestConsent() async {
    final accepted = await _AmapConsentCoordinator.request(context);
    await _saveConsent(accepted);
  }

  Future<void> _saveConsent(bool accepted) async {
    if (!mounted) {
      return;
    }
    await ref
        .read(settingsProvider)
        .write(.mapAmapPrivacyConsentVersion, accepted ? _amapPrivacyPolicyVersion : -_amapPrivacyPolicyVersion);
  }
}

class _AmapConsentCoordinator {
  static Future<bool>? _activeRequest;

  static Future<bool> request(BuildContext context) {
    return _activeRequest ??= _showDialog(context).whenComplete(() => _activeRequest = null);
  }

  static Future<bool> _showDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AmapPrivacyDialog(onSelected: (accepted) => Navigator.of(context).pop(accepted)),
    );
    return result ?? false;
  }
}

class _AmapPrivacyDialog extends StatelessWidget {
  final ValueChanged<bool> onSelected;

  const _AmapPrivacyDialog({required this.onSelected});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('map_amap_privacy_title'.t(context: context)),
    content: Text('map_amap_privacy_content'.t(context: context)),
    actions: [
      TextButton(
        onPressed: () =>
            launchUrl(Uri.parse('https://lbs.amap.com/pages/privacy/'), mode: LaunchMode.externalApplication),
        child: Text('map_amap_privacy_policy'.t(context: context)),
      ),
      TextButton(
        onPressed: () => onSelected(false),
        child: Text('map_amap_privacy_use_fallback'.t(context: context)),
      ),
      FilledButton(
        onPressed: () => onSelected(true),
        child: Text('map_amap_privacy_agree'.t(context: context)),
      ),
    ],
  );
}
