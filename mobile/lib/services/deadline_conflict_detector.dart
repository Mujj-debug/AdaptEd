// lib/utils/deadline_conflict_detector.dart
//
// Pure-Dart utility. No Firebase imports.
// Call detect() synchronously in DashboardScreen.build() — it's fast.

import "../models/app_models.dart";

enum ConflictSeverity {
  /// Total required hours fits comfortably within the available window.
  ok,

  /// Required hours exceed available hours by up to 50%.
  warning,

  /// Required hours exceed available hours by more than 50%.
  critical,
}

/// A group of tasks whose combined estimated time exceeds the student's
/// available study hours within a given deadline window.
class ConflictWarning {
  const ConflictWarning({
    required this.tasks,
    required this.windowLabel,
    required this.requiredHours,
    required this.availableHours,
    required this.severity,
  });

  /// The tasks contributing to this conflict (all due within [windowLabel]).
  final List<TaskItem> tasks;

  /// Human-readable window label, e.g. "today", "tomorrow", "next 3 days".
  final String windowLabel;

  /// Sum of aiEstimatedMinutes / 60 for all tasks in this window.
  final double requiredHours;

  /// Student's available study hours for this window (from profile).
  final double availableHours;

  final ConflictSeverity severity;

  String get requiredLabel => _fmt(requiredHours);
  String get availableLabel => _fmt(availableHours);

  String _fmt(double h) =>
      h == h.roundToDouble() ? "${h.round()}h" : "${h.toStringAsFixed(1)}h";

  /// Short summary shown in the dashboard warning card.
  String get summary {
    final String taskWord = tasks.length == 1 ? "task" : "tasks";
    return "${tasks.length} $taskWord due $windowLabel need $requiredLabel — ~$availableLabel available";
  }
}

class DeadlineConflictDetector {
  DeadlineConflictDetector({
    /// How many hours the student can study per day.
    /// Derived from UserProfile.studyFocus and productivityPreference.
    required this.dailyStudyHours,
  });

  final double dailyStudyHours;

  /// Builds the daily hours from a [UserProfile].
  ///
  /// studyFocus 1–2 → 2 h/day
  /// studyFocus 3   → 3 h/day (default)
  /// studyFocus 4   → 4 h/day
  /// studyFocus 5   → 5 h/day
  ///
  /// Night / morning pref adds 30 min because those students tend to have
  /// a concentrated peak window.
  factory DeadlineConflictDetector.fromProfile(UserProfile profile) {
    final double base = switch (profile.studyFocus) {
      1 || 2 => 2.0,
      3      => 3.0,
      4      => 4.0,
      _      => 5.0,
    };
    final double pref =
        profile.productivityPreference == ProductivityPreference.flexible
            ? 0.0
            : 0.5;
    return DeadlineConflictDetector(dailyStudyHours: base + pref);
  }

  /// Returns conflicts ordered by severity (critical first).
  /// Only incomplete tasks with a positive aiEstimatedMinutes are considered.
  List<ConflictWarning> detect(List<TaskItem> tasks) {
    final List<TaskItem> pending = tasks
        .where((TaskItem t) => !t.completed && t.aiEstimatedMinutes > 0)
        .toList();

    final DateTime now = DateTime.now();
    final DateTime todayEnd = _endOfDay(now);
    final DateTime tomorrowEnd = _endOfDay(now.add(const Duration(days: 1)));
    final DateTime threeDayEnd = _endOfDay(now.add(const Duration(days: 3)));

    final List<ConflictWarning> results = <ConflictWarning>[];

    _checkWindow(
      pending: pending,
      windowEnd: todayEnd,
      availableHours: dailyStudyHours,
      label: "today",
      results: results,
    );
    _checkWindow(
      pending: pending,
      windowEnd: tomorrowEnd,
      availableHours: dailyStudyHours * 2,
      label: "by tomorrow",
      results: results,
    );
    _checkWindow(
      pending: pending,
      windowEnd: threeDayEnd,
      availableHours: dailyStudyHours * 3,
      label: "in the next 3 days",
      results: results,
    );

    // Deduplicate: if "today" is already critical, skip "by tomorrow" if it
    // contains the exact same task set.
    final List<ConflictWarning> deduped = <ConflictWarning>[];
    for (final ConflictWarning w in results) {
      final bool alreadyCovered = deduped.any((ConflictWarning prev) {
        final Set<String> prevIds = prev.tasks.map((t) => t.id).toSet();
        final Set<String> wIds = w.tasks.map((t) => t.id).toSet();
        return prevIds.containsAll(wIds);
      });
      if (!alreadyCovered) deduped.add(w);
    }

    deduped.sort((ConflictWarning a, ConflictWarning b) =>
        b.severity.index.compareTo(a.severity.index));
    return deduped;
  }

  void _checkWindow({
    required List<TaskItem> pending,
    required DateTime windowEnd,
    required double availableHours,
    required String label,
    required List<ConflictWarning> results,
  }) {
    final List<TaskItem> inWindow = pending
        .where((TaskItem t) => t.deadline.isBefore(windowEnd))
        .toList();
    if (inWindow.isEmpty) return;

    final double requiredHours = inWindow.fold(
          0.0,
          (double sum, TaskItem t) => sum + t.aiEstimatedMinutes,
        ) /
        60.0;

    final ConflictSeverity severity;
    if (requiredHours <= availableHours) return; // no conflict
    if (requiredHours > availableHours * 1.5) {
      severity = ConflictSeverity.critical;
    } else {
      severity = ConflictSeverity.warning;
    }

    results.add(ConflictWarning(
      tasks: inWindow,
      windowLabel: label,
      requiredHours: requiredHours,
      availableHours: availableHours,
      severity: severity,
    ));
  }

  DateTime _endOfDay(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, 23, 59, 59);
}
