// lib/screens/flashcard_screen.dart
//
// FlashcardScreen — AI-generated flashcards with swipe-based spaced repetition.
//
// Flow:
//   1. Generate phase  — shows loading state while AI creates cards.
//   2. Review phase    — full-screen card flip + swipe (right = know, left = again).
//   3. Results phase   — mastered count, XP earned, option to retry missed cards.

import "dart:math" as math;

import "package:flutter/material.dart";

import "../design_tokens.dart";
import "../models/app_models.dart";
import "../models/study_material_models.dart";
import "../services/claude_service_study.dart";

// ── Public Entry ──────────────────────────────────────────────────────────────

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({
    super.key,
    required this.subject,
    required this.content,
    this.taskName,
    this.profile,
    this.cardCount = 10,
  });

  final String subject;
  final String content;
  final String? taskName;
  final UserProfile? profile;
  final int cardCount;

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen>
    with TickerProviderStateMixin {
  // ── State ─────────────────────────────────────────────────────────────────
  List<FlashCard> _cards = <FlashCard>[];
  bool _loading = true;
  String? _error;

  int _currentIndex = 0;
  bool _showingBack = false;
  int _masteredCount = 0;
  int _againCount = 0;

  // Tracks which cards go back into the deck (again)
  final List<FlashCard> _againQueue = <FlashCard>[];

  // Phase: "generate" | "review" | "results"
  String _phase = "generate";

  // Difficulty selection
  String _difficulty = "medium";

  // ── Animation ─────────────────────────────────────────────────────────────
  late AnimationController _flipCtrl;
  late AnimationController _swipeCtrl;
  double _swipeDx = 0;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _swipeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _generateCards();
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    _swipeCtrl.dispose();
    super.dispose();
  }

  // ── Generation ────────────────────────────────────────────────────────────

  Future<void> _generateCards() async {
    setState(() {
      _loading = true;
      _error = null;
      _phase = "generate";
    });

    final List<FlashCard> cards = await ClaudeStudyService.generateFlashcards(
      subject: widget.subject,
      content: widget.content,
      count: widget.cardCount,
      difficulty: _difficulty,
      profile: widget.profile,
    );

    if (!mounted) return;

    if (cards.isEmpty) {
      setState(() {
        _loading = false;
        _error = "Couldn't generate flashcards. Check your connection and try again.";
      });
      return;
    }

    setState(() {
      _cards = cards;
      _loading = false;
      _currentIndex = 0;
      _showingBack = false;
      _masteredCount = 0;
      _againCount = 0;
      _againQueue.clear();
      _phase = "review";
    });
  }

  // ── Flashcard interactions ────────────────────────────────────────────────

  void _flipCard() {
    if (_flipCtrl.isAnimating) return;
    if (_showingBack) {
      _flipCtrl.reverse();
    } else {
      _flipCtrl.forward();
    }
    setState(() => _showingBack = !_showingBack);
  }

  void _handleKnow() {
    if (!_showingBack) {
      // Nudge user to see the answer first
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Flip the card first to see the answer!"),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _masteredCount++);
    _nextCard();
  }

  void _handleAgain() {
    if (_currentIndex < _cards.length) {
      _againQueue.add(_cards[_currentIndex]);
      setState(() => _againCount++);
    }
    _nextCard();
  }

  void _nextCard() {
    // Reset flip
    _flipCtrl.reset();
    setState(() {
      _showingBack = false;
      _currentIndex++;
    });

    if (_currentIndex >= _cards.length) {
      // First pass done — add again-queue to review, or show results
      if (_againQueue.isNotEmpty) {
        setState(() {
          _cards = List<FlashCard>.from(_againQueue);
          _againQueue.clear();
          _currentIndex = 0;
        });
      } else {
        setState(() => _phase = "results");
      }
    }
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text("Flashcards",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kDark)),
            Text(widget.subject, style: kSubtitle),
          ],
        ),
        actions: <Widget>[
          if (_phase == "review")
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  "${_currentIndex + 1} / ${_cards.length}",
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kMuted),
                ),
              ),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (_phase) {
          "generate" => _buildGenerating(),
          "review" => _buildReview(),
          "results" => _buildResults(),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  // ── Generating phase ──────────────────────────────────────────────────────

  Widget _buildGenerating() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text("😕",
                  style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kMuted, fontSize: 14)),
              const SizedBox(height: 24),
              DarkPillButton(label: "Try Again", onPressed: _generateCards),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Difficulty selector shown before generating
          if (_loading == false) ...<Widget>[
            const Text("Select difficulty",
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: kDark)),
            const SizedBox(height: 16),
            _DifficultySelector(
              value: _difficulty,
              onChanged: (String d) => setState(() => _difficulty = d),
            ),
            const SizedBox(height: 24),
            DarkPillButton(
                label: "Generate ${widget.cardCount} Cards",
                onPressed: _generateCards),
          ] else ...<Widget>[
            const SunMascot(walking: true, size: 80),
            const SizedBox(height: 24),
            Text(
              "Generating flashcards for\n${widget.subject}…",
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: kDark,
                  height: 1.4),
            ),
            const SizedBox(height: 16),
            const BouncingDots(),
          ],
        ],
      ),
    );
  }

  // ── Review phase ──────────────────────────────────────────────────────────

  Widget _buildReview() {
    if (_currentIndex >= _cards.length) return const SizedBox.shrink();
    final FlashCard card = _cards[_currentIndex];
    final int total = _masteredCount + _againCount;
    final double progress = _cards.length > 0
        ? _currentIndex / (_cards.length + _againQueue.length)
        : 0;

    return Column(
      children: <Widget>[
        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: kOrangeSoft,
              valueColor: const AlwaysStoppedAnimation<Color>(kOrange),
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Stats row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              _StatChip(
                  icon: Icons.check_circle_outline_rounded,
                  label: "$_masteredCount know",
                  color: kGreen),
              _StatChip(
                  icon: Icons.replay_rounded,
                  label: "$_againCount again",
                  color: kPink),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Card
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: _flipCard,
              child: AnimatedBuilder(
                animation: _flipCtrl,
                builder: (_, __) {
                  final double angle = _flipCtrl.value * math.pi;
                  final bool showFront = angle <= math.pi / 2;
                  return Transform(
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    alignment: Alignment.center,
                    child: Transform(
                      transform: showFront
                          ? Matrix4.identity()
                          : (Matrix4.identity()..rotateY(math.pi)),
                      alignment: Alignment.center,
                      child: showFront
                          ? _CardFace(
                              label: "QUESTION",
                              text: card.front,
                              hint: card.hint,
                              accentColor: kOrange,
                              isBack: false,
                            )
                          : _CardFace(
                              label: "ANSWER",
                              text: card.back,
                              accentColor: kGreen,
                              isBack: true,
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // Tap hint
        if (!_showingBack)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text("Tap card to reveal answer",
                style: TextStyle(fontSize: 12, color: kMuted)),
          ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _ActionButton(
                  label: "Again 🔄",
                  color: kPink,
                  onTap: _handleAgain,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  label: "Know It ✓",
                  color: kGreen,
                  onTap: _handleKnow,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Results phase ─────────────────────────────────────────────────────────

  Widget _buildResults() {
    final int total = _masteredCount + _againCount;
    final double pct =
        total > 0 ? _masteredCount / total : 0.0;
    final int xp = (_masteredCount * 5).clamp(5, 50);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        children: <Widget>[
          const SunMascot(size: 80),
          const SizedBox(height: 16),
          Text(
            pct >= 0.8
                ? "Excellent work! 🎉"
                : pct >= 0.5
                    ? "Good progress! 💪"
                    : "Keep practicing — you'll get there! 📚",
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: kDark,
                letterSpacing: -0.4),
          ),
          const SizedBox(height: 24),

          // Score card
          LocketCard(
            child: Column(
              children: <Widget>[
                _ResultRow(
                    emoji: "✅",
                    label: "Cards mastered",
                    value: "$_masteredCount",
                    color: kGreen),
                const Divider(height: 20),
                _ResultRow(
                    emoji: "🔄",
                    label: "Needs more review",
                    value: "$_againCount",
                    color: kPink),
                const Divider(height: 20),
                _ResultRow(
                    emoji: "⚡",
                    label: "XP earned",
                    value: "+$xp XP",
                    color: kYellow),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Progress ring
          _ScoreRing(value: pct),
          const SizedBox(height: 28),

          // Actions
          DarkPillButton(
            label: "New Round — ${widget.cardCount} Cards",
            onPressed: _generateCards,
            icon: Icons.refresh_rounded,
          ),
          const SizedBox(height: 12),
          OutlinePillButton(
            label: "Back to Study Hub",
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

// ── Card Face ─────────────────────────────────────────────────────────────────

class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.label,
    required this.text,
    required this.accentColor,
    required this.isBack,
    this.hint = "",
  });

  final String label;
  final String text;
  final Color accentColor;
  final bool isBack;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: accentColor.withOpacity(0.35), width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: kDark.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                    letterSpacing: 0.8),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: kDark,
                height: 1.45,
                letterSpacing: -0.2,
              ),
            ),
            if (!isBack && hint.isNotEmpty) ...<Widget>[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: kOrangeSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "Hint: $hint",
                  style: const TextStyle(
                      fontSize: 12,
                      color: kMuted,
                      fontStyle: FontStyle.italic),
                ),
              ),
            ],
            if (!isBack) ...<Widget>[
              const SizedBox(height: 28),
              const Text("Tap to reveal",
                  style: TextStyle(fontSize: 11, color: kMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Supporting Widgets ────────────────────────────────────────────────────────

class _DifficultySelector extends StatelessWidget {
  const _DifficultySelector(
      {required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <String>["easy", "medium", "hard"].map((String d) {
        final bool sel = value == d;
        return GestureDetector(
          onTap: () => onChanged(d),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? kDark : kSurface,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                  color: sel ? kDark : kMuted.withOpacity(0.3),
                  width: 1.5),
            ),
            child: Text(
              d[0].toUpperCase() + d.substring(1),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : kDark,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.label,
      required this.color,
      required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
              color: color.withOpacity(0.45), width: 1.5),
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kDark)),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kDark)),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow(
      {required this.emoji,
      required this.label,
      required this.value,
      required this.color});
  final String emoji;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: kDark, fontWeight: FontWeight.w500))),
        Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color)),
      ],
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CircularProgressIndicator(
            value: value,
            strokeWidth: 10,
            backgroundColor: kOrangeSoft,
            valueColor: AlwaysStoppedAnimation<Color>(
                value >= 0.8
                    ? kSuccess
                    : value >= 0.5
                        ? kOrange
                        : kError),
          ),
          Text(
            "${(value * 100).round()}%",
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: kDark),
          ),
        ],
      ),
    );
  }
}
