import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:localsend_app/features/app_update/windows_updater_scripts.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppUpdateInstaller {
  bool get isSupported {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isWindows;
  }

  Future<Directory> extractZip(File zipFile) async {
    final tempRoot = await getTemporaryDirectory();
    final out = Directory(p.join(tempRoot.path, 'localsend_update_${DateTime.now().millisecondsSinceEpoch}'));
    if (await out.exists()) {
      await out.delete(recursive: true);
    }
    await out.create(recursive: true);
    await extractFileToDisk(zipFile.path, out.path);
    return resolveWindowsPayloadRoot(out);
  }

  @visibleForTesting
  static Future<Directory> resolveWindowsPayloadRoot(
    Directory extracted, {
    String? exeFileName,
  }) async {
    final exeName = exeFileName ?? (Platform.isWindows ? p.basename(Platform.resolvedExecutable) : 'localsend_app.exe');
    final direct = File(p.join(extracted.path, exeName));
    if (await direct.exists()) {
      return extracted;
    }
    final dirs = (await extracted.list().toList()).whereType<Directory>().toList();
    if (dirs.length == 1) {
      final nested = File(p.join(dirs.first.path, exeName));
      if (await nested.exists()) {
        return dirs.first;
      }
    }
    for (final dir in dirs) {
      final nested = File(p.join(dir.path, exeName));
      if (await nested.exists()) {
        return dir;
      }
    }
    return extracted;
  }

  Future<void> installAndroidApk(File apkFile) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('APK installation is supported only on Android');
    }
    final allowed = await android_channel.canRequestPackageInstalls();
    if (!allowed) {
      await android_channel.openUnknownSourcesSettings();
      throw StateError('Allow installation from unknown sources, then try the update again');
    }
    await android_channel.installApk(apkFile.path);
  }

  Future<void> applyWindowsZipUpdate(Directory extractedDir) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('ZIP self-update is supported only on Windows');
    }
    final exePath = Platform.resolvedExecutable;
    final installDir = File(exePath).parent.path;
    final payloadDir = await resolveWindowsPayloadRoot(extractedDir);
    final scriptFile = File(p.join(Directory.systemTemp.path, 'localsend_updater_$pid.ps1'));
    await scriptFile.writeAsBytes(utf8.encode('\uFEFF$windowsUpdaterScript'), flush: true);
    final relaunchFile = File(p.join(Directory.systemTemp.path, 'localsend_relaunch_$pid.ps1'));
    await relaunchFile.writeAsBytes(utf8.encode('\uFEFF$windowsRelaunchScript'), flush: true);

    await _startDetachedPowershell(
      scriptPath: scriptFile.path,
      extraArgs: [
        '-InstallDir',
        installDir,
        '-SourceDir',
        payloadDir.path,
        '-ExePath',
        exePath,
        '-TargetPid',
        '$pid',
        '-SkipLaunch',
      ],
    );
    await _startDetachedPowershell(
      scriptPath: relaunchFile.path,
      extraArgs: [
        '-InstallDir',
        installDir,
        '-ExePath',
        exePath,
        '-TargetPid',
        '$pid',
      ],
    );

    await Future<void>.delayed(const Duration(milliseconds: 800));
    exit(0);
  }
}

Future<void> _startDetachedPowershell({
  required String scriptPath,
  required List<String> extraArgs,
}) {
  return Process.start(
    'cmd.exe',
    [
      '/c',
      'start',
      '',
      '/min',
      'powershell.exe',
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      scriptPath,
      ...extraArgs,
    ],
    mode: ProcessStartMode.detached,
    runInShell: false,
  );
}
