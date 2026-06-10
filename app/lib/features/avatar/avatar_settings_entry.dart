import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:localsend_app/features/avatar/avatar_crop_page.dart';
import 'package:localsend_app/features/avatar/avatar_provider.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/widget/device_avatar.dart';
import 'package:localsend_app/widget/dialogs/text_field_tv.dart';
import 'package:refena_flutter/refena_flutter.dart';

class AvatarSettingsEntry extends StatelessWidget {
  final TextEditingController urlController;

  const AvatarSettingsEntry({
    required this.urlController,
  });

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final hasLocal = ref.watch(avatarLocalProvider);
    final previewDevice = ref.watch(deviceFullInfoProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DeviceAvatar(
              device: previewDevice,
              size: 56,
              useLocalAvatarFile: hasLocal,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async => _pickAndCrop(context, ref),
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(t.settingsTab.network.avatar.pickImage),
                  ),
                  if (hasLocal)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ref.notifier(avatarLocalProvider).clear(ref);
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(t.settingsTab.network.avatar.remove),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFieldTv(
          name: t.settingsTab.network.avatarUrl,
          controller: urlController,
          onChanged: (s) async {
            if (ref.read(avatarLocalProvider)) {
              await ref.notifier(avatarLocalProvider).clear(ref);
            }
            await ref.notifier(settingsProvider).setAvatarUrl(s);
          },
        ),
      ],
    );
  }

  Future<void> _pickAndCrop(BuildContext context, Ref ref) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) {
      return;
    }

    final bytes = await picked.readAsBytes();
    if (!context.mounted) {
      return;
    }

    final cropped = await AvatarCropPage.open(context: context, imageBytes: bytes);
    if (cropped == null || !context.mounted) {
      return;
    }

    urlController.text = '';
    await ref.notifier(settingsProvider).setAvatarUrl(null);
    await ref.notifier(avatarLocalProvider).saveCropped(cropped, ref);
  }
}
