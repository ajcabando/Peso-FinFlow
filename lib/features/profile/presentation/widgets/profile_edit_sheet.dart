import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../providers/profile_providers.dart';

/// Bottom sheet for editing the user profile: display name and avatar photo.
Future<void> showProfileEditSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ProfileEditSheet(),
  );
}

class _ProfileEditSheet extends ConsumerStatefulWidget {
  const _ProfileEditSheet();

  @override
  ConsumerState<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends ConsumerState<_ProfileEditSheet> {
  late final TextEditingController _nameController;
  String _picture = '';
  bool _saving = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider);
    _nameController = TextEditingController(text: profile.name);
    _picture = profile.picture;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickPicture() async {
    const typeGroup = XTypeGroup(
      label: 'Profile picture',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'heic', 'heif', 'gif', 'bmp'],
      uniformTypeIdentifiers: ['public.image'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null || !mounted) return;

    setState(() => _picking = true);
    try {
      final bytes = await file.readAsBytes();
      final jpeg = await _encodeProfilePicture(bytes);
      if (jpeg == null) {
        if (mounted) {
          context.showSnack(
            "Couldn't read that image — try a JPG or PNG.",
          );
        }
        return;
      }
      setState(
        () => _picture = 'data:image/jpeg;base64,${base64Encode(jpeg)}',
      );
    } on Exception {
      if (mounted) {
        context.showSnack("Couldn't read that image — try a JPG or PNG.");
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final controller = ref.read(profileProvider.notifier);
      await controller.setName(_nameController.text);
      if (_picture != ref.read(profileProvider).picture) {
        await controller.setPicture(_picture);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated')));
    } on Exception {
      if (mounted) {
        setState(() => _saving = false);
        context.showSnack('Could not save your profile.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit profile',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'How should FinFlow greet you?',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: GestureDetector(
                onTap: _picking ? null : _pickPicture,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    ProfileAvatar(picture: _picture, size: 96, iconSize: 44),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: _picking
                          ? Padding(
                              padding: const EdgeInsets.all(7),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : Icon(
                              Icons.photo_camera_outlined,
                              size: 15,
                              color: theme.colorScheme.onPrimary,
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_picture.isNotEmpty)
              TextButton(
                onPressed: _picking
                    ? null
                    : () => setState(() => _picture = ''),
                child: const Text('Remove photo'),
              ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              controller: _nameController,
              label: 'Your name',
              hintText: 'e.g. Alain',
              prefixIcon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: _saving ? 'Saving…' : 'Save profile',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// Decodes [bytes] with Flutter's native codec (handles HEIC and friends),
/// resizes the frame to fit a 384px box, and re-encodes as a compact JPEG so
/// the stored data URI stays well under the 100 KB per-op sync limit.
Future<Uint8List?> _encodeProfilePicture(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final source = frame.image;
  try {
    const maxDim = 384.0;
    final scale = (source.width > source.height
            ? maxDim / source.width
            : maxDim / source.height)
        .clamp(0.1, 1.0);
    final width = (source.width * scale).round().clamp(1, maxDim.toInt());
    final height = (source.height * scale).round().clamp(1, maxDim.toInt());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      source,
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final resized = await recorder.endRecording().toImage(width, height);
    try {
      final rgba = await resized.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rgba == null) return null;
      final dartImage = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgba.buffer,
        order: img.ChannelOrder.rgba,
      );
      return Uint8List.fromList(img.encodeJpg(dartImage, quality: 85));
    } finally {
      resized.dispose();
    }
  } finally {
    source.dispose();
  }
}
