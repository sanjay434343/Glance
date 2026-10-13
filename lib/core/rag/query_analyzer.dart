import '../temporal/temporal_query_resolver.dart';

/// Represents the analyzed intent and entities from a user's natural language query.
class AnalyzedQuery {
  final QueryIntent intent;
  final List<String> keywords;
  final String? appName;
  final String? typeFilter;
  final TimeRange? timeRange;
  final String originalQuery;
  final String searchDescription;
  final bool isCountQuery;
  final bool isAggregateQuery;
  final List<String> targetCallTypes;

  AnalyzedQuery({
    required this.intent,
    required this.keywords,
    this.appName,
    this.typeFilter,
    this.timeRange,
    required this.originalQuery,
    required this.searchDescription,
    this.isCountQuery = false,
    this.isAggregateQuery = false,
    this.targetCallTypes = const [],
  });
}

/// The type of search intent detected from the user's query.
enum QueryIntent {
  appUsage,           // "how much did I use Instagram", "Instagram usage"
  clipboardSearch,    // "what did I copy", "show copied texts"
  screenshotSearch,   // "show my screenshots"
  timeSearch,         // "what did I do today/yesterday"
  contentSearch,      // general keyword search across all memories
  callLogSearch,      // "incoming and outgoing and missed calls count", "call logs", "who called"
  messageSearch,      // "sms messages", "text messages from Alex"
  notificationSearch, // "show my notifications", "messages from WhatsApp"
  calendarSearch,     // "calendar events", "meetings today", "scheduled appointments"
  documentSearch,     // "show documents", "find my pdf", "resume", "invoice"
  entitySearch,       // "what is my otp", "find phone numbers", "find email", "show addresses", "urls"
  conversational,     // "hi", "tell me a joke", "how are you"
}

/// AI-powered query analyzer that decomposes natural language into structured search parameters.
/// Maps user intent to database query strategies without requiring a real LLM.
class QueryAnalyzer {
  // ── App name synonyms and common variations ──────────────────────────
  static const Map<String, List<String>> _appSynonyms = {
    'instagram': ['instagram', 'insta', 'ig'],
    'whatsapp': ['whatsapp', 'wa', 'watsapp'],
    'youtube': ['youtube', 'yt'],
    'twitter': ['twitter', 'x app'],
    'facebook': ['facebook', 'fb'],
    'snapchat': ['snapchat', 'snap'],
    'telegram': ['telegram', 'tg'],
    'chrome': ['chrome', 'google chrome'],
    'gmail': ['gmail'],
    'spotify': ['spotify'],
    'netflix': ['netflix'],
    'tiktok': ['tiktok', 'tik tok'],
    'linkedin': ['linkedin'],
    'discord': ['discord'],
    'reddit': ['reddit'],
    'pinterest': ['pinterest'],
    'phone': ['phone', 'dialer'],
    'messages': ['messages', 'messaging'],
    'camera': ['camera'],
    'gallery': ['gallery', 'photos app'],
    'calendar': ['calendar'],
    'settings': ['settings'],
    'maps': ['maps', 'google maps'],
    'clock': ['clock', 'alarm'],
    'calculator': ['calculator'],
    'files': ['files', 'file manager'],
    'play store': ['play store', 'google play'],
    'amazon': ['amazon'],
    'flipkart': ['flipkart'],
    'zomato': ['zomato'],
    'swiggy': ['swiggy'],
    'uber': ['uber'],
    'ola': ['ola'],
    'paytm': ['paytm'],
    'gpay': ['gpay', 'google pay'],
    'phonepe': ['phonepe', 'phone pe'],
  };

  // ── Conversational patterns ──────────────────────────────────────────
  static const List<String> _greetings = [
    'hi', 'hello', 'hey', 'howdy', 'sup', 'yo',
    'good morning', 'good evening', 'good afternoon', 'good night',
  ];

  static const List<String> _conversationalPatterns = [
    'how are you', 'who are you', 'what can you do', 'what are you',
    'help me', 'joke', 'tell me a joke', 'thank', 'thanks',
    'bye', 'goodbye', 'see you', 'good night',
  ];

  // ── Stop words to filter from keyword extraction ─────────────────────
  static const Set<String> _stopWords = {
    'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
    'should', 'may', 'might', 'can', 'shall', 'must', 'need',
    'i', 'me', 'my', 'mine', 'we', 'us', 'our', 'ours',
    'you', 'your', 'yours', 'he', 'him', 'his', 'she', 'her', 'hers',
    'it', 'its', 'they', 'them', 'their', 'theirs',
    'this', 'that', 'these', 'those',
    'what', 'which', 'who', 'whom', 'whose', 'when', 'where', 'why', 'how',
    'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'from', 'about',
    'into', 'through', 'during', 'before', 'after', 'above', 'below',
    'and', 'but', 'or', 'nor', 'not', 'so', 'yet', 'both', 'either',
    'tell', 'show', 'find', 'search', 'get', 'give', 'list', 'display',
    'much', 'many', 'more', 'most', 'some', 'any', 'all', 'each', 'every',
    'please', 'just', 'also', 'very', 'really', 'quite', 'rather',
  };

  static const Set<String> _typeWords = {
    'usage', 'use', 'used', 'using', 'app', 'apps', 'application',
    'copied', 'clipboard', 'copy', 'paste', 'pasted',
    'screenshot', 'screenshots', 'photo', 'photos', 'image', 'images',
    'picture', 'pictures', 'pic', 'pics', 'media', 'wallpaper',
    'entire', 'whole', 'pull',
    'notification', 'notifications', 'notif',
    'today', 'yesterday', 'week', 'month', 'year', 'ago', 'last', 'recent',
    'morning', 'evening', 'night', 'afternoon', 'activity',
  };

  // ═══════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════

  /// Analyzes a natural language query and returns structured search parameters.
  static AnalyzedQuery analyze(String query) {
    final lower = query.toLowerCase().trim();

    // 1. Conversational intent (no DB search needed)
    if (_isConversational(lower)) {
      return AnalyzedQuery(
        intent: QueryIntent.conversational,
        keywords: [],
        originalQuery: query,
        searchDescription: 'Responding to your message...',
      );
    }

    final isCount = _isCountQuery(lower);
    final targetCallTypes = _extractTargetCallTypes(lower);

    // 2. Call Log queries (e.g. "incoming and outgoing and missed calls count", "call logs", "who called")
    if (_isCallLogQuery(lower)) {
      final callDesc = isCount
          ? 'Calculating your call statistics & counts...'
          : 'Searching your call history & records...';
      return AnalyzedQuery(
        intent: QueryIntent.callLogSearch,
        keywords: _extractKeywords(lower, excludeTypeWords: true),
        appName: 'Phone',
        typeFilter: 'call_log',
        timeRange: _resolveTime(lower),
        originalQuery: query,
        searchDescription: callDesc,
        isCountQuery: isCount,
        isAggregateQuery: targetCallTypes.length > 1 || isCount,
        targetCallTypes: targetCallTypes,
      );
    }

    // 3. SMS & text message queries
    if (_isSmsQuery(lower)) {
      return AnalyzedQuery(
        intent: QueryIntent.messageSearch,
        keywords: _extractKeywords(lower, excludeTypeWords: true),
        appName: 'Messages',
        typeFilter: 'sms',
        timeRange: _resolveTime(lower),
        originalQuery: query,
        searchDescription: 'Searching your SMS & text messages...',
        isCountQuery: isCount,
      );
    }

    // 4. Detect app-specific queries
    final detectedApp = _detectAppName(lower);
    if (detectedApp != null && _isAppUsageQuery(lower)) {
      return AnalyzedQuery(
        intent: QueryIntent.appUsage,
        keywords: [detectedApp],
        appName: detectedApp,
        typeFilter: 'app_activity',
        timeRange: _resolveTime(lower),
        originalQuery: query,
        searchDescription: 'Searching $detectedApp usage & activity...',
        isCountQuery: isCount,
      );
    }

    // 5. Clipboard / copied text queries
    if (_isClipboardQuery(lower)) {
      return AnalyzedQuery(
        intent: QueryIntent.clipboardSearch,
        keywords: _extractKeywords(lower, excludeTypeWords: true),
        typeFilter: 'copied_text',
        timeRange: _resolveTime(lower),
        originalQuery: query,
        searchDescription: 'Searching your clipboard & copied text history...',
        isCountQuery: isCount,
      );
    }

    // 6. Visual (Images, Photos, Screenshots, Pictures) queries
    if (_isVisualQuery(lower)) {
      final kws = _extractKeywords(lower, excludeTypeWords: true);
      final isPullAll = kws.isEmpty || lower.contains('all') || lower.contains('entire') || lower.contains('have');
      return AnalyzedQuery(
        intent: QueryIntent.screenshotSearch,
        keywords: kws,
        typeFilter: 'visual',
        timeRange: _resolveTime(lower),
        originalQuery: query,
        searchDescription: isPullAll
            ? 'Retrieving all your images and photos...'
            : 'Searching images and photos...',
        isCountQuery: isCount,
      );
    }

    // 7. Calendar / meeting / schedule queries
    if (_isCalendarQuery(lower)) {
      return AnalyzedQuery(
        intent: QueryIntent.calendarSearch,
        keywords: _extractKeywords(lower, excludeTypeWords: true),
        typeFilter: 'calendar_event',
        appName: 'Calendar',
        timeRange: _resolveTime(lower),
        originalQuery: query,
        searchDescription: 'Searching your calendar events & meetings...',
        isCountQuery: isCount,
      );
    }

    // 8. Smart Entity queries (e.g. "what is my otp", "find phone numbers", "find email", "urls", "verification code")
    if (_isEntityQuery(lower)) {
      final entityType = _detectEntityType(lower);
      return AnalyzedQuery(
        intent: QueryIntent.entitySearch,
        keywords: [if (entityType != null) entityType, ..._extractKeywords(lower, excludeTypeWords: true)],
        typeFilter: null,
        timeRange: _resolveTime(lower),
        originalQuery: query,
        searchDescription: 'Searching smart entities & data ($entityType)...',
        isCountQuery: isCount,
      );
    }

    // 9. Document & PDF queries
    if (_isDocumentQuery(lower)) {
      return AnalyzedQuery(
        intent: QueryIntent.documentSearch,
        keywords: _extractKeywords(lower, excludeTypeWords: true),
        typeFilter: 'document',
        timeRange: _resolveTime(lower),
        originalQuery: query,
        searchDescription: 'Searching your documents & PDFs...',
        isCountQuery: isCount,
      );
    }

    // 10. Notification queries (non-call, non-SMS)
    if (_isNotificationQuery(lower)) {
      return AnalyzedQuery(
        intent: QueryIntent.notificationSearch,
        keywords: _extractKeywords(lower, excludeTypeWords: true),
        typeFilter: 'notification',
        appName: detectedApp,
        timeRange: _resolveTime(lower),
        originalQuery: query,
        searchDescription: 'Searching notifications & alerts...',
        isCountQuery: isCount,
      );
    }

    // 9. Time-based queries ("what did I do today")
    final timeRange = _resolveTime(lower);
    if (timeRange != null && _isTimeQuery(lower)) {
      return AnalyzedQuery(
        intent: QueryIntent.timeSearch,
        keywords: _extractKeywords(lower, excludeTypeWords: true),
        appName: detectedApp,
        timeRange: timeRange,
        originalQuery: query,
        searchDescription: 'Searching your activity for ${timeRange.label}...',
        isCountQuery: isCount,
      );
    }

    // 10. App name detected but not specifically usage
    if (detectedApp != null) {
      return AnalyzedQuery(
        intent: QueryIntent.appUsage,
        keywords: [detectedApp, ..._extractKeywords(lower, excludeTypeWords: true)],
        appName: detectedApp,
        timeRange: timeRange,
        originalQuery: query,
        searchDescription: 'Searching all activity related to $detectedApp...',
        isCountQuery: isCount,
      );
    }

    // 11. General content search (fallback)
    final keywords = _extractKeywords(lower, excludeTypeWords: false);
    final desc = keywords.isNotEmpty
        ? 'Searching all memories for "${keywords.take(3).join(', ')}"...'
        : 'Searching your memory database...';
    return AnalyzedQuery(
      intent: QueryIntent.contentSearch,
      keywords: keywords,
      timeRange: timeRange,
      originalQuery: query,
      searchDescription: desc,
      isCountQuery: isCount,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // INTENT DETECTION
  // ═══════════════════════════════════════════════════════════════════════

  static bool _isConversational(String lower) {
    for (final g in _greetings) {
      if (lower == g ||
          lower.startsWith('$g ') ||
          lower.startsWith('$g,') ||
          lower.startsWith('$g!')) {
        return true;
      }
    }
    for (final p in _conversationalPatterns) {
      if (lower.contains(p)) return true;
    }
    return false;
  }

  static bool _isAppUsageQuery(String lower) {
    const usageKeywords = [
      'usage', 'use', 'used', 'using', 'open', 'opened', 'launch', 'launched',
      'time spent', 'how long', 'how much', 'screen time', 'activity',
      'how often', 'frequently', 'recent', 'last time', 'did i',
    ];
    return usageKeywords.any((k) => lower.contains(k));
  }

  static bool _isClipboardQuery(String lower) {
    const clipKeywords = [
      'copied', 'clipboard', 'copy', 'paste', 'pasted', 'copied text',
      'what did i copy', 'show copied', 'clip', 'clipped', 'text i copied',
      'search copied', 'find copied',
    ];
    return clipKeywords.any((k) => lower.contains(k));
  }

  static bool _isVisualQuery(String lower) {
    const visualKeywords = [
      'screenshot', 'screenshots', 'screen capture', 'screen shot', 'screen grab',
      'image', 'images', 'photo', 'photos', 'picture', 'pictures', 'pic', 'pics',
      'wallpaper', 'media', 'camera capture',
    ];
    return visualKeywords.any((k) => lower.contains(k));
  }

  static bool _isCalendarQuery(String lower) {
    const calKeywords = [
      'calendar', 'meeting', 'meetings', 'schedule', 'scheduled',
      'appointment', 'appointments', 'event', 'events', 'agenda',
    ];
    return calKeywords.any((k) => lower.contains(k));
  }

  static bool _isCallLogQuery(String lower) {
    const callKeywords = [
      'call', 'calls', 'caller', 'calling', 'dialed', 'dialer',
      'incoming call', 'outgoing call', 'missed call', 'rejected call',
      'incoming', 'outgoing', 'missed', 'phone call', 'call log', 'call logs',
      'call history', 'phone history', 'who called',
    ];
    return callKeywords.any((k) => lower.contains(k));
  }

  static bool _isSmsQuery(String lower) {
    const smsKeywords = [
      'sms', 'text message', 'text messages', 'inbox', 'texted',
      'received sms', 'sent sms',
    ];
    return smsKeywords.any((k) => lower.contains(k));
  }

  static bool _isCountQuery(String lower) {
    const countKeywords = [
      'count', 'how many', 'total', 'number of', 'sum', 'calculate',
      'breakdown', 'stats', 'statistics', 'how much', 'quantity', 'add',
      'how many times',
    ];
    return countKeywords.any((k) => lower.contains(k));
  }

  static List<String> _extractTargetCallTypes(String lower) {
    final types = <String>[];
    if (lower.contains('incoming')) types.add('incoming');
    if (lower.contains('outgoing')) types.add('outgoing');
    if (lower.contains('missed')) types.add('missed');
    if (lower.contains('rejected')) types.add('rejected');
    if (types.isEmpty && _isCallLogQuery(lower)) {
      return ['incoming', 'outgoing', 'missed', 'rejected'];
    }
    return types;
  }

  static bool _isEntityQuery(String lower) {
    const entityKeywords = [
      'otp', 'pin', 'verification code', 'security code', 'password',
      'phone number', 'mobile number', 'contact number',
      'email', 'email address', 'mail id',
      'url', 'website link', 'web link', 'http',
      'address', 'location address',
    ];
    return entityKeywords.any((k) => lower.contains(k));
  }

  static String? _detectEntityType(String lower) {
    if (lower.contains('otp') || lower.contains('pin') || lower.contains('verification') || lower.contains('code')) {
      return 'OTP_PIN';
    }
    if (lower.contains('phone') || lower.contains('mobile') || lower.contains('number')) {
      return 'PHONE';
    }
    if (lower.contains('email') || lower.contains('mail')) {
      return 'EMAIL';
    }
    if (lower.contains('url') || lower.contains('link') || lower.contains('website')) {
      return 'URL';
    }
    if (lower.contains('address')) {
      return 'ADDRESS';
    }
    return null;
  }

  static bool _isDocumentQuery(String lower) {
    const docKeywords = [
      'document', 'documents', 'doc', 'docs', 'pdf', 'pdfs',
      'file', 'files', 'resume', 'cv', 'invoice', 'receipt',
      'marksheet', 'grade card', 'certificate', 'salary slip',
      'docx', 'pptx', 'xlsx',
    ];
    return docKeywords.any((k) => lower.contains(k));
  }

  static bool _isNotificationQuery(String lower) {
    const notifKeywords = [
      'notification', 'notif', 'alert', 'alerts',
      'whatsapp message', 'telegram message',
    ];
    return notifKeywords.any((k) => lower.contains(k));
  }

  static bool _isTimeQuery(String lower) {
    const timeKeywords = [
      'today', 'yesterday', 'last week', 'this month', 'this week',
      'ago', 'morning', 'evening', 'night', 'afternoon',
      'what did i do', 'what happened', 'show me', 'recent activity',
    ];
    return timeKeywords.any((k) => lower.contains(k));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ENTITY EXTRACTION
  // ═══════════════════════════════════════════════════════════════════════

  /// Detects app names from the query text using synonym mapping.
  static String? _detectAppName(String lower) {
    for (final entry in _appSynonyms.entries) {
      for (final synonym in entry.value) {
        // Match whole word or as part of a phrase
        if (lower.contains(synonym)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  /// Extracts meaningful content keywords after removing stop words and type markers.
  static List<String> _extractKeywords(String lower, {bool excludeTypeWords = false}) {
    final words = lower.split(RegExp(r'\s+'));
    final keywords = <String>[];

    for (final word in words) {
      final cleaned = word.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (cleaned.isEmpty || cleaned.length < 2) continue;
      if (_stopWords.contains(cleaned)) continue;
      if (excludeTypeWords && _typeWords.contains(cleaned)) continue;
      keywords.add(cleaned);
    }

    return keywords;
  }

  /// Resolves temporal expressions into concrete timestamp ranges.
  static TimeRange? _resolveTime(String lower) {
    return TemporalQueryResolver.resolveTimeConstraint(lower);
  }
}
