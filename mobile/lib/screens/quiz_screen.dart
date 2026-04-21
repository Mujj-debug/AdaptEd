// lib/screens/quiz_screen.dart
//
// QuizScreen — AI-generated adaptive quiz with MCQ, True/False, and Short Answer.
//
// Flow:
//   1. Setup phase   — difficulty + question type selectors.
//   2. Quiz phase    — one question at a time, answer revealed after submission.
//   3. Results phase — score, grade, AI-generated personalised feedback + XP.

import "dart:async";

import "package:flutter/material.dart";

import "../design_tokens.dart";
import "../models/app_models.dart";
import "../models/study_material_models.dart";
import "../services/claude_service_study.dart";

// ── Public Entry ──────────────────────────────────────────────────────────────

class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.subject,
    required this.content,
    this.taskName,
    this.profile,
    this.playerLevel = 1,
  });

  final String subject;
  final String content;
  final String? taskName;
  final UserProfile? profile;
  final int playerLevel;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  // ── Setup state ───────────────────────────────────────────────────────────
  String _difficulty = "medium";
  List<QuestionType> _selectedTypes = <QuestionType>[
    QuestionType.mcq,
    QuestionType.trueFalse,
  ];
  int _questionCount = 10;

  // ── Quiz state ────────────────────────────────────────────────────────────
  List<QuizQuestion> _questions = <QuizQuestion>[];
  bool _loading = false;
  String? _error;

  int _currentIndex = 0;
  String? _selectedAnswer;
  bool _answered = false;

  // Short answer
  final TextEditingController _shortAnswerCtrl = TextEditingController();

  // Timing
  late DateTime _quizStartTime;
  late DateTime _questionStartTime;

  // Results
  final List<QuizAnswerRecord> _records = <QuizAnswerRecord>[];

  // Phase: "setup" | "quiz" | "loading_results" | "results"
  String _phase = "setup";

  // AI feedback
  Map<String, dynamic>? _feedback;
  bool _loadingFeedback = false;

  @override
  void dispose() {
    _shortAnswerCtrl.dispose();
    super.dispose();
  }

  // ── Generation ────────────────────────────────────────────────────────────

  Future<void> _generateQuiz() async {
    if (_selectedTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pick at least one question type.")),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _phase = "quiz";
      _records.clear();
    });

    final List<QuizQuestion> questions =
        await ClaudeStudyService.generateQuiz(
      subject: widget.subject,
      content: widget.content,
      questionCount: _questionCount,
      types: _selectedTypes,
      difficulty: _difficulty,
      playerLevel: widget.playerLevel,
    );

    if (!mounted) return;

    if (questions.isEmpty) {
      setState(() {
        _loading = false;
        _error = "Couldn't generate quiz questions. Please try again.";
        _phase = "setup";
      });
      return;
    }

    setState(() {
      _questions = questions;
      _loading = false;
      _currentIndex = 0;
      _selectedAnswer = null;
      _answered = false;
      _quizStartTime = DateTime.now();
      _questionStartTime = DateTime.now();
      _phase = "quiz";
    });
  }

  // ── Quiz interactions ─────────────────────────────────────────────────────

  void _submitAnswer(String answer) {
    if (_answered) return;
    final QuizQuestion q = _questions[_currentIndex];
    final bool correct = _checkAnswer(answer, q);

    setState(() {
      _selectedAnswer = answer;
      _answered = true;
    });

    _records.add(QuizAnswerRecord(
      question: q.question,
      userAnswer: answer,
      correctAnswer: q.correctAnswer,
      isCorrect: correct,
      explanation: q.explanation,
    ));
  }

  bool _checkAnswer(String answer, QuizQuestion q) {
    if (q.type == QuestionType.mcq) {
      return answer == q.correctAnswer;
    } else if (q.type == QuestionType.trueFalse) {
      return answer.toLowerCase() == q.correctAnswer.toLowerCase();
    } else {
      // Short answer — basic keyword match (production would use AI grading)
      final String lower = answer.toLowerCase();
      final String correct = q.correctAnswer.toLowerCase();
      final List<String> keywords = correct
          .split(RegExp(r"\s+"))
          .where((String w) => w.length > 4)
          .toList();
      if (keywords.isEmpty) return false;
      final int matched =
          keywords.where((String k) => lower.contains(k)).length;
      return matched >= (keywords.length * 0.5).ceil();
    }
  }

  void _nextQuestion() {
    _shortAnswerCtrl.clear();
    setState(() {
      _selectedAnswer = null;
      _answered = false;
      _currentIndex++;
      _questionStartTime = DateTime.now();
    });

    if (_currentIndex >= _questions.length) {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final int duration =
        DateTime.now().difference(_quizStartTime).inSeconds;
    final int correct =
        _records.where((QuizAnswerRecord r) => r.isCorrect).length;

    final QuizResult result = QuizResult(
      totalQuestions: _questions.length,
      correctCount: correct,
      subject: widget.subject,
      completedAt: DateTime.now(),
      answers: _records,
      durationSeconds: duration,
    );

    setState(() {
      _phase = "results";
      _loadingFeedback = true;
    });

    // Generate AI feedback in background
    if (widget.profile != null) {
      final Map<String, dynamic> fb =
          await ClaudeStudyService.generateQuizFeedback(
        result: result,
        profile: widget.profile!,
      );
      if (mounted) {
        setState(() {
          _feedback = fb;
          _loadingFeedback = false;
        });
      }
    } else {
      if (mounted) setState(() => _loadingFeedback = false);
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
            const Text("Practice Quiz",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kDark)),
            Text(widget.subject, style: kSubtitle),
          ],
        ),
        actions: <Widget>[
          if (_phase == "quiz" && !_loading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  "${_currentIndex + 1} / ${_questions.length}",
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
        duration: const Duration(milliseconds: 280),
        child: switch (_phase) {
          "setup" => _buildSetup(),
          "quiz" => _loading ? _buildLoading() : _buildQuiz(),
          "results" => _buildResults(),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  // ── Setup phase ───────────────────────────────────────────────────────────

  Widget _buildSetup() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LocketCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text("SUBJECT",
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kMuted,
                        letterSpacing: 0.8)),
                const SizedBox(height: 6),
                Text(
                  widget.taskName ?? widget.subject,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kDark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Question types
          const _SettingLabel(label: "QUESTION TYPES"),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _TypeToggle(
                label: "Multiple Choice",
                emoji: "📋",
                selected:
                    _selectedTypes.contains(QuestionType.mcq),
                onToggle: () => _toggleType(QuestionType.mcq),
              ),
              _TypeToggle(
                label: "True / False",
                emoji: "✅",
                selected:
                    _selectedTypes.contains(QuestionType.trueFalse),
                onToggle: () => _toggleType(QuestionType.trueFalse),
              ),
              _TypeToggle(
                label: "Short Answer",
                emoji: "✏️",
                selected:
                    _selectedTypes.contains(QuestionType.shortAnswer),
                onToggle: () => _toggleType(QuestionType.shortAnswer),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Difficulty
          const _SettingLabel(label: "DIFFICULTY"),
          const SizedBox(height: 10),
          _DifficultyRow(
            value: _difficulty,
            onChanged: (String d) => setState(() => _difficulty = d),
          ),
          const SizedBox(height: 20),

          // Question count
          const _SettingLabel(label: "NUMBER OF QUESTIONS"),
          const SizedBox(height: 10),
          Row(
            children: <int>[5, 10, 15, 20].map((int n) {
              final bool sel = _questionCount == n;
              return GestureDetector(
                onTap: () => setState(() => _questionCount = n),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  width: 52,
                  height: 44,
                  decoration: BoxDecoration(
                    color: sel ? kDark : kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: sel ? kDark : kMuted.withOpacity(0.25),
                        width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      "$n",
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: sel ? Colors.white : kDark),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),

          DarkPillButton(
            label: "Start Quiz",
            onPressed: _generateQuiz,
            icon: Icons.play_arrow_rounded,
          ),
        ],
      ),
    );
  }

  void _toggleType(QuestionType t) {
    setState(() {
      if (_selectedTypes.contains(t)) {
        if (_selectedTypes.length > 1) _selectedTypes.remove(t);
      } else {
        _selectedTypes.add(t);
      }
    });
  }

  // ── Loading phase ─────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SunMascot(walking: true, size: 80),
          const SizedBox(height: 20),
          Text(
            "Crafting your ${_questionCount}-question quiz…",
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: kDark),
          ),
          const SizedBox(height: 16),
          const BouncingDots(),
        ],
      ),
    );
  }

  // ── Quiz phase ────────────────────────────────────────────────────────────

  Widget _buildQuiz() {
    if (_currentIndex >= _questions.length) return const SizedBox.shrink();
    final QuizQuestion q = _questions[_currentIndex];
    final double progress = _questions.isNotEmpty
        ? _currentIndex / _questions.length
        : 0.0;

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
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text("Q${_currentIndex + 1}",
                  style: kSubtitle),
              PillBadge(
                color: switch (q.type) {
                  QuestionType.mcq => kBlue,
                  QuestionType.trueFalse => kYellow,
                  QuestionType.shortAnswer => kSage,
                },
                label: switch (q.type) {
                  QuestionType.mcq => "Multiple Choice",
                  QuestionType.trueFalse => "True / False",
                  QuestionType.shortAnswer => "Short Answer",
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Question card
                LocketCard(
                  child: Text(
                    q.question,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kDark,
                        height: 1.45),
                  ),
                ),
                const SizedBox(height: 16),

                // Answer options
                if (q.type == QuestionType.mcq)
                  ...q.options.map((String opt) => _McqOption(
                        option: opt,
                        selected: _selectedAnswer == opt,
                        answered: _answered,
                        isCorrect: opt == q.correctAnswer,
                        onTap: () => _submitAnswer(opt),
                      ))
                else if (q.type == QuestionType.trueFalse)
                  _TrueFalseOptions(
                    selected: _selectedAnswer,
                    answered: _answered,
                    correctAnswer: q.correctAnswer,
                    onSelect: _submitAnswer,
                  )
                else
                  _ShortAnswerInput(
                    controller: _shortAnswerCtrl,
                    answered: _answered,
                    onSubmit: () =>
                        _submitAnswer(_shortAnswerCtrl.text.trim()),
                  ),

                // Explanation (after answering)
                if (_answered) ...<Widget>[
                  const SizedBox(height: 16),
                  _ExplanationCard(
                    isCorrect: _records.last.isCorrect,
                    explanation: q.explanation,
                    correctAnswer: q.type != QuestionType.mcq
                        ? q.correctAnswer
                        : null,
                  ),
                  const SizedBox(height: 16),
                  DarkPillButton(
                    label: _currentIndex < _questions.length - 1
                        ? "Next Question →"
                        : "See Results",
                    onPressed: _nextQuestion,
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Results phase ─────────────────────────────────────────────────────────

  Widget _buildResults() {
    final int correct =
        _records.where((QuizAnswerRecord r) => r.isCorrect).length;
    final int total = _records.length;
    final int pct = total > 0 ? (correct / total * 100).round() : 0;
    final int duration =
        DateTime.now().difference(_quizStartTime).inSeconds;
    final int xp = _feedback?["xpEarned"] as int? ??
        (pct >= 80 ? 50 : pct >= 60 ? 30 : 15);

    final String grade = pct >= 90
        ? "A"
        : pct >= 80
            ? "B"
            : pct >= 70
                ? "C"
                : pct >= 60
                    ? "D"
                    : "F";

    final Color gradeColor = pct >= 70
        ? kSuccess
        : pct >= 50
            ? kOrange
            : kError;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        children: <Widget>[
          // Grade circle
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: gradeColor.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: gradeColor, width: 3),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  grade,
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: gradeColor),
                ),
                Text(
                  "$pct%",
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // AI headline
          if (_feedback != null)
            Text(
              (_feedback!["headline"] ?? "") as String,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: kDark,
                  height: 1.35,
                  letterSpacing: -0.2),
            )
          else
            Text(
              pct >= 70
                  ? "Great work! 🎉"
                  : "Keep practicing — you're building knowledge! 📚",
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: kDark),
            ),
          const SizedBox(height: 24),

          // Stats row
          Row(
            children: <Widget>[
              Expanded(
                child: StatPill(
                    value: "$correct/$total",
                    label: "Correct",
                    color: kGreen),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatPill(
                    value: "${duration ~/ 60}m ${duration % 60}s",
                    label: "Time",
                    color: kBlue),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatPill(
                    value: "+$xp XP",
                    label: "Earned",
                    color: kYellow),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // AI feedback card
          if (_loadingFeedback)
            LocketCard(
              child: Row(
                children: <Widget>[
                  const BouncingDots(),
                  const SizedBox(width: 12),
                  const Text("Generating personalised feedback…",
                      style: TextStyle(color: kMuted, fontSize: 13)),
                ],
              ),
            )
          else if (_feedback != null) ...<Widget>[
            if ((_feedback!["gapMessage"] ?? "").toString().isNotEmpty)
              LocketCard(
                margin: const EdgeInsets.only(bottom: 12),
                color: kPink.withOpacity(0.18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text("NEEDS WORK",
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: kError,
                            letterSpacing: 0.8)),
                    const SizedBox(height: 6),
                    Text(
                      (_feedback!["gapMessage"] ?? "") as String,
                      style: const TextStyle(
                          fontSize: 13,
                          color: kDark,
                          height: 1.45),
                    ),
                  ],
                ),
              ),
            if ((_feedback!["nextStep"] ?? "").toString().isNotEmpty)
              LocketCard(
                color: kOrangeSoft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text("→",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: kOrange)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text("NEXT STEP",
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: kOrange,
                                  letterSpacing: 0.8)),
                          const SizedBox(height: 4),
                          Text(
                            (_feedback!["nextStep"] ?? "") as String,
                            style: const TextStyle(
                                fontSize: 13,
                                color: kDark,
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 20),

          // Review wrong answers
          if (_records.any((QuizAnswerRecord r) => !r.isCorrect)) ...<Widget>[
            const _SettingLabel(label: "REVIEW WRONG ANSWERS"),
            const SizedBox(height: 10),
            ..._records
                .where((QuizAnswerRecord r) => !r.isCorrect)
                .map((QuizAnswerRecord r) => _ReviewCard(record: r)),
            const SizedBox(height: 20),
          ],

          DarkPillButton(
            label: "Try Again",
            onPressed: () => setState(() {
              _phase = "setup";
              _records.clear();
              _feedback = null;
            }),
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

// ── Supporting Widgets ────────────────────────────────────────────────────────

class _SettingLabel extends StatelessWidget {
  const _SettingLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: kMuted,
            letterSpacing: 0.8));
  }
}

class _DifficultyRow extends StatelessWidget {
  const _DifficultyRow({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <String>["easy", "medium", "hard"].map((String d) {
        final bool sel = value == d;
        return GestureDetector(
          onTap: () => onChanged(d),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: sel ? kDark : kSurface,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                  color: sel ? kDark : kMuted.withOpacity(0.25),
                  width: 1.5),
            ),
            child: Text(
              d[0].toUpperCase() + d.substring(1),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : kDark),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onToggle,
  });

  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? kDark : kSurface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
              color: selected ? kDark : kMuted.withOpacity(0.25),
              width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : kDark)),
          ],
        ),
      ),
    );
  }
}

class _McqOption extends StatelessWidget {
  const _McqOption({
    required this.option,
    required this.selected,
    required this.answered,
    required this.isCorrect,
    required this.onTap,
  });

  final String option;
  final bool selected;
  final bool answered;
  final bool isCorrect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = kSurface;
    Color border = kMuted.withOpacity(0.2);

    if (answered) {
      if (isCorrect) {
        bg = kGreen.withOpacity(0.18);
        border = kSuccess;
      } else if (selected) {
        bg = kPink.withOpacity(0.2);
        border = kError;
      }
    } else if (selected) {
      bg = kOrangeSoft;
      border = kOrange;
    }

    return GestureDetector(
      onTap: answered ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(option,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: kDark)),
            ),
            if (answered && isCorrect)
              const Icon(Icons.check_circle_rounded,
                  color: kSuccess, size: 18),
            if (answered && selected && !isCorrect)
              const Icon(Icons.cancel_rounded, color: kError, size: 18),
          ],
        ),
      ),
    );
  }
}

class _TrueFalseOptions extends StatelessWidget {
  const _TrueFalseOptions({
    required this.selected,
    required this.answered,
    required this.correctAnswer,
    required this.onSelect,
  });

  final String? selected;
  final bool answered;
  final String correctAnswer;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _TfButton(
            label: "True",
            emoji: "✅",
            selected: selected == "True",
            answered: answered,
            isCorrect: correctAnswer == "True",
            onTap: () => onSelect("True"),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TfButton(
            label: "False",
            emoji: "❌",
            selected: selected == "False",
            answered: answered,
            isCorrect: correctAnswer == "False",
            onTap: () => onSelect("False"),
          ),
        ),
      ],
    );
  }
}

class _TfButton extends StatelessWidget {
  const _TfButton({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.answered,
    required this.isCorrect,
    required this.onTap,
  });

  final String label;
  final String emoji;
  final bool selected;
  final bool answered;
  final bool isCorrect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = kSurface;
    if (answered && isCorrect) bg = kGreen.withOpacity(0.18);
    else if (answered && selected && !isCorrect) bg = kPink.withOpacity(0.2);
    else if (selected) bg = kOrangeSoft;

    return GestureDetector(
      onTap: answered ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 70,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: answered && isCorrect
                  ? kSuccess
                  : answered && selected
                      ? kError
                      : selected
                          ? kOrange
                          : kMuted.withOpacity(0.2),
              width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kDark)),
          ],
        ),
      ),
    );
  }
}

class _ShortAnswerInput extends StatelessWidget {
  const _ShortAnswerInput({
    required this.controller,
    required this.answered,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool answered;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TextField(
          controller: controller,
          enabled: !answered,
          maxLines: 4,
          decoration: locketFieldStyle("Type your answer…"),
          style: const TextStyle(
              fontSize: 14, color: kDark, fontWeight: FontWeight.w500),
        ),
        if (!answered) ...<Widget>[
          const SizedBox(height: 12),
          DarkPillButton(label: "Submit Answer", onPressed: onSubmit),
        ],
      ],
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard({
    required this.isCorrect,
    required this.explanation,
    this.correctAnswer,
  });

  final bool isCorrect;
  final String explanation;
  final String? correctAnswer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCorrect
            ? kGreen.withOpacity(0.12)
            : kPink.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCorrect ? kSuccess.withOpacity(0.4) : kError.withOpacity(0.3),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isCorrect
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: isCorrect ? kSuccess : kError,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                isCorrect ? "Correct! ✨" : "Not quite — here's why:",
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isCorrect ? kSuccess : kError),
              ),
            ],
          ),
          if (correctAnswer != null && !isCorrect) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              "Answer: $correctAnswer",
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kDark),
            ),
          ],
          const SizedBox(height: 8),
          Text(explanation,
              style: const TextStyle(
                  fontSize: 13, color: kDark, height: 1.45)),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.record});
  final QuizAnswerRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: kDark.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(record.question,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kDark)),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              const Icon(Icons.close_rounded, size: 12, color: kError),
              const SizedBox(width: 4),
              Expanded(
                  child: Text("You: ${record.userAnswer}",
                      style: const TextStyle(
                          fontSize: 11, color: kError))),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              const Icon(Icons.check_rounded, size: 12, color: kSuccess),
              const SizedBox(width: 4),
              Expanded(
                  child: Text("Answer: ${record.correctAnswer}",
                      style: const TextStyle(
                          fontSize: 11, color: kSuccess))),
            ],
          ),
        ],
      ),
    );
  }
}
