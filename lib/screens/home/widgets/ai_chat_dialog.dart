import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/glance_providers.dart';
import '../../../core/rag/context_builder.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<String>? sources;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.sources,
  });
}

/// Dialog for interactive AI Memory Chat powered by Llamadart GGUF generator and Hybrid RAG.
class AiChatDialog extends ConsumerStatefulWidget {
  const AiChatDialog({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AiChatDialog(),
    );
  }

  @override
  ConsumerState<AiChatDialog> createState() => _AiChatDialogState();
}

class _AiChatDialogState extends ConsumerState<AiChatDialog> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _messages.add(
      ChatMessage(
        text: "Hello! I am your Glance AI Assistant. Ask me anything—your device activity, copied text, screenshots, or any question on your mind!",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage(String query) async {
    if (query.trim().isEmpty || _isGenerating) return;

    _controller.clear();
    setState(() {
      _messages.add(
        ChatMessage(
          text: query,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
      _isGenerating = true;
    });

    _scrollToBottom();

    // 1. Hybrid RAG Candidate Retrieval
    final retriever = ref.read(hybridRetrieverProvider);
    final llamaService = ref.read(llamaServiceProvider);

    final candidates = await retriever.retrieve(
      userQuery: query,
      candidateLimit: 500,
      finalLimit: 250,
    );
    final contextBlock = ContextBuilder.buildContext(
      candidates,
      userQuestion: query,
    );
    final sourceLabels = candidates.take(3).map((c) => "${c.memory.type.toUpperCase()} from ${c.memory.sourceApp ?? 'App'}").toList();

    // Add initial placeholder message for AI streaming
    final aiMessageIndex = _messages.length;
    setState(() {
      _messages.add(
        ChatMessage(
          text: "",
          isUser: false,
          timestamp: DateTime.now(),
          sources: sourceLabels.isNotEmpty ? sourceLabels : null,
        ),
      );
    });

    StringBuffer responseBuffer = StringBuffer();

    // 2. Stream generation via Llamadart Engine
    final stream = llamaService.generateAnswerStream(
      systemPrompt: ContextBuilder.systemPrompt,
      retrievedContext: contextBlock,
      userQuestion: query,
    );

    await for (final token in stream) {
      if (!mounted) break;
      responseBuffer.write(token);
      setState(() {
        _messages[aiMessageIndex] = ChatMessage(
          text: responseBuffer.toString(),
          isUser: false,
          timestamp: DateTime.now(),
          sources: sourceLabels.isNotEmpty ? sourceLabels : null,
        );
      });
      _scrollToBottom();
    }

    if (mounted) {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle & Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E7EB),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.auto_awesome, color: primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Glance AI Assistant',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      'Ask anything • Memory & Chat Engine',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ],
            ),
          ),

          // Suggestion Chips (shown when few messages)
          if (_messages.length <= 2)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildSuggestionChip('What did I do today?'),
                    _buildSuggestionChip('Tell me a joke'),
                    _buildSuggestionChip('What apps did I open?'),
                    _buildSuggestionChip('Search copied text'),
                  ],
                ),
              ),
            ),

          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildChatBubble(msg, isDark, primaryColor);
              },
            ),
          ),

          // Input Bar
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF181818) : const Color(0xFFF9FAFB),
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E7EB),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Ask anything (memories, questions, tasks)...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.grey[500] : Colors.grey[400],
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.send_rounded, color: primaryColor),
                  onPressed: _isGenerating ? null : () => _sendMessage(_controller.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        backgroundColor: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF0F4F8),
        onPressed: () => _sendMessage(label),
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage msg, bool isDark, Color primaryColor) {
    final isUser = msg.isUser;
    final bubbleColor = isUser
        ? primaryColor
        : (isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF3F4F6));
    final textColor = isUser
        ? Colors.white
        : (isDark ? Colors.white : const Color(0xFF111418));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, color: primaryColor, size: 14),
            ),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                  ),
                  child: Text(
                    msg.text.isEmpty ? "Thinking..." : msg.text,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                if (msg.sources != null && msg.sources!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: msg.sources!.map((s) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
