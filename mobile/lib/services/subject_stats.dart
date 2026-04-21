// lib/utils/subject_stats.dart
//
// Computed model — never written to Firestore as a separate document.
// Call SubjectStatsCalculator.compute() with existing tasks + sessions.

import "../models/app_models.dart";

/// Per-subject performance snapshot derived from completed tasks and sessions.
class SubjectStats {
  const SubjectStats({
    required this.subject,
    required this.totalMinutes,
    required this.completedTasks,
    required this.totalTasks,
    required this.avgFeltDifficulty,
    required this.lastStudiedAt,
  });

  final String subject;

  /// Total study minutes logged across all sessions for this subject.
  final int totalMinutes;

  /// Number of completed tasks in this subject.
  final int completedTasks;

  /// Total tasks (completed + pending) in this subject.
  final int totalTasks;

  /// Average felt difficulty across sessions (1–5), or 0 if no sessions.
  final double avgFeltDifficulty;

  /// Most recent session date, or null if never studied.
  final DateTime? lastStudiedAt;

  double get completionRate =>
      totalTasks > 0 ? completedTasks / totalTasks : 0.0;

  /// A subject is a "struggle subject" when the student finds it hard
  /// AND has a poor completion rate — both signals together.
  bool get isStruggling =>
      avgFeltDifficulty >= 4.0 && completionRate < 0.5 && totalTasks >= 2;

  /// Human-readable label for the AI prompt injection.
  String toPromptContext() {
    if (totalMinutes == 0 && totalTasks == 0) {
      return "No history for $subject yet.";
    }
    final String rate = "${(completionRate * 100).round()}%";
    final String diff = avgFeltDifficulty > 0
        ? avgFeltDifficulty.toStringAsFixed(1)
        : "unknown";
    final String struggle = isStruggling ? " (STRUGGLE SUBJECT)" : "";
    return "$subject$struggle: ${totalMinutes}min studied, "
        "$completedTasks/$totalTasks tasks completed ($rate), "
        "avg felt difficulty $diff/5.";
  }
}

class SubjectStatsCalculator {
  /// Computes stats for every subject mentioned in [tasks] or [sessions].
  /// Returns a map keyed by subject name, sorted by total minutes descending.
  static Map<String, SubjectStats> compute({
    required List<TaskItem> tasks,
    required List<StudySession> sessions,
  }) {
    final Map<String, _Builder> builders = <String, _Builder>{};

    for (final TaskItem t in tasks) {
      if (t.subject.isEmpty) continue;
      final _Builder b = builders.putIfAbsent(t.subject, () => _Builder(t.subject));
      b.totalTasks++;
      if (t.completed) b.completedTasks++;
    }

    for (final StudySession s in sessions) {
      if (s.subject.isEmpty) continue;
      final _Builder b = builders.putIfAbsent(s.subject, () => _Builder(s.subject));
      b.totalMinutes += s.actualMinutes;
      if (s.feltDifficulty > 0) {
        b.difficultySum += s.feltDifficulty;
        b.difficultySamples++;
      }
      if (b.lastStudiedAt == null ||
          s.completedAt.isAfter(b.lastStudiedAt!)) {
        b.lastStudiedAt = s.completedAt;
      }
    }

    final List<MapEntry<String, SubjectStats>> entries = builders.entries
        .map((MapEntry<String, _Builder> e) =>
            MapEntry<String, SubjectStats>(e.key, e.value.build()))
        .toList()
      ..sort((MapEntry<String, SubjectStats> a,
              MapEntry<String, SubjectStats> b) =>
          b.value.totalMinutes.compareTo(a.value.totalMinutes));

    return Map<String, SubjectStats>.fromEntries(entries);
  }

  /// Returns a multi-line prompt context string for all subjects,
  /// highlighting struggling subjects first.
  static String buildPromptContext(Map<String, SubjectStats> stats) {
    if (stats.isEmpty) return "No subject history available yet.";
    final List<SubjectStats> sorted = stats.values.toList()
      ..sort((SubjectStats a, SubjectStats b) {
        // struggling subjects first, then by most time spent
        if (a.isStruggling != b.isStruggling) {
          return a.isStruggling ? -1 : 1;
        }
        return b.totalMinutes.compareTo(a.totalMinutes);
      });
    return sorted.map((SubjectStats s) => s.toPromptContext()).join("\n");
  }
}

class _Builder {
  _Builder(this.subject);

  final String subject;
  int totalMinutes = 0;
  int completedTasks = 0;
  int totalTasks = 0;
  double difficultySum = 0;
  int difficultySamples = 0;
  DateTime? lastStudiedAt;

  SubjectStats build() => SubjectStats(
        subject: subject,
        totalMinutes: totalMinutes,
        completedTasks: completedTasks,
        totalTasks: totalTasks,
        avgFeltDifficulty:
            difficultySamples > 0 ? difficultySum / difficultySamples : 0,
        lastStudiedAt: lastStudiedAt,
      );
}
