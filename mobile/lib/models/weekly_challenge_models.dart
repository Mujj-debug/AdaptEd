// ── WeeklyChallenge ───────────────────────────────────────────────────────────
//
// Add this block to app_models.dart (after GamificationState).
// Also append WeeklyChallengeDef and weeklyChallengePool below.

import "package:cloud_firestore/cloud_firestore.dart";

/// Tracks the student's progress on one weekly challenge.
class WeeklyChallenge {
  WeeklyChallenge({
    required this.id,
    required this.defId,
    required this.title,
    required this.description,
    required this.xpReward,
    required this.targetCount,
    required this.currentCount,
    required this.completed,
    required this.weekStartDate,
    this.completedAt,
  });

  factory WeeklyChallenge.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return WeeklyChallenge(
      id: doc.id,
      defId: (d["defId"] ?? "") as String,
      title: (d["title"] ?? "") as String,
      description: (d["description"] ?? "") as String,
      xpReward: (d["xpReward"] ?? 75) as int,
      targetCount: (d["targetCount"] ?? 1) as int,
      currentCount: (d["currentCount"] ?? 0) as int,
      completed: (d["completed"] ?? false) as bool,
      weekStartDate:
          (d["weekStartDate"] as Timestamp?)?.toDate() ?? DateTime.now(),
      completedAt: (d["completedAt"] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String defId;
  final String title;
  final String description;
  final int xpReward;
  final int targetCount;
  final int currentCount;
  final bool completed;
  final DateTime weekStartDate;
  final DateTime? completedAt;

  double get progress =>
      targetCount > 0 ? (currentCount / targetCount).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toMap() => <String, dynamic>{
        "defId": defId,
        "title": title,
        "description": description,
        "xpReward": xpReward,
        "targetCount": targetCount,
        "currentCount": currentCount,
        "completed": completed,
        "weekStartDate": Timestamp.fromDate(weekStartDate),
        if (completedAt != null)
          "completedAt": Timestamp.fromDate(completedAt!),
      };
}

// ── WeeklyChallengeDef ────────────────────────────────────────────────────────

/// Static definition of a challenge type.
/// The pool is rotated each Monday — 3 are selected per week.
class WeeklyChallengeDef {
  const WeeklyChallengeDef({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required this.targetCount,
    required this.eventType, // matches FirestoreRepository event strings
    this.xpReward = 75,
    this.difficultyFilter, // "hard" | "medium" | null = any
  });

  final String id;
  final String emoji;
  final String title;
  final String description;
  final int targetCount;
  final String eventType;
  final int xpReward;
  final String? difficultyFilter;
}

/// Full pool of available weekly challenges.
/// 3 are deterministically selected each Monday using the week number as seed.
const List<WeeklyChallengeDef> weeklyChallengePool =
    <WeeklyChallengeDef>[
  // ── Completion challenges ─────────────────────────────────────────────────
  WeeklyChallengeDef(
    id: "complete_5_tasks",
    emoji: "✅",
    title: "Task Blitz",
    description: "Complete 5 tasks this week.",
    targetCount: 5,
    eventType: "task_completed",
  ),
  WeeklyChallengeDef(
    id: "complete_3_hard",
    emoji: "🔥",
    title: "Hard Mode",
    description: "Complete 3 hard-difficulty tasks this week.",
    targetCount: 3,
    eventType: "task_completed",
    difficultyFilter: "hard",
  ),
  WeeklyChallengeDef(
    id: "complete_2_medium",
    emoji: "⚙️",
    title: "Steady Grind",
    description: "Complete 2 medium-difficulty tasks this week.",
    targetCount: 2,
    eventType: "task_completed",
    difficultyFilter: "medium",
  ),
  // ── Focus Mode challenges ─────────────────────────────────────────────────
  WeeklyChallengeDef(
    id: "pomodoro_10",
    emoji: "🍅",
    title: "Pomodoro Champion",
    description: "Complete 10 Pomodoros across any sessions this week.",
    targetCount: 10,
    eventType: "pomodoro",
  ),
  WeeklyChallengeDef(
    id: "deep_sessions_3",
    emoji: "🏊",
    title: "Deep Diver",
    description: "Complete 3 Focus Mode sessions with 3+ Pomodoros each.",
    targetCount: 3,
    eventType: "deep_session",
  ),
  WeeklyChallengeDef(
    id: "sessions_5",
    emoji: "📅",
    title: "Show Up",
    description: "Log 5 study sessions this week, any length.",
    targetCount: 5,
    eventType: "study_session",
  ),
  // ── Mood & wellbeing challenges ───────────────────────────────────────────
  WeeklyChallengeDef(
    id: "mood_5",
    emoji: "🧘",
    title: "Check In",
    description: "Log your mood 5 times this week.",
    targetCount: 5,
    eventType: "mood_logged",
  ),
  WeeklyChallengeDef(
    id: "mood_streak_3",
    emoji: "💚",
    title: "Consistent Self",
    description: "Log your mood 3 days in a row this week.",
    targetCount: 3,
    eventType: "mood_streak",
  ),
  // ── Strategy & learning challenges ───────────────────────────────────────
  WeeklyChallengeDef(
    id: "share_strategy",
    emoji: "📖",
    title: "Knowledge Sharer",
    description: "Share 1 study strategy to the library this week.",
    targetCount: 1,
    eventType: "insight_posted",
  ),
  // ── Streak challenges ─────────────────────────────────────────────────────
  WeeklyChallengeDef(
    id: "streak_5",
    emoji: "🔗",
    title: "Streak Builder",
    description: "Be active for 5 days this week.",
    targetCount: 5,
    eventType: "daily_active",
    xpReward: 100,
  ),
  WeeklyChallengeDef(
    id: "streak_7",
    emoji: "💥",
    title: "Perfect Week",
    description: "Be active every single day this week.",
    targetCount: 7,
    eventType: "daily_active",
    xpReward: 150,
  ),
  // ── Subject variety challenge ─────────────────────────────────────────────
  WeeklyChallengeDef(
    id: "multi_subject",
    emoji: "🎓",
    title: "Renaissance Student",
    description: "Complete tasks across 3 different subjects this week.",
    targetCount: 3,
    eventType: "subject_variety",
  ),
];
