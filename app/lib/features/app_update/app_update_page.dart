import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/features/app_update/app_update_service.dart';
import 'package:localsend_app/features/app_update/github_release_models.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:routerino/routerino.dart';

class AppUpdatePage extends StatefulWidget {
  const AppUpdatePage({super.key, this.service});

  final AppUpdateService? service;

  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage> {
  late final AppUpdateService _service;
  late final bool _ownsService;
  PackageInfo? _info;
  DateTime? _installedPublishedAt;
  AppUpdateCheckResult? _check;
  String? _error;
  bool _busy = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? AppUpdateService();
    unawaited(_load());
  }

  @override
  void dispose() {
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    final installedAt = await _service.installedReleasePublishedAt(info.version);
    if (!mounted) {
      return;
    }
    setState(() {
      _info = info;
      _installedPublishedAt = installedAt;
    });
    await _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      final result = await _service.checkForUpdate();
      if (!mounted) {
        return;
      }
      setState(() {
        _check = result;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _install() async {
    final check = _check;
    if (check == null || !check.updateAvailable) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      await _service.downloadAndInstall(
        check,
        onProgress: (p) {
          if (!mounted) {
            return;
          }
          setState(() => _progress = p);
        },
      );
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      context.showSnackBar(t.appUpdatePage.installerOpened);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final check = _check;
    final currentDate = _installedPublishedAt ?? check?.currentRelease?.displayDate;
    final currentDateText = formatAppUpdateDate(currentDate);
    final versionLabel = info == null
        ? t.appUpdatePage.loading
        : currentDateText.isEmpty
        ? '${info.version} (${info.buildNumber})'
        : '${info.version} (${info.buildNumber})\n${t.appUpdatePage.released(date: currentDateText)}';
    final remote = check?.release;
    final remoteDateText = formatAppUpdateDate(remote?.displayDate ?? check?.asset?.updatedAt);
    final remoteSubtitleParts = <String>[
      if (remoteDateText.isNotEmpty) t.appUpdatePage.released(date: remoteDateText),
      if (check?.updateAvailable == true)
        (check?.message == 'same-version' ? t.appUpdatePage.sameVersionRefresh : t.appUpdatePage.updateAvailable)
      else
        t.appUpdatePage.upToDate,
    ];

    return Scaffold(
      appBar: basicLocalSendAppbar(t.appUpdatePage.title),
      body: ResponsiveListView(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.appUpdatePage.softwareUpdates, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(t.appUpdatePage.softwareUpdatesHint, style: Theme.of(context).textTheme.bodySmall),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline),
                    title: Text(t.appUpdatePage.currentVersion),
                    subtitle: Text(versionLabel),
                  ),
                  if (remote != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.new_releases_outlined),
                      title: Text(t.appUpdatePage.remote(version: remote.versionLabel, tag: remote.tagName)),
                      subtitle: Text(remoteSubtitleParts.join('\n')),
                    ),
                  if (_progress != null) ...[
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: 6),
                    Text(
                      (_progress ?? 0) >= 0.999
                          ? t.appUpdatePage.installing
                          : t.appUpdatePage.downloadProgress(percent: ((_progress ?? 0) * 100).toStringAsFixed(0)),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: _busy ? null : _checkUpdate,
                          child: _SingleLineButtonLabel(t.appUpdatePage.checkAgain),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: _busy || check == null || !check.updateAvailable || !_service.isSupported ? null : _install,
                          child: _SingleLineButtonLabel(
                            check?.updateAvailable == true ? t.appUpdatePage.downloadAndInstall : t.appUpdatePage.noUpdateNeeded,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (check?.release?.body.trim().isNotEmpty == true) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.appUpdatePage.releaseNotes, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    SelectableText(check!.release!.body.trim()),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> maybePromptAppUpdate(BuildContext context) async {
  final service = AppUpdateService();
  try {
    if (!service.isSupported) {
      return;
    }
    final result = await service.checkForUpdate();
    if (!result.updateAvailable || result.release == null) {
      return;
    }
    final skipped = await service.skippedVersion();
    if (skipped != null && skipped == result.release!.versionLabel && result.message != 'same-version') {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.appUpdatePage.newVersionAvailable(version: result.release!.versionLabel)),
        content: Text(_startupPromptBody(result)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: Text(t.appUpdatePage.skipVersion),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'later'),
            child: Text(t.appUpdatePage.later),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'update'),
            child: Text(t.appUpdatePage.updateNow),
          ),
        ],
      ),
    );
    if (!context.mounted) {
      return;
    }
    if (action == 'skip') {
      await service.skipVersion(result.release!.versionLabel);
    } else if (action == 'update') {
      await context.push(() => AppUpdatePage(service: service));
      return;
    }
  } catch (_) {
    // Startup check failures stay silent.
  } finally {
    service.dispose();
  }
}

String _startupPromptBody(AppUpdateCheckResult result) {
  final date = formatAppUpdateDate(result.release?.displayDate ?? result.asset?.updatedAt);
  final message = result.message == 'same-version' ? t.appUpdatePage.sameVersionRefresh : t.appUpdatePage.updateAvailable;
  if (date.isEmpty) {
    return message;
  }
  return '$message\n${t.appUpdatePage.released(date: date)}';
}

class _SingleLineButtonLabel extends StatelessWidget {
  final String text;

  const _SingleLineButtonLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
      ),
    );
  }
}
