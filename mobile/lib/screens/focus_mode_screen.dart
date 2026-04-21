import "dart:async";

import "package:flutter/material.dart";

import "../design_tokens.dart";
import "../models/app_models.dart";
import "../services/claude_service.dart";
import "../services/firestore_repository.dart";

class FocusModeScreen extends StatefulWidget {
  const FocusModeScreen({
    super.key,
    required this.task,
    required this.repo,
    required this.profile,
  });

  final TaskItem task;
  final FirestoreRepository repo;
  final UserProfile profile;

  @override
  State<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends State<FocusModeScreen> {
  // Configurable work duration — user picks 15, 25, or 45 min before starting.
  int _selectedMinutes = 25;
  int get _workSeconds => _selectedMinutes * 60;
  static const int _shortBreakSeconds = 5 * 60;
  static const int _longBreakSeconds = 15 * 60;

  _Phase _phase = _Phase.idle;
  int _secondsLeft = 25 * 60; // default 25 min, updated when user picks duration
  int _pomodorosCompleted = 0;
  Timer? _timer;
  late final DateTime _sessionStart;

  bool _sessionDone = false;
  int _feltDifficulty = 3;
  String _midSessionMood = "neutral";
  final TextEditingController _noteCtrl = TextEditingController();
  bool _saving = false;

  // ── Mid-session check-in state ──────────────────────────────────────────────
  final List<MidCheckIn> _checkIns = <MidCheckIn>[];
  bool _checkInShown = false;

  // ── AI session summary state ────────────────────────────────────────────────
  String? _aiSummary;
  bool _generatingSummary = false;

  @override
  void dispose() {
    _timer?.cancel();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _startWork() {
    _sessionStart = DateTime.now();
    setState(() {
      _phase = _Phase.work;
      _secondsLeft = _workSeconds; // uses _selectedMinutes * 60
    });
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        _onTimerDone();
      }
    });
  }

  void _onTimerDone() {
    _timer?.cancel();
    if (_phase == _Phase.work) {
      setState(() {
        _pomodorosCompleted++;
        if (_pomodorosCompleted % 4 == 0) {
          _phase = _Phase.longBreak;
          _secondsLeft = _longBreakSeconds;
        } else {
          _phase = _Phase.shortBreak;
          _secondsLeft = _shortBreakSeconds;
        }
      });
      // Fire mid-session check-in after the 2nd Pomodoro, once per session.
      if (_pomodorosCompleted == 2 && !_checkInShown) {
        _checkInShown = true;
        Future.delayed(
          const Duration(milliseconds: 500),
          _showMidCheckIn,
        );
      }
      _tick();
    } else {
      setState(() {
        _phase = _Phase.idle;
        _secondsLeft = _workSeconds;
      });
    }
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _phase = _Phase.paused);
  }

  void _resume() {
    setState(() => _phase = _Phase.work);
    _tick();
  }

  void _endSession() {
    _timer?.cancel();
    if (_pomodorosCompleted == 0 && _phase == _Phase.idle) {
      Navigator.pop(context);
      return;
    }
    final int actualMinutes =
        DateTime.now().difference(_sessionStart).inMinutes.clamp(1, 999);

    setState(() {
      _sessionDone = true;
      _phase = _Phase.done;
      _generatingSummary = true;
    });

    // Generate AI summary in the background while the user fills in the form.
    ClaudeService.generateSessionSummary(
      taskName: widget.task.name,
      subject: widget.task.subject,
      pomodorosCompleted: _pomodorosCompleted,
      actualMinutes: actualMinutes,
      plannedMinutes: widget.task.aiEstimatedMinutes,
      feltDifficulty: _feltDifficulty,
      checkIns: _checkIns,
      profile: widget.profile,
    ).then((String summary) {
      if (mounted) {
        setState(() {
          _aiSummary = summary;
          _generatingSummary = false;
        });
      }
    });
  }

  Future<void> _saveSession() async {
    setState(() => _saving = true);
    final int actualMinutes =
        DateTime.now().difference(_sessionStart).inMinutes.clamp(1, 999);
    try {
      await widget.repo.logStudySession(
        taskId: widget.task.id,
        taskName: widget.task.name,
        subject: widget.task.subject,
        plannedMinutes: widget.task.aiEstimatedMinutes,
        actualMinutes: actualMinutes,
        pomodorosCompleted: _pomodorosCompleted,
        feltDifficulty: _feltDifficulty,
        startedAt: _sessionStart,
        midSessionMood: _midSessionMood,
        note: _noteCtrl.text.trim(),
        checkIns: _checkIns,
        aiSessionSummary: _aiSummary,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Session saved! +${_pomodorosCompleted * 5} XP 🎉"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to save session: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatTime(int seconds) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    return "${m.toString().padLeft(2, "0")}:${s.toString().padLeft(2, "0")}";
  }

  double get _progress {
    final int total = _phase == _Phase.longBreak
        ? _longBreakSeconds
        : _phase == _Phase.shortBreak
            ? _shortBreakSeconds
            : _workSeconds;
    return (total - _secondsLeft) / total;
  }

  Color get _phaseColor {
    return switch (_phase) {
      _Phase.work || _Phase.paused => kOrange,
      _Phase.shortBreak => kGreen,
      _Phase.longBreak => kBlue,
      _ => kOrange,
    };
  }

  String get _phaseLabel {
    return switch (_phase) {
      _Phase.idle => "Ready to Focus",
      _Phase.work => "Focus Time",
      _Phase.paused => "Paused",
      _Phase.shortBreak => "Short Break",
      _Phase.longBreak => "Long Break",
      _Phase.done => "Session Complete",
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Focus Mode"),
        actions: <Widget>[
          if (!_sessionDone)
            TextButton(
              onPressed: _endSession,
              child: const Text("End Session"),
            ),
        ],
      ),
      body: _sessionDone ? _buildSummary() : _buildTimer(),
    );
  }

  // ── Mid-session check-in bottom sheet ────────────────────────────────────────

  void _showMidCheckIn() {
    if (!mounted) return;
    String checkMood = "neutral";
    final TextEditingController quickNoteCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setSheet) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: kMuted.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Quick check-in 🍅 × $_pomodorosCompleted",
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  "How are you feeling right now?",
                  style: TextStyle(
                      fontSize: 13, color: kMuted),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    for (final (String val, String emoji)
                        in <(String, String)>[
                      ("happy", "😊"),
                      ("neutral", "😐"),
                      ("sad", "😔"),
                    ]) ...<Widget>[
                      GestureDetector(
                        onTap: () => setSheet(() => checkMood = val),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: checkMood == val
                                ? kOrangeSoft
                                : kBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: checkMood == val
                                  ? kDark
                                  : kMuted.withOpacity(0.3),
                              width: checkMood == val ? 1.5 : 1,
                            ),
                          ),
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 24)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: quickNoteCtrl,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    hintText: "Quick note — optional",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: kDark),
                    onPressed: () {
                      setState(() {
                        _checkIns.add(MidCheckIn(
                          mood: checkMood,
                          note: quickNoteCtrl.text.trim(),
                          atPomodoro: _pomodorosCompleted,
                          capturedAt: DateTime.now(),
                        ));
                      });
                      quickNoteCtrl.dispose();
                      Navigator.pop(ctx);
                    },
                    child: const Text("Continue session"),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  String _moodEmoji(String mood) {
    return switch (mood) {
      "happy" => "😊",
      "sad" => "😔",
      _ => "😐",
    };
  }

  Widget _buildTimer() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kOrangeSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kOrange.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.assignment_outlined,
                      size: 16, color: kOrange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.task.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.task.subject,
                style: TextStyle(
                    fontSize: 12, color: kOrange),
              ),
              if (widget.task.aiBreakStrategy.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  "🍅 ${widget.task.aiBreakStrategy}",
                  style: TextStyle(
                      fontSize: 11, color: kMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 32),
        Center(
          child: Text(
            _phaseLabel,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _phaseColor,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                SizedBox(
                  width: 220,
                  height: 220,
                  child: CircularProgressIndicator(
                    value: _phase == _Phase.idle ? 0 : _progress,
                    strokeWidth: 14,
                    backgroundColor: kDark.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(_phaseColor),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _formatTime(_secondsLeft),
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                        color: _phaseColor,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures()
                        ],
                      ),
                    ),
                    if (_pomodorosCompleted > 0)
                      Text(
                        "🍅 × $_pomodorosCompleted",
                        style: const TextStyle(fontSize: 16),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        if (_phase == _Phase.idle) ...<Widget>[
          // ── Duration picker ──────────────────────────────────────────────────
          Column(
            children: <Widget>[
              const SunMascot(size: 72),
              const SizedBox(height: 16),
              const Text(
                "Choose session length",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: kDark,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (final int mins in <int>[15, 25, 45]) ...<Widget>[
                    GestureDetector(
                      onTap: () => setState(() {
                        _selectedMinutes = mins;
                        _secondsLeft = mins * 60;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedMinutes == mins ? kDark : kOrangeSoft,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _selectedMinutes == mins
                                ? kDark
                                : kOrange.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          children: <Widget>[
                            Text(
                              "$mins",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: _selectedMinutes == mins
                                    ? Colors.white
                                    : kDark,
                              ),
                            ),
                            Text(
                              "min",
                              style: TextStyle(
                                fontSize: 11,
                                color: _selectedMinutes == mins
                                    ? Colors.white70
                                    : kMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _startWork,
                icon: const Icon(Icons.play_arrow),
                label: Text("Start $_selectedMinutes-min Session"),
                style: FilledButton.styleFrom(
                  backgroundColor: kDark,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ] else if (_phase == _Phase.work) ...<Widget>[
          // ── SunMascot studying alongside ─────────────────────────────────────
          Center(child: SunMascot(walking: true, size: 68)),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: _pause,
                  icon: const Icon(Icons.pause),
                  label: const Text("Pause"),
                  style: FilledButton.styleFrom(backgroundColor: kDark),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _endSession,
                  icon: const Icon(Icons.stop),
                  label: const Text("End"),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
        ] else if (_phase == _Phase.paused) ...<Widget>[
          Center(child: SunMascot(size: 68)),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: _resume,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Resume"),
                  style: FilledButton.styleFrom(backgroundColor: kDark),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _endSession,
                  icon: const Icon(Icons.stop),
                  label: const Text("End"),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
        ] else if (_phase == _Phase.shortBreak ||
            _phase == _Phase.longBreak) ...<Widget>[
          Center(child: SunMascot(size: 68)),
          const SizedBox(height: 10),
          Center(
            child: Text(
              _phase == _Phase.shortBreak
                  ? "Take a 5-minute breather 🌿"
                  : "Great work! Long break — recharge 🌙",
              style: TextStyle(
                  fontSize: 14,
                  color: _phaseColor,
                  fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _endSession,
            icon: const Icon(Icons.stop),
            label: const Text("End Session"),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ],
        if (_pomodorosCompleted > 0) ...<Widget>[
          const SizedBox(height: 24),
          Center(
            child: Wrap(
              spacing: 6,
              children: List<Widget>.generate(
                _pomodorosCompleted,
                (_) => const Text("🍅", style: TextStyle(fontSize: 20)),
              ),
            ),
          ),
        ],
        if (_phase == _Phase.work &&
            widget.task.aiStudyTips.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kOrangeSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "💡 Study Tip",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: kOrange,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.task.aiStudyTips[
                      _pomodorosCompleted % widget.task.aiStudyTips.length],
                   style: const TextStyle(fontSize: 13, color: kDark),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummary() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Center(
          child: Column(
            children: <Widget>[
              const Text("🎉", style: TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text(
                "Session Complete!",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: kDark,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                "$_pomodorosCompleted Pomodoro${_pomodorosCompleted == 1 ? "" : "s"} completed  •  +${_pomodorosCompleted * 5} XP",
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── AI session summary ──────────────────────────────────────────────
        if (_generatingSummary || _aiSummary != null) ...<Widget>[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kOrangeSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kOrange.withOpacity(0.2)),
            ),
            child: _generatingSummary
                ? Row(
                    children: <Widget>[
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kOrange,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "Generating your session summary...",
                        style: TextStyle(
                            fontSize: 13,
                            color: kOrange),
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.auto_awesome,
                          size: 16, color: kOrange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _aiSummary!,
                          style: TextStyle(
                            fontSize: 13,
                            color: kDark,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
        ],

        // ── Mid-session mood trail ──────────────────────────────────────────
        if (_checkIns.isNotEmpty) ...<Widget>[
          Text(
            "Mood during session",
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: _checkIns
                .map((MidCheckIn c) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(_moodEmoji(c.mood),
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 2),
                          Text(
                            "after ${c.atPomodoro}🍅",
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey),
                          ),
                          if (c.note.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 2),
                            SizedBox(
                              width: 70,
                              child: Text(
                                c.note,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
        ],

        Text(
          "How difficult was this session?",
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List<Widget>.generate(5, (int i) {
            final int val = i + 1;
            final bool selected = _feltDifficulty == val;
            return GestureDetector(
              onTap: () => setState(() => _feltDifficulty = val),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: selected
                      ? kDark
                      : kOrangeSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? kDark
                        : kOrange.withOpacity(0.2),
                  ),
                ),
                child: Center(
                  child: Text(
                    "$val",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : kDark,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text("Easy", style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text("Hard", style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "How did you feel during the session?",
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (final (String val, String emoji) in <(String, String)>[
              ("happy", "😊"),
              ("neutral", "😐"),
              ("sad", "😔"),
            ]) ...<Widget>[
              GestureDetector(
                onTap: () => setState(() => _midSessionMood = val),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _midSessionMood == val
                        ? kOrangeSoft
                        : kBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _midSessionMood == val
                          ? kDark
                          : kMuted.withOpacity(0.3),
                      width: _midSessionMood == val ? 1.5 : 1,
                    ),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Text(
          "Session note (optional)",
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: "What did you accomplish? Any blockers?",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving ? null : _saveSession,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined),
          label: Text(_saving
              ? "Saving..."
              : "Save Session  +${_pomodorosCompleted * 5} XP"),
          style: FilledButton.styleFrom(
            backgroundColor: kDark,
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Discard"),
        ),
      ],
    );
  }
}

enum _Phase { idle, work, paused, shortBreak, longBreak, done }
