import "package:flutter/material.dart";

import "../design_tokens.dart";
import "../models/app_models.dart";
import "../models/weekly_challenge_models.dart";
import "../services/firestore_repository.dart";
import "focus_mode_screen.dart";

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.profile,
    required this.tasks,
    required this.moods,
    required this.game,
    required this.sessions,
    required this.repo,
    this.weeklyChallenges = const <WeeklyChallenge>[],
    this.onStartStudy,
    this.onGoToXp,
    this.onGoToInsights,
    this.assessmentFailed = false,
  });

  final UserProfile profile;
  final List<TaskItem> tasks;
  final List<MoodLog> moods;
  final GamificationState game;
  final List<StudySession> sessions;
  final FirestoreRepository repo;
  final List<WeeklyChallenge> weeklyChallenges;
  final VoidCallback? onStartStudy;
  final VoidCallback? onGoToXp;
  final VoidCallback? onGoToInsights;
  final bool assessmentFailed;

  @override
  Widget build(BuildContext context) {
    final List<TaskItem> pending = tasks
        .where((TaskItem t) => !t.completed)
        .toList()
      ..sort((TaskItem a, TaskItem b) =>
          b.priorityScore.compareTo(a.priorityScore));

    final TaskItem? top = pending.isNotEmpty ? pending.first : null;

    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day);

    final int completedToday = tasks
        .where((TaskItem t) =>
            t.completed &&
            t.completedAt != null &&
            t.completedAt!.isAfter(todayStart))
        .length;

    final int sessionMinutesToday = sessions
        .where((StudySession s) => s.completedAt.isAfter(todayStart))
        .fold(0, (int sum, StudySession s) => sum + s.actualMinutes);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: <Widget>[
        // ── Header ────────────────────────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SunMascot(size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    "AdaptEd",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: kDark,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    _greeting(),
                    style: kSubtitle,
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kOrangeSoft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.stars_rounded, size: 14, color: kOrange),
                  const SizedBox(width: 4),
                  Text(
                    "Lv ${game.level}  •  ${game.xp} XP",
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Assessment error banner ────────────────────────────────────────────
        if (assessmentFailed) ...<Widget>[
          GestureDetector(
            onTap: onGoToInsights,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: kPink.withOpacity(0.18),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kError.withOpacity(0.3)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.warning_amber_rounded, color: kError, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Your AI profile needs attention — tap to retry in Insights.",
                      style: TextStyle(fontSize: 13, color: kDark, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: kMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── Weekly challenge strip ────────────────────────────────────────────
        if (weeklyChallenges.isNotEmpty) ...<Widget>[
          _WeeklyChallengeStrip(
            challenges: weeklyChallenges,
            onTap: onGoToXp,
          ),
          const SizedBox(height: 14),
        ],

        // ── Stats row ──────────────────────────────────────────────────────────
        Row(
          children: <Widget>[
            StatPill(
              value: "🔥 ${game.streakDays}d",
              label: "streak",
              color: kYellow,
            ),
            const SizedBox(width: 8),
            StatPill(
              value: "✅ $completedToday",
              label: "done today",
              color: kGreen,
            ),
            const SizedBox(width: 8),
            StatPill(
              value: sessionMinutesToday > 0
                  ? "⏱ ${sessionMinutesToday}m"
                  : "📋 ${pending.length}",
              label: sessionMinutesToday > 0 ? "focus today" : "pending",
              color: sessionMinutesToday > 0 ? kBlue : kPink,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Daily AI Recommendation ────────────────────────────────────────────
        _AiDailyCard(
          task: top,
          repo: repo,
          profile: profile,
          onStartStudy: onStartStudy,
        ),
        const SizedBox(height: 14),

        // ── Future-You Simulator (compact) ────────────────────────────────────
        _FutureYouCard(tasks: tasks, sessions: sessions),
        const SizedBox(height: 14),

        // ── Mood quick log ─────────────────────────────────────────────────────
        _MoodQuickLog(repo: repo),
        const SizedBox(height: 14),

        // ── Smart Energy Mapping ───────────────────────────────────────────────
        _SmartEnergyCard(profile: profile),
        const SizedBox(height: 14),

        // ── Today's Focus Block ───────────────────────────────────────────────
        _TodaysFocusBlock(sessions: sessions, todayStart: todayStart),
        const SizedBox(height: 14),

        // ── Productivity preference ────────────────────────────────────────────
        LocketCard(
          child: Row(
            children: <Widget>[
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: kSage.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_outline_rounded, color: kDark, size: 18),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text("Productivity preference",
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: kDark)),
                  Text(_cap(profile.productivityPreference.name),
                      style: kSubtitle),
                ],
              ),
            ],
          ),
        ),

        // ── Latest mood ────────────────────────────────────────────────────────
        if (moods.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          LocketCard(
            child: Row(
              children: <Widget>[
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: kBlue.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.mood_rounded, color: kDark, size: 18),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text("Latest mood",
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: kDark)),
                    Text(
                        "${_cap(moods.first.mood.name)} • ${moods.first.activity}",
                        style: kSubtitle),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _greeting() {
    final int h = DateTime.now().hour;
    if (h < 12) return "Good morning! Ready to focus?";
    if (h < 17) return "Good afternoon! Keep the momentum going.";
    return "Good evening! Wrap up strong.";
  }
}

// ── AI Daily Card ─────────────────────────────────────────────────────────────

class _AiDailyCard extends StatelessWidget {
  const _AiDailyCard({
    required this.task,
    required this.repo,
    required this.profile,
    this.onStartStudy,
  });
  final TaskItem? task;
  final FirestoreRepository repo;
  final UserProfile profile;
  final VoidCallback? onStartStudy;

  @override
  Widget build(BuildContext context) {
    if (task == null) {
      return LocketCard(
        color: kOrangeSoft,
        child: Row(
          children: <Widget>[
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: kOrange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome, color: kOrange, size: 20),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                "No pending tasks — great work! Add a new task to get AI study guidance.",
                style: TextStyle(color: kDark, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF2D1B69), Color(0xFF1A1041)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF5B4EFF).withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: kOrange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.auto_awesome, color: kOrange, size: 12),
                    SizedBox(width: 5),
                    Text(
                      "TODAY'S PRIORITY",
                      style: TextStyle(
                        color: kOrange,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            task!.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            task!.subject,
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
          ),
          if (task!.aiProductivityAdvice.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.tips_and_updates_outlined,
                      color: kOrange.withOpacity(0.7), size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task!.aiProductivityAdvice,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          // ── Focus session button ─────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: kOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99)),
              ),
              onPressed: () {
                Navigator.push<bool>(
                  context,
                  MaterialPageRoute<bool>(
                    builder: (_) =>
                        FocusModeScreen(task: task!, repo: repo, profile: profile),
                  ),
                );
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.play_arrow_rounded, size: 18),
                  SizedBox(width: 6),
                  Text("Start Focus Session",
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── Study session button ─────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.12),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99)),
              ),
              onPressed: onStartStudy,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.auto_awesome_rounded, size: 16),
                  SizedBox(width: 6),
                  Text("Start Study Session",
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Future-You Simulator (compact card) ──────────────────────────────────────

class _FutureYouCard extends StatelessWidget {
  const _FutureYouCard({required this.tasks, required this.sessions});
  final List<TaskItem> tasks;
  final List<StudySession> sessions;

  @override
  Widget build(BuildContext context) {
    final List<String> predictions = _buildPredictions();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF3D1F00), Color(0xFF1A0D00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFF8C00).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: kOrange.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.auto_graph_rounded,
                        color: kOrange, size: 12),
                    SizedBox(width: 5),
                    Text(
                      "FUTURE-YOU SIMULATOR",
                      style: TextStyle(
                        color: kOrange,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (predictions.isEmpty)
            const Text(
              "Start a session today to unlock your academic forecast.",
              style: TextStyle(
                color: Color(0xFFE8C99A),
                fontSize: 13,
                height: 1.5,
              ),
            )
          else
            ...predictions.map((String p) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text("→  ",
                          style: TextStyle(
                              color: kOrange,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      Expanded(
                        child: Text(
                          p,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          const SizedBox(height: 4),
          const Text(
            "Based on your current study habits",
            style: TextStyle(
                fontSize: 11, color: Color(0xFFBB8A50), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  List<String> _buildPredictions() {
    if (tasks.isEmpty && sessions.isEmpty) return <String>[];

    final DateTime now = DateTime.now();
    final int total = tasks.length;
    final int completed = tasks.where((TaskItem t) => t.completed).length;
    final double completionRate = total > 0 ? completed / total : 0.0;

    final int overdue = tasks
        .where((TaskItem t) => !t.completed && t.deadline.isBefore(now))
        .length;

    final DateTime weekAgo = now.subtract(const Duration(days: 7));
    final Set<String> studyDaySet = sessions
        .where((StudySession s) => s.completedAt.isAfter(weekAgo))
        .map((StudySession s) =>
            "${s.completedAt.year}-${s.completedAt.month}-${s.completedAt.day}")
        .toSet();
    final int studyDaysThisWeek = studyDaySet.length;

    final List<String> results = <String>[];

    if (studyDaysThisWeek >= 5 && completionRate >= 0.75) {
      results.add("Strong consistency → mastery on track in ~3 weeks");
      results.add("27% fewer overdue tasks predicted next week");
    } else if (studyDaysThisWeek >= 3 && completionRate >= 0.5) {
      results.add("Good momentum — keep it up for faster results");
      if (overdue > 0) {
        results.add("$overdue overdue task${overdue > 1 ? 's' : ''} could slow you down");
      }
    } else if (overdue >= 3) {
      results.add("40% chance of task pile-up next week");
      results.add("Starting 1 session/day can reverse this trend");
    } else if (sessions.isNotEmpty) {
      results.add("Build to 3 sessions/week for measurable progress");
      results.add("${((completionRate * 100).round())}% completion rate — room to grow");
    }

    return results;
  }
}

// ── Smart Energy Mapping ──────────────────────────────────────────────────────

class _SmartEnergyCard extends StatelessWidget {
  const _SmartEnergyCard({required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final Map<String, String> energy = _computeEnergyMap();

    return LocketCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: kOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bolt_rounded, color: kOrange, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                "Smart Energy Map",
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: kDark),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _energyRow("🟢", "Deep Focus", energy["deep"] ?? "—"),
          const SizedBox(height: 8),
          _energyRow("🟡", "Light Study", energy["light"] ?? "—"),
          const SizedBox(height: 8),
          _energyRow("🔴", "Avoid Heavy Tasks", energy["avoid"] ?? "—"),
        ],
      ),
    );
  }

  Widget _energyRow(String dot, String label, String time) {
    return Row(
      children: <Widget>[
        Text(dot, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: kDark),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: kOrangeSoft,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            time,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: kDark),
          ),
        ),
      ],
    );
  }

  Map<String, String> _computeEnergyMap() {
    final String pref = profile.productivityPreference.name;
    if (pref == "morning") {
      return <String, String>{
        "deep": "6am – 12pm",
        "light": "2pm – 5pm",
        "avoid": "9pm – 6am",
      };
    } else if (pref == "night") {
      return <String, String>{
        "deep": "9pm – 1am",
        "light": "6pm – 9pm",
        "avoid": "Before 2pm",
      };
    } else {
      return <String, String>{
        "deep": "Peak window",
        "light": "Off-peak hours",
        "avoid": "Late night",
      };
    }
  }
}

// ── Mood quick log ────────────────────────────────────────────────────────────

class _MoodQuickLog extends StatefulWidget {
  const _MoodQuickLog({required this.repo});
  final FirestoreRepository repo;

  @override
  State<_MoodQuickLog> createState() => _MoodQuickLogState();
}

class _MoodQuickLogState extends State<_MoodQuickLog> {
  bool _logged = false;

  Future<void> _log(MoodEmoji mood) async {
    await widget.repo.logMood(mood: mood, activity: "study", note: "");
    if (mounted) setState(() => _logged = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_logged) {
      return LocketCard(
        color: kGreen.withOpacity(0.18),
        child: const Row(
          children: <Widget>[
            Icon(Icons.check_circle_rounded, color: kSuccess, size: 20),
            SizedBox(width: 10),
            Text("Mood logged! +5 XP",
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kDark,
                    fontSize: 13)),
          ],
        ),
      );
    }
    return LocketCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text("How are you feeling?",
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14, color: kDark)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _moodBtn("😊", "Happy", MoodEmoji.happy),
              _moodBtn("😐", "Okay", MoodEmoji.neutral),
              _moodBtn("😔", "Low", MoodEmoji.sad),
            ],
          ),
        ],
      ),
    );
  }

  Widget _moodBtn(String emoji, String label, MoodEmoji mood) {
    return GestureDetector(
      onTap: () => _log(mood),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: kOrangeSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: <Widget>[
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 4),
            Text(label, style: kCaption),
          ],
        ),
      ),
    );
  }
}

// ── Today's Focus Block ───────────────────────────────────────────────────────

class _TodaysFocusBlock extends StatelessWidget {
  const _TodaysFocusBlock({
    required this.sessions,
    required this.todayStart,
  });

  final List<StudySession> sessions;
  final DateTime todayStart;

  @override
  Widget build(BuildContext context) {
    final List<StudySession> todaySessions = sessions
        .where((StudySession s) => s.completedAt.isAfter(todayStart))
        .toList();

    if (todaySessions.isEmpty) {
      return LocketCard(
        child: Row(
          children: <Widget>[
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: kBlue.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.timer_outlined, color: kDark, size: 18),
            ),
            const SizedBox(width: 14),
            const Text(
              "No focus sessions yet today.",
              style: TextStyle(color: kMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final int totalMinutes = todaySessions
        .fold(0, (int sum, StudySession s) => sum + s.actualMinutes);
    final int totalPomodoros = todaySessions
        .fold(0, (int sum, StudySession s) => sum + s.pomodorosCompleted);

    return LocketCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: kBlue.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.timer_outlined, color: kDark, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                "Today's Focus",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: kDark,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              PillBadge(
                color: kOrangeSoft,
                label: "${totalMinutes}m  •  🍅×$totalPomodoros",
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...todaySessions.take(3).map((StudySession s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 8, height: 8,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: const BoxDecoration(
                        color: kOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s.taskName.isNotEmpty ? s.taskName : s.subject,
                        style: const TextStyle(fontSize: 13, color: kDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      "${s.actualMinutes}m  🍅×${s.pomodorosCompleted}",
                      style: kCaption,
                    ),
                  ],
                ),
              )),
          if (todaySessions.length > 3)
            Text(
              "+${todaySessions.length - 3} more session${todaySessions.length - 3 == 1 ? '' : 's'}",
              style: kCaption,
            ),
        ],
      ),
    );
  }
}

// ── Weekly Challenge Strip ────────────────────────────────────────────────────
// Compact horizontal strip showing up to 3 weekly challenges as tappable cards.
// Shown at the top of the dashboard so challenges are always visible.

class _WeeklyChallengeStrip extends StatelessWidget {
  const _WeeklyChallengeStrip({
    required this.challenges,
    this.onTap,
  });

  final List<WeeklyChallenge> challenges;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final List<WeeklyChallenge> visible = challenges.take(3).toList();
    final int done = challenges.where((WeeklyChallenge c) => c.completed).length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kOrange.withOpacity(0.15)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: kDark.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text("🏆", style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                const Text(
                  "This Week's Challenges",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: kDark,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: done == challenges.length && challenges.isNotEmpty
                        ? kGreen.withOpacity(0.2)
                        : kOrangeSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    "$done/${challenges.length} done",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: done == challenges.length && challenges.isNotEmpty
                          ? kSuccess
                          : kDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: visible.map((WeeklyChallenge c) {
                final bool isDone = c.completed;
                final double pct = c.progress.clamp(0.0, 1.0);
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDone
                          ? kGreen.withOpacity(0.1)
                          : kOrangeSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDone
                            ? kGreen.withOpacity(0.4)
                            : kOrange.withOpacity(0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _emojiFor(c.defId),
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.title,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: kDark,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 5,
                            backgroundColor: kDark.withOpacity(0.08),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDone ? kSuccess : kOrange,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isDone
                              ? "✅ Complete"
                              : "${c.currentCount}/${c.targetCount}",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isDone ? kSuccess : kMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _emojiFor(String defId) {
    return weeklyChallengePool
            .where((WeeklyChallengeDef d) => d.id == defId)
            .firstOrNull
            ?.emoji ??
        "🏆";
  }
}

