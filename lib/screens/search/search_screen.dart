import 'dart:async';
import 'dart:convert';
import '../../core/theme/theme.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:glance/core/database/glance_db.dart';

import '../../../core/models/memory_models.dart';
import '../../../core/providers/glance_providers.dart';
import '../../../core/rag/context_builder.dart';
import '../../../core/services/app_icon_cache.dart';
import '../collection/widgets/smart_collection_card.dart';
import '../details/detail_router.dart';
import '../home/widgets/home_filter_chip.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounceTimer;
  bool _isSearching = false;
  String? _currentQuery;

  // AI RAG Insight State
  String? _aiResponse;
  bool _isAiGenerating = false;
  StreamSubscription<String>? _aiSubscription;

  // Results
  List<RetrievalCandidate> _allCandidates = [];
  List<RetrievalCandidate> _filteredCandidates = [];

  // Filtering
  String _selectedCategory = 'All';
  final List<Map<String, String>> _categories = [
    {'name': 'All', 'icon': 'assets/icons/all.png'},
    {'name': 'Copied Text', 'icon': 'assets/icons/copied_text.png'},
    {'name': 'App Usage', 'icon': 'assets/icons/ap_activity.png'},
    {'name': 'Screenshots', 'icon': 'assets/icons/screenshot.png'},
    {'name': 'Notifications', 'icon': 'assets/icons/notification.png'},
  ];

  // Recent queries history
  final List<String> _recentSearches = [
    'Notes',
    'Note',
    'Phone',
    'Id card',
    'Text',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Give the Hero animation time to glide the bar into the bottom island
      Future.delayed(const Duration(milliseconds: 320), () {
        if (mounted && _currentQuery == null) {
          _focusNode.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _aiSubscription?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCategorySelected(String category) {
    setState(() {
      _selectedCategory = category;
      _applyCategoryFilter();
    });
  }

  void _applyCategoryFilter() {
    if (_selectedCategory == 'All') {
      _filteredCandidates = List.from(_allCandidates);
      return;
    }

    _filteredCandidates = _allCandidates.where((c) {
      final t = c.memory.type.toLowerCase();
      switch (_selectedCategory) {
        case 'Copied Text':
          return t == 'copied_text' || t == 'clipboard';
        case 'App Usage':
          return t == 'app_activity';
        case 'Screenshots':
          return t == 'screenshot' ||
              t == 'ocr_text' ||
              t == 'photo' ||
              t == 'camera_capture' ||
              c.memory.filePath != null ||
              c.memory.thumbnailPath != null;
        case 'Notifications':
          return t == 'notification' || t == 'sms' || t == 'call_log';
        default:
          return true;
      }
    }).toList();
  }

  Future<void> _executeSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || _isSearching) return;

    // Close keyboard and make search bar inactive from focusing
    _focusNode.unfocus();
    FocusScope.of(context).unfocus();

    _debounceTimer?.cancel();
    _aiSubscription?.cancel();

    setState(() {
      _isSearching = true;
      _currentQuery = trimmed;
      _allCandidates = [];
      _filteredCandidates = [];
      _aiResponse = null;
      _isAiGenerating = false;
    });

    final retriever = ref.read(hybridRetrieverProvider);
    final candidates = await retriever.retrieve(
      userQuery: trimmed,
      candidateLimit: 500,
      finalLimit: 250,
    );

    if (mounted) {
      setState(() {
        _allCandidates = candidates;
        _applyCategoryFilter();
        _isSearching = false;
        if (!_recentSearches.contains(trimmed)) {
          _recentSearches.insert(0, trimmed);
          if (_recentSearches.length > 8) _recentSearches.removeLast();
        }
      });

      // Execute AI RAG answer generation on retrieved memories
      _generateAiResponse(trimmed, candidates);
    }
  }

  void _generateAiResponse(String query, List<RetrievalCandidate> candidates) {
    _aiSubscription?.cancel();

    setState(() {
      _isAiGenerating = true;
      _aiResponse = '';
    });

    final contextText = ContextBuilder.buildContext(
      candidates,
      userQuestion: query,
    );
    final llamaService = ref.read(llamaServiceProvider);

    final stream = llamaService.generateAnswerStream(
      systemPrompt: ContextBuilder.systemPrompt,
      retrievedContext: contextText,
      userQuestion: query,
    );

    final StringBuffer buffer = StringBuffer();
    _aiSubscription = stream.listen(
      (chunk) {
        if (mounted) {
          buffer.write(chunk);
          setState(() {
            _aiResponse = buffer.toString();
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isAiGenerating = false;
          });
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() {
            _isAiGenerating = false;
            if (buffer.isEmpty) {
              _aiResponse = 'Unable to synthesize AI answer at this moment.';
            }
          });
        }
      },
      cancelOnError: true,
    );
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _aiSubscription?.cancel();
    _controller.clear();
    setState(() {
      _currentQuery = null;
      _allCandidates = [];
      _filteredCandidates = [];
      _isSearching = false;
      _selectedCategory = 'All';
      _aiResponse = null;
      _isAiGenerating = false;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        FocusScope.of(context).unfocus(); // Unfocus first to reset state
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            _focusNode.requestFocus();
            SystemChannels.textInput.invokeMethod('TextInput.show');
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.getScaffoldBackground(isDark) : Colors.white;
    final surfaceColor = isDark ? const Color(0xFF1B1C22) : Colors.white;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Simple Back Button ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 4, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: isDark ? Colors.white : Colors.black87,
                    size: 24,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Back',
                ),
              ),
            ),

            // ── Main Body: Empty State vs Results View ────────────────────────
            Expanded(
              child: _currentQuery == null || _currentQuery!.isEmpty
                  ? _buildEmptyStateView(isDark, surfaceColor, primaryColor)
                  : _buildSearchResultsView(isDark, surfaceColor, primaryColor),
            ),

            // ── Bottom Floating Pill Search Bar ──────────────────────────────
            _buildBottomFloatingSearchBar(isDark, surfaceColor, primaryColor),
          ],
        ),
      ),
    );
  }

  // ── Bottom Floating Pill Search Bar ────────────────────────────────────────
  Widget _buildBottomFloatingSearchBar(
    bool isDark,
    Color surfaceColor,
    Color primaryColor,
  ) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final pillBg = isDark ? const Color(0xFF1F2228) : const Color(0xFFEBEFF4);
    final iconColor = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563);
    final hintColor = isDark ? const Color(0xFF828A97) : const Color(0xFF6B7280);
    final textColor = isDark ? Colors.white : const Color(0xFF111827);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 6,
        bottom: 12 + bottomInset,
      ),
      child: Hero(
        tag: 'search_bar_hero',
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(28),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.search,
                    cursorColor: isDark ? Colors.white : Colors.black87,
                    readOnly: _isSearching,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15.5,
                    ),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: 'Search or ask',
                      hintStyle: TextStyle(
                        color: hintColor,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: (val) {
                      setState(() {});
                      final trimmed = val.trim();
                      if (trimmed.isEmpty && _currentQuery != null) {
                        _clearSearch();
                      }
                    },
                    onSubmitted: (val) {
                      _executeSearch(val);
                    },
                  ),
                ),
                if (_controller.text.trim().isNotEmpty &&
                    _controller.text.trim() != _currentQuery)
                  GestureDetector(
                    onTap: () => _executeSearch(_controller.text),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  )
                else if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: _clearSearch,
                    child: Icon(
                      Icons.close_rounded,
                      color: iconColor,
                      size: 20,
                    ),
                  )
                else
                  Icon(
                    Icons.mic_none_rounded,
                    color: iconColor,
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color bgColor(bool isDark) =>
      isDark ? const Color(0xFF0F0F12) : const Color(0xFFF7F8FA);

  // ── 2. Category Filter Row with image icons ──────────────────────────────
  Widget _buildCategoryFilterRow(bool isDark, Color primaryColor) {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final name = cat['name']!;
          final iconPath = cat['icon']!;
          final isSelected = _selectedCategory == name;

          return HomeFilterChip(
            label: name,
            imagePath: iconPath,
            isSelected: isSelected,
            isDark: isDark,
            onTap: () => _onCategorySelected(name),
          );
        },
      ),
    );
  }

  // Shimmer skeleton for category filter chips row while searching / generating
  Widget _buildChipsShimmer(bool isDark) {
    final pillWidths = [60.0, 115.0, 105.0, 120.0, 115.0];
    return SizedBox(
      height: 38,
      child: _RadiantPinkVioletShimmer(
        isDark: isDark,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: pillWidths.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Container(
                width: pillWidths[index],
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── 3. Empty State / Search History View ─────────────────────────────────
  Widget _buildEmptyStateView(
    bool isDark,
    Color surfaceColor,
    Color primaryColor,
  ) {
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE5E7EB);
    final iconColor = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF374151);
    final textColor = isDark ? Colors.white : const Color(0xFF111827);

    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        Divider(height: 1, thickness: 1, color: dividerColor),
        ..._recentSearches.map((query) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () {
                  _controller.text = query;
                  _executeSearch(query);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 22,
                        color: iconColor,
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          query,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w400,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: dividerColor),
            ],
          );
        }),
      ],
    );
  }

  // ── 5. Search Results View ────────────────────────────────────────────────
  Widget _buildSearchResultsView(
    bool isDark,
    Color surfaceColor,
    Color primaryColor,
  ) {
    final isLoading = _isSearching || _isAiGenerating;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // ── Direct AI Screen Response (No Card Container) ─────────────────
        if (isLoading ||
            (_aiResponse != null && _aiResponse!.isNotEmpty)) ...[
          const SizedBox(height: 16),
          _buildDirectAiResponse(isDark, primaryColor),
          const SizedBox(height: 16),
        ],

        // ── Divider Separating AI Insight from Memories Section ───────────
        Divider(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          height: 24,
          thickness: 1,
        ),
        const SizedBox(height: 6),

        // ── Category Filter Chips (Above RETRIEVED MEMORIES Title) ────────
        // Show shimmer pills while AI generates, show real chips once loaded
        if (isLoading)
          _buildChipsShimmer(isDark)
        else
          _buildCategoryFilterRow(isDark, primaryColor),

        const SizedBox(height: 18),

        // ── Retrieved Memories Section (Title + Cards Grid) ───────────────
        // Show shimmer cards while loading, show real cards once loaded
        if (isLoading) ...[
          _RadiantPinkVioletShimmer(
            isDark: isDark,
            child: const Text(
              'RETRIEVED MEMORIES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildSearchShimmer(isDark),
        ] else ...[
          _buildRetrievedMemoriesSection(isDark, surfaceColor, primaryColor),
        ],
      ],
    );
  }

  // ── Direct On-Screen AI Response ─────────────────────────────────────────
  Widget _buildDirectAiResponse(bool isDark, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row: Sparkle Icon + Title + Pill Badge + Status/Copy
        Row(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xFF8B5CF6),
                  Color(0xFF6366F1),
                  Color(0xFFEC4899),
                ],
              ).createShader(bounds),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'AI Insight',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const Spacer(),
            if (_isSearching || _isAiGenerating)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Thinking...',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ],
              )
            else if (_aiResponse != null && _aiResponse!.trim().isNotEmpty)
              IconButton(
                icon: Icon(
                  Icons.copy_rounded,
                  size: 17,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                tooltip: 'Copy response',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _aiResponse!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('AI insight copied to clipboard'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Direct Text Stream or Shimmer Placeholder
        if ((_isSearching || _isAiGenerating) &&
            (_aiResponse == null || _aiResponse!.trim().isEmpty))
          _buildAiShimmer(isDark)
        else
          _buildFormattedAiText(isDark, primaryColor),
        const SizedBox(height: 14),

        // Action Buttons Row: Re-search & Regenerate (Shimmer until AI finishes)
        if (_isSearching || _isAiGenerating)
          _buildButtonsShimmer(isDark)
        else
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              InkWell(
                onTap: () {
                  if (_currentQuery != null && _currentQuery!.isNotEmpty) {
                    _executeSearch(_currentQuery!);
                  }
                },
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E2029)
                        : const Color(0xFFEFF1F5),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        size: 15,
                        color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Re-search',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  if (_currentQuery != null && _currentQuery!.isNotEmpty) {
                    _generateAiResponse(_currentQuery!, _allCandidates);
                  }
                },
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: isDark ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: isDark ? 0.35 : 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: primaryColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Regenerate',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ── Retrieved Memories Section (Grounded Database Evidence) ──────────────
  Widget _buildRetrievedMemoriesSection(
    bool isDark,
    Color surfaceColor,
    Color primaryColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'RETRIEVED MEMORIES (${_filteredCandidates.length})',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            if (_selectedCategory != 'All')
              Text(
                'Filter: $_selectedCategory',
                style: TextStyle(
                  fontSize: 12,
                  color: primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Memory Results Cards
        if (_filteredCandidates.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 40,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 8),
                Text(
                  'No matching memories found for "$_selectedCategory"',
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemCount: _filteredCandidates.length,
            itemBuilder: (context, index) {
              final candidate = _filteredCandidates[index];
              final mem = candidate.memory;
              return _PopInAnimatedCard(
                key: ValueKey('${mem.id}_$index'),
                index: index,
                child: SmartCollectionCard(
                  height: null,
                  imageHeight: 74,
                  image: _buildMemoryPreview(mem, isDark),
                  title: _getCleanTitle(mem),
                  itemsCount: _formatRelativeTime(
                    DateTime.fromMillisecondsSinceEpoch(mem.capturedAt),
                  ),
                  isDark: isDark,
                  onTap: () => DetailRouter.openDetailScreen(context, mem),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildFormattedAiText(bool isDark, Color primaryColor) {
    final rawText = _aiResponse ?? '';
    // Strip any emojis to ensure 100% clean output
    String formattedText = rawText.replaceAll(
      RegExp(
        r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{1FA00}-\u{1FAFF}]',
        unicode: true,
      ),
      '',
    );

    // Convert any squashed inline bullets (e.g. "Text • Item 1 • Item 2") into clean newlines
    formattedText = formattedText.replaceAllMapped(
      RegExp(r'([^\n\r])\s*[•●]\s+'),
      (match) => '${match.group(1)}\n\n- ',
    );
    formattedText = formattedText.replaceAll(RegExp(r'(^|\n)\s*[•●]\s+'), r'$1- ');

    // Normalize spacing so multiple consecutive empty lines do not accumulate
    formattedText = formattedText.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    final textColor = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155);
    final boldColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBody(
          data: formattedText,
          selectable: false,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              fontSize: 14.5,
              height: 1.62,
              letterSpacing: 0.1,
              color: textColor,
              fontWeight: FontWeight.w400,
            ),
            strong: TextStyle(
              fontWeight: FontWeight.w700,
              color: boldColor,
            ),
            listBullet: TextStyle(
              color: primaryColor,
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
            ),
            listIndent: 16,
            h1: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
              color: boldColor,
            ),
            h2: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.bold,
              color: boldColor,
            ),
            h3: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: boldColor,
            ),
            blockSpacing: 12,
          ),
        ),
        if (_isAiGenerating)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 7,
              height: 15,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAiShimmer(bool isDark) {
    return _RadiantPinkVioletShimmer(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: MediaQuery.of(context).size.width * 0.76,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: MediaQuery.of(context).size.width * 0.48,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ],
      ),
    );
  }

  // Shimmer for action buttons while AI is generating with pink & violet shine
  Widget _buildButtonsShimmer(bool isDark) {
    return _RadiantPinkVioletShimmer(
      isDark: isDark,
      child: Row(
        children: [
          Container(
            width: 98,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 108,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ],
      ),
    );
  }

  // Shimmer skeleton loading effect for retrieved memories cards with radiant pink & violet
  Widget _buildSearchShimmer(bool isDark) {
    return _RadiantPinkVioletShimmer(
      isDark: isDark,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 8,
          childAspectRatio: 0.85,
        ),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.55),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(23),
                topRight: Radius.circular(23),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 74,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(23),
                      topRight: Radius.circular(23),
                      bottomLeft: Radius.circular(23),
                      bottomRight: Radius.circular(23),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 6.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        width: 40,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _getCleanTitle(Memory mem) {
    final typeLower = mem.type.toLowerCase();
    if (typeLower == 'screenshot' || typeLower == 'ocr_text') {
      return 'Captured Screenshot';
    }
    if (typeLower == 'photo' || typeLower == 'camera_capture') {
      return 'Captured Image';
    }

    String title = mem.title.trim();
    if (typeLower == 'app_activity') {
      if (mem.sourceApp != null &&
          mem.sourceApp!.isNotEmpty &&
          !mem.sourceApp!.startsWith('com.')) {
        return mem.sourceApp!;
      }
    }

    if (title.startsWith('com.') ||
        (title.contains('.') && !title.contains(' '))) {
      if (mem.sourceApp != null &&
          mem.sourceApp!.isNotEmpty &&
          !mem.sourceApp!.startsWith('com.')) {
        return mem.sourceApp!;
      }
      final parts = title.split('.');
      String last = parts.last;
      if (last.isNotEmpty) {
        return last[0].toUpperCase() + last.substring(1);
      }
    }

    if (title.isEmpty) {
      if (mem.content.isNotEmpty) {
        final snippet = mem.content.replaceAll('\n', ' ').trim();
        return snippet.length > 25 ? '${snippet.substring(0, 25)}...' : snippet;
      }
      return mem.sourceApp ?? 'Captured Memory';
    }

    return title;
  }

  Widget _buildMemoryPreview(Memory mem, bool isDark) {
    final typeLower = mem.type.toLowerCase();

    // 1. Preview from DB-stored Base64 copy if available
    if (mem.imageBase64 != null && mem.imageBase64!.trim().isNotEmpty) {
      return Image.memory(
        base64Decode(mem.imageBase64!.trim()),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 200,
        cacheHeight: 200,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildCategoryAssetIcon(mem, isDark),
      );
    }

    // 2. Preview file from storage if available
    String? validImgPath;
    if (mem.thumbnailPath != null && mem.thumbnailPath!.trim().isNotEmpty) {
      validImgPath = mem.thumbnailPath!.trim();
    } else if (mem.filePath != null && mem.filePath!.trim().isNotEmpty) {
      validImgPath = mem.filePath!.trim();
    }

    if (validImgPath != null) {
      if (validImgPath.startsWith('http://') || validImgPath.startsWith('https://')) {
        return Image.network(
          validImgPath,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: 200,
          cacheHeight: 200,
          errorBuilder: (_, _, _) => _buildCategoryAssetIcon(mem, isDark),
        );
      }
      return Image.file(
        File(validImgPath),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 200,
        cacheHeight: 200,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildCategoryAssetIcon(mem, isDark),
      );
    }

    // 2. App activity icon from memory cache
    if (typeLower == 'app_activity' &&
        mem.sourcePackage != null &&
        mem.sourcePackage!.trim().isNotEmpty) {
      return Container(
        color: isDark ? const Color(0xFF241A2E) : const Color(0xFFF5E8FF),
        alignment: Alignment.center,
        child: AppIconWidget(
          packageName: mem.sourcePackage!.trim(),
          size: 40,
          fallbackIcon: _buildCategoryAssetIcon(mem, isDark),
        ),
      );
    }

    // 3. Fallback to category asset icon
    return _buildCategoryAssetIcon(mem, isDark);
  }

  Widget _buildCategoryAssetIcon(Memory mem, bool isDark) {
    final typeLower = mem.type.toLowerCase();
    String assetPath;
    Color bgColor;
    IconData fallbackIcon;
    Color iconColor;

    switch (typeLower) {
      case 'notification':
      case 'sms':
      case 'call_log':
        assetPath = 'assets/icons/notification.png';
        bgColor = isDark ? const Color(0xFF162534) : const Color(0xFFE0F2FE);
        fallbackIcon = Icons.notifications_rounded;
        iconColor = const Color(0xFF3478F6);
        break;
      case 'copied_text':
      case 'clipboard':
        assetPath = 'assets/icons/copied_text.png';
        bgColor = isDark ? const Color(0xFF241A2E) : const Color(0xFFF3E8FF);
        fallbackIcon = Icons.content_copy_rounded;
        iconColor = const Color(0xFF9C27B0);
        break;
      case 'app_activity':
        assetPath = 'assets/icons/ap_activity.png';
        bgColor = isDark ? const Color(0xFF241A2E) : const Color(0xFFF5E8FF);
        fallbackIcon = Icons.apps_rounded;
        iconColor = Colors.purpleAccent;
        break;
      case 'screenshot':
      case 'ocr_text':
        assetPath = 'assets/icons/screenshot.png';
        bgColor = isDark ? const Color(0xFF2A1722) : const Color(0xFFFCE7F3);
        fallbackIcon = Icons.photo_camera_rounded;
        iconColor = Colors.pinkAccent;
        break;
      case 'pdf':
      case 'document':
      case 'file':
        assetPath = 'assets/icons/documens.png';
        bgColor = isDark ? const Color(0xFF2E2214) : const Color(0xFFFEF3C7);
        fallbackIcon = Icons.picture_as_pdf_rounded;
        iconColor = Colors.orange;
        break;
      case 'location':
        assetPath = 'assets/icons/location.png';
        bgColor = isDark ? const Color(0xFF2A1722) : const Color(0xFFFCE7F3);
        fallbackIcon = Icons.place_rounded;
        iconColor = Colors.pink;
        break;
      case 'webpage':
      case 'url':
        assetPath = 'assets/icons/website.png';
        bgColor = isDark ? const Color(0xFF142236) : const Color(0xFFE0EDFB);
        fallbackIcon = Icons.language_rounded;
        iconColor = Colors.blueAccent;
        break;
      default:
        assetPath = 'assets/icons/images.png';
        bgColor = isDark ? const Color(0xFF1E2420) : const Color(0xFFE8F5E9);
        fallbackIcon = Icons.image_rounded;
        iconColor = Colors.green;
        break;
    }

    return Container(
      color: bgColor,
      alignment: Alignment.center,
      child: Image.asset(
        assetPath,
        width: 32,
        height: 32,
        errorBuilder: (_, _, _) =>
            Icon(fallbackIcon, color: iconColor, size: 28),
      ),
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }
}

/// Shimmer effect sweeping an animated, radiant pink and violet shine.
class _RadiantPinkVioletShimmer extends StatefulWidget {
  final Widget child;
  final bool isDark;

  const _RadiantPinkVioletShimmer({
    required this.child,
    required this.isDark,
  });

  @override
  State<_RadiantPinkVioletShimmer> createState() =>
      _RadiantPinkVioletShimmerState();
}

class _RadiantPinkVioletShimmerState extends State<_RadiantPinkVioletShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            final progress = _controller.value;
            // Sweep smooth gradient from left to right across the element
            final double start = -2.2 + (progress * 4.4);
            final double end = -0.8 + (progress * 4.4);

            return LinearGradient(
              begin: Alignment(start, -0.3),
              end: Alignment(end, 0.3),
              colors: widget.isDark
                  ? const [
                      Color(0xFF241535), // Dark violet base
                      Color(0xFF581C87), // Deep purple
                      Color(0xFF8B5CF6), // Vivid violet
                      Color(0xFFEC4899), // Radiant shining pink
                      Color(0xFFF472B6), // Bright glowing pink
                      Color(0xFFA855F7), // Purple shine
                      Color(0xFF241535), // Dark violet base
                    ]
                  : const [
                      Color(0xFFF5E8FF), // Soft lavender base
                      Color(0xFFE9D5FF), // Light purple
                      Color(0xFFC084FC), // Vivid violet
                      Color(0xFFF472B6), // Radiant shining pink
                      Color(0xFFFB7185), // Coral shining pink
                      Color(0xFFE879F9), // Fuchsia violet
                      Color(0xFFF5E8FF), // Soft lavender base
                    ],
              stops: const [0.0, 0.18, 0.36, 0.5, 0.64, 0.82, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Pop-in animated wrapper for retrieved memory cards.
/// Triggers individually one by one with a 300ms staggered delay.
class _PopInAnimatedCard extends StatefulWidget {
  final Widget child;
  final int index;

  const _PopInAnimatedCard({
    super.key,
    required this.child,
    required this.index,
  });

  @override
  State<_PopInAnimatedCard> createState() => _PopInAnimatedCardState();
}

class _PopInAnimatedCardState extends State<_PopInAnimatedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );

    _scaleAnimation = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Stagger each individual card with a smooth delay (60ms step up to 360ms)
    final delay = Duration(milliseconds: (widget.index * 60).clamp(0, 360));
    _timer = Timer(delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
