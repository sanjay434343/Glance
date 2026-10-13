import 'package:flutter/material.dart';
import '../../../core/services/model_download_service.dart';
import '../../../core/theme/theme.dart';

class ModelDownloadBanner extends StatelessWidget {
  final bool hasModelOnPath;
  final bool isLoadedInRam;
  final bool isAutoLoading;
  final ModelDownloadProgress? downloadProgress;
  final bool isDark;
  final VoidCallback onTap;

  const ModelDownloadBanner({
    super.key,
    required this.hasModelOnPath,
    this.isLoadedInRam = false,
    this.isAutoLoading = false,
    required this.downloadProgress,
    required this.isDark,
    required this.onTap,
  });

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final isDownloading = downloadProgress != null && downloadProgress!.isDownloading;

    // Show banner if downloading, loading into RAM, or if model file is not present on the primary storage path
    if (hasModelOnPath && !isDownloading && !isAutoLoading) {
      return const SizedBox.shrink();
    }

    final total = downloadProgress?.totalBytes ?? 0;
    final downloaded = downloadProgress?.downloadedBytes ?? 0;
    final percent = total > 0 ? (downloaded / total).clamp(0.0, 1.0) : 0.0;
    final percentInt = (percent * 100).toInt();
    final speed = downloadProgress?.speedMBps ?? 0.0;

    // Same background and border as Recent Activity cards
    final cardBg = AppTheme.getCardBackground(isDark);
    final cardBorder = AppTheme.getCardBorder(isDark);

    final titleColor = AppTheme.getPrimaryText(isDark);
    final descColor = AppTheme.getSecondaryText(isDark);
    const accentColor = Color(0xFF3478F6);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: cardBorder,
          width: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (isDownloading || isAutoLoading) ? null : onTap,
          borderRadius: BorderRadius.circular(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isAutoLoading
                            ? const Color(0xFF10B981).withValues(alpha: 0.12)
                            : accentColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: (isDownloading || isAutoLoading)
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: isAutoLoading ? const Color(0xFF10B981) : accentColor,
                              ),
                            )
                          : const Icon(
                              Icons.cloud_download_rounded,
                              color: accentColor,
                              size: 20,
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  isAutoLoading
                                      ? 'Loading Model into RAM...'
                                      : (isDownloading
                                          ? 'Downloading AI Model'
                                          : (isLoadedInRam
                                              ? 'Model in RAM • Missing on Storage'
                                              : 'AI Model Not Installed')),
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: titleColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isDownloading) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$percentInt%',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                              ] else if (isAutoLoading) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Loading to RAM',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isAutoLoading
                                ? 'Loading Gemma 3N E2B IT weights into device RAM & GPU memory...'
                                : (isDownloading
                                    ? '${_formatBytes(downloaded)} of ${_formatBytes(total)} (${speed.toStringAsFixed(1)} MB/s)'
                                    : (isLoadedInRam
                                        ? 'Model active in memory, but not saved in .glance/models. Tap to download & persist.'
                                        : 'Tap to download Gemma 3N E2B IT for local offline vision & reasoning.')),
                            style: TextStyle(
                              fontSize: 12,
                              color: descColor,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isDownloading && !isAutoLoading) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: descColor,
                      ),
                    ],
                  ],
                ),
                if (isDownloading || isAutoLoading) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: SizedBox(
                        height: 5,
                        child: LinearProgressIndicator(
                          value: isAutoLoading ? null : (total > 0 ? percent : null),
                          backgroundColor: isDark ? Colors.white12 : Colors.black12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isAutoLoading ? const Color(0xFF10B981) : accentColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
