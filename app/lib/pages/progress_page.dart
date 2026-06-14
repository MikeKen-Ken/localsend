import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:common/model/dto/file_dto.dart';
import 'package:common/model/file_status.dart';
import 'package:common/model/session_status.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/model/state/server/receiving_file.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/favorites.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/file_speed_helper.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/native/taskbar_helper.dart';
import 'package:localsend_app/util/ui/nav_bar_padding.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_app/widget/custom_progress_bar.dart';
import 'package:localsend_app/widget/dialogs/cancel_session_dialog.dart';
import 'package:localsend_app/widget/dialogs/error_dialog.dart';
import 'package:localsend_app/widget/file_thumbnail.dart';
import 'package:localsend_app/widget/session_peer_header.dart';
import 'package:path/path.dart' as path;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

class ProgressPage extends StatefulWidget {
  final bool showAppBar;
  final bool closeSessionOnClose;
  final String sessionId;

  const ProgressPage({
    required this.showAppBar,
    required this.closeSessionOnClose,
    required this.sessionId,
  });

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> with Refena {
  int _totalBytes = double.maxFinite.toInt();
  int _lastRemainingTimeUpdate = 0; // millis since epoch
  String? _remainingTime;
  List<FileDto> _files = []; // also contains declined files (files without token)
  Set<String> _selectedFiles = {};
  SessionStatus? _lastStatus;

  Timer? _wakelockPlusTimer;

  bool _advanced = false;

  @override
  void initState() {
    super.initState();

    // init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        unawaited(WakelockPlus.enable());
      } catch (_) {}

      // Periodically call WakelockPlus.enable() to keep the screen awake
      _wakelockPlusTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        final finished =
            ref.read(serverProvider)?.session?.files.values.map((e) => e.status).isFinishedOrSkipped ??
            ref.read(sendProvider)[widget.sessionId]?.files.values.map((e) => e.status).isFinishedOrSkipped ??
            true;
        if (finished) {
          timer.cancel();
          try {
            unawaited(WakelockPlus.disable());
          } catch (_) {}
        } else {
          try {
            unawaited(WakelockPlus.enable());
          } catch (_) {}
        }
      });

      setState(() {
        final receiveSession = ref.read(serverProvider)?.session;
        if (receiveSession != null) {
          _files = receiveSession.files.values.map((f) => f.file).toList();

          // We previously used f.token != null here, but this may not work on very fast networks.
          _selectedFiles = receiveSession.files.values.where((f) => f.status != FileStatus.skipped).map((f) => f.file.id).toSet();
        } else {
          final sendSession = ref.read(sendProvider)[widget.sessionId];
          if (sendSession != null) {
            _files = sendSession.files.values.map((f) => f.file).toList();
            _selectedFiles = sendSession.files.values.where((f) => f.status != FileStatus.skipped).map((f) => f.file.id).toSet();
          }
        }

        _totalBytes = _files.where((f) => _selectedFiles.contains(f.id)).fold(0, (prev, curr) => prev + curr.size);
      });
    });
  }

  void _exit({required bool closeSession}) async {
    final receiveSession = ref.read(serverProvider.select((s) => s?.session));
    final sendSession = ref.read(sendProvider)[widget.sessionId];
    final SessionStatus? status = receiveSession?.status ?? sendSession?.status;
    final keepSession = !closeSession && (status == SessionStatus.sending || status == SessionStatus.finishedWithErrors);
    final result = status == null || keepSession || await _askCancelConfirmation(status);

    if (result && mounted) {
      // ignore: unawaited_futures
      context.popUntilRoot();
    }
  }

  Future<bool> _askCancelConfirmation(SessionStatus status) async {
    final bool result = switch (status == SessionStatus.sending) {
      true => (await context.pushBottomSheet(() => const CancelSessionDialog())) == true,
      false => true,
    };
    if (result) {
      final receiveSession = ref.read(serverProvider)?.session;
      final sendState = ref.read(sendProvider)[widget.sessionId];

      if (receiveSession != null) {
        if (receiveSession.status == SessionStatus.sending) {
          ref.notifier(serverProvider).cancelSession();
        } else {
          ref.notifier(serverProvider).closeSession();
        }
      } else if (sendState != null) {
        if (sendState.status == SessionStatus.sending) {
          ref.notifier(sendProvider).cancelSession(widget.sessionId);
        } else {
          ref.notifier(sendProvider).closeSession(widget.sessionId);
        }
      }
    }
    return result;
  }

  List<ReceivingFile> _finishedReceiveFiles(ReceiveSessionState session) {
    return session.files.values.where((f) => f.status == FileStatus.finished).toList();
  }

  bool _canOpenReceivedFile(List<ReceivingFile> files) {
    return files.any((f) => f.path != null || (f.savedToGallery && defaultTargetPlatform == TargetPlatform.android));
  }

  bool _canSendReceivedFiles(List<ReceivingFile> files) {
    return files.any((f) => f.path != null && f.path!.isNotEmpty);
  }

  Future<void> _openReceivedEntry(ReceivingFile entry) async {
    if (entry.savedToGallery && defaultTargetPlatform == TargetPlatform.android) {
      await android_channel.openGallery();
      return;
    }

    final filePath = entry.path;
    if (filePath != null && mounted) {
      await openFile(context, entry.file.fileType, filePath);
    }
  }

  Future<void> _openReceivedFiles(ReceiveSessionState session) async {
    final files = _finishedReceiveFiles(session);
    final openable = files.where((f) => f.path != null || (f.savedToGallery && defaultTargetPlatform == TargetPlatform.android)).toList();
    if (openable.isEmpty) {
      return;
    }

    if (openable.length == 1) {
      await _openReceivedEntry(openable.first);
      return;
    }

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in openable)
              ListTile(
                title: Text(entry.desiredName ?? entry.file.fileName),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _openReceivedEntry(entry);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openReceiveFolder(ReceiveSessionState session, {String? fileName}) async {
    await openFolder(
      folderPath: session.destinationDirectory,
      fileName: fileName,
    );
  }

  Future<void> _sendReceivedFiles(ReceiveSessionState session) async {
    final paths = _finishedReceiveFiles(session).map((f) => f.path).whereType<String>().where((p) => p.isNotEmpty).toList();
    if (paths.isEmpty) {
      return;
    }

    ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction());
    await ref.redux(selectedSendingFilesProvider).dispatchAsync(
      AddFilesAction(
        files: paths.map(File.new),
        converter: CrossFileConverters.convertFile,
      ),
    );

    ref.notifier(serverProvider).closeSession();
    if (mounted) {
      // ignore: unawaited_futures
      context.pushRootImmediately(() => const HomePage(initialTab: HomeTab.send, appStart: false));
    }
  }

  @override
  void dispose() {
    super.dispose();
    _wakelockPlusTimer?.cancel();
    TaskbarHelper.clearProgressBar(); // ignore: discarded_futures
    try {
      WakelockPlus.disable(); // ignore: discarded_futures
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final progressNotifier = ref.watch(progressProvider);
    final currBytes = _files.fold<int>(
      0,
      (prev, curr) => prev + ((progressNotifier.getProgress(sessionId: widget.sessionId, fileId: curr.id) * curr.size).round()),
    );

    final receiveSession = ref.watch(serverProvider.select((s) => s?.session));
    final sendSession = ref.watch(sendProvider)[widget.sessionId];

    final SessionState? commonSessionState = receiveSession ?? sendSession;

    if (commonSessionState == null) {
      return Scaffold(
        body: Container(),
      );
    }

    final status = commonSessionState.status;

    if (status == SessionStatus.sending) {
      // ignore: discarded_futures
      TaskbarHelper.setProgressBar(currBytes, _totalBytes);
    } else if (status != _lastStatus) {
      _lastStatus = status;
      // ignore: discarded_futures
      TaskbarHelper.visualizeStatus(status);
    }

    final title = receiveSession != null ? t.progressPage.titleReceiving : t.progressPage.titleSending;
    final startTime = commonSessionState.startTime;
    final endTime = commonSessionState.endTime;
    final int? speedInBytes;
    if (startTime != null && currBytes >= 500 * 1024) {
      speedInBytes = getFileSpeed(start: startTime, end: endTime ?? DateTime.now().millisecondsSinceEpoch, bytes: currBytes);

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastRemainingTimeUpdate >= 1000) {
        _remainingTime = getRemainingTime(bytesPerSeconds: speedInBytes, remainingBytes: _totalBytes - currBytes);
        _lastRemainingTimeUpdate = now;
      }
    } else {
      speedInBytes = null;
    }

    final fileStatusMap = receiveSession?.files.map((k, f) => MapEntry(k, f.status)) ?? sendSession!.files.map((k, f) => MapEntry(k, f.status));
    final finishedCount = fileStatusMap.values.where((s) => s == FileStatus.finished).length;
    final hasFailedFiles = sendSession != null && fileStatusMap.values.any((s) => s == FileStatus.failed);
    final isReceiveFinished =
        receiveSession != null && (status == SessionStatus.finished || status == SessionStatus.finishedWithErrors);
    final finishedReceiveFiles = isReceiveFinished ? _finishedReceiveFiles(receiveSession!) : <ReceivingFile>[];
    final canOpenReceived = finishedReceiveFiles.isNotEmpty && _canOpenReceivedFile(finishedReceiveFiles);
    final canOpenReceiveFolder = isReceiveFinished && checkPlatformWithFileSystem() && !checkPlatform([TargetPlatform.iOS]);
    final canSendReceived = finishedReceiveFiles.isNotEmpty && _canSendReceivedFiles(finishedReceiveFiles);
    final singleReceiveFileName = finishedReceiveFiles.length == 1 && finishedReceiveFiles.first.path != null
        ? path.basename(finishedReceiveFiles.first.path!)
        : null;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // Already popped.
          // Because the user cannot pop this page, we can safely assume that all sessions are closed if they should be.
          return;
        }
        _exit(closeSession: widget.closeSessionOnClose);
      },
      canPop: false,
      child: Scaffold(
        appBar: widget.showAppBar ? basicLocalSendAppbar(title) : null,
        body: Stack(
          children: [
            ListView.builder(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 20,
                bottom: 150 + getNavBarPadding(context),
                left: 15,
                right: 30,
              ),
              itemCount: _files.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  final peerDevice = receiveSession?.sender ?? sendSession?.target;
                  final peerName = receiveSession != null
                      ? receiveSession.senderAlias
                      : peerDevice == null
                      ? null
                      : ref.watch(favoritesProvider.select((state) => state.findDevice(peerDevice)))?.alias ?? peerDevice.alias;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!widget.showAppBar)
                          Text(title, style: Theme.of(context).textTheme.titleLarge),
                        if (peerDevice != null && peerName != null)
                          SessionPeerHeader(device: peerDevice, displayName: peerName),
                        if (checkPlatformWithFileSystem() && receiveSession != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${t.settingsTab.receive.destination}: ',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                  TextSpan(
                                    text: receiveSession.destinationDirectory,
                                    style: TextStyle(
                                      color: checkPlatform([TargetPlatform.iOS]) ? Colors.grey : Theme.of(context).colorScheme.primary,
                                    ),
                                    recognizer: checkPlatform([TargetPlatform.iOS])
                                        ? null
                                        : (TapGestureRecognizer()
                                            ..onTap = () async {
                                              await openFolder(folderPath: receiveSession.destinationDirectory);
                                            }),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }

                if (index == 1) {
                  // error card
                  final errorMessage = sendSession?.errorMessage;
                  if (errorMessage == null) {
                    return Container();
                  }

                  return SelectableText(errorMessage, style: TextStyle(color: Theme.of(context).colorScheme.warning));
                }

                final file = _files[index - 2];
                final String fileName = receiveSession?.files[file.id]?.desiredName ?? file.fileName;

                final fileStatus = fileStatusMap[file.id]!;
                final savedToGallery = receiveSession?.files[file.id]?.savedToGallery ?? false;

                final String? filePath;
                if (receiveSession != null && fileStatus == FileStatus.finished && !savedToGallery) {
                  filePath = receiveSession.files[file.id]!.path;
                } else if (sendSession != null) {
                  filePath = sendSession.files[file.id]!.path;
                } else {
                  filePath = null;
                }

                final String? errorMessage;
                if (receiveSession != null) {
                  errorMessage = receiveSession.files[file.id]!.errorMessage;
                } else if (sendSession != null) {
                  errorMessage = sendSession.files[file.id]!.errorMessage;
                } else {
                  errorMessage = null;
                }

                final Uint8List? thumbnail;
                final AssetEntity? asset;
                if (sendSession != null) {
                  thumbnail = sendSession.files[file.id]!.thumbnail;
                  asset = sendSession.files[file.id]!.asset;
                } else {
                  thumbnail = null;
                  asset = null;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: InkWell(
                    splashColor: Colors.transparent,
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    onTap: filePath != null && receiveSession != null ? () async => openFile(context, file.fileType, filePath!) : null,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SmartFileThumbnail(
                          bytes: thumbnail,
                          asset: asset,
                          path: filePath,
                          fileType: file.fileType,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      fileName,
                                      style: const TextStyle(fontSize: 16, height: 1),
                                      maxLines: 1,
                                      overflow: TextOverflow.fade,
                                      softWrap: false,
                                    ),
                                  ),
                                  Text(' (${file.size.asReadableFileSize})', style: const TextStyle(fontSize: 16, height: 1)),
                                ],
                              ),
                              const SizedBox(height: 5),
                              if (fileStatus == FileStatus.sending)
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: CustomProgressBar(
                                    progress: progressNotifier.getProgress(sessionId: widget.sessionId, fileId: file.id),
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        savedToGallery ? t.progressPage.savedToGallery : fileStatus.label,
                                        style: TextStyle(color: fileStatus.getColor(context), height: 1),
                                      ),
                                    ),
                                    if (errorMessage != null) ...[
                                      const SizedBox(width: 5),
                                      InkWell(
                                        onTap: () async {
                                          await showDialog(
                                            context: context,
                                            builder: (_) => ErrorDialog(
                                              error: errorMessage!,
                                              onRetry: sendSession != null && fileStatus == FileStatus.failed
                                                  ? () async {
                                                      await ref
                                                          .notifier(sendProvider)
                                                          .sendFile(
                                                            sessionId: widget.sessionId,
                                                            isolateIndex: 0,
                                                            file: sendSession.files[file.id]!,
                                                            isRetry: true,
                                                          );
                                                    }
                                                  : null,
                                            ),
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 5),
                                          child: Icon(Icons.info, color: Theme.of(context).colorScheme.warning, size: 20),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        ),
                        if (sendSession != null && fileStatus == FileStatus.failed)
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: () async {
                              await ref
                                  .notifier(sendProvider)
                                  .sendFile(
                                    sessionId: widget.sessionId,
                                    isolateIndex: 0,
                                    file: sendSession.files[file.id]!,
                                    isRetry: true,
                                  );
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 10, bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 15, right: 15, bottom: 5, top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            status.getLabel(
                              remainingTime: _remainingTime ?? '-',
                            ),
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(height: 5),
                          TweenAnimationBuilder(
                            tween: Tween<double>(begin: 0, end: _totalBytes == 0 ? 0 : currBytes / _totalBytes),
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            builder: (context, value, child) {
                              return CustomProgressBar(
                                progress: value,
                                borderRadius: 5,
                              );
                            },
                          ),
                          AnimatedCrossFade(
                            crossFadeState: _advanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 200),
                            alignment: Alignment.topLeft,
                            firstChild: Container(),
                            secondChild: Padding(
                              padding: const EdgeInsets.only(top: 10, bottom: 5),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.progressPage.total.count(
                                      curr: finishedCount,
                                      n: _selectedFiles.length,
                                    ),
                                  ),
                                  Text(
                                    t.progressPage.total.size(
                                      curr: currBytes.asReadableFileSize,
                                      n: _totalBytes == double.maxFinite.toInt() ? '-' : _totalBytes.asReadableFileSize,
                                    ),
                                  ),
                                  if (speedInBytes != null)
                                    Text(
                                      t.progressPage.total.speed(
                                        speed: speedInBytes.asReadableFileSize,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (isReceiveFinished) ...[
                            const SizedBox(height: 5),
                            Wrap(
                              alignment: WrapAlignment.end,
                              children: [
                                if (canOpenReceived)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                                    onPressed: () async => await _openReceivedFiles(receiveSession!),
                                    icon: const Icon(Icons.open_in_new),
                                    label: Text(t.progressPage.actions.openFile),
                                  ),
                                if (canOpenReceiveFolder)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                                    onPressed: () async => await _openReceiveFolder(receiveSession!, fileName: singleReceiveFileName),
                                    icon: const Icon(Icons.folder_open),
                                    label: Text(t.progressPage.actions.openFolder),
                                  ),
                                if (canSendReceived)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                                    onPressed: () async => await _sendReceivedFiles(receiveSession!),
                                    icon: const Icon(Icons.send),
                                    label: Text(t.progressPage.actions.sendTo),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                                onPressed: () {
                                  setState(() => _advanced = !_advanced);
                                },
                                icon: const Icon(Icons.info),
                                label: Text(_advanced ? t.general.hide : t.general.advanced),
                              ),
                              if (status == SessionStatus.finishedWithErrors && hasFailedFiles)
                                TextButton.icon(
                                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                                  onPressed: () async {
                                    await ref.notifier(sendProvider).retryFailedFiles(widget.sessionId);
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: Text(t.general.retry),
                                ),
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                                onPressed: () => _exit(closeSession: true),
                                icon: Icon(status == SessionStatus.sending ? Icons.close : Icons.check_circle),
                                label: Text(
                                  status == SessionStatus.sending ? t.general.cancel : t.general.done,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            checkPlatform([TargetPlatform.macOS])
                ? Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 40,
                    child: MoveWindow(),
                  )
                : SizedBox(),
          ],
        ),
      ),
    );
  }
}

extension on FileStatus {
  String get label {
    switch (this) {
      case FileStatus.queue:
        return t.general.queue;
      case FileStatus.skipped:
        return t.general.skipped;
      case FileStatus.sending:
        return ''; // progress bar will be showed here
      case FileStatus.failed:
        return t.general.error;
      case FileStatus.finished:
        return t.general.done;
    }
  }

  Color getColor(BuildContext context) {
    switch (this) {
      case FileStatus.queue:
        return Theme.of(context).colorScheme.primary;
      case FileStatus.skipped:
        return Colors.grey;
      case FileStatus.sending:
        return Theme.of(context).colorScheme.primary;
      case FileStatus.failed:
        return Theme.of(context).colorScheme.warning;
      case FileStatus.finished:
        return Theme.of(context).colorScheme.primary;
    }
  }
}

extension on SessionStatus {
  String getLabel({required String remainingTime}) {
    switch (this) {
      case SessionStatus.sending:
        return t.progressPage.total.title.sending(
          time: remainingTime,
        );
      case SessionStatus.finished:
        return t.general.finished;
      case SessionStatus.finishedWithErrors:
        return t.progressPage.total.title.finishedError;
      case SessionStatus.canceledBySender:
        return t.progressPage.total.title.canceledSender;
      case SessionStatus.canceledByReceiver:
        return t.progressPage.total.title.canceledReceiver;
      default:
        return '';
    }
  }
}
