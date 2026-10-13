import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/memory_models.dart';
import 'widgets/related_memories_carousel.dart';

class WebDetailScreen extends StatelessWidget {
  final Memory memory;

  const WebDetailScreen({super.key, required this.memory});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final textSecondary = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);

    final dateStr = DateTime.fromMillisecondsSinceEpoch(memory.capturedAt).toLocal().toString().split('.').first;
    final url = memory.url ?? 'https://webrtc.org/documentation';

    String host = '';
    try {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      host = uri.host;
    } catch (_) {}

    final stopWords = {
      'this', 'that', 'with', 'from', 'have', 'your', 'about', 'will',
      'what', 'when', 'where', 'which', 'there', 'their', 'they', 'them',
      'some', 'than', 'then', 'also', 'http', 'https', 'com', 'org', 'www',
      'html', 'page', 'site'
    };
    final words = '${memory.title} ${memory.content}'
        .toLowerCase()
        .split(RegExp(r'[^a-zA-Z]+'))
        .where((w) => w.length > 3 && !stopWords.contains(w))
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .toSet()
        .toList();

    final tags = ['Website', 'Web', if (host.isNotEmpty) host, ...words].take(8).toList();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Web Entry Detail',
          style: TextStyle(
            color: textColor,
            fontFamily: 'DMSans',
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Web Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.language, color: primaryColor, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              memory.title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              url,
                              style: TextStyle(
                                fontSize: 13,
                                color: primaryColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open Webpage'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Extracted Web Content Snippet
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Page Summary & Content',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    memory.content,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: textColor,
                    ),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Visited Date', style: TextStyle(fontSize: 13, color: textSecondary)),
                      Text(dateStr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ==========================================
            // RELATED CAPTURES CAROUSEL
            // ==========================================
            RelatedMemoriesCarousel(
              currentMemory: memory,
              tags: tags,
              isDark: isDark,
              primaryColor: primaryColor,
            ),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
