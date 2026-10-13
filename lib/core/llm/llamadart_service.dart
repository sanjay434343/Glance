import 'dart:async';
import '../services/gemma_mediapipe_service.dart';

/// Configuration for engine parameters including hardware acceleration.
class LlamaGpuConfig {
  final int gpuLayers;
  final int contextSize;
  final double temperature;
  final int maxTokens;
  final int threads;

  const LlamaGpuConfig({
    this.gpuLayers = 33,
    this.contextSize = 2048,
    this.temperature = 0.2,
    this.maxTokens = 256,
    this.threads = 4,
  });

  LlamaGpuConfig copyWith({
    int? gpuLayers,
    int? contextSize,
    double? temperature,
    int? maxTokens,
    int? threads,
  }) {
    return LlamaGpuConfig(
      gpuLayers: gpuLayers ?? this.gpuLayers,
      contextSize: contextSize ?? this.contextSize,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      threads: threads ?? this.threads,
    );
  }
}

/// Service wrapping native Gemma MediaPipe LLM engine & inference pipeline.
class LlamaDartService {
  LlamaGpuConfig config;
  bool _isModelLoaded = false;
  String? _loadedModelPath;

  LlamaDartService({this.config = const LlamaGpuConfig()}) {
    _loadedModelPath = 'gemma-2b-it.task';
    _isModelLoaded = true;
  }

  bool get isModelLoaded => _isModelLoaded;
  String? get loadedModelPath => _loadedModelPath;

  void updateConfig(LlamaGpuConfig newConfig) {
    config = newConfig;
  }

  Future<bool> loadModel(String modelPath) async {
    _loadedModelPath = modelPath;
    final success = await GemmaMediaPipeService.instance.initModel(customModelPath: modelPath);
    _isModelLoaded = success;
    return success;
  }

  /// Streams token-by-token completion for RAG queries and general conversational chat.
  Stream<String> generateAnswerStream({
    required String systemPrompt,
    required String retrievedContext,
    required String userQuestion,
  }) async* {
    final qLower = userQuestion.toLowerCase().trim();
    final hasContext = retrievedContext.isNotEmpty &&
        !retrievedContext.contains("No relevant memories found") &&
        !retrievedContext.contains("No items");

    List<String> words;

    if (_isGreeting(qLower)) {
      words = _greetingResponse();
    } else if (_isMetaQuestion(qLower)) {
      words = _metaResponse();
    } else if (qLower.contains('joke')) {
      words = _jokeResponse();
    } else if (qLower.contains('thank')) {
      words = _thanksResponse();
    } else if (hasContext) {
      if (GemmaMediaPipeService.instance.isInitialized) {
        final ragPrompt = """<start_of_turn>user
You are Glance AI. Answer the user's question directly, accurately, and concisely based strictly on the retrieved device memories.

Formatting & Structure Rules:
1. Relevance: Focus strictly on what the user asked. Do NOT talk about phone calls or call statistics unless the user specifically asked about calls.
2. Structure for clarity:
   - For lists, recaps, or multiple items: Start with a brief, clear introductory sentence. Then list each item on its own separate line using standard markdown bullets (- Item). Never combine multiple bullet items into a single line.
   - For direct questions: Give a clear, direct paragraph answer first, followed by supporting bullet details if helpful.
   - For count or breakdown queries: State the total count clearly, then provide a distinct bulleted breakdown.
3. Highlighting: Use bold (**App**, **Time/Date**, **Details**, **Count**) for important names and timestamps.
4. Clean output: Strictly NO emojis anywhere in the answer.

Retrieved Memories:
$retrievedContext

User Question: $userQuestion<end_of_turn>
<start_of_turn>model
""";
        try {
          // Hard cap AI latency to 20 seconds max to guarantee fast response
          final liveResponse = await GemmaMediaPipeService.instance
              .generateText(ragPrompt)
              .timeout(const Duration(seconds: 20));
          if (liveResponse.isNotEmpty &&
              !liveResponse.startsWith("Error") &&
              !liveResponse.startsWith("Model not loaded")) {
            words = liveResponse.split(' ').map((w) => '$w ').toList();
          } else {
            words = _synthesizeFromContext(retrievedContext, userQuestion);
          }
        } catch (_) {
          // Timeout or inference error: immediately provide synthesized result
          words = _synthesizeFromContext(retrievedContext, userQuestion);
        }
      } else {
        words = _synthesizeFromContext(retrievedContext, userQuestion);
      }
    } else {
      if (GemmaMediaPipeService.instance.isInitialized) {
        final prompt = """<start_of_turn>user
You are Glance AI. Answer the following question concisely in under 500 characters. Strictly NO emojis. Use markdown bolding for key terms:
$userQuestion<end_of_turn>
<start_of_turn>model
""";
        try {
          final liveResponse = await GemmaMediaPipeService.instance
              .generateText(prompt)
              .timeout(const Duration(seconds: 20));
          if (liveResponse.isNotEmpty &&
              !liveResponse.startsWith("Error") &&
              !liveResponse.startsWith("Model not loaded")) {
            words = liveResponse.split(' ').map((w) => '$w ').toList();
          } else {
            words = _noResultsResponse(userQuestion);
          }
        } catch (_) {
          words = _noResultsResponse(userQuestion);
        }
      } else {
        words = _noResultsResponse(userQuestion);
      }
    }

    final emojiRegex = RegExp(
      r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{1FA00}-\u{1FAFF}]',
      unicode: true,
    );

    final StringBuffer fullText = StringBuffer();
    for (final rawWord in words) {
      final word = rawWord.replaceAll(emojiRegex, '');
      if (word.trim().isEmpty && rawWord.trim().isNotEmpty) {
        continue;
      }
      if (fullText.length + word.length > 1000) {
        break; // Reasonable ceiling at 1000 characters max
      }
      fullText.write(word);
      await Future.delayed(const Duration(milliseconds: 14));
      yield word;
    }
  }

  List<String> _synthesizeFromContext(String context, String question) {
    final blocks = context
        .split('---')
        .where((b) => b.trim().isNotEmpty)
        .toList();

    if (blocks.isEmpty) return _noResultsResponse(question);

    final entries = blocks.map((b) => _ParsedMemory.fromBlock(b)).toList();
    final qLower = question.toLowerCase();

    // 1. Direct query intent matching first
    if (_isClipQuery(qLower)) {
      final clipEntries = entries
          .where((e) => e.type == 'COPIED TEXT' || e.type == 'CLIPBOARD')
          .toList();
      return _formatClipboardAnswer(
          clipEntries.isNotEmpty ? clipEntries : entries);
    }
    if (_isAppQuery(qLower)) {
      final appEntries =
          entries.where((e) => e.type == 'APP ACTIVITY').toList();
      return _formatAppUsageAnswer(
          appEntries.isNotEmpty ? appEntries : entries, qLower);
    }
    if (_isCallQuery(qLower)) {
      return _formatCallAnswer(entries, qLower, rawContext: context);
    }
    if (_isSmsQuery(qLower)) {
      return _formatSmsAnswer(entries, qLower, rawContext: context);
    }
    if (_isNotifQuery(qLower)) {
      final notifEntries = entries
          .where((e) => e.type == 'NOTIFICATION' || e.type == 'SMS')
          .toList();
      return _formatNotificationAnswer(
          notifEntries.isNotEmpty ? notifEntries : entries);
    }
    if (_isVisualQuery(qLower)) {
      final visEntries = entries
          .where((e) =>
              e.type == 'SCREENSHOT' ||
              e.type == 'PHOTO' ||
              e.type == 'CAMERA_CAPTURE')
          .toList();
      return _formatVisualAnswer(visEntries.isNotEmpty ? visEntries : entries);
    }

    // 2. If no specific intent keyword, check if ALL retrieved memories share a single type
    final types = entries.map((e) => e.type.toUpperCase()).toSet();
    if (types.length == 1) {
      final onlyType = types.first;
      if (onlyType == 'COPIED TEXT' || onlyType == 'CLIPBOARD') {
        return _formatClipboardAnswer(entries);
      }
      if (onlyType == 'APP ACTIVITY') {
        return _formatAppUsageAnswer(entries, qLower);
      }
      if (onlyType == 'CALL LOG' || onlyType == 'CALL') {
        return _formatCallAnswer(entries, qLower, rawContext: context);
      }
      if (onlyType == 'SMS') {
        return _formatSmsAnswer(entries, qLower, rawContext: context);
      }
      if (onlyType == 'SCREENSHOT' ||
          onlyType == 'PHOTO' ||
          onlyType == 'CAMERA_CAPTURE') {
        return _formatVisualAnswer(entries);
      }
      if (onlyType == 'NOTIFICATION') {
        return _formatNotificationAnswer(entries);
      }
    }

    // 3. Fallback to clean, well-spaced mixed memory summary
    return _formatMixedAnswer(entries, question);
  }

  bool _isCallQuery(String q) =>
      q.contains('call') ||
      q.contains('missed') ||
      q.contains('incoming') ||
      q.contains('outgoing') ||
      q.contains('phone') ||
      q.contains('dial');

  String _classifyTimeGroup(String timeStr) {
    final t = timeStr.toLowerCase().trim();
    if (t.isEmpty) return 'Today';
    if (t.contains('yesterday') || t == '1d ago' || t.startsWith('1 day')) {
      return 'Yesterday';
    }
    if (t.contains('2d ago') || t.contains('2 days')) {
      return '2 days ago';
    }
    if (t.contains('3d ago') || t.contains('3 days')) {
      return '3 days ago';
    }
    if (t.contains('d ago') || t.contains('week') || t.contains('month') || t.contains('year') || RegExp(r'\d{1,2}\s+[a-z]{3}').hasMatch(t)) {
      return timeStr.isNotEmpty ? timeStr : 'Earlier';
    }
    return 'Today';
  }

  List<String> _formatCallAnswer(List<_ParsedMemory> entries, String question, {String? rawContext}) {
    // 1. Try to extract exact statistics from rawContext header if present
    int totalCalls = 0;
    int incomingCount = 0;
    int outgoingCount = 0;
    int missedCount = 0;
    int rejectedCount = 0;

    bool foundStats = false;
    if (rawContext != null && rawContext.contains('[EXACT CALL STATISTICS FROM DATABASE]')) {
      final totalMatch = RegExp(r'Total Calls:\s*(\d+)').firstMatch(rawContext);
      final incomingMatch = RegExp(r'Incoming Calls:\s*(\d+)').firstMatch(rawContext);
      final outgoingMatch = RegExp(r'Outgoing Calls:\s*(\d+)').firstMatch(rawContext);
      final missedMatch = RegExp(r'Missed Calls:\s*(\d+)').firstMatch(rawContext);
      final rejectedMatch = RegExp(r'Rejected Calls:\s*(\d+)').firstMatch(rawContext);

      if (totalMatch != null) {
        totalCalls = int.tryParse(totalMatch.group(1)!) ?? 0;
        incomingCount = int.tryParse(incomingMatch?.group(1) ?? '0') ?? 0;
        outgoingCount = int.tryParse(outgoingMatch?.group(1) ?? '0') ?? 0;
        missedCount = int.tryParse(missedMatch?.group(1) ?? '0') ?? 0;
        rejectedCount = int.tryParse(rejectedMatch?.group(1) ?? '0') ?? 0;
        foundStats = true;
      }
    }

    // 2. Filter call entries from parsed memory items
    final callEntries = entries.where((e) {
      final t = e.type.toUpperCase();
      if (t == 'CALL LOG' || t == 'CALL') return true;
      final combined = '${e.fields['Title'] ?? ''} ${e.fields['Content'] ?? ''} ${e.fields['From'] ?? ''} ${e.fields['Details'] ?? ''} ${e.fields['Type'] ?? ''}'.toLowerCase();
      return combined.contains('call') || combined.contains('phone');
    }).toList();

    // If stats were not in header, compute from entries directly
    if (!foundStats) {
      for (final e in callEntries) {
        final text = '${e.fields['Type'] ?? ''} ${e.fields['Title'] ?? ''} ${e.fields['Content'] ?? ''} ${e.fields['Details'] ?? ''}'.toLowerCase();
        if (text.contains('incoming')) {
          incomingCount++;
        } else if (text.contains('outgoing')) {
          outgoingCount++;
        } else if (text.contains('missed')) {
          missedCount++;
        } else if (text.contains('rejected')) {
          rejectedCount++;
        }
      }
      totalCalls = callEntries.length;
    }

    final buffer = StringBuffer();
    final mentionsIncoming = question.contains('incoming');
    final mentionsOutgoing = question.contains('outgoing');
    final mentionsMissed = question.contains('missed');

    // Case A: Specific single category (e.g. only missed calls requested)
    if (mentionsMissed && !mentionsIncoming && !mentionsOutgoing) {
      buffer.writeln("Found **$missedCount missed ${missedCount == 1 ? 'call' : 'calls'}** (out of **$totalCalls total**):\n");
    } else if (mentionsIncoming && !mentionsOutgoing && !mentionsMissed) {
      buffer.writeln("Found **$incomingCount incoming ${incomingCount == 1 ? 'call' : 'calls'}** (out of **$totalCalls total**):\n");
    } else if (mentionsOutgoing && !mentionsIncoming && !mentionsMissed) {
      buffer.writeln("Found **$outgoingCount outgoing ${outgoingCount == 1 ? 'call' : 'calls'}** (out of **$totalCalls total**):\n");
    } else {
      // Case B: Multi-category or general call count query (e.g. "incoming and outgoing and missed calls count")
      buffer.writeln("Found **$totalCalls call ${totalCalls == 1 ? 'record' : 'records'}** in your Glance data:\n");
      buffer.writeln("• **Incoming Calls:** **$incomingCount**");
      buffer.writeln("• **Outgoing Calls:** **$outgoingCount**");
      buffer.writeln("• **Missed Calls:** **$missedCount**");
      if (rejectedCount > 0) {
        buffer.writeln("• **Rejected Calls:** **$rejectedCount**");
      }
      buffer.writeln("• **Total Calls:** **$totalCalls**\n");
    }

    // List recent calls grouped by date
    final Map<String, List<String>> groups = {};
    for (int i = 0; i < callEntries.length && i < 10; i++) {
      final entry = callEntries[i];
      final callType = entry.fields['Type'] ?? 'Call';
      final contact = entry.fields['Contact'] ?? entry.fields['Title'] ?? entry.fields['From'] ?? 'Phone';
      final time = entry.fields['Date'] ?? entry.fields['Time'] ?? '';

      String cleanContact = contact.replaceAll(RegExp(r'^(Incoming|Outgoing|Missed|Rejected)\s+Call:\s*', caseSensitive: false), '').trim();
      if (cleanContact.isEmpty) cleanContact = 'Unknown';

      final group = _classifyTimeGroup(time);
      final itemLine = "• **$callType**: $cleanContact${time.isNotEmpty ? ' — **$time**' : ''}";
      groups.putIfAbsent(group, () => []).add(itemLine);
    }

    if (groups.isNotEmpty) {
      buffer.writeln("**Recent Call Activity:**");
      for (final grp in groups.entries) {
        buffer.writeln("**${grp.key}**");
        for (final line in grp.value) {
          buffer.writeln(line);
        }
        buffer.writeln();
      }
    }

    final full = buffer.toString().trimRight();
    return full.split(' ').map((w) => '$w ').toList();
  }

  List<String> _formatSmsAnswer(List<_ParsedMemory> entries, String question, {String? rawContext}) {
    int totalSms = entries.length;
    int receivedSms = 0;
    int sentSms = 0;

    if (rawContext != null && rawContext.contains('[EXACT MESSAGE STATISTICS FROM DATABASE]')) {
      final totalMatch = RegExp(r'Total Messages:\s*(\d+)').firstMatch(rawContext);
      final recMatch = RegExp(r'Received Messages:\s*(\d+)').firstMatch(rawContext);
      final sentMatch = RegExp(r'Sent Messages:\s*(\d+)').firstMatch(rawContext);
      if (totalMatch != null) {
        totalSms = int.tryParse(totalMatch.group(1)!) ?? totalSms;
        receivedSms = int.tryParse(recMatch?.group(1) ?? '0') ?? 0;
        sentSms = int.tryParse(sentMatch?.group(1) ?? '0') ?? 0;
      }
    }

    final buffer = StringBuffer();
    buffer.writeln("Found **$totalSms SMS ${totalSms == 1 ? 'message' : 'messages'}**:\n");
    if (receivedSms > 0 || sentSms > 0) {
      buffer.writeln("• **Received:** **$receivedSms**");
      buffer.writeln("• **Sent:** **$sentSms**\n");
    }

    for (int i = 0; i < entries.length && i < 6; i++) {
      final entry = entries[i];
      final fromTo = entry.fields['From/To'] ?? entry.fields['Title'] ?? 'SMS';
      final msg = entry.fields['Message'] ?? entry.fields['Content'] ?? '';
      final time = entry.fields['Date'] ?? entry.fields['Time'] ?? '';

      final preview = msg.length > 80 ? '${msg.substring(0, 80)}...' : msg;
      buffer.writeln("• **$fromTo**${time.isNotEmpty ? ' — **$time**' : ''}");
      if (preview.isNotEmpty) {
        buffer.writeln("  $preview");
      }
    }

    final full = buffer.toString().trimRight();
    return full.split(' ').map((w) => '$w ').toList();
  }

  List<String> _formatAppUsageAnswer(List<_ParsedMemory> entries, String question) {
    final Map<String, _AppUsageRecord> appMap = {};

    for (final entry in entries) {
      String appName = entry.fields['App'] ?? entry.fields['Details'] ?? 'App';
      if (appName.contains(' (')) {
        appName = appName.split(' (').first.trim();
      }
      if (appName.startsWith('com.') && appName.contains('.')) {
        final parts = appName.split('.');
        appName = parts.last;
        if (appName.isNotEmpty) {
          appName = appName[0].toUpperCase() + appName.substring(1);
        }
      }

      final lastActive = entry.fields['Last Active'] ?? '';
      final opensRaw = entry.fields['Opens'] ?? '1';
      final usageStr = entry.fields['Usage Time'] ?? '< 1m';

      int opens = int.tryParse(RegExp(r'\d+').firstMatch(opensRaw)?.group(0) ?? '1') ?? 1;

      if (!appMap.containsKey(appName)) {
        appMap[appName] = _AppUsageRecord(
          name: appName,
          lastActive: lastActive,
          opens: opens,
          usageTime: usageStr,
        );
      } else {
        final existing = appMap[appName]!;
        appMap[appName] = _AppUsageRecord(
          name: appName,
          lastActive: existing.lastActive.isEmpty ? lastActive : existing.lastActive,
          opens: existing.opens + opens,
          usageTime: existing.usageTime == '< 1m' ? usageStr : existing.usageTime,
        );
      }
    }

    final buffer = StringBuffer();
    final isYesterday = question.toLowerCase().contains('yesterday');
    buffer.writeln(isYesterday ? "Yesterday's app usage breakdown:\n" : "App usage breakdown:\n");

    for (final app in appMap.values) {
      final line = "• **${app.name}**: **${app.usageTime}** used • **${app.opens} ${app.opens == 1 ? 'open' : 'opens'}** • Last active **${app.lastActive}**\n";
      if (buffer.length + line.length > 480) {
        break; // Hard limit 500 characters
      }
      buffer.write(line);
    }

    final full = buffer.toString().trimRight();
    return full.split(' ').map((w) => '$w ').toList();
  }

  List<String> _formatClipboardAnswer(List<_ParsedMemory> entries) {
    final buffer = StringBuffer();
    buffer.writeln("Here is the text you copied recently:\n");

    for (int i = 0; i < entries.length && i < 6; i++) {
      final entry = entries[i];
      final content = entry.fields['Content'] ?? '';
      final copiedAt = entry.fields['Copied At'] ?? '';
      final source = entry.fields['Source'] ?? 'Clipboard';

      final preview =
          content.length > 120 ? '${content.substring(0, 120)}...' : content;
      final timeStr = copiedAt.isNotEmpty ? "**$copiedAt**" : "";
      final sourceStr =
          (source.isNotEmpty && source != 'Clipboard') ? " ($source)" : "";

      buffer.writeln("- $timeStr$sourceStr: \"$preview\"\n");
      if (buffer.length > 480) break;
    }

    final full = buffer.toString().trimRight();
    return full.split(' ').map((w) => '$w ').toList();
  }

  List<String> _formatNotificationAnswer(List<_ParsedMemory> entries) {
    final buffer = StringBuffer();
    buffer.writeln("Recent notifications:\n");

    for (int i = 0; i < entries.length && i < 6; i++) {
      final entry = entries[i];
      final from = entry.fields['From'] ?? 'App';
      final title = entry.fields['Title'] ?? '';
      final content = entry.fields['Content'] ?? '';
      final time = entry.fields['Time'] ?? '';

      final line = StringBuffer();
      line.write("• **$from**");
      if (title.isNotEmpty && title != from) line.write(": $title");
      if (time.isNotEmpty) line.write(" — **$time**");
      line.writeln();
      if (content.isNotEmpty && content != title) {
        final preview = content.length > 80 ? '${content.substring(0, 80)}...' : content;
        line.writeln("  $preview");
      }

      if (buffer.length + line.length > 480) break;
      buffer.write(line.toString());
    }

    final full = buffer.toString().trimRight();
    return full.split(' ').map((w) => '$w ').toList();
  }

  List<String> _formatVisualAnswer(List<_ParsedMemory> entries) {
    final buffer = StringBuffer();
    buffer.writeln("Recent captures:\n");

    for (int i = 0; i < entries.length && i < 5; i++) {
      final entry = entries[i];
      final file = entry.fields['File'] ?? 'Capture';
      final captured = entry.fields['Captured'] ?? '';
      final content = entry.fields['Content'] ?? '';

      final line = StringBuffer();
      line.write("• **$file**");
      if (captured.isNotEmpty) line.write(" — **$captured**");
      line.writeln();
      if (content.isNotEmpty && content.length > 10) {
        final preview = content.length > 80 ? '${content.substring(0, 80)}...' : content;
        line.writeln("  $preview");
      }

      if (buffer.length + line.length > 480) break;
      buffer.write(line.toString());
    }

    final full = buffer.toString().trimRight();
    return full.split(' ').map((w) => '$w ').toList();
  }

  List<String> _formatMixedAnswer(List<_ParsedMemory> entries, String question) {
    final buffer = StringBuffer();
    buffer.writeln("Here are the matching memories found:\n");

    final Map<String, List<String>> groups = {};
    for (int i = 0; i < entries.length && i < 6; i++) {
      final entry = entries[i];
      final mainField = entry.fields['Content'] ??
          entry.fields['Details'] ??
          entry.fields['Title'] ??
          '';

      final preview = mainField.length > 120 ? '${mainField.substring(0, 120)}...' : mainField;
      final source = entry.fields['App'] ??
          entry.fields['From'] ??
          entry.fields['Source'] ??
          '';
      final time = entry.fields['Last Active'] ??
          entry.fields['Time'] ??
          entry.fields['Copied At'] ??
          entry.fields['Captured'] ??
          entry.fields['Date'] ??
          '';

      final itemLine =
          "• ${source.isNotEmpty ? '**$source**: ' : ''}$preview${time.isNotEmpty ? ' — **$time**' : ''}";

      final group = _classifyTimeGroup(time);
      groups.putIfAbsent(group, () => []).add(itemLine);
    }

    for (final grp in groups.entries) {
      buffer.writeln("**${grp.key}**");
      for (final line in grp.value) {
        buffer.writeln(line);
      }
      buffer.writeln(); // Gaps between date groups
    }

    final full = buffer.toString().trimRight();
    return full.split(' ').map((w) => '$w ').toList();
  }

  bool _isAppQuery(String q) =>
      q.contains('app') || q.contains('usage') || q.contains('use') ||
      q.contains('open') || q.contains('time') || q.contains('screen') ||
      q.contains('activity') || q.contains('launch') ||
      q.contains('today') || q.contains('yesterday') || q.contains('history');

  bool _isClipQuery(String q) =>
      q.contains('cop') || q.contains('clip') || q.contains('paste') || q.contains('text');

  bool _isSmsQuery(String q) =>
      q.contains('sms') || q.contains('text message') || q.contains('inbox');

  bool _isNotifQuery(String q) =>
      q.contains('notif') || q.contains('alert') || q.contains('notification');

  bool _isVisualQuery(String q) =>
      q.contains('photo') ||
      q.contains('image') ||
      q.contains('screenshot') ||
      q.contains('picture') ||
      q.contains('camera') ||
      q.contains('gallery');

  bool _isGreeting(String q) {
    return q == 'hi' || q == 'hello' || q == 'hey' || q.startsWith('hi ') ||
        q.startsWith('hello ') || q.startsWith('hey ') ||
        q.startsWith('good morning') || q.startsWith('good evening') ||
        q.startsWith('good afternoon');
  }

  bool _isMetaQuestion(String q) {
    return q.contains('how are you') || q.contains('who are you') || q.contains('what can you do');
  }

  List<String> _greetingResponse() {
    return [
      "Hello!", " How", " can", " I", " help", " you", " today?",
      " You", " can", " ask", " me", " anything", "—", "whether", " it's", " about",
      " your", " device", " activity,", " screenshots,", " copied", " text,", " or", " general", " questions!"
    ];
  }

  List<String> _metaResponse() {
    return [
      "I", " am", " your", " Glance", " AI", " Assistant.", " Powered", " by", " Gemma", " MediaPipe.",
      " I", " can", " help", " you", " recall", " anything", " on", " your", " device!"
    ];
  }

  List<String> _jokeResponse() {
    return [
      "Here's", " a", " quick", " joke", " for", " you:\n\n",
      "Why", " do", " programmers", " prefer", " dark", " mode?\n\n",
      "Because", " light", " attracts", " bugs!"
    ];
  }

  List<String> _thanksResponse() {
    return [
      "You're", " very", " welcome!", " Let", " me", " know", " if", " you", " need", " anything", " else."
    ];
  }

  List<String> _noResultsResponse(String question) {
    return [
      "I", " searched", " your", " device", " memories", " for", " '", question, "',",
      " but", " couldn't", " find", " matching", " results.", "\n\n",
      "Try", " asking", " about:\n",
      "• Your", " recent", " app", " activity\n",
      "• Copied", " text", " history\n",
      "• Screenshots", " you've", " taken\n",
      "• Notifications", " or", " missed", " calls\n",
    ];
  }
}

class _ParsedMemory {
  final String type;
  final Map<String, String> fields;

  _ParsedMemory({required this.type, required this.fields});

  factory _ParsedMemory.fromBlock(String block) {
    final lines = block.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    String type = 'UNKNOWN';
    final fields = <String, String>{};

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.startsWith('[Memory')) {
        final afterBracket = trimmed.replaceFirst(RegExp(r'\[Memory \d+\]\s*'), '');
        type = afterBracket.replaceAll('(', '').replaceAll(')', '').trim();
        continue;
      }

      if (trimmed.startsWith('- ')) {
        final fieldStr = trimmed.substring(2);
        final colonIdx = fieldStr.indexOf(':');
        if (colonIdx > 0) {
          final key = fieldStr.substring(0, colonIdx).trim();
          final value = fieldStr.substring(colonIdx + 1).trim();
          fields[key] = value;
        }
      }
    }

    return _ParsedMemory(type: type, fields: fields);
  }
}

class _AppUsageRecord {
  final String name;
  final String lastActive;
  final int opens;
  final String usageTime;

  _AppUsageRecord({
    required this.name,
    required this.lastActive,
    required this.opens,
    required this.usageTime,
  });
}
