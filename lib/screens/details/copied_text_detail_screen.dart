import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';

import '../../core/models/memory_models.dart';
import '../../core/services/smart_entity_service.dart';
import 'widgets/related_memories_carousel.dart';

class SmartEntity {
  final String type;
  final String text;
  SmartEntity(this.type, this.text);
}

class CopiedTextDetailScreen extends StatefulWidget {
  final Memory memory;

  const CopiedTextDetailScreen({super.key, required this.memory});

  @override
  State<CopiedTextDetailScreen> createState() => _CopiedTextDetailScreenState();
}

class _CopiedTextDetailScreenState extends State<CopiedTextDetailScreen> {
  List<SmartEntity> _entities = [];

  @override
  void initState() {
    super.initState();
    _extractEntities();
  }

  bool _isValidPhoneNumber(String raw) {
    if (raw.contains('\n')) return false;
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10 || digits.length > 15) return false;
    if (RegExp(r'^(100|050|000|038|062|085|\s)+$').hasMatch(cleaned)) return false;
    if (RegExp(r'(\d{2,3})\s+\1\s+\1').hasMatch(cleaned)) return false;
    final isStandardPhone = RegExp(
      r'^\+?[0-9]{1,4}?[-.\s]?\(?[0-9]{1,4}?\)?[-.\s]?[0-9]{3,4}[-.\s]?[0-9]{3,4}$',
    ).hasMatch(cleaned);
    final isMobile = RegExp(r'^(\+91[\-\s]?)?[6-9]\d{9}$').hasMatch(digits);
    return isStandardPhone || isMobile;
  }

  bool _isValidUrl(String raw) {
    if (raw.contains('\n')) return false;
    final cleaned = raw.replaceAll(RegExp(r'\s+'), '').trim();
    final degreeAbbr = RegExp(
      r'^(B|M|D)\.(Sc|Se|E|Tech|Com|Ed|A|Phil|Pharm|Arch)$',
      caseSensitive: false,
    );
    if (degreeAbbr.hasMatch(cleaned)) return false;
    if (cleaned.startsWith('http://') ||
        cleaned.startsWith('https://') ||
        cleaned.startsWith('www.')) {
      return true;
    }
    final webDomain = RegExp(
      r'^[a-zA-Z0-9][-a-zA-Z0-9]*\.(com|org|net|edu|gov|io|ai|in|co|app)(\/.*)?$',
      caseSensitive: false,
    );
    return webDomain.hasMatch(cleaned);
  }

  bool _isValidEmail(String raw) {
    if (raw.contains('\n')) return false;
    final cleaned = raw.trim();
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(cleaned);
  }

  bool _isValidAddress(String raw) {
    if (raw.contains('\n')) return false;
    final cleaned = raw.trim();
    return cleaned.length >= 6 && RegExp(r'[a-zA-Z]').hasMatch(cleaned);
  }

  bool _isValidDateTime(String raw) {
    if (raw.contains('\n')) return false;
    final cleaned = raw.trim();
    if (RegExp(r'^\d{1,3}$').hasMatch(cleaned)) return false;
    return cleaned.length >= 4;
  }

  Future<void> _extractEntities() async {
    final finalText = '${widget.memory.title}\n${widget.memory.content}'.trim();
    if (finalText.length <= 5) return;

    List<SmartEntity> validEntities = [];

    // 1. Extract OTPs / PINs using Regex
    final otpRegExp = RegExp(r'(?<!\d)(\d{4,8})(?!\d)');
    final matches = otpRegExp.allMatches(finalText);
    for (final match in matches) {
      final otpStr = match.group(1)!;
      final startIndex = (match.start - 30).clamp(0, finalText.length);
      final endIndex = (match.end + 30).clamp(0, finalText.length);
      final surrounding = finalText.substring(startIndex, endIndex).toLowerCase();
      
      if (surrounding.contains('otp') || 
          surrounding.contains('pin') || 
          surrounding.contains('code') || 
          surrounding.contains('verification')) {
        validEntities.add(SmartEntity('OTP_PIN', otpStr));
      }
    }

    // 2. Extract standard entities using ML Kit
    try {
      final entityExtractor =
          EntityExtractor(language: EntityExtractorLanguage.english);
      final rawEntities = await entityExtractor.annotateText(finalText);
      entityExtractor.close();

      for (final annotation in rawEntities) {
        final type = annotation.entities.first.type;
        final text = annotation.text;

        if (type == EntityType.phone && _isValidPhoneNumber(text)) {
          validEntities.add(SmartEntity('PHONE', text));
        } else if (type == EntityType.url && _isValidUrl(text)) {
          validEntities.add(SmartEntity('URL', text));
        } else if (type == EntityType.email && _isValidEmail(text)) {
          validEntities.add(SmartEntity('EMAIL', text));
        } else if (type == EntityType.address && _isValidAddress(text)) {
          validEntities.add(SmartEntity('ADDRESS', text));
        } else if (type == EntityType.dateTime && _isValidDateTime(text)) {
          validEntities.add(SmartEntity('DATETIME', text));
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _entities = validEntities;
      });

      // Push extracted entities to SQLite so search & RAG can query them
      if (validEntities.isNotEmpty) {
        try {
          SmartEntityService.instance.enrichMemoryWithEntities(widget.memory);
        } catch (_) {}
      }
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Copied to clipboard!',
          style: TextStyle(fontFamily: 'DMSans'),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    // Expressive M3 palette with pure white background in light mode
    final bgColor = isDark ? const Color(0xFF121315) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final buttonColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFF1A1D21);
    const buttonIconColor = Colors.white;
    final borderColor =
        isDark ? const Color(0xFF2E3238) : const Color(0xFFE2E8F0);

    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(widget.memory.capturedAt),
    );
    final wordCount = widget.memory.content
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;

    // Auto-generate tags from content
    final stopWords = {
      'this', 'like', 'that', 'with', 'from', 'have', 'your', 'dear',
      'user', 'about', 'will', 'what', 'when', 'where', 'which', 'there',
      'their', 'they', 'them', 'some', 'than', 'then', 'also', 'http',
      'https', 'com', 'org', 'www'
    };
    final words = widget.memory.content
        .toLowerCase()
        .split(RegExp(r'[^a-zA-Z]+'))
        .where((w) => w.length > 3 && !stopWords.contains(w))
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .toSet()
        .toList();

    // Appended Entity Tags
    for (final entity in _entities) {
      if (entity.type == 'ADDRESS') {
        final addr = entity.text.toLowerCase();
        if (addr.contains('coimbatore')) words.add('Coimbatore');
        if (addr.contains('tamil nadu')) words.add('Tamil Nadu');
      }
    }

    final sourceApp = widget.memory.sourceApp?.replaceAll(RegExp(r'^com\.[^.]+\.'), '') ?? 'Clipboard';
    final allTags = ['Clipboard', if (widget.memory.sourceApp != null) sourceApp, ...words];
    final displayTags = allTags.toSet().take(8).toList();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: buttonColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: buttonIconColor,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  _copyToClipboard(widget.memory.content);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: buttonColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.copy_rounded,
                    color: buttonIconColor,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 30 * (1 - value)),
              child: child,
            ),
          );
        },
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ==========================================
              // HERO PREVIEW CARD (Material 3 Expressive)
              // ==========================================
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                width: double.infinity,
                height: 360,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF181A1D) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background gradient surface
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [const Color(0xFF1C2026), const Color(0xFF131518)]
                                : [const Color(0xFFFDFEFE), const Color(0xFFF1F4F9)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Source App Pill
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.content_paste_rounded,
                                        size: 14,
                                        color: primaryColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        sourceApp.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.8,
                                          color: primaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Large Expressive Text Snippet
                            Expanded(
                              child: ShaderMask(
                                shaderCallback: (rect) {
                                  return const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black,
                                      Colors.black,
                                      Colors.transparent,
                                    ],
                                    stops: [0.0, 0.75, 1.0],
                                  ).createShader(rect);
                                },
                                blendMode: BlendMode.dstIn,
                                child: SingleChildScrollView(
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: Text(
                                    widget.memory.content,
                                    style: TextStyle(
                                      fontFamily: 'DMSans',
                                      fontSize: 18,
                                      height: 1.6,
                                      fontWeight: FontWeight.w500,
                                      color: textColor.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 48), // Padding for bottom pills
                          ],
                        ),
                      ),

                      // Top-Right Quick Copy Icon Button
                      Positioned(
                        top: 20,
                        right: 20,
                        child: GestureDetector(
                          onTap: () {
                            _copyToClipboard(widget.memory.content);
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2A2D34) : Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.copy_rounded,
                              color: isDark ? Colors.white : Colors.black87,
                              size: 18,
                            ),
                          ),
                        ),
                      ),

                      // Bottom-Left Date Pill
                      Positioned(
                        bottom: 20,
                        left: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2A2D34) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            dateStr,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),

                      // Bottom-Right Word Count Pill
                      Positioned(
                        bottom: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF22252A)
                                : const Color(0xFFEAEFF5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$wordCount Words',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ==========================================
                    // TITLE & METADATA CHIPS
                    // ==========================================
                    Text(
                      'Copied Snippet',
                      style: TextStyle(
                        color: textColor,
                        fontFamily: 'DMSans',
                        fontWeight: FontWeight.bold,
                        fontSize: 26,
                        letterSpacing: -0.5,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Metadata Pill Badges
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMetaBadge(
                          icon: Icons.apps_rounded,
                          label: sourceApp,
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                        _buildMetaBadge(
                          icon: Icons.segment_rounded,
                          label: '$wordCount Words',
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                        _buildMetaBadge(
                          icon: Icons.text_fields_rounded,
                          label: '${widget.memory.content.length} Chars',
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // ==========================================
                    // SMART ENTITIES (Strictly Validated Real Entities Only)
                    // ==========================================
                    if (_entities.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            size: 16,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'SMART ENTITIES',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _entities.map((entity) {
                          final type = entity.type;
                          final cleanEntityText = entity.text
                              .replaceAll(RegExp(r'\s+'), ' ')
                              .trim();

                          IconData icon = Icons.info_outline_rounded;
                          if (type.contains('PHONE')) {
                            icon = Icons.phone_rounded;
                          } else if (type.contains('EMAIL')) {
                            icon = Icons.email_rounded;
                          } else if (type.contains('ADDRESS')) {
                            icon = Icons.location_on_rounded;
                          } else if (type.contains('URL')) {
                            icon = Icons.link_rounded;
                          } else if (type.contains('DATETIME')) {
                            icon = Icons.calendar_today_rounded;
                          } else if (type.contains('OTP_PIN')) {
                            icon = Icons.password_rounded;
                          }

                          return InkWell(
                            onTap: () => _copyToClipboard(cleanEntityText),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 320),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: primaryColor.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon, size: 16, color: primaryColor),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      cleanEntityText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 28),
                    ],

                    // ==========================================
                    // TAGS SECTION (Under the Title)
                    // ==========================================
                    Row(
                      children: [
                        Icon(
                          Icons.local_offer_outlined,
                          size: 16,
                          color: primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'TAGS',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: displayTags.map((t) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF25282E)
                                : const Color(0xFFF1F4F9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF383C44)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '#',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                t,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 32),

                    // ==========================================
                    // RELATED CAPTURES CAROUSEL
                    // ==========================================
                    RelatedMemoriesCarousel(
                      currentMemory: widget.memory,
                      tags: displayTags,
                      isDark: isDark,
                      primaryColor: primaryColor,
                    ),

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaBadge({
    required IconData icon,
    required String label,
    required bool isDark,
    required Color primaryColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF22252A) : const Color(0xFFF1F4F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF333740) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: primaryColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.grey[300] : const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}
