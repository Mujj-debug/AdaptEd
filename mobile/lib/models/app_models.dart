import "dart:math";

import "package:cloud_firestore/cloud_firestore.dart";

enum PersonalityType { introvert, extrovert }
enum ProductivityPreference { morning, night, flexible }
enum Difficulty { easy, medium, hard }
enum Workload { low, medium, high }
enum MoodEmoji { happy, neutral, sad }

// ── Profile field descriptions ─────────────────────────────────────────────────
// These are the semantic meanings of the 1–5 integer fields.
// Used in AI prompt injection and ProfileScreen display.
//
// studyFocus:
//   1–2 = short bursts (< 25 min sessions)
//   3   = moderate (25–45 min)
//   4   = sustained (45–75 min)
//   5   = deep work (75+ min)
//
// socialEnergy:
//   1–2 = strongly introverted, drains quickly in groups
//   3   = ambivert
//   4–5 = extroverted, energised by collaboration
//
// restImportance:
//   1–2 = pushes through, rarely rests
//   3   = balanced
//   4–5 = rest is non-negotiable for performance
//
// creativity:
//   1–2 = prefers structured, defined tasks
//   3   = hybrid
//   4–5 = thrives on open-ended, generative work
//
// physicalActivity:
//   1–2 = mostly sedentary
//   3   = moderate
//   4–5 = regularly active, exercise is part of routine

String studyFocusLabel(int v) => switch (v) {
      1 || 2 => "Short bursts (< 25 min)",
      3      => "Moderate (25–45 min)",
      4      => "Sustained (45–75 min)",
      _      => "Deep work (75+ min)",
    };

String socialEnergyLabel(int v) => switch (v) {
      1 || 2 => "Strongly introverted",
      3      => "Ambivert",
      _      => "Extroverted",
    };

String restImportanceLabel(int v) => switch (v) {
      1 || 2 => "Pushes through",
      3      => "Balanced",
      _      => "Rest is essential",
    };

String creativityLabel(int v) => switch (v) {
      1 || 2 => "Structured tasks",
      3      => "Hybrid",
      _      => "Open-ended work",
    };

String physicalActivityLabel(int v) => switch (v) {
      1 || 2 => "Mostly sedentary",
      3      => "Moderately active",
      _      => "Regularly active",
    };

class UserProfile {
  UserProfile({
    required this.personalityType,
    required this.productivityPreference,
    required this.socialEnergy,
    required this.studyFocus,
    required this.restImportance,
    required this.creativity,
    required this.physicalActivity,
    this.dailyStudyHours = 3.0,
  });

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    return UserProfile(
      personalityType: PersonalityType.values.byName(
          data["personalityType"] ?? "introvert"),
      productivityPreference: ProductivityPreference.values.byName(
          data["productivityPreference"] ?? "flexible"),
      socialEnergy: (data["socialEnergy"] ?? 3) as int,
      studyFocus: (data["studyFocus"] ?? 3) as int,
      restImportance: (data["restImportance"] ?? 3) as int,
      creativity: (data["creativity"] ?? 3) as int,
      physicalActivity: (data["physicalActivity"] ?? 3) as int,
      dailyStudyHours: ((data["dailyStudyHours"] ?? 3.0) as num).toDouble(),
    );
  }

  PersonalityType personalityType;
  ProductivityPreference productivityPreference;
  int socialEnergy;
  int studyFocus;
  int restImportance;
  int creativity;
  int physicalActivity;

  /// Student's self-reported or profile-derived available study hours per day.
  /// Used by DeadlineConflictDetector. Defaults to 3.0 h/day.
  double dailyStudyHours;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      "personalityType": personalityType.name,
      "productivityPreference": productivityPreference.name,
      "socialEnergy": socialEnergy,
      "studyFocus": studyFocus,
      "restImportance": restImportance,
      "creativity": creativity,
      "physicalActivity": physicalActivity,
      "dailyStudyHours": dailyStudyHours,
      "updatedAt": FieldValue.serverTimestamp(),
    };
  }
}

UserProfile defaultProfile() => UserProfile(
      personalityType: PersonalityType.introvert,
      productivityPreference: ProductivityPreference.flexible,
      socialEnergy: 3,
      studyFocus: 3,
      restImportance: 3,
      creativity: 3,
      physicalActivity: 3,
    );

// ── ProfileChangeLogEntry ──────────────────────────────────────────────────────

/// Written to users/{uid}/profile_change_log whenever _updateProfileFromBehavior
/// mutates a field. Surfaced in ProfileScreen as "Why did this change?".
class ProfileChangeLogEntry {
  ProfileChangeLogEntry({
    required this.field,
    required this.fromValue,
    required this.toValue,
    required this.reason,
    required this.changedAt,
  });

  factory ProfileChangeLogEntry.fromMap(Map<String, dynamic> data) {
    return ProfileChangeLogEntry(
      field: (data["field"] ?? "") as String,
      fromValue: (data["fromValue"] ?? 0) as int,
      toValue: (data["toValue"] ?? 0) as int,
      reason: (data["reason"] ?? "") as String,
      changedAt:
          (data["changedAt"] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  final String field;
  final int fromValue;
  final int toValue;
  final String reason;
  final DateTime changedAt;

  Map<String, dynamic> toMap() => <String, dynamic>{
        "field": field,
        "fromValue": fromValue,
        "toValue": toValue,
        "reason": reason,
        "changedAt": Timestamp.fromDate(changedAt),
      };
}

class TaskItem {
  TaskItem({
    required this.id,
    required this.name,
    required this.description,
    required this.subject,
    required this.deadline,
    required this.difficulty,
    required this.workload,
    required this.completed,
    required this.priorityScore,
    required this.priorityLabel,
    required this.priorityReason,
    this.completedAt,
    this.aiMethod = "",
    this.aiSteps = const <String>[],
    this.aiStudyTips = const <String>[],
    this.aiProductivityAdvice = "",
    this.aiSuggestedResources = const <Map<String, String>>[],
    this.aiEstimatedMinutes = 0,
    this.aiBestTime = "",
    this.aiPomodoroSessions = 0,
    this.aiBreakStrategy = "",
    this.aiOverlapWarning,
  });

  factory TaskItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};

    List<String> strList(dynamic raw) {
      if (raw == null) return <String>[];
      return (raw as List<dynamic>).map((dynamic e) => "$e").toList();
    }

    List<Map<String, String>> resourceList(dynamic raw) {
      if (raw == null) return <Map<String, String>>[];
      return (raw as List<dynamic>).map((dynamic e) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(e as Map);
        return <String, String>{
          "title": (m["title"] ?? "") as String,
          "url": (m["url"] ?? "") as String,
        };
      }).toList();
    }

    return TaskItem(
      id: doc.id,
      name: (data["name"] ?? "") as String,
      description: (data["description"] ?? "") as String,
      subject: (data["subject"] ?? "") as String,
      deadline:
          (data["deadline"] as Timestamp?)?.toDate() ?? DateTime.now(),
      difficulty:
          Difficulty.values.byName(data["difficulty"] ?? "medium"),
      workload: Workload.values.byName(data["workload"] ?? "medium"),
      completed: (data["completed"] ?? false) as bool,
      completedAt: (data["completedAt"] as Timestamp?)?.toDate(),
      priorityScore: (data["priorityScore"] ?? 0) as int,
      priorityLabel: (data["priorityLabel"] ?? "Quick Task") as String,
      priorityReason:
          (data["priorityReason"] ?? "Recommendation pending.") as String,
      aiMethod: (data["aiMethod"] ?? "") as String,
      aiSteps: strList(data["aiSteps"]),
      aiStudyTips: strList(data["aiStudyTips"]),
      aiProductivityAdvice: (data["aiProductivityAdvice"] ?? "") as String,
      aiSuggestedResources: resourceList(data["aiSuggestedResources"]),
      aiEstimatedMinutes: (data["aiEstimatedMinutes"] ?? 0) as int,
      aiBestTime: (data["aiBestTime"] ?? "") as String,
      aiPomodoroSessions: (data["aiPomodoroSessions"] ?? 0) as int,
      aiBreakStrategy: (data["aiBreakStrategy"] ?? "") as String,
      aiOverlapWarning: data["aiOverlapWarning"] as String?,
    );
  }

  final String id;
  final String name;
  final String description;
  final String subject;
  final DateTime deadline;
  final Difficulty difficulty;
  final Workload workload;
  final bool completed;
  final DateTime? completedAt;
  final int priorityScore;
  final String priorityLabel;
  final String priorityReason;
  final String aiMethod;
  final List<String> aiSteps;
  final List<String> aiStudyTips;
  final String aiProductivityAdvice;
  final List<Map<String, String>> aiSuggestedResources;
  final int aiEstimatedMinutes;
  final String aiBestTime;
  final int aiPomodoroSessions;
  final String aiBreakStrategy;
  final String? aiOverlapWarning;
}

class MoodLog {
  MoodLog({
    required this.id,
    required this.mood,
    required this.activity,
    required this.note,
    required this.createdAt,
  });

  factory MoodLog.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return MoodLog(
      id: doc.id,
      mood: MoodEmoji.values.byName(data["mood"] ?? "neutral"),
      activity: (data["activity"] ?? "study") as String,
      note: (data["note"] ?? "") as String,
      createdAt:
          (data["createdAt"] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  final String id;
  final MoodEmoji mood;
  final String activity;
  final String note;
  final DateTime createdAt;
}

// ── MidCheckIn ────────────────────────────────────────────────────────────────

/// A lightweight snapshot captured during a Focus Mode session.
/// Triggered automatically after the 2nd completed Pomodoro.
class MidCheckIn {
  MidCheckIn({
    required this.mood,
    required this.atPomodoro,
    required this.capturedAt,
    this.note = "",
  });

  factory MidCheckIn.fromMap(Map<String, dynamic> data) {
    return MidCheckIn(
      mood: (data["mood"] ?? "neutral") as String,
      note: (data["note"] ?? "") as String,
      atPomodoro: (data["atPomodoro"] ?? 0) as int,
      capturedAt:
          (data["capturedAt"] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// "happy" | "neutral" | "sad"
  final String mood;

  /// Optional one-line note from the student.
  final String note;

  /// Which Pomodoro number triggered this check-in (e.g. 2).
  final int atPomodoro;

  final DateTime capturedAt;

  Map<String, dynamic> toMap() => <String, dynamic>{
        "mood": mood,
        "note": note,
        "atPomodoro": atPomodoro,
        "capturedAt": Timestamp.fromDate(capturedAt),
      };
}

// ── ActiveSession ─────────────────────────────────────────────────────────────

/// Written to users/{uid}/active_session when a Focus Mode session starts.
/// Deleted when the session is completed or abandoned.
/// Enables session resume after app kill / backgrounding.
class ActiveSession {
  ActiveSession({
    required this.taskId,
    required this.taskName,
    required this.subject,
    required this.plannedMinutes,
    required this.pomodorosTarget,
    required this.pomodorosCompleted,
    required this.startedAt,
    this.state = "running",
  });

  factory ActiveSession.fromMap(Map<String, dynamic> data) {
    return ActiveSession(
      taskId: (data["taskId"] ?? "") as String,
      taskName: (data["taskName"] ?? "") as String,
      subject: (data["subject"] ?? "") as String,
      plannedMinutes: (data["plannedMinutes"] ?? 25) as int,
      pomodorosTarget: (data["pomodorosTarget"] ?? 1) as int,
      pomodorosCompleted: (data["pomodorosCompleted"] ?? 0) as int,
      startedAt:
          (data["startedAt"] as Timestamp?)?.toDate() ?? DateTime.now(),
      state: (data["state"] ?? "running") as String,
    );
  }

  final String taskId;
  final String taskName;
  final String subject;
  final int plannedMinutes;
  final int pomodorosTarget;
  final int pomodorosCompleted;
  final DateTime startedAt;

  /// "running" | "paused" | "completed"
  final String state;

  int get elapsedMinutes =>
      DateTime.now().difference(startedAt).inMinutes.clamp(0, plannedMinutes);

  Map<String, dynamic> toMap() => <String, dynamic>{
        "taskId": taskId,
        "taskName": taskName,
        "subject": subject,
        "plannedMinutes": plannedMinutes,
        "pomodorosTarget": pomodorosTarget,
        "pomodorosCompleted": pomodorosCompleted,
        "startedAt": Timestamp.fromDate(startedAt),
        "state": state,
      };
}

// ── Study Session ─────────────────────────────────────────────────────────────

class StudySession {
  StudySession({
    required this.id,
    required this.taskId,
    required this.taskName,
    required this.subject,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.pomodorosCompleted,
    required this.feltDifficulty,
    required this.startedAt,
    required this.completedAt,
    this.midSessionMood = "",
    this.note = "",
    this.checkIns = const <MidCheckIn>[],
    this.aiSessionSummary,
  });

  factory StudySession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};

    final List<MidCheckIn> checkIns = <MidCheckIn>[];
    if (data["checkIns"] != null) {
      for (final dynamic item in data["checkIns"] as List<dynamic>) {
        checkIns.add(MidCheckIn.fromMap(
            Map<String, dynamic>.from(item as Map)));
      }
    }

    return StudySession(
      id: doc.id,
      taskId: (data["taskId"] ?? "") as String,
      taskName: (data["taskName"] ?? "") as String,
      subject: (data["subject"] ?? "") as String,
      plannedMinutes: (data["plannedMinutes"] ?? 0) as int,
      actualMinutes: (data["actualMinutes"] ?? 0) as int,
      pomodorosCompleted: (data["pomodorosCompleted"] ?? 0) as int,
      feltDifficulty: (data["feltDifficulty"] ?? 3) as int,
      startedAt:
          (data["startedAt"] as Timestamp?)?.toDate() ?? DateTime.now(),
      completedAt:
          (data["completedAt"] as Timestamp?)?.toDate() ?? DateTime.now(),
      midSessionMood: (data["midSessionMood"] ?? "") as String,
      note: (data["note"] ?? "") as String,
      checkIns: checkIns,
      aiSessionSummary: data["aiSessionSummary"] as String?,
    );
  }

  final String id;
  final String taskId;
  final String taskName;
  final String subject;
  final int plannedMinutes;
  final int actualMinutes;
  final int pomodorosCompleted;
  final int feltDifficulty; // 1–5
  final DateTime startedAt;
  final DateTime completedAt;
  final String midSessionMood;
  final String note;

  /// Mid-session mood snapshots captured during the session.
  final List<MidCheckIn> checkIns;

  /// AI-generated 2–3 sentence summary generated at session end.
  final String? aiSessionSummary;

  Map<String, dynamic> toMap() => <String, dynamic>{
        "taskId": taskId,
        "taskName": taskName,
        "subject": subject,
        "plannedMinutes": plannedMinutes,
        "actualMinutes": actualMinutes,
        "pomodorosCompleted": pomodorosCompleted,
        "feltDifficulty": feltDifficulty,
        "startedAt": Timestamp.fromDate(startedAt),
        "completedAt": FieldValue.serverTimestamp(),
        "midSessionMood": midSessionMood,
        "note": note,
        "checkIns": checkIns.map((MidCheckIn c) => c.toMap()).toList(),
        if (aiSessionSummary != null) "aiSessionSummary": aiSessionSummary,
      };
}

// ── Study Strategy ────────────────────────────────────────────────────────────

class StudyStrategy {
  StudyStrategy({
    required this.id,
    required this.title,
    required this.category,
    required this.summary,
    required this.steps,
    required this.evidence,
    required this.authorUsername,
    this.isSystem = false,
    this.reactions = 0,
  });

  factory StudyStrategy.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return StudyStrategy(
      id: doc.id,
      title: (data["title"] ?? "") as String,
      category: (data["category"] ?? "General") as String,
      summary: (data["summary"] ?? "") as String,
      steps: ((data["steps"] ?? <dynamic>[]) as List<dynamic>)
          .map((dynamic e) => "$e")
          .toList(),
      evidence: (data["evidence"] ?? "") as String,
      authorUsername: (data["authorUsername"] ?? "Community") as String,
      isSystem: (data["isSystem"] ?? false) as bool,
      reactions: (data["reactions"] ?? 0) as int,
    );
  }

  /// Construct from a Realtime Database entry (key = id, value = data map).
  factory StudyStrategy.fromRtdb(String key, Map<String, dynamic> data) {
    return StudyStrategy(
      id: key,
      title: (data["title"] ?? "") as String,
      category: (data["category"] ?? "General") as String,
      summary: (data["summary"] ?? "") as String,
      steps: ((data["steps"] ?? <dynamic>[]) as List<dynamic>)
          .map((dynamic e) => "$e")
          .toList(),
      evidence: (data["evidence"] ?? "") as String,
      authorUsername: (data["authorUsername"] ?? "Community") as String,
      isSystem: (data["isSystem"] ?? false) as bool,
      reactions: (data["reactions"] ?? 0) as int,
    );
  }

  final String id;
  final String title;
  final String category;
  final String summary;
  final List<String> steps;
  final String evidence;
  final String authorUsername;
  final bool isSystem;
  final int reactions;

  Map<String, dynamic> toMap() => <String, dynamic>{
        "title": title,
        "category": category,
        "summary": summary,
        "steps": steps,
        "evidence": evidence,
        "authorUsername": authorUsername,
        "isSystem": isSystem,
        "reactions": reactions,
        "createdAt": FieldValue.serverTimestamp(),
      };
}

// ── InsightCardData ───────────────────────────────────────────────────────────

class InsightCardData {
  InsightCardData({
    required this.title,
    required this.message,
    required this.why,
    this.actionItem = "",
    this.actionVerb = "",
    this.actionTarget = "",
    this.urgency = InsightUrgency.info,
    this.category = InsightCategory.general,
  });

  factory InsightCardData.fromMap(Map<String, dynamic> map) {
    return InsightCardData(
      title: (map["title"] ?? "") as String,
      message: (map["message"] ?? "") as String,
      why: (map["why"] ?? "") as String,
      actionItem: (map["actionItem"] ?? "") as String,
      actionVerb: (map["actionVerb"] ?? "") as String,
      actionTarget: (map["actionTarget"] ?? "") as String,
      urgency: InsightUrgency.values.byName(
        (map["urgency"] ?? "info") as String,
      ),
      category: InsightCategory.values.byName(
        (map["category"] ?? "general") as String,
      ),
    );
  }

  final String title;
  final String message;
  final String why;

  /// Full action sentence, e.g. "Add a 45-min Math session before 10 AM tomorrow."
  final String actionItem;

  /// Verb extracted for deep-link routing, e.g. "add_session", "complete_task".
  final String actionVerb;

  /// Target for the action, e.g. a subject name or task id.
  final String actionTarget;

  final InsightUrgency urgency;
  final InsightCategory category;

  Map<String, dynamic> toMap() => <String, dynamic>{
        "title": title,
        "message": message,
        "why": why,
        "actionItem": actionItem,
        "actionVerb": actionVerb,
        "actionTarget": actionTarget,
        "urgency": urgency.name,
        "category": category.name,
      };
}

enum InsightUrgency { info, positive, warning, critical }

enum InsightCategory {
  general,
  mood,
  productivity,
  peakHours,
  taskCompletion,
  social,
  risk,
}

// ── GamificationState ─────────────────────────────────────────────────────────

class GamificationState {
  GamificationState({
    required this.xp,
    required this.streakDays,
    required this.badges,
    this.pendingBadges = const <String>[],
  });

  factory GamificationState.fromMap(Map<String, dynamic>? data) {
    final Map<String, dynamic> safe = data ?? <String, dynamic>{};
    return GamificationState(
      xp: (safe["xp"] ?? 0) as int,
      streakDays: (safe["streakDays"] ?? 0) as int,
      badges: ((safe["badges"] ?? <dynamic>[]) as List<dynamic>)
          .map((dynamic e) => "$e")
          .toList(),
      pendingBadges: ((safe["pendingBadges"] ?? <dynamic>[]) as List<dynamic>)
          .map((dynamic e) => "$e")
          .toList(),
    );
  }

  final int xp;
  final int streakDays;
  final List<String> badges;

  /// Badges earned since the last time the user was shown a celebration.
  /// Cleared after GamificationScreen displays the unlock dialog.
  final List<String> pendingBadges;

  int get level => sqrt(xp / 100).floor() + 1;
}

// ── HeatmapSlot ───────────────────────────────────────────────────────────────

class HeatmapSlot {
  const HeatmapSlot({
    required this.hour,
    this.sessionMinutes = 0,
    this.sessionCount = 0,
    this.avgMoodScore,
  });

  factory HeatmapSlot.fromMap(Map<String, dynamic> data) {
    return HeatmapSlot(
      hour: (data["hour"] ?? 0) as int,
      sessionMinutes: (data["sessionMinutes"] ?? 0) as int,
      sessionCount: (data["sessionCount"] ?? 0) as int,
      avgMoodScore: data["avgMoodScore"] != null
          ? ((data["avgMoodScore"] as num).toDouble())
          : null,
    );
  }

  final int hour;
  final int sessionMinutes;
  final int sessionCount;
  final double? avgMoodScore;

  double intensity(int maxMinutes) =>
      maxMinutes > 0 ? (sessionMinutes / maxMinutes).clamp(0.0, 1.0) : 0.0;

  String get label {
    if (hour == 0) return "12 AM";
    if (hour < 12) return "$hour AM";
    if (hour == 12) return "12 PM";
    return "${hour - 12} PM";
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        "hour": hour,
        "sessionMinutes": sessionMinutes,
        "sessionCount": sessionCount,
        if (avgMoodScore != null) "avgMoodScore": avgMoodScore,
      };
}

// ── MoodProductivityCorrelation ───────────────────────────────────────────────

class MoodProductivityCorrelation {
  const MoodProductivityCorrelation({
    this.happyCompletionRate = 0.0,
    this.neutralCompletionRate = 0.0,
    this.sadCompletionRate = 0.0,
    this.happyAvgPomodoros = 0.0,
    this.neutralAvgPomodoros = 0.0,
    this.sadAvgPomodoros = 0.0,
    this.happySamples = 0,
    this.neutralSamples = 0,
    this.sadSamples = 0,
  });

  factory MoodProductivityCorrelation.fromMap(Map<String, dynamic> data) {
    return MoodProductivityCorrelation(
      happyCompletionRate:
          ((data["happyCompletionRate"] ?? 0.0) as num).toDouble(),
      neutralCompletionRate:
          ((data["neutralCompletionRate"] ?? 0.0) as num).toDouble(),
      sadCompletionRate:
          ((data["sadCompletionRate"] ?? 0.0) as num).toDouble(),
      happyAvgPomodoros:
          ((data["happyAvgPomodoros"] ?? 0.0) as num).toDouble(),
      neutralAvgPomodoros:
          ((data["neutralAvgPomodoros"] ?? 0.0) as num).toDouble(),
      sadAvgPomodoros:
          ((data["sadAvgPomodoros"] ?? 0.0) as num).toDouble(),
      happySamples: (data["happySamples"] ?? 0) as int,
      neutralSamples: (data["neutralSamples"] ?? 0) as int,
      sadSamples: (data["sadSamples"] ?? 0) as int,
    );
  }

  final double happyCompletionRate;
  final double neutralCompletionRate;
  final double sadCompletionRate;
  final double happyAvgPomodoros;
  final double neutralAvgPomodoros;
  final double sadAvgPomodoros;
  final int happySamples;
  final int neutralSamples;
  final int sadSamples;

  String? get bestMoodForStudy {
    const int minSamples = 3;
    final List<(String, double, int)> candidates = <(String, double, int)>[
      ("happy", happyAvgPomodoros, happySamples),
      ("neutral", neutralAvgPomodoros, neutralSamples),
      ("sad", sadAvgPomodoros, sadSamples),
    ].where(((String, double, int) e) => e.$3 >= minSamples).toList();

    if (candidates.isEmpty) return null;
    candidates.sort(((String, double, int) a, (String, double, int) b) =>
        b.$2.compareTo(a.$2));
    return candidates.first.$1;
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        "happyCompletionRate": happyCompletionRate,
        "neutralCompletionRate": neutralCompletionRate,
        "sadCompletionRate": sadCompletionRate,
        "happyAvgPomodoros": happyAvgPomodoros,
        "neutralAvgPomodoros": neutralAvgPomodoros,
        "sadAvgPomodoros": sadAvgPomodoros,
        "happySamples": happySamples,
        "neutralSamples": neutralSamples,
        "sadSamples": sadSamples,
      };
}

// ── BehaviorAnalytics ─────────────────────────────────────────────────────────

class BehaviorAnalytics {
  BehaviorAnalytics({
    this.studyPeakHour,
    this.avgInsightWordCount = 0,
    this.taskCompletionRate = 0.0,
    this.moodTrend = "neutral",
    this.totalTasksCreated = 0,
    this.totalTasksCompleted = 0,
    this.totalMoodsLogged = 0,
    this.totalCardsPosted = 0,
    this.totalSessionsCompleted = 0,
    this.totalSessionMinutes = 0,
    this.avgFeltDifficulty = 0.0,
    this.subjectSessionMinutes = const <String, int>{},
    this.hourlyHeatmap = const <HeatmapSlot>[],
    this.moodProductivity = const MoodProductivityCorrelation(),
    this.consecutiveSadMoods = 0,
    this.recentMoodBeforeStudy = "",
    this.taskAdjustmentRecommended = false,
  });

  factory BehaviorAnalytics.fromMap(Map<String, dynamic>? data) {
    final Map<String, dynamic> d = data ?? <String, dynamic>{};

    Map<String, int> subjectMinutes = <String, int>{};
    if (d["subjectSessionMinutes"] != null) {
      (d["subjectSessionMinutes"] as Map<dynamic, dynamic>).forEach(
        (dynamic k, dynamic v) =>
            subjectMinutes["$k"] = (v ?? 0) as int,
      );
    }

    final List<HeatmapSlot> heatmap = <HeatmapSlot>[];
    if (d["hourlyHeatmap"] != null) {
      for (final dynamic slot in d["hourlyHeatmap"] as List<dynamic>) {
        heatmap.add(
            HeatmapSlot.fromMap(Map<String, dynamic>.from(slot as Map)));
      }
    }

    MoodProductivityCorrelation moodProd =
        const MoodProductivityCorrelation();
    if (d["moodProductivity"] != null) {
      moodProd = MoodProductivityCorrelation.fromMap(
          Map<String, dynamic>.from(d["moodProductivity"] as Map));
    }

    return BehaviorAnalytics(
      studyPeakHour: d["studyPeakHour"] as int?,
      avgInsightWordCount: (d["avgInsightWordCount"] ?? 0) as int,
      taskCompletionRate:
          ((d["taskCompletionRate"] ?? 0.0) as num).toDouble(),
      moodTrend: (d["moodTrend"] ?? "neutral") as String,
      totalTasksCreated: (d["totalTasksCreated"] ?? 0) as int,
      totalTasksCompleted: (d["totalTasksCompleted"] ?? 0) as int,
      totalMoodsLogged: (d["totalMoodsLogged"] ?? 0) as int,
      totalCardsPosted: (d["totalCardsPosted"] ?? 0) as int,
      totalSessionsCompleted: (d["totalSessionsCompleted"] ?? 0) as int,
      totalSessionMinutes: (d["totalSessionMinutes"] ?? 0) as int,
      avgFeltDifficulty:
          ((d["avgFeltDifficulty"] ?? 0.0) as num).toDouble(),
      subjectSessionMinutes: subjectMinutes,
      hourlyHeatmap: heatmap,
      moodProductivity: moodProd,
      consecutiveSadMoods: (d["consecutiveSadMoods"] ?? 0) as int,
      recentMoodBeforeStudy:
          (d["recentMoodBeforeStudy"] ?? "") as String,
      taskAdjustmentRecommended:
          (d["taskAdjustmentRecommended"] ?? false) as bool,
    );
  }

  final int? studyPeakHour;
  final int avgInsightWordCount;
  final double taskCompletionRate;
  final String moodTrend;
  final int totalTasksCreated;
  final int totalTasksCompleted;
  final int totalMoodsLogged;
  final int totalCardsPosted;
  final int totalSessionsCompleted;
  final int totalSessionMinutes;
  final double avgFeltDifficulty;
  final Map<String, int> subjectSessionMinutes;
  final List<HeatmapSlot> hourlyHeatmap;
  final MoodProductivityCorrelation moodProductivity;
  final int consecutiveSadMoods;
  final String recentMoodBeforeStudy;
  final bool taskAdjustmentRecommended;

  List<HeatmapSlot> topPeakHours({int n = 3}) {
    final List<HeatmapSlot> sorted =
        List<HeatmapSlot>.from(hourlyHeatmap)
          ..sort((HeatmapSlot a, HeatmapSlot b) =>
              b.sessionMinutes.compareTo(a.sessionMinutes));
    return sorted.take(n).toList();
  }

  int get heatmapMaxMinutes => hourlyHeatmap.isEmpty
      ? 0
      : hourlyHeatmap
          .map((HeatmapSlot s) => s.sessionMinutes)
          .reduce((int a, int b) => a > b ? a : b);

  Map<String, dynamic> toMap() => <String, dynamic>{
        if (studyPeakHour != null) "studyPeakHour": studyPeakHour,
        "avgInsightWordCount": avgInsightWordCount,
        "taskCompletionRate": taskCompletionRate,
        "moodTrend": moodTrend,
        "totalTasksCreated": totalTasksCreated,
        "totalTasksCompleted": totalTasksCompleted,
        "totalMoodsLogged": totalMoodsLogged,
        "totalCardsPosted": totalCardsPosted,
        "totalSessionsCompleted": totalSessionsCompleted,
        "totalSessionMinutes": totalSessionMinutes,
        "avgFeltDifficulty": avgFeltDifficulty,
        "subjectSessionMinutes": subjectSessionMinutes,
        "hourlyHeatmap":
            hourlyHeatmap.map((HeatmapSlot s) => s.toMap()).toList(),
        "moodProductivity": moodProductivity.toMap(),
        "consecutiveSadMoods": consecutiveSadMoods,
        "recentMoodBeforeStudy": recentMoodBeforeStudy,
        "taskAdjustmentRecommended": taskAdjustmentRecommended,
      };
}
