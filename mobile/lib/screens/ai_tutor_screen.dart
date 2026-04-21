// lib/screens/ai_tutor_screen.dart
//
// AiTutorScreen — a conversational AI study assistant.
//
// Features:
//   • Full chat interface with streaming-style text reveal.
//   • Context-aware: knows the student's subject, task, and profile.
//   • Quick-prompt chips for common questions (e.g. "Explain this topic",
//     "Give me an example", "Make it simpler", "What could be tested?").
//   • Typing indicator while AI is generating.
//   • Chat history preserved for the session (up to 20 turns).

import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../design_tokens.dart";
import "../models/app_models.dart";
import "../models/study_material_models.dart";
import "../services/claude_service_study.dart";

// ── Public Entry ──────────────────────────────────────────────────────────────

class AiTutorScreen extends StatefulWidget {
  const AiTutorScreen({
    super.key,
    required this.subject,
    this.taskContext = "",
    this.taskName,
    this.profile,
    this.playerLevel = 1,
  });

  final String subject;
  final String taskContext;
  final String? taskName;
  final UserProfile? profile;
  final int playerLevel;

  @override
  State<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends State<AiTutorScreen> {
  final List<TutorMessage> _messages = <TutorMessage>[];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  bool _sending = false;
  bool _inputEnabled = true;

  // ── Quick prompt chips ────────────────────────────────────────────────────

  static const List<_QuickPrompt> _quickPrompts = <_QuickPrompt>[
    _QuickPrompt(
        label: "Explain this topic",
        emoji: "📖",
        template:
            "Can you give me a clear, simple explanation of the key concepts in {subject}?"),
    _QuickPrompt(
        label: "Give me an example",
        emoji: "💡",
        template:
            "Can you give me a concrete real-world example that illustrates the main idea in {subject}?"),
    _QuickPrompt(
        label: "Make it simpler",
        emoji: "🔤",
        template:
            "Explain {subject} as if I were encountering it for the first time. Use simple language and an analogy."),
    _QuickPrompt(
        label: "What could be tested?",
        emoji: "📝",
        template:
            "Based on {subject}, what are the most likely concepts or questions that could appear in an exam?"),
    _QuickPrompt(
        label: "Common mistakes",
        emoji: "⚠️",
        template:
            "What are the most common mistakes students make when studying {subject}, and how do I avoid them?"),
    _QuickPrompt(
        label: "Memory trick",
        emoji: "🧠",
        template:
            "Give me a mnemonic or memory trick to remember the key points of {subject}."),
  ];

  bool _showQuickPrompts = true;

  @override
  void initState() {
    super.initState();
    // Initial greeting from the tutor
    _messages.add(TutorMessage(
      role: "assistant",
      content:
          "Hi! I'm your AI study tutor 🎓\n\n"
          "I'm here to help you understand **${widget.subject}**"
          "${widget.taskName != null ? ' — specifically for *${widget.taskName}*' : ''}.\n\n"
          "Ask me anything: concepts, examples, practice problems, or revision tips. "
          "What would you like to explore first?",
      timestamp: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Messaging ─────────────────────────────────────────────────────────────

  Future<void> _send(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;

    _inputCtrl.clear();
    setState(() {
      _sending = true;
      _inputEnabled = false;
      _showQuickPrompts = false;

      _messages.add(TutorMessage(
        role: "user",
        content: trimmed,
        timestamp: DateTime.now(),
      ));

      // Placeholder typing indicator
      _messages.add(TutorMessage(
        role: "assistant",
        content: "",
        timestamp: DateTime.now(),
        isLoading: true,
      ));
    });

    _scrollToBottom();

    final String reply = await ClaudeStudyService.chatWithTutor(
      history: _messages
          .where((TutorMessage m) => !m.isLoading)
          .toList()
          .sublist(0, _messages
                  .where((TutorMessage m) => !m.isLoading)
                  .length -
              1), // exclude just-added user message from history
      userMessage: trimmed,
      subject: widget.subject,
      taskContext: widget.taskContext,
      profile: widget.profile,
      playerLevel: widget.playerLevel,
    );

    if (!mounted) return;

    setState(() {
      // Replace loading placeholder
      _messages.removeWhere((TutorMessage m) => m.isLoading);
      _messages.add(TutorMessage(
        role: "assistant",
        content: reply,
        timestamp: DateTime.now(),
      ));
      _sending = false;
      _inputEnabled = true;
    });

    _scrollToBottom();
  }

  void _sendQuickPrompt(_QuickPrompt prompt) {
    final String text =
        prompt.template.replaceAll("{subject}", widget.subject);
    _send(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Copied to clipboard"),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFF1A1410),
                shape: BoxShape.circle,
              ),
              child: const Center(
                  child: Text("🤖",
                      style: TextStyle(fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text("AI Study Tutor",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kDark)),
                Text(widget.subject,
                    style: kSubtitle),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: kMuted, size: 20),
            tooltip: "Clear chat",
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // ── Chat messages ─────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: _messages.length +
                  (_showQuickPrompts ? 1 : 0),
              itemBuilder: (_, int i) {
                if (_showQuickPrompts &&
                    i == _messages.length) {
                  return _QuickPromptChips(
                    prompts: _quickPrompts,
                    onSelect: _sendQuickPrompt,
                  );
                }
                return _MessageBubble(
                  message: _messages[i],
                  onCopy: () => _copyMessage(_messages[i].content),
                );
              },
            ),
          ),

          // ── Input bar ─────────────────────────────────────────────────────
          _InputBar(
            controller: _inputCtrl,
            enabled: _inputEnabled,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  void _confirmClear() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text("Clear Chat",
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: kDark)),
        content: const Text(
          "This will delete the entire conversation. Continue?",
          style: TextStyle(fontSize: 13, color: kMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel",
                style: TextStyle(color: kMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _messages.clear();
                _showQuickPrompts = true;
                _messages.add(TutorMessage(
                  role: "assistant",
                  content:
                      "Chat cleared! What would you like to study next?",
                  timestamp: DateTime.now(),
                ));
              });
            },
            child: const Text("Clear",
                style: TextStyle(
                    color: kError, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Message Bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {required this.message, required this.onCopy});
  final TutorMessage message;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.isUser;

    if (message.isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            _Avatar(isUser: false),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                      color: kDark.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: const BouncingDots(),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onLongPress: !isUser ? onCopy : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (!isUser) ...<Widget>[
              _Avatar(isUser: false),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isUser ? kDark : kSurface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 18),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                        color: kDark.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: _RichText(
                  text: message.content,
                  color: isUser ? Colors.white : kDark,
                ),
              ),
            ),
            if (isUser) ...<Widget>[
              const SizedBox(width: 8),
              _Avatar(isUser: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.isUser});
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: isUser ? kOrange : const Color(0xFF1A1410),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          isUser ? "👤" : "🤖",
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}

/// Renders simple markdown-like text: **bold**, *italic*, bullet lists.
class _RichText extends StatelessWidget {
  const _RichText({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Build inline-styled text spans for **bold** and *italic*
    final List<TextSpan> spans = _parseMarkdown(text, color);
    return RichText(
      text: TextSpan(children: spans),
    );
  }

  static List<TextSpan> _parseMarkdown(String text, Color baseColor) {
    final List<TextSpan> spans = <TextSpan>[];
    // Replace \n with actual newlines, handle bullet points
    final String processed = text
        .replaceAll("\\n", "\n")
        .replaceAll("• ", "\n• ");

    final RegExp pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');
    int last = 0;

    for (final RegExpMatch match in pattern.allMatches(processed)) {
      if (match.start > last) {
        spans.add(TextSpan(
          text: processed.substring(last, match.start),
          style: TextStyle(
              fontSize: 14,
              color: baseColor,
              height: 1.5,
              fontWeight: FontWeight.w400),
        ));
      }

      if (match.group(1) != null) {
        // **bold**
        spans.add(TextSpan(
          text: match.group(1),
          style: TextStyle(
              fontSize: 14,
              color: baseColor,
              fontWeight: FontWeight.w700,
              height: 1.5),
        ));
      } else if (match.group(2) != null) {
        // *italic*
        spans.add(TextSpan(
          text: match.group(2),
          style: TextStyle(
              fontSize: 14,
              color: baseColor,
              fontStyle: FontStyle.italic,
              height: 1.5),
        ));
      }

      last = match.end;
    }

    if (last < processed.length) {
      spans.add(TextSpan(
        text: processed.substring(last),
        style: TextStyle(
            fontSize: 14,
            color: baseColor,
            height: 1.5,
            fontWeight: FontWeight.w400),
      ));
    }

    return spans.isEmpty
        ? <TextSpan>[
            TextSpan(
                text: processed,
                style: TextStyle(
                    fontSize: 14,
                    color: baseColor,
                    height: 1.5))
          ]
        : spans;
  }
}

// ── Quick Prompt Chips ────────────────────────────────────────────────────────

class _QuickPrompt {
  const _QuickPrompt(
      {required this.label,
      required this.emoji,
      required this.template});
  final String label;
  final String emoji;
  final String template;
}

class _QuickPromptChips extends StatelessWidget {
  const _QuickPromptChips(
      {required this.prompts, required this.onSelect});
  final List<_QuickPrompt> prompts;
  final ValueChanged<_QuickPrompt> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              "Quick Questions",
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: kMuted),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: prompts
                .map((p) => GestureDetector(
                      onTap: () => onSelect(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                              color: kMuted.withOpacity(0.2),
                              width: 1.2),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                                color: kDark.withOpacity(0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(p.emoji,
                                style: const TextStyle(
                                    fontSize: 13)),
                            const SizedBox(width: 6),
                            Text(p.label,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: kDark)),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ── Input Bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(
            top: BorderSide(
                color: kMuted.withOpacity(0.12), width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: "Ask anything about ${controller.text.isEmpty ? 'the topic' : '...'}",
                hintStyle:
                    const TextStyle(color: kMuted, fontSize: 14),
                filled: true,
                fillColor: kBg,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                      color: kOrange, width: 1.5),
                ),
              ),
              style: const TextStyle(
                  fontSize: 14, color: kDark, height: 1.4),
              onSubmitted: enabled ? onSend : null,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: enabled
                ? () => onSend(controller.text)
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: enabled ? kDark : kMuted.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
