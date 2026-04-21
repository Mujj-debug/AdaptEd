import "../models/app_models.dart";
import "claude_service.dart";

// ─── Task analysis ────────────────────────────────────────────────────────────

Future<Map<String, dynamic>> analyzeTaskFromDescription({
  required String title,
  required String description,
  required String subject,
  required UserProfile profile,
}) {
  return ClaudeService.analyzeTask(
    title: title,
    description: description,
    subject: subject,
    profile: profile,
  );
}

// ─── Priority calculation (kept local — deterministic, no AI needed) ──────────

Map<String, dynamic> calculatePriorityLocally({
  required DateTime deadline,
  required Difficulty difficulty,
  required Workload workload,
  required UserProfile profile,
  required List<MoodLog> moods,
}) {
  final DateTime now = DateTime.now();
  final int hours = deadline.difference(now).inHours;

  int deadlineWeight = 5;
  if (hours <= 24) {
    deadlineWeight = 50;
  } else if (hours <= 72) {
    deadlineWeight = 35;
  } else if (hours <= 168) {
    deadlineWeight = 20;
  }

  final int difficultyWeight = switch (difficulty) {
    Difficulty.easy => 5,
    Difficulty.medium => 10,
    Difficulty.hard => 20,
  };
  final int workloadWeight = switch (workload) {
    Workload.low => 3,
    Workload.medium => 8,
    Workload.high => 15,
  };

  int behaviorWeight = 0;
  final int hour = now.hour;
  if (profile.productivityPreference == ProductivityPreference.night &&
      hour >= 18 &&
      difficulty == Difficulty.hard) {
    behaviorWeight += 8;
  }
  if (profile.productivityPreference == ProductivityPreference.morning &&
      hour <= 11 &&
      difficulty != Difficulty.easy) {
    behaviorWeight += 8;
  }

  // ── Mood → task adjustment logic ──────────────────────────────────────────
  // Count consecutive sad moods from the most recent 3 entries.
  // If the student is trending sad AND the task is high-workload,
  // we de-prioritize slightly to protect their mental energy.
  final int sadCount =
      moods.take(3).where((MoodLog m) => m.mood == MoodEmoji.sad).length;
  if (sadCount >= 2 && workload == Workload.high) {
    behaviorWeight -= 5;
  }

  // FIX #12: Clamp score to 0 minimum so behaviorWeight penalties can never
  // produce a negative score, which would break label thresholds.
  final int rawScore =
      deadlineWeight + difficultyWeight + workloadWeight + behaviorWeight;
  final int score = rawScore.clamp(0, 100);

  final String label;
  if (score >= 70) {
    label = "High Priority";
  } else if (score >= 40) {
    label = (workload == Workload.high || difficulty == Difficulty.hard)
        ? "Heavy Load"
        : "Needs Early Start";
  } else {
    label = (difficulty == Difficulty.easy && workload == Workload.low)
        ? "Quick Task"
        : "Needs Early Start";
  }

  final List<String> reasons = <String>[];
  if (deadlineWeight >= 35) reasons.add("deadline is near");
  if (difficultyWeight >= 20) reasons.add("difficulty is high");
  if (workloadWeight >= 15) reasons.add("workload is high");
  if (behaviorWeight > 0) reasons.add("timing matches your preference");
  if (behaviorWeight < 0) reasons.add("recent mood suggests a lighter start");
  final String reason = reasons.isEmpty
      ? "Suggested using your current profile and deadlines."
      : "Suggested because ${reasons.take(2).join(" and ")}.";

  return <String, dynamic>{"score": score, "label": label, "reason": reason};
}

// ─── Mood → task adjustment recommendation ───────────────────────────────────

/// Returns true when the student's recent mood pattern warrants recommending
/// lighter tasks. Requires ≥2 sad moods in the last 3 logged moods.
///
/// This is the public API used by [FirestoreRepository] when saving the
/// [BehaviorAnalytics.taskAdjustmentRecommended] flag.
bool shouldRecommendTaskAdjustment(List<MoodLog> recentMoods) {
  if (recentMoods.isEmpty) return false;
  final int sadCount =
      recentMoods.take(3).where((MoodLog m) => m.mood == MoodEmoji.sad).length;
  return sadCount >= 2;
}

/// Returns the most recent mood logged within [windowMinutes] before [sessionStart],
/// or an empty string when no recent mood entry exists.
String recentMoodBeforeSession({
  required DateTime sessionStart,
  required List<MoodLog> moods,
  int windowMinutes = 60,
}) {
  final DateTime cutoff =
      sessionStart.subtract(Duration(minutes: windowMinutes));
  final List<MoodLog> candidates = moods
      .where((MoodLog m) =>
          m.createdAt.isAfter(cutoff) &&
          m.createdAt.isBefore(sessionStart))
      .toList()
    ..sort((MoodLog a, MoodLog b) => b.createdAt.compareTo(a.createdAt));

  if (candidates.isEmpty) return "";
  return candidates.first.mood.name;
}

/// Returns how many consecutive sad entries appear at the start of [moods]
/// (which should be sorted newest-first).
int countConsecutiveSadMoods(List<MoodLog> moods) {
  int count = 0;
  for (final MoodLog m in moods) {
    if (m.mood == MoodEmoji.sad) {
      count++;
    } else {
      break;
    }
  }
  return count;
}

// ─── Heatmap builder ─────────────────────────────────────────────────────────

/// Builds a 24-slot [HeatmapSlot] list from raw [StudySession] and [MoodLog]
/// lists — fully local, no API call.
///
/// Algorithm:
///  1. Bucket each session by the hour of [StudySession.startedAt].
///  2. Accumulate [StudySession.actualMinutes] and Pomodoro counts.
///  3. For each slot, find moods logged within 1 hour before the session
///     start and average their numeric scores (happy=3, neutral=2, sad=1).
///
/// Only slots with at least one session are returned (sparse list).
/// Callers can use [HeatmapSlot.intensity] to normalise for rendering.
List<HeatmapSlot> buildHourlyHeatmap({
  required List<StudySession> sessions,
  required List<MoodLog> moods,
}) {
  // bucket[hour] = { minutes, count, moodScoreSum, moodSamples }
  final Map<int, Map<String, num>> buckets = <int, Map<String, num>>{};

  for (final StudySession session in sessions) {
    final int hour = session.startedAt.hour;
    buckets.putIfAbsent(
      hour,
      () => <String, num>{
        "minutes": 0,
        "count": 0,
        "moodSum": 0.0,
        "moodSamples": 0,
      },
    );

    buckets[hour]!["minutes"] =
        buckets[hour]!["minutes"]! + session.actualMinutes;
    buckets[hour]!["count"] = buckets[hour]!["count"]! + 1;

    // Find the most recent mood within 60 min before session start.
    final String preMood = recentMoodBeforeSession(
      sessionStart: session.startedAt,
      moods: moods,
    );
    if (preMood.isNotEmpty) {
      final double score = switch (preMood) {
        "happy" => 3.0,
        "neutral" => 2.0,
        "sad" => 1.0,
        _ => 2.0,
      };
      buckets[hour]!["moodSum"] = buckets[hour]!["moodSum"]! + score;
      buckets[hour]!["moodSamples"] = buckets[hour]!["moodSamples"]! + 1;
    }
  }

  return buckets.entries.map((MapEntry<int, Map<String, num>> entry) {
    final int hour = entry.key;
    final Map<String, num> b = entry.value;
    final int samples = (b["moodSamples"] as num).toInt();
    final double? avgMood = samples > 0
        ? (b["moodSum"] as double) / samples
        : null;

    return HeatmapSlot(
      hour: hour,
      sessionMinutes: (b["minutes"] as num).toInt(),
      sessionCount: (b["count"] as num).toInt(),
      avgMoodScore: avgMood,
    );
  }).toList()
    ..sort((HeatmapSlot a, HeatmapSlot b) => a.hour.compareTo(b.hour));
}

// ─── Mood-productivity correlation builder ────────────────────────────────────

/// Derives [MoodProductivityCorrelation] from sessions and moods — local only.
///
/// Uses [StudySession.midSessionMood] as the primary mood signal.
/// Falls back to the pre-session mood window when midSessionMood is empty.
MoodProductivityCorrelation buildMoodProductivityCorrelation({
  required List<StudySession> sessions,
  required List<MoodLog> moods,
}) {
  // Accumulators per mood bucket
  final Map<String, _MoodBucket> buckets = <String, _MoodBucket>{
    "happy": _MoodBucket(),
    "neutral": _MoodBucket(),
    "sad": _MoodBucket(),
  };

  for (final StudySession session in sessions) {
    // Determine the effective mood for this session
    String effectiveMood = session.midSessionMood;
    if (effectiveMood.isEmpty) {
      effectiveMood = recentMoodBeforeSession(
        sessionStart: session.startedAt,
        moods: moods,
      );
    }
    if (effectiveMood.isEmpty) effectiveMood = "neutral";

    final _MoodBucket? bucket = buckets[effectiveMood];
    if (bucket == null) continue;

    bucket.count++;
    bucket.totalPomodoros += session.pomodorosCompleted;

    // "Completed" = actual minutes reached ≥ 90% of planned
    if (session.plannedMinutes > 0 &&
        session.actualMinutes >= session.plannedMinutes * 0.9) {
      bucket.completedSessions++;
    }
  }

  double _rate(_MoodBucket b) =>
      b.count > 0 ? b.completedSessions / b.count : 0.0;
  double _avg(_MoodBucket b) =>
      b.count > 0 ? b.totalPomodoros / b.count : 0.0;

  return MoodProductivityCorrelation(
    happyCompletionRate: _rate(buckets["happy"]!),
    neutralCompletionRate: _rate(buckets["neutral"]!),
    sadCompletionRate: _rate(buckets["sad"]!),
    happyAvgPomodoros: _avg(buckets["happy"]!),
    neutralAvgPomodoros: _avg(buckets["neutral"]!),
    sadAvgPomodoros: _avg(buckets["sad"]!),
    happySamples: buckets["happy"]!.count,
    neutralSamples: buckets["neutral"]!.count,
    sadSamples: buckets["sad"]!.count,
  );
}

// Private accumulator helper
class _MoodBucket {
  int count = 0;
  int completedSessions = 0;
  int totalPomodoros = 0;
}

// ─── Insight generation ───────────────────────────────────────────────────────

Future<List<InsightCardData>> generateInsights({
  required UserProfile profile,
  required List<MoodLog> moods,
  required List<TaskItem> tasks,
  int thoughtsShared = 0,
}) {
  return ClaudeService.generateInsights(
    profile: profile,
    moods: moods,
    tasks: tasks,
    thoughtsShared: thoughtsShared,
  );
}

Future<List<InsightCardData>> generateBehaviorInsights({
  required UserProfile profile,
  required List<MoodLog> moods,
  required List<TaskItem> tasks,
  required BehaviorAnalytics analytics,
}) {
  return ClaudeService.generateBehaviorInsights(
    profile: profile,
    moods: moods,
    tasks: tasks,
    analytics: analytics,
  );
}

// ─── Offline prescriptive fallback ───────────────────────────────────────────

/// Fully synchronous fallback used when the AI service is unavailable.
///
/// Key improvements over the old version:
///   • Every insight includes a concrete [InsightCardData.actionItem].
///   • [InsightCardData.urgency] and [InsightCardData.category] are set so
///     the UI can colour-code and group cards correctly.
///   • Raw stats are converted into prescriptive "do this next" language.
///   • Mood-productivity correlation drives the mood insight.
///   • Peak-hour data drives the timing insight.
List<InsightCardData> generateInsightsLocally({
  required UserProfile profile,
  required List<MoodLog> moods,
  required List<TaskItem> tasks,
  required BehaviorAnalytics analytics,
  int thoughtsShared = 0,
}) {
  final List<InsightCardData> insights = <InsightCardData>[];

  // ── 1. Task completion → prescriptive ────────────────────────────────────
  if (analytics.totalTasksCreated >= 2) {
    final int rate = (analytics.taskCompletionRate * 100).round();
    final bool lowRate = rate < 50;
    insights.add(InsightCardData(
      title: lowRate ? "Boost Your Follow-Through" : "Strong Completion Rate",
      message: lowRate
          ? "Only $rate% of your tasks are completed. Breaking tasks into smaller steps could help you close the gap."
          : "You've completed $rate% of your tasks — you're building real consistency.",
      why:
          "${analytics.totalTasksCompleted} completed out of ${analytics.totalTasksCreated} created.",
      actionItem: lowRate
          ? "Pick one pending task today and break it into 3 micro-steps before starting."
          : "Keep the streak going — try completing one task each day this week.",
      urgency: lowRate ? InsightUrgency.warning : InsightUrgency.positive,
      category: InsightCategory.taskCompletion,
    ));
  }

  // ── 2. Mood → productivity (correlation-aware) ───────────────────────────
  final MoodProductivityCorrelation corr = analytics.moodProductivity;
  final String? bestMood = corr.bestMoodForStudy;

  if (bestMood != null) {
    final double bestAvg = switch (bestMood) {
      "happy" => corr.happyAvgPomodoros,
      "neutral" => corr.neutralAvgPomodoros,
      _ => corr.sadAvgPomodoros,
    };
    final String moodLabel = switch (bestMood) {
      "happy" => "in a happy mood 😊",
      "neutral" => "feeling neutral 😐",
      _ => "studying through low moods 💪",
    };
    insights.add(InsightCardData(
      title: "Your Peak Study Mood",
      message:
          "You average ${bestAvg.toStringAsFixed(1)} Pomodoros per session when $moodLabel — more than any other mood state.",
      why:
          "Computed from ${corr.happySamples + corr.neutralSamples + corr.sadSamples} sessions with mood data.",
      actionItem: bestMood == "happy" || bestMood == "neutral"
          ? "Log your mood before your next session so the app can time hard tasks to your best windows."
          : "Try a 2-minute breathing exercise before studying to reset your mood.",
      urgency: InsightUrgency.info,
      category: InsightCategory.mood,
    ));
  } else if (moods.isNotEmpty) {
    // Fallback to raw trend when no correlation data exists yet
    final int happy =
        moods.where((MoodLog m) => m.mood == MoodEmoji.happy).length;
    final int sad =
        moods.where((MoodLog m) => m.mood == MoodEmoji.sad).length;
    final bool positive = happy > sad;
    insights.add(InsightCardData(
      title: positive ? "Positive Mood Trend" : "Low Mood Pattern Detected",
      message: positive
          ? "Your logged mood is trending positive — $happy positive entries vs $sad low entries."
          : "You've logged more low moods ($sad) than positive ones ($happy) recently.",
      why: "Derived from ${moods.length} recent mood logs.",
      actionItem: positive
          ? "Log your mood before studying — you may find your best sessions cluster around these positive windows."
          : "Consider lighter tasks or a short walk before your next study block.",
      urgency:
          positive ? InsightUrgency.positive : InsightUrgency.warning,
      category: InsightCategory.mood,
    ));
  }

  // ── 3. Mood → task adjustment recommendation ─────────────────────────────
  if (analytics.taskAdjustmentRecommended) {
    insights.add(InsightCardData(
      title: "Time for a Lighter Load",
      message:
          "You've logged ${analytics.consecutiveSadMoods} consecutive low moods. Pushing through heavy tasks now may widen the gap.",
      why:
          "Task adjustment is recommended when 2+ consecutive sad moods appear before high-workload sessions.",
      actionItem:
          "Swap your next hard task for an easy review session. Return to heavy work once your mood rebounds.",
      urgency: InsightUrgency.warning,
      category: InsightCategory.mood,
    ));
  }

  // ── 4. Peak hours insight ─────────────────────────────────────────────────
  if (analytics.hourlyHeatmap.isNotEmpty) {
    final List<HeatmapSlot> top = analytics.topPeakHours(n: 2);
    if (top.isNotEmpty) {
      final String topLabels =
          top.map((HeatmapSlot s) => s.label).join(" and ");
      insights.add(InsightCardData(
        title: "Your Peak Study Windows",
        message:
            "You log the most study minutes around $topLabels — schedule your hardest tasks in these windows.",
        why:
            "Derived from ${analytics.totalSessionsCompleted} sessions across the hourly heatmap.",
        actionItem:
            "Block ${top.first.label} in your calendar tomorrow for your highest-priority task.",
        urgency: InsightUrgency.info,
        category: InsightCategory.peakHours,
      ));
    }
  } else if (analytics.studyPeakHour != null) {
    // Legacy fallback for users without heatmap data yet
    final int h = analytics.studyPeakHour!;
    final String period = h < 12 ? "AM" : "PM";
    final int h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    insights.add(InsightCardData(
      title: "Peak Hour Detected",
      message:
          "Your most recent study activity was logged around $h12 $period. Try scheduling hard tasks then.",
      why: "Derived from studyPeakHour recorded during your last session.",
      actionItem: "Set a recurring focus block at $h12 $period this week.",
      urgency: InsightUrgency.info,
      category: InsightCategory.peakHours,
    ));
  }

  // ── 5. Session quality insight ─────────────────────────────────────────────
  if (analytics.totalSessionsCompleted > 0) {
    final int avgMins = analytics.totalSessionsCompleted > 0
        ? analytics.totalSessionMinutes ~/
            analytics.totalSessionsCompleted
        : 0;
    final bool shortSessions = avgMins < 25;
    insights.add(InsightCardData(
      title: shortSessions
          ? "Sessions Ending Too Early"
          : "Solid Session Length",
      message: shortSessions
          ? "Your average session is $avgMins minutes — less than one full Pomodoro. You may be stopping before reaching flow state."
          : "You average $avgMins minutes per session across ${analytics.totalSessionsCompleted} sessions.",
      why:
          "${analytics.totalSessionMinutes} total study minutes over ${analytics.totalSessionsCompleted} sessions.",
      actionItem: shortSessions
          ? "Commit to completing at least one full 25-minute Pomodoro before stopping next session."
          : "Try adding one extra Pomodoro to your longest sessions to deepen retention.",
      urgency: shortSessions ? InsightUrgency.warning : InsightUrgency.info,
      category: InsightCategory.productivity,
    ));
  }

  // ── 6. Reflection / social activity ──────────────────────────────────────
  if (thoughtsShared > 0 || analytics.totalCardsPosted > 0) {
    final int posts = analytics.totalCardsPosted > 0
        ? analytics.totalCardsPosted
        : thoughtsShared;
    insights.add(InsightCardData(
      title: "Reflection Builds Retention",
      message:
          "You've shared $posts learning ${posts == 1 ? 'thought' : 'thoughts'} — reflection strengthens long-term memory.",
      why:
          "Active recall via writing has been shown to improve retention by up to 50%.",
      actionItem:
          "After each study session, write one sentence on what you learned and share it.",
      urgency: InsightUrgency.positive,
      category: InsightCategory.social,
    ));
  }

  return insights;
}
