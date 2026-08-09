import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';

/// Circular avatar: the user's picture when set, otherwise a brand-gradient
/// circle with a person icon. Used on the dashboard greeting and the Settings
/// profile card.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.picture,
    this.size = 42,
    this.iconSize,
    this.onTap,
  });

  /// Base64 data URI of the picture (`data:image/jpeg;base64,…`); empty
  /// renders the gradient fallback.
  final String picture;

  final double size;

  /// Icon size for the fallback person glyph (defaults to 55% of [size]).
  final double? iconSize;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (picture.isEmpty) {
      final gradient =
          Theme.of(context).extension<FinFlowTheme>()?.heroGradient ??
          const [AppColors.brandBright, AppColors.brand];
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.person_rounded,
          color: Colors.white,
          size: iconSize ?? size * 0.55,
        ),
      );
    } else {
      child = Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Image.memory(
          _decodePicture(picture),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }

    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }

  static Uint8List _decodePicture(String dataUri) {
    final comma = dataUri.indexOf(',');
    final base64 = comma >= 0 ? dataUri.substring(comma + 1) : dataUri;
    return base64Decode(base64);
  }
}
