import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/memory_models.dart';
import '../../../core/services/app_icon_cache.dart';
import '../../../core/theme/theme.dart';

class HomeContinueCard extends StatelessWidget {
  final Memory? memory;
  final IconData? icon;
  final String? title;
  final String? subtitle;
  final bool isDark;
  final VoidCallback? onTap;

  const HomeContinueCard({
    super.key,
    this.memory,
    this.icon,
    this.title,
    this.subtitle,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final type = memory?.type ?? 'activity';
    final typeColor = AppTheme.getTypeColor(type);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    Widget imageOrIcon;
    final imgPath = memory?.imagePath;
    final srcPkg = memory?.sourcePackage;
    if (memory?.imageBase64 != null && memory!.imageBase64!.trim().isNotEmpty) {
      imageOrIcon = Image.memory(
        base64Decode(memory!.imageBase64!.trim()),
        fit: BoxFit.cover,
        cacheWidth: 280,
        cacheHeight: 180,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(typeColor),
      );
    } else if (imgPath != null && imgPath.trim().isNotEmpty) {
      final file = File(imgPath.trim());
      imageOrIcon = Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 280,
        cacheHeight: 180,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(typeColor),
      );
    } else if (srcPkg != null && srcPkg.trim().isNotEmpty) {
      imageOrIcon = Center(
        child: AppIconWidget(
          packageName: srcPkg.trim(),
          size: 40,
          fallbackIcon: _buildFallbackIcon(typeColor),
        ),
      );
    } else if (icon != null) {
      imageOrIcon = Center(child: Icon(icon, color: typeColor, size: 30));
    } else {
      imageOrIcon = Center(child: _buildFallbackIcon(typeColor));
    }

    final String displayTitle = title != null && title!.isNotEmpty
        ? title!
        : (memory != null && memory!.title.trim().isNotEmpty
            ? memory!.title.trim()
            : type.toUpperCase());

    final String displaySubtitle = subtitle != null && subtitle!.isNotEmpty
        ? subtitle!
        : type.replaceAll('_', ' ').toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 150,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Visual preview (image or icon container)
                SizedBox(
                  height: 84,
                  width: double.infinity,
                  child: Container(
                    color: isDark
                        ? typeColor.withValues(alpha: 0.12)
                        : typeColor.withValues(alpha: 0.08),
                    child: imageOrIcon,
                  ),
                ),
                // Title and tag
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF111418),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        displaySubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: typeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackIcon(Color color) {
    if (icon != null) {
      return Icon(icon, color: color, size: 30);
    }
    final t = memory?.type.toLowerCase() ?? '';
    IconData iconData;
    switch (t) {
      case 'screenshot':
      case 'photo':
      case 'camera_capture':
        iconData = Icons.photo_outlined;
        break;
      case 'webpage':
      case 'url':
        iconData = Icons.language_rounded;
        break;
      case 'copied_text':
      case 'clipboard':
        iconData = Icons.content_copy_rounded;
        break;
      case 'pdf':
      case 'document':
        iconData = Icons.insert_drive_file_outlined;
        break;
      case 'location':
        iconData = Icons.place_outlined;
        break;
      default:
        iconData = Icons.auto_awesome;
    }
    return Icon(iconData, color: color, size: 30);
  }
}
