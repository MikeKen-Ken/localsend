import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:collection/collection.dart';
import 'package:common/model/device.dart';
import 'package:common/model/session_status.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/pages/selected_files_page.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/pages/troubleshoot_page.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/features/avatar/avatar_provider.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/tv_provider.dart';
import 'package:localsend_app/util/favorites.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/big_button.dart';
import 'package:localsend_app/widget/custom_icon_button.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_app/pages/qr_scan_page.dart';
import 'package:localsend_app/widget/dialogs/qr_share_dialog.dart';
import 'package:localsend_app/widget/dialogs/send_mode_help_dialog.dart';
import 'package:localsend_app/widget/selected_files_preview.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:localsend_app/widget/list_tile/device_placeholder_list_tile.dart';
import 'package:localsend_app/widget/opacity_slideshow.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_app/widget/responsive_wrap_view.dart';
import 'package:localsend_app/widget/rotating_widget.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

const _horizontalPadding = 15.0;
final _options = FilePickerOption.getOptionsForPlatform();

class SendTab extends StatelessWidget {
  const SendTab();

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder(
      provider: (ref) => sendTabVmProvider,
      init: (context) async => context.global.dispatchAsync(SendTabInitAction(context)), // ignore: discarded_futures
      builder: (context, vm) {
        final sizingInformation = SizingInformation(MediaQuery.sizeOf(context).width);
        final buttonWidth = sizingInformation.isDesktop ? BigButton.desktopWidth : BigButton.mobileWidth;
        final ref = context.ref;
        final myDevice = ref.watch(deviceFullInfoProvider);
        final avatarRevision = ref.watch(avatarLocalProvider);
        final avatarBytes = ref.watch(avatarLocalBytesProvider);
        final hasLocalAvatar = avatarRevision > 0 || avatarBytes != null;
        return Stack(
          children: [
            ResponsiveListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
                  child: Text(
                    t.sendTab.thisDevice,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 10, left: _horizontalPadding, right: _horizontalPadding),
                  child: DeviceListTile(
                    device: myDevice,
                    useLocalAvatarFile: hasLocalAvatar,
                    localAvatarRevision: avatarRevision,
                  ),
                ),
                if (vm.selectedFiles.isEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
                    child: Text(
                      t.sendTab.selection.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ResponsiveWrapView(
                    outerHorizontalPadding: 15,
                    outerVerticalPadding: 10,
                    childPadding: 10,
                    minChildWidth: buttonWidth,
                    children: _options.map((option) {
                      return BigButton(
                        icon: option.icon,
                        label: option.label,
                        filled: false,
                        onTap: () async => ref.global.dispatchAsync(
                          PickFileAction(
                            option: option,
                            context: context,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ] else ...[
                  Card(
                    margin: const EdgeInsets.only(bottom: 10, left: _horizontalPadding, right: _horizontalPadding),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 15, top: 5, bottom: 15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                t.sendTab.selection.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              _QrShareLimitButton(
                                onShare: (maxUses) async {
                                  await QrShareDialog.open(
                                    context: context,
                                    files: vm.selectedFiles,
                                    maxUses: maxUses,
                                  );
                                },
                              ),
                              const SizedBox(width: 5),
                              CustomIconButton(
                                onPressed: () => ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction()),
                                child: Icon(Icons.close, color: Theme.of(context).colorScheme.secondary),
                              ),
                              const SizedBox(width: 5),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(t.sendTab.selection.files(files: vm.selectedFiles.length)),
                          Text(t.sendTab.selection.size(size: vm.selectedFiles.fold(0, (prev, curr) => prev + curr.size).asReadableFileSize)),
                          const SizedBox(height: 10),
                          SelectedFilesPreview(files: vm.selectedFiles),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                                ),
                                onPressed: () async {
                                  await context.push(() => const SelectedFilesPage());
                                },
                                child: Text(t.general.edit),
                              ),
                              const SizedBox(width: 15),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                ),
                                onPressed: () async {
                                  if (_options.length == 1) {
                                    // open directly
                                    await ref.global.dispatchAsync(
                                      PickFileAction(
                                        option: _options.first,
                                        context: context,
                                      ),
                                    );
                                    return;
                                  }
                                  await AddFileDialog.open(
                                    context: context,
                                    options: _options,
                                  );
                                },
                                icon: const Icon(Icons.add),
                                label: Text(t.general.add),
                              ),
                              const SizedBox(width: 15),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                Row(
                  children: [
                    const SizedBox(width: _horizontalPadding),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(t.sendTab.nearbyDevices, style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ScanButton(
                      ips: vm.localIps,
                    ),
                    if (checkPlatformWithCamera() && !ref.watch(tvProvider))
                      Tooltip(
                        message: t.dialogs.qr.scanTitle,
                        child: CustomIconButton(
                          onPressed: () async => QrScanPage.open(context),
                          child: const Icon(Icons.qr_code_scanner),
                        ),
                      ),
                    Tooltip(
                      message: t.sendTab.manualSending,
                      child: CustomIconButton(
                        onPressed: () async => vm.onTapAddress(context),
                        child: const Icon(Icons.ads_click),
                      ),
                    ),
                    Tooltip(
                      message: t.dialogs.favoriteDialog.title,
                      child: CustomIconButton(
                        onPressed: () async => await vm.onTapFavorite(context),
                        child: const Icon(Icons.favorite),
                      ),
                    ),
                    _SendModeButton(
                      onSelect: (mode) async => vm.onTapSendMode(context, mode),
                    ),
                  ],
                ),
                if (vm.nearbyDevices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10, left: _horizontalPadding, right: _horizontalPadding),
                    child: Opacity(
                      opacity: 0.3,
                      child: DevicePlaceholderListTile(),
                    ),
                  ),
                ...vm.nearbyDevices.map((device) {
                  final favoriteEntry = vm.favoriteDevices.findDevice(device);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10, left: _horizontalPadding, right: _horizontalPadding),
                    child: Hero(
                      tag: 'device-${device.ip}',
                      child: vm.sendMode == SendMode.multiple
                          ? _MultiSendDeviceListTile(
                              device: device,
                              isFavorite: favoriteEntry != null,
                              nameOverride: favoriteEntry?.alias,
                              vm: vm,
                            )
                          : DeviceListTile(
                              device: device,
                              isFavorite: favoriteEntry != null,
                              nameOverride: favoriteEntry?.alias,
                              onFavoriteTap: () async => await vm.onToggleFavorite(context, device),
                              onTap: () async => await vm.onTapDevice(context, device),
                            ),
                    ),
                  );
                }),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () async {
                      await context.push(() => const TroubleshootPage());
                    },
                    child: Text(t.troubleshootPage.title),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
                  child: Consumer(
                    builder: (context, ref) {
                      final animations = ref.watch(animationProvider);
                      return OpacitySlideshow(
                        durationMillis: 6000,
                        running: animations,
                        children: [
                          Text(
                            t.sendTab.help,
                            style: const TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                          if (checkPlatformCanReceiveShareIntent())
                            Text(
                              t.sendTab.shareIntentInfo,
                              style: const TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 50),
              ],
            ),
            // make the top draggable on Desktop
            checkPlatform([TargetPlatform.macOS])
                ? SizedBox(height: 50, child: MoveWindow())
                : SizedBox(
                    height: 0,
                    width: 0,
                  ),
          ],
        );
      },
    );
  }
}

/// Converts persisted QR share limit (0 = unlimited) to [maxUses] for web send.
int? _qrShareMaxUsesFromPersistence(int value) => value == 0 ? null : value;

String _qrShareLimitLabel(int value) {
  return switch (value) {
    0 => '∞',
    _ => '×$value',
  };
}

/// Selects how many times a QR share link can be used, then opens the QR dialog.
class _QrShareLimitButton extends StatefulWidget {
  final Future<void> Function(int? maxUses) onShare;

  const _QrShareLimitButton({required this.onShare});

  @override
  State<_QrShareLimitButton> createState() => _QrShareLimitButtonState();
}

class _QrShareLimitButtonState extends State<_QrShareLimitButton> with Refena {
  late int _maxUsesSetting;

  static const _options = [1, 3, 5, 0];

  @override
  void initState() {
    super.initState();
    _maxUsesSetting = ref.read(persistenceProvider).getQrShareMaxUses();
  }

  Future<void> _setMaxUses(int value) async {
    setState(() => _maxUsesSetting = value);
    await ref.read(persistenceProvider).setQrShareMaxUses(value);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircularPopupButton<int>(
          tooltip: t.dialogs.qr.useLimit,
          onSelected: _setMaxUses,
          itemBuilder: (_) => _options.map((value) {
            return PopupMenuItem(
              value: value,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Visibility(
                    visible: _maxUsesSetting == value,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: const Icon(Icons.check_circle),
                  ),
                  const SizedBox(width: 10),
                  Text(switch (value) {
                    1 => t.dialogs.qr.useLimitSingle,
                    3 => t.dialogs.qr.useLimitTriple,
                    5 => t.dialogs.qr.useLimitFive,
                    _ => t.dialogs.qr.useLimitUnlimited,
                  }),
                ],
              ),
            );
          }).toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              _qrShareLimitLabel(_maxUsesSetting),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        Tooltip(
          message: t.dialogs.qr.shareTitle,
          child: CustomIconButton(
            onPressed: () => widget.onShare(_qrShareMaxUsesFromPersistence(_maxUsesSetting)),
            child: Icon(Icons.qr_code, color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ],
    );
  }
}

/// A button that opens a popup menu to select [T].
/// This is used for the scan button and the send mode button.
class _CircularPopupButton<T> extends StatelessWidget {
  final String tooltip;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final Widget child;

  const _CircularPopupButton({
    required this.tooltip,
    required this.onSelected,
    required this.itemBuilder,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9999),
      child: Material(
        type: MaterialType.transparency,
        child: DividerTheme(
          data: DividerThemeData(
            color: Theme.of(context).brightness == Brightness.light ? Colors.teal.shade100 : Colors.grey.shade700,
          ),
          child: PopupMenuButton(
            offset: const Offset(0, 40),
            onSelected: onSelected,
            tooltip: tooltip,
            itemBuilder: itemBuilder,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The scan button that uses [_CircularPopupButton].
class _ScanButton extends StatelessWidget {
  final List<String> ips;

  const _ScanButton({
    required this.ips,
  });

  @override
  Widget build(BuildContext context) {
    final (scanningFavorites, scanningIps) = context.ref.watch(nearbyDevicesProvider.select((s) => (s.runningFavoriteScan, s.runningIps)));
    final animations = context.ref.watch(animationProvider);

    final spinning = (scanningFavorites || scanningIps.isNotEmpty) && animations;
    final iconColor = !animations && scanningIps.isNotEmpty ? Theme.of(context).colorScheme.warning : null;

    if (ips.length <= StartSmartScan.maxInterfaces) {
      return Tooltip(
        message: t.sendTab.scan,
        child: RotatingWidget(
          duration: const Duration(seconds: 2),
          spinning: spinning,
          reverse: true,
          child: CustomIconButton(
            onPressed: () async {
              context.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
              await context.global.dispatchAsync(StartSmartScan(forceLegacy: true));
            },
            child: Icon(Icons.sync, color: iconColor),
          ),
        ),
      );
    }

    return _CircularPopupButton(
      tooltip: t.sendTab.scan,
      onSelected: (ip) async {
        context.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
        await context.global.dispatchAsync(StartLegacySubnetScan(subnets: [ip]));
      },
      itemBuilder: (_) {
        return [
          ...ips.map(
            (ip) => PopupMenuItem(
              value: ip,
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RotatingSyncIcon(ip),
                  const SizedBox(width: 10),
                  Text(ip),
                ],
              ),
            ),
          ),
        ];
      },
      child: RotatingWidget(
        duration: const Duration(seconds: 2),
        spinning: spinning,
        reverse: true,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.sync, color: iconColor),
        ),
      ),
    );
  }
}

/// A separate widget, so it gets the latest data from provider.
class _RotatingSyncIcon extends StatelessWidget {
  final String ip;

  const _RotatingSyncIcon(this.ip);

  @override
  Widget build(BuildContext context) {
    final scanningIps = context.ref.watch(nearbyDevicesProvider.select((s) => s.runningIps));
    return RotatingWidget(
      duration: const Duration(seconds: 2),
      spinning: scanningIps.contains(ip),
      reverse: true,
      child: const Icon(Icons.sync),
    );
  }
}

class _SendModeButton extends StatelessWidget {
  final void Function(SendMode mode) onSelect;

  const _SendModeButton({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return _CircularPopupButton<int>(
      tooltip: t.sendTab.sendMode,
      onSelected: (mode) async {
        switch (mode) {
          case 0:
            onSelect(SendMode.single);
            break;
          case 1:
            onSelect(SendMode.multiple);
            break;
          case 2:
            onSelect(SendMode.link);
            break;
          case -1:
            await showDialog(context: context, builder: (_) => const SendModeHelpDialog());
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(
                builder: (context, ref) {
                  final sendMode = ref.watch(settingsProvider.select((s) => s.sendMode));
                  return Visibility(
                    visible: sendMode == SendMode.single,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: const Icon(Icons.check_circle),
                  );
                },
              ),
              const SizedBox(width: 10),
              Text(t.sendTab.sendModes.single),
            ],
          ),
        ),
        PopupMenuItem(
          value: 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(
                builder: (context, ref) {
                  final sendMode = ref.watch(settingsProvider.select((s) => s.sendMode));
                  return Visibility(
                    visible: sendMode == SendMode.multiple,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: const Icon(Icons.check_circle),
                  );
                },
              ),
              const SizedBox(width: 10),
              Text(t.sendTab.sendModes.multiple),
            ],
          ),
        ),
        PopupMenuItem(
          value: 2,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Icon(Icons.check_circle),
              ),
              const SizedBox(width: 10),
              Text(t.sendTab.sendModes.link),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: -1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Directionality(
                textDirection: TextDirection.ltr,
                child: Icon(Icons.help),
              ),
              const SizedBox(width: 10),
              Text(t.sendTab.sendModeHelp),
            ],
          ),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.settings),
      ),
    );
  }
}

/// An advanced list tile which shows the progress of the file transfer.
class _MultiSendDeviceListTile extends StatelessWidget {
  final Device device;
  final bool isFavorite;
  final String? nameOverride;
  final SendTabVm vm;

  const _MultiSendDeviceListTile({
    required this.device,
    required this.isFavorite,
    required this.nameOverride,
    required this.vm,
  });

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final session = ref.watch(sendProvider).values.firstWhereOrNull((s) => s.target.ip == device.ip);
    final double? progress;
    if (session != null) {
      final files = session.files.values.where((f) => f.token != null);
      final progressNotifier = ref.watch(progressProvider);
      final currBytes = files.fold<int>(
        0,
        (prev, curr) => prev + ((progressNotifier.getProgress(sessionId: session.sessionId, fileId: curr.file.id) * curr.file.size).round()),
      );
      final totalBytes = files.fold<int>(0, (prev, curr) => prev + curr.file.size);
      progress = totalBytes == 0 ? 0 : currBytes / totalBytes;
    } else {
      progress = null;
    }
    return DeviceListTile(
      device: device,
      info: session?.status.humanString,
      progress: progress,
      isFavorite: isFavorite,
      nameOverride: nameOverride,
      onFavoriteTap: device.ip == null ? null : () async => await vm.onToggleFavorite(context, device),
      onTap: () async => await vm.onTapDeviceMultiSend(context, device),
    );
  }
}

extension on SessionStatus {
  String? get humanString {
    switch (this) {
      case SessionStatus.waiting:
        return t.sendPage.waiting;
      case SessionStatus.recipientBusy:
        return t.sendPage.busy;
      case SessionStatus.declined:
        return t.sendPage.rejected;
      case SessionStatus.tooManyAttempts:
        return t.sendPage.tooManyAttempts;
      case SessionStatus.sending:
        return null;
      case SessionStatus.finished:
        return t.general.finished;
      case SessionStatus.finishedWithErrors:
        return t.progressPage.total.title.finishedError;
      case SessionStatus.canceledBySender:
        return t.progressPage.total.title.canceledSender;
      case SessionStatus.canceledByReceiver:
        return t.progressPage.total.title.canceledReceiver;
    }
  }
}
