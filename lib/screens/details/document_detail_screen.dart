import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/models/memory_models.dart';
import '../../core/services/smart_entity_service.dart';
import 'widgets/related_memories_carousel.dart';

class SmartEntity {
  final String type;
  final String text;
  SmartEntity(this.type, this.text);
}

class DocumentDetailScreen extends StatefulWidget {
  final Memory memory;

  const DocumentDetailScreen({super.key, required this.memory});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final List<String> _pageImages = [];
  final List<String> _tempFilesToDelete = [];
  late final PageController _pageController;

  int _selectedPageIndex = 0;
  bool _isLoadingPreview = true;

  String? _extractedPdfText;
  String? _fileSizeStr;
  int? _pageCount;
  List<SmartEntity> _entities = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadDocumentPreviewAndText();
  }

  @override
  void dispose() {
    _pageController.dispose();
    // Clean up temporary rendered page images
    for (final tempPath in _tempFilesToDelete) {
      try {
        final f = File(tempPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _cleanFileName(String name) {
    if (name.contains('.')) {
      final parts = name.split('.');
      parts.removeLast();
      final base = parts.join('.');
      if (base.trim().isNotEmpty) return base.replaceAll('_', ' ');
    }
    return name.replaceAll('_', ' ');
  }

  bool _isGibberishOrTimestamp(String s) {
    final trimmed = s.replaceAll(RegExp(r'\s+'), '');
    // Pure numeric like 102952035357637
    if (RegExp(r'^\d{6,}$').hasMatch(trimmed)) return true;
    // Hex UUID or hash
    if (RegExp(r'^[0-9a-fA-F_-]{16,}$').hasMatch(trimmed)) return true;
    if (trimmed.toLowerCase().startsWith('doc_') ||
        trimmed.toLowerCase().startsWith('file_')) {
      return true;
    }
    return false;
  }

  String _toTitleCase(String s) {
    return s.split(' ').map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  String _getDisplayTitle() {
    // 1. Try reading clean title from memory.summary if available
    try {
      if (widget.memory.summary != null &&
          widget.memory.summary!.trim().isNotEmpty) {
        final map = jsonDecode(widget.memory.summary!) as Map<String, dynamic>;
        if (map['title'] != null &&
            map['title'].toString().trim().isNotEmpty) {
          final t = map['title'].toString().trim();
          if (!_isGibberishOrTimestamp(t)) return t;
        }
      }
    } catch (_) {}

    // 2. Check if memory.title is a normal human-readable name
    final baseTitle = _cleanFileName(widget.memory.title);
    if (!_isGibberishOrTimestamp(baseTitle)) {
      return baseTitle;
    }

    // 3. Infer human-friendly title from extracted document content
    if (_extractedPdfText != null && _extractedPdfText!.isNotEmpty) {
      final textLower = _extractedPdfText!.toLowerCase();

      if (textLower.contains('grade card') ||
          textLower.contains('marksheet') ||
          textLower.contains('mark sheet')) {
        if (textLower.contains('consolidated')) {
          return 'Consolidated Grade Card';
        }
        return 'Grade Card';
      }
      if (textLower.contains('tax invoice') || textLower.contains('invoice')) {
        return 'Tax Invoice';
      }
      if (textLower.contains('receipt') ||
          textLower.contains('payment confirmation')) {
        return 'Payment Receipt';
      }
      if (textLower.contains('resume') ||
          textLower.contains('curriculum vitae')) {
        return 'Resume';
      }
      if (textLower.contains('offer letter') ||
          textLower.contains('appointment letter')) {
        return 'Offer Letter';
      }
      if (textLower.contains('certificate')) return 'Certificate';
      if (textLower.contains('salary slip') || textLower.contains('payslip')) {
        return 'Salary Slip';
      }

      // Check first few lines for college / company / institution heading
      final lines = _extractedPdfText!
          .split('\n')
          .map((l) => l.trim())
          .where((l) =>
              l.length >= 4 &&
              l.length <= 48 &&
              !RegExp(r'^\d+$').hasMatch(l))
          .toList();
      if (lines.isNotEmpty) {
        return _toTitleCase(lines.first);
      }
    }

    return 'Document';
  }

  // =========================================================================
  // STRICT ENTITY VALIDATION (Stops random table marks from becoming phones)
  // =========================================================================

  bool _isValidPhoneNumber(String raw) {
    // Cannot have newlines
    if (raw.contains('\n')) return false;
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Remove all non-digits
    final digits = raw.replaceAll(RegExp(r'\D'), '');

    // Real phone numbers have 10 to 15 digits
    if (digits.length < 10 || digits.length > 15) return false;

    // Reject tabular marks patterns like "100 050 050", "038 100 100"
    if (RegExp(r'^(100|050|000|038|062|085|\s)+$').hasMatch(cleaned)) {
      return false;
    }

    // Reject if too many repeated identical tokens
    if (RegExp(r'(\d{2,3})\s+\1\s+\1').hasMatch(cleaned)) return false;

    // Check standard phone number formats
    final isStandardPhone = RegExp(
      r'^\+?[0-9]{1,4}?[-.\s]?\(?[0-9]{1,4}?\)?[-.\s]?[0-9]{3,4}[-.\s]?[0-9]{3,4}$',
    ).hasMatch(cleaned);

    // Standard 10-digit mobile (Indian or international)
    final isMobile = RegExp(r'^(\+91[\-\s]?)?[6-9]\d{9}$').hasMatch(digits);

    return isStandardPhone || isMobile;
  }

  bool _isValidUrl(String raw) {
    if (raw.contains('\n')) return false;
    final cleaned = raw.replaceAll(RegExp(r'\s+'), '').trim();

    // Reject degree abbreviations mistakenly parsed as URLs (e.g. B.Sc, B.Se, M.Sc, Ph.D)
    final degreeAbbr = RegExp(
      r'^(B|M|D)\.(Sc|Se|E|Tech|Com|Ed|A|Phil|Pharm|Arch)$',
      caseSensitive: false,
    );
    if (degreeAbbr.hasMatch(cleaned)) return false;

    // Real URL must start with http/https/www or have a genuine top-level domain
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
    // Must not be a raw 1-3 digit mark
    if (RegExp(r'^\d{1,3}$').hasMatch(cleaned)) return false;
    return cleaned.length >= 4;
  }

  Future<void> _loadDocumentPreviewAndText() async {
    final path = widget.memory.filePath ??
        '/storage/emulated/0/Documents/${widget.memory.title}';
    final ext = widget.memory.title.contains('.')
        ? widget.memory.title.split('.').last.toLowerCase()
        : 'pdf';

    final file = File(path);
    if (!file.existsSync()) {
      if (mounted) {
        setState(() {
          _isLoadingPreview = false;
          _extractedPdfText = widget.memory.content;
        });
      }
      return;
    }

    try {
      final size = file.lengthSync();
      _fileSizeStr = _formatFileSize(size);
    } catch (_) {}

    setState(() {
      _isLoadingPreview = true;
    });

    try {
      final bytes = await file.readAsBytes();
      String extractedText = '';

      if (ext == 'pdf') {
        try {
          final document = PdfDocument(inputBytes: bytes);
          _pageCount = document.pages.count;
          final pageCount = _pageCount ?? document.pages.count;
          final textExtractor = PdfTextExtractor(document);
          final maxPage = pageCount > 3 ? 2 : (pageCount > 0 ? pageCount - 1 : 0);
          extractedText = textExtractor.extractText(startPageIndex: 0, endPageIndex: maxPage);
          document.dispose();
        } catch (_) {}

        // Render high-res page images via native Android bridge
        try {
          const channel = MethodChannel('com.glance.app/native_bridge');
          final List<dynamic>? rendered = await channel.invokeMethod(
            'renderPdfToImages',
            {'pdfPath': path},
          );
          if (rendered != null && rendered.isNotEmpty) {
            final pagePaths = rendered.cast<String>();
            _pageImages.addAll(pagePaths);
            _tempFilesToDelete.addAll(pagePaths);
          }
        } catch (e) {
          debugPrint('Error rendering PDF images: $e');
        }

        // Fallback OCR if scanned PDF has no embedded text
        if (extractedText.trim().isEmpty && _pageImages.isNotEmpty) {
          try {
            final textRecognizer = TextRecognizer();
            final ocrSb = StringBuffer();
            for (final imgPath in _pageImages.take(5)) {
              final inputImage = InputImage.fromFilePath(imgPath);
              final recognizedText =
                  await textRecognizer.processImage(inputImage);
              ocrSb.writeln(recognizedText.text);
            }
            textRecognizer.close();
            extractedText = ocrSb.toString();
          } catch (_) {}
        }
      } else if (ext == 'docx' || ext == 'pptx' || ext == 'xlsx') {
        final archive = ZipDecoder().decodeBytes(bytes);
        final sb = StringBuffer();

        for (final item in archive) {
          final fileName = item.name;
          if ((ext == 'docx' && fileName == 'word/document.xml') ||
              (ext == 'pptx' &&
                  fileName.startsWith('ppt/slides/slide') &&
                  fileName.endsWith('.xml')) ||
              (ext == 'xlsx' && fileName == 'xl/sharedStrings.xml')) {
            final content = utf8.decode(item.content as List<int>);
            final text = content
                .replaceAll(RegExp(r'<[^>]*>'), ' ')
                .replaceAll(RegExp(r'\s+'), ' ');
            sb.writeln(text.trim());
          }
        }
        extractedText = sb.toString();
      }

      if (_pageImages.isEmpty &&
          widget.memory.thumbnailPath != null &&
          widget.memory.thumbnailPath!.isNotEmpty) {
        if (File(widget.memory.thumbnailPath!).existsSync()) {
          _pageImages.add(widget.memory.thumbnailPath!);
        }
      }

      // Entity Extraction with STRICT FILTERING
      List<SmartEntity> validEntities = [];
      final finalText = extractedText.trim().isNotEmpty
          ? extractedText.trim()
          : widget.memory.content;

      if (finalText.length > 5) {
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

        try {
          final sampleText = finalText.length > 2000 ? finalText.substring(0, 2000) : finalText;
          final entityExtractor =
              EntityExtractor(language: EntityExtractorLanguage.english);
          final rawEntities = await entityExtractor
              .annotateText(sampleText)
              .timeout(const Duration(seconds: 2), onTimeout: () => []);
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
      }

      if (mounted) {
        setState(() {
          _extractedPdfText = finalText;
          _entities = validEntities;
          _isLoadingPreview = false;
        });

        // Push extracted entities to SQLite so search & RAG can query them
        if (validEntities.isNotEmpty) {
          try {
            SmartEntityService.instance.enrichMemoryWithEntities(
              widget.memory.copyWith(content: finalText),
            );
          } catch (_) {}
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _extractedPdfText = "Could not extract text: $e";
          _isLoadingPreview = false;
        });
      }
    }
  }

  List<String> _extractTags() {
    final List<String> tags = [];

    // 1. Check JSON tags in summary
    try {
      if (widget.memory.summary != null &&
          widget.memory.summary!.trim().isNotEmpty) {
        final map = jsonDecode(widget.memory.summary!) as Map<String, dynamic>;
        if (map['tags'] is List) {
          tags.addAll(
            (map['tags'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty),
          );
        }
      }
    } catch (_) {}

    // 2. Semantic topics inferred from document text (no generic placeholders)
    final textLower = (_extractedPdfText ?? widget.memory.content).toLowerCase();

    if (textLower.contains('grade card') || textLower.contains('marksheet')) {
      tags.add('Grade Card');
      tags.add('Academic');
    }
    if (textLower.contains('college') || textLower.contains('university')) {
      tags.add('College');
    }
    if (textLower.contains('computer science')) {
      tags.add('Computer Science');
    }
    if (textLower.contains('ai & ml') ||
        textLower.contains('artificial intelligence')) {
      tags.add('AI & ML');
    }
    if (textLower.contains('invoice') || textLower.contains('bill')) {
      tags.add('Invoice');
    }
    if (textLower.contains('receipt')) {
      tags.add('Receipt');
    }
    if (textLower.contains('statement')) {
      tags.add('Financial');
    }
    if (textLower.contains('certificate')) {
      tags.add('Certificate');
    }
    if (textLower.contains('resume') || textLower.contains('cv')) {
      tags.add('Resume');
    }

    // Inferred location keywords from real addresses
    for (final entity in _entities) {
      if (entity.type == 'ADDRESS') {
        final addr = entity.text.toLowerCase();
        if (addr.contains('coimbatore')) tags.add('Coimbatore');
        if (addr.contains('tamil nadu')) tags.add('Tamil Nadu');
      }
    }

    // Format & Document
    final ext = widget.memory.title.contains('.')
        ? widget.memory.title.split('.').last.toUpperCase()
        : 'PDF';
    tags.add(ext);
    tags.add('Document');

    return tags.toSet().toList(); // Deduplicate
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    // Pure white background in light mode
    final bgColor = isDark ? const Color(0xFF121315) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E2024) : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : const Color(0xFF111418);
    final textSecondary = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);
    final buttonColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFF1A1D21);
    const buttonIconColor = Colors.white;

    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(widget.memory.capturedAt),
    );

    final cleanFileName = _cleanFileName(widget.memory.title);
    final displayTitle = _getDisplayTitle();
    final ext = widget.memory.title.contains('.')
        ? widget.memory.title.split('.').last.toUpperCase()
        : 'PDF';

    final pageCountStr = _pageCount != null
        ? '$_pageCount ${_pageCount == 1 ? "Page" : "Pages"}'
        : null;

    // JSON Overview
    String? jsonDescription;
    try {
      if (widget.memory.summary != null &&
          widget.memory.summary!.trim().isNotEmpty) {
        final map = jsonDecode(widget.memory.summary!) as Map<String, dynamic>;
        if (map['description'] != null &&
            map['description'].toString().trim().isNotEmpty) {
          jsonDescription = map['description'].toString().trim();
        } else if (map['summary'] != null &&
            map['summary'].toString().trim().isNotEmpty) {
          jsonDescription = map['summary'].toString().trim();
        }
      }
    } catch (_) {}

    final tags = _extractTags();

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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'File: ${widget.memory.title}',
                        style: const TextStyle(fontFamily: 'DMSans'),
                      ),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: buttonColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: buttonIconColor,
                    size: 20,
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
              // HERO PDF PREVIEW CARD (420px height)
              // Clean document viewing without covering signature/date!
              // ==========================================
              _buildHeroPreviewCard(
                context: context,
                isDark: isDark,
                cardColor: cardColor,
                textColor: textColor,
                textSecondary: textSecondary,
                ext: ext,
              ),

              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ==========================================
                    // TITLE & SUBTITLE
                    // ==========================================
                    Text(
                      displayTitle,
                      style: TextStyle(
                        color: textColor,
                        fontFamily: 'DMSans',
                        fontWeight: FontWeight.bold,
                        fontSize: 26,
                        letterSpacing: -0.5,
                        height: 1.25,
                      ),
                    ),

                    if (displayTitle != cleanFileName &&
                        cleanFileName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        cleanFileName,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Metadata Pill Badges (Format, Page Count, File Size, Date)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMetaBadge(
                          icon: Icons.picture_as_pdf_rounded,
                          label: ext,
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                        if (pageCountStr != null)
                          _buildMetaBadge(
                            icon: Icons.auto_stories_rounded,
                            label: pageCountStr,
                            isDark: isDark,
                            primaryColor: primaryColor,
                          ),
                        if (_fileSizeStr != null)
                          _buildMetaBadge(
                            icon: Icons.storage_rounded,
                            label: _fileSizeStr!,
                            isDark: isDark,
                            primaryColor: primaryColor,
                          ),
                        _buildMetaBadge(
                          icon: Icons.access_time_rounded,
                          label: dateStr,
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // ==========================================
                    // OVERVIEW / DESCRIPTION (If available)
                    // ==========================================
                    if (jsonDescription != null &&
                        jsonDescription.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: primaryColor,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'OVERVIEW',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        jsonDescription,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          fontWeight: FontWeight.w400,
                          color: textColor.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],

                    // ==========================================
                    // TAGS SECTION (Under Title & Metadata)
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
                      children: tags.map((t) {
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

                    // ==========================================
                    // SMART ENTITIES (Strictly Validated Real Entities Only)
                    // ==========================================
                    if (_entities.isNotEmpty) ...[
                      const SizedBox(height: 28),
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
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: cleanEntityText));
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
                            },
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
                    ],

                    const SizedBox(height: 32),

                    // ==========================================
                    // RELATED CAPTURES CAROUSEL
                    // ==========================================
                    RelatedMemoriesCarousel(
                      currentMemory: widget.memory,
                      tags: tags,
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

  Widget _buildHeroPreviewCard({
    required BuildContext context,
    required bool isDark,
    required Color cardColor,
    required Color textColor,
    required Color textSecondary,
    required String ext,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      width: double.infinity,
      height: 420,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181A1D) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(
          color: isDark ? const Color(0xFF2E3238) : const Color(0xFFE5E7EB),
        ),
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
            // Preview Content
            if (_isLoadingPreview)
              Shimmer.fromColors(
                baseColor: isDark ? Colors.grey[900]! : Colors.grey[300]!,
                highlightColor: isDark ? Colors.grey[800]! : Colors.grey[100]!,
                child: Container(color: cardColor),
              )
            else if (_pageImages.isNotEmpty)
              PageView.builder(
                controller: _pageController,
                itemCount: _pageImages.length,
                onPageChanged: (idx) => setState(() => _selectedPageIndex = idx),
                itemBuilder: (context, index) {
                  final imgPath = _pageImages[index];
                  final file = File(imgPath);
                  if (file.existsSync()) {
                    return Container(
                      color: isDark
                          ? const Color(0xFF141619)
                          : const Color(0xFFF1F3F5),
                      child: Center(
                        // Physical paper sheet card effect with subtle shadow
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              file,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return _buildDocumentIconFallback(isDark, ext);
                },
              )
            else
              _buildDocumentIconFallback(isDark, ext),

            // Top-Right Fullscreen Zoom Button
            if (_pageImages.isNotEmpty)
              Positioned(
                top: 16,
                right: 16,
                child: GestureDetector(
                  onTap: () {
                    final imgPath = _pageImages[_selectedPageIndex];
                    final imgFile = File(imgPath);
                    if (imgFile.existsSync()) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            backgroundColor: Colors.black,
                            body: Stack(
                              children: [
                                Center(
                                  child: InteractiveViewer(
                                    minScale: 0.5,
                                    maxScale: 4.0,
                                    child: Image.file(imgFile),
                                  ),
                                ),
                                Positioned(
                                  top: 40,
                                  left: 10,
                                  child: IconButton(
                                    icon: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2D34) : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.fullscreen_rounded,
                      color: isDark ? Colors.white : Colors.black87,
                      size: 24,
                    ),
                  ),
                ),
              ),

            // Bottom-Right Page Counter (Only if multi-page)
            if (_pageImages.length > 1)
              Positioned(
                bottom: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_selectedPageIndex + 1} / ${_pageImages.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentIconFallback(bool isDark, String ext) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E2228), const Color(0xFF141619)]
              : [const Color(0xFFEEF2F6), const Color(0xFFE2E8F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.picture_as_pdf_rounded,
                size: 64,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$ext DOCUMENT',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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

