// lib/screens/ai_study_hub_screen.dart
//
// AI Study Hub — the central entry point for all AI-powered learning tools.
// Houses four pillars: Flashcards, Quiz, Study Materials, and AI Tutor chat.
// Accessible as a tab or from individual task cards via deep-link.

import "package:flutter/material.dart";
import "package:intl/intl.dart";

import "../design_tokens.dart";
import "../models/app_models.dart";
import "../models/study_material_models.dart";
import "../services/firestore_repository.dart";
import "flashcard_screen.dart";
import "quiz_screen.dart";
import "ai_tutor_screen.dart";
import "study_material_viewer_screen.dart";

// ── Public entry-point ────────────────────────────────────────────────────────

class AiStudyHubScreen extends StatefulWidget {
  const AiStudyHubScreen({
    super.key,
    required this.profile,
    required this.tasks,
    required this.repo,
    this.preselectedTask,
  });

  final UserProfile profile;
  final List<TaskItem> tasks;
  final FirestoreRepository repo;

  /// When launched from a task card, jumps straight to that task's context.
  final TaskItem? preselectedTask;

  @override
  State<AiStudyHubScreen> createState() => _AiStudyHubScreenState();
}

class _AiStudyHubScreenState extends State<AiStudyHubScreen> {
  TaskItem? _selectedTask;

  // ── Derived helpers ───────────────────────────────────────────────────────

  List<TaskItem> get _pending =>
      widget.tasks.where((TaskItem t) => !t.completed).toList()
        ..sort((TaskItem a, TaskItem b) =>
            b.priorityScore.compareTo(a.priorityScore));

  String get _contextSubject =>
      _selectedTask?.subject ??
      (_pending.isNotEmpty ? _pending.first.subject : "General");

  String get _contextContent =>
      _selectedTask != null
          ? "${_selectedTask!.name}. ${_selectedTask!.description}"
          : "General study session";

  @override
  void initState() {
    super.initState();
    _selectedTask = widget.preselectedTask ??
        (_pending.isNotEmpty ? _pending.first : null);
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _openFlashcards() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => FlashcardScreen(
          subject: _contextSubject,
          content: _contextContent,
          taskName: _selectedTask?.name,
          profile: widget.profile,
        ),
      ),
    );
  }

  void _openQuiz() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => QuizScreen(
          subject: _contextSubject,
          content: _contextContent,
          taskName: _selectedTask?.name,
          profile: widget.profile,
          playerLevel: widget.profile.studyFocus,
        ),
      ),
    );
  }

  void _openTutor() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AiTutorScreen(
          subject: _contextSubject,
          taskContext: _selectedTask?.description ?? "",
          taskName: _selectedTask?.name,
          profile: widget.profile,
          playerLevel: widget.profile.studyFocus,
        ),
      ),
    );
  }

  void _openMaterial(StudyMaterialType type) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StudyMaterialViewerScreen(
          type: type,
          subject: _contextSubject,
          content: _contextContent,
          taskId: _selectedTask?.id ?? "",
          taskName: _selectedTask?.name ?? "",
          profile: widget.profile,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        slivers: <Widget>[
          // ── App Bar ───────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: kBg,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: const Text(
              "AI Study Hub",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: kDark,
                letterSpacing: -0.3,
              ),
            ),
            actions: <Widget>[
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: kOrange,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.auto_awesome_rounded,
                        size: 13, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      "AI-Powered",
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // ── Context selector ──────────────────────────────────────
                  _ContextSelector(
                    tasks: _pending,
                    selected: _selectedTask,
                    onChanged: (TaskItem? t) =>
                        setState(() => _selectedTask = t),
                  ),
                  const SizedBox(height: 24),

                  // ── Primary pillars ───────────────────────────────────────
                  const _SectionLabel(label: "PRACTICE & REVIEW"),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _PillarCard(
                          emoji: "🃏",
                          title: "Flashcards",
                          subtitle: "AI-generated active recall",
                          color: kYellow,
                          onTap: _openFlashcards,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PillarCard(
                          emoji: "📝",
                          title: "Practice Quiz",
                          subtitle: "MCQ, T/F & short answer",
                          color: kPink,
                          onTap: _openQuiz,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // AI Tutor — full-width highlight card
                  _TutorHighlightCard(onTap: _openTutor),
                  const SizedBox(height: 24),

                  // ── Study materials ───────────────────────────────────────
                  const _SectionLabel(label: "STUDY MATERIALS"),
                  const SizedBox(height: 12),
                  _MaterialsRow(onSelect: _openMaterial),
                  const SizedBox(height: 28),

                  // ── Quick tips banner ─────────────────────────────────────
                  _QuickTipsBanner(profile: widget.profile),
                  const SizedBox(height: 24),

                  // ── Recent tasks quick-launch ─────────────────────────────
                  if (_pending.isNotEmpty) ...<Widget>[
                    const _SectionLabel(label: "QUICK LAUNCH"),
                    const SizedBox(height: 12),
                    ..._pending
                        .take(3)
                        .map((TaskItem t) => _QuickLaunchRow(
                              task: t,
                              isSelected: _selectedTask?.id == t.id,
                              onFlashcards: () {
                                setState(() => _selectedTask = t);
                                _openFlashcards();
                              },
                              onQuiz: () {
                                setState(() => _selectedTask = t);
                                _openQuiz();
                              },
                              onTutor: () {
                                setState(() => _selectedTask = t);
                                _openTutor();
                              },
                            )),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Context Selector ──────────────────────────────────────────────────────────

class _ContextSelector extends StatelessWidget {
  const _ContextSelector({
    required this.tasks,
    required this.selected,
    required this.onChanged,
  });

  final List<TaskItem> tasks;
  final TaskItem? selected;
  final ValueChanged<TaskItem?> onChanged;

  @override
  Widget build(BuildContext context) {
    return LocketCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            "STUDYING FOR",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: kMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            const Text(
              "No active tasks — AI tools will use General mode.",
              style: TextStyle(fontSize: 13, color: kMuted),
            )
          else
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected?.id,
                isExpanded: true,
                icon: const Icon(Icons.expand_more_rounded,
                    color: kOrange, size: 20),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kDark),
                hint: const Text("Select a task…",
                    style: TextStyle(color: kMuted, fontSize: 14)),
                items: tasks
                    .map((TaskItem t) => DropdownMenuItem<String>(
                          value: t.id,
                          child: Text(
                            t.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (String? id) {
                  onChanged(tasks.firstWhere(
                      (TaskItem t) => t.id == id,
                      orElse: () => tasks.first));
                },
              ),
            ),
          if (selected != null) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: <Widget>[
                PillBadge(
                  color: kOrangeSoft,
                  label: selected!.subject,
                ),
                PillBadge(
                  color: switch (selected!.difficulty) {
                    Difficulty.hard => kPink,
                    Difficulty.medium => kYellow,
                    Difficulty.easy => kGreen,
                  },
                  label: selected!.difficulty.name,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Pillar Card ───────────────────────────────────────────────────────────────

class _PillarCard extends StatelessWidget {
  const _PillarCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kDark)),
            const SizedBox(height: 4),
            Text(subtitle, style: kSubtitle),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kDark,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text("Start →",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tutor Highlight Card ──────────────────────────────────────────────────────

class _TutorHighlightCard extends StatelessWidget {
  const _TutorHighlightCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF1A1410), Color(0xFF3D2E1A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: kOrange.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text("🤖", style: TextStyle(fontSize: 26)),
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "AI Study Tutor",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Ask anything about your subject. Get instant explanations, examples, and guidance.",
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                        height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: kOrange,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                "Chat",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Materials Row ─────────────────────────────────────────────────────────────

class _MaterialsRow extends StatelessWidget {
  const _MaterialsRow({required this.onSelect});
  final ValueChanged<StudyMaterialType> onSelect;

  static const List<_MaterialDef> _defs = <_MaterialDef>[
    _MaterialDef(
        type: StudyMaterialType.summary,
        emoji: "📋",
        label: "Summary",
        color: kBlue),
    _MaterialDef(
        type: StudyMaterialType.reviewer,
        emoji: "📖",
        label: "Reviewer",
        color: kGreen),
    _MaterialDef(
        type: StudyMaterialType.studyGuide,
        emoji: "🗺️",
        label: "Study Guide",
        color: kSage),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _defs.asMap().entries.map((MapEntry<int, _MaterialDef> entry) {
        final _MaterialDef def = entry.value;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelect(def.type),
            child: Container(
              margin: EdgeInsets.only(
                  left: entry.key == 0 ? 0 : 6,
                  right: entry.key == _defs.length - 1 ? 0 : 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: def.color.withOpacity(0.22),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: def.color.withOpacity(0.45), width: 1.2),
              ),
              child: Column(
                children: <Widget>[
                  Text(def.emoji,
                      style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 6),
                  Text(def.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kDark)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MaterialDef {
  const _MaterialDef({
    required this.type,
    required this.emoji,
    required this.label,
    required this.color,
  });

  final StudyMaterialType type;
  final String emoji;
  final String label;
  final Color color;
}

// ── Quick Tips Banner ─────────────────────────────────────────────────────────

class _QuickTipsBanner extends StatelessWidget {
  const _QuickTipsBanner({required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final String tip = switch (profile.personalityType) {
      PersonalityType.introvert =>
        "💡 Tip: You focus best alone. Use Flashcards first to warm up, then tackle the Quiz.",
      PersonalityType.extrovert =>
        "💡 Tip: Try the AI Tutor — explaining concepts out loud helps extroverts retain more.",
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kOrangeSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 2),
          Expanded(
            child: Text(tip,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: kDark,
                    height: 1.45)),
          ),
        ],
      ),
    );
  }
}

// ── Quick Launch Row ──────────────────────────────────────────────────────────

class _QuickLaunchRow extends StatelessWidget {
  const _QuickLaunchRow({
    required this.task,
    required this.isSelected,
    required this.onFlashcards,
    required this.onQuiz,
    required this.onTutor,
  });

  final TaskItem task;
  final bool isSelected;
  final VoidCallback onFlashcards;
  final VoidCallback onQuiz;
  final VoidCallback onTutor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSelected ? kOrangeSoft : kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected ? kOrange.withOpacity(0.4) : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: kDark.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      task.name,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(task.subject, style: kSubtitle),
                  ],
                ),
              ),
              PillBadge(
                color: switch (task.difficulty) {
                  Difficulty.hard => kPink,
                  Difficulty.medium => kYellow,
                  Difficulty.easy => kGreen,
                },
                label: task.difficulty.name,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              _MiniActionBtn(
                  label: "🃏 Cards", onTap: onFlashcards),
              const SizedBox(width: 8),
              _MiniActionBtn(label: "📝 Quiz", onTap: onQuiz),
              const SizedBox(width: 8),
              _MiniActionBtn(label: "🤖 Tutor", onTap: onTutor),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniActionBtn extends StatelessWidget {
  const _MiniActionBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: kDark,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ),
    );
  }
}

// ── Shared section label widget ───────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: kMuted,
        letterSpacing: 0.9,
      ),
    );
  }
}
