import "dart:math";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/foundation.dart" show debugPrint;

import "../models/app_models.dart";
import "../models/weekly_challenge_models.dart";
import "gamification_utils.dart";

/// Mixin that adds weekly-challenge logic to [FirestoreRepository].
/// Call [ensureWeeklyChallengesAssigned] at app boot and after any event.
/// Call the increment helpers from the relevant repo write methods.
mixin WeeklyChallengeService {
  // ── These must be provided by the host class ───────────────────────────────
  String get uid;
  FirebaseFirestore get db;

  DocumentReference<Map<String, dynamic>> get userRef =>
      db.collection("users").doc(uid);

  // ── Public API ─────────────────────────────────────────────────────────────

  Stream<List<WeeklyChallenge>> watchWeeklyChallenges() {
    final DateTime weekStart = _currentWeekStart();
    return userRef
        .collection("weekly_challenges")
        .where("weekStartDate",
            isEqualTo: Timestamp.fromDate(weekStart))
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) =>
            s.docs.map(WeeklyChallenge.fromDoc).toList());
  }

  /// Call once at app start and each Monday — idempotent (won't re-create
  /// challenges that already exist for the current week).
  Future<void> ensureWeeklyChallengesAssigned() async {
    try {
      final DateTime weekStart = _currentWeekStart();
      final QuerySnapshot<Map<String, dynamic>> existing = await userRef
          .collection("weekly_challenges")
          .where("weekStartDate",
              isEqualTo: Timestamp.fromDate(weekStart))
          .get();
      if (existing.docs.isNotEmpty) return; // already assigned

      final List<WeeklyChallengeDef> selected =
          _selectChallengesForWeek(weekStart);

      final WriteBatch batch = db.batch();
      for (final WeeklyChallengeDef def in selected) {
        final DocumentReference<Map<String, dynamic>> ref =
            userRef.collection("weekly_challenges").doc();
        batch.set(ref, <String, dynamic>{
          "defId": def.id,
          "title": def.title,
          "description": def.description,
          "emoji": def.emoji,
          "xpReward": def.xpReward,
          "targetCount": def.targetCount,
          "currentCount": 0,
          "completed": false,
          "weekStartDate": Timestamp.fromDate(weekStart),
          "createdAt": FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      debugPrint(
          "[WeeklyChallenges] Assigned ${selected.length} challenges for week of $weekStart");
    } catch (e) {
      debugPrint("[WeeklyChallenges] ensureWeeklyChallengesAssigned failed: $e");
    }
  }

  /// Increment progress for challenges that match [eventType].
  /// Optionally filter by [difficulty] and/or [subject].
  /// Pass [pomodoroCount] when the event is a study session.
  Future<void> incrementChallengeProgress({
    required String eventType,
    String? difficulty,
    String? subject,
    int pomodoroCount = 0,
    bool isDeepSession = false,
  }) async {
    try {
      final DateTime weekStart = _currentWeekStart();
      final QuerySnapshot<Map<String, dynamic>> snap = await userRef
          .collection("weekly_challenges")
          .where("weekStartDate",
              isEqualTo: Timestamp.fromDate(weekStart))
          .where("completed", isEqualTo: false)
          .get();

      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snap.docs) {
        final Map<String, dynamic> data = doc.data();
        final String defId = (data["defId"] ?? "") as String;
        final WeeklyChallengeDef? def = weeklyChallengePool
            .where((WeeklyChallengeDef d) => d.id == defId)
            .firstOrNull;
        if (def == null) continue;

        int increment = 0;

        switch (def.eventType) {
          case "task_completed":
            if (eventType == "task_completed") {
              if (def.difficultyFilter == null ||
                  def.difficultyFilter == difficulty) {
                increment = 1;
              }
            }

          case "pomodoro":
            if (eventType == "study_session" && pomodoroCount > 0) {
              increment = pomodoroCount;
            }

          case "study_session":
            if (eventType == "study_session") increment = 1;

          case "deep_session":
            if (eventType == "study_session" && isDeepSession) increment = 1;

          case "mood_logged":
            if (eventType == "mood_logged") increment = 1;

          case "mood_streak":
            // Handled separately by _checkMoodStreak — skip here.
            break;

          case "insight_posted":
            if (eventType == "insight_posted") increment = 1;

          case "daily_active":
            // Handled separately by incrementDailyActiveChallenge.
            break;

          case "subject_variety":
            // Handled separately by _checkSubjectVariety.
            break;
        }

        if (increment > 0) {
          await _applyIncrement(doc.reference, data, increment);
        }
      }

      // Special aggregated checks
      if (eventType == "task_completed" && subject != null) {
        await _checkSubjectVariety(weekStart);
      }
      if (eventType == "mood_logged") {
        await _checkMoodStreak(weekStart);
      }
    } catch (e) {
      debugPrint("[WeeklyChallenges] incrementChallengeProgress failed: $e");
    }
  }

  /// Call from _touchDailyActivity — marks one active day for streak challenges.
  Future<void> incrementDailyActiveChallenge() async {
    try {
      final DateTime weekStart = _currentWeekStart();
      final QuerySnapshot<Map<String, dynamic>> snap = await userRef
          .collection("weekly_challenges")
          .where("weekStartDate",
              isEqualTo: Timestamp.fromDate(weekStart))
          .where("completed", isEqualTo: false)
          .get();

      final String todayKey = _dayKey(DateTime.now());

      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snap.docs) {
        final Map<String, dynamic> data = doc.data();
        final String defId = (data["defId"] ?? "") as String;
        if (defId != "streak_5" && defId != "streak_7") continue;

        // Only count once per calendar day
        final List<dynamic> activeDays =
            (data["activeDays"] as List<dynamic>?) ?? <dynamic>[];
        if (activeDays.contains(todayKey)) continue;

        final List<String> updated =
            <String>[...activeDays.cast<String>(), todayKey];
        final int newCount = updated.length;
        final int target = (data["targetCount"] ?? 7) as int;
        final bool nowDone = newCount >= target;

        final Map<String, dynamic> updates = <String, dynamic>{
          "activeDays": updated,
          "currentCount": newCount,
        };

        if (nowDone) {
          updates["completed"] = true;
          updates["completedAt"] = FieldValue.serverTimestamp();
        }

        await doc.reference.set(updates, SetOptions(merge: true));

        if (nowDone) {
          await _awardChallengeXp(data["xpReward"] as int? ?? 75);
        }
      }
    } catch (e) {
      debugPrint("[WeeklyChallenges] incrementDailyActiveChallenge failed: $e");
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _applyIncrement(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
    int increment,
  ) async {
    final int current = (data["currentCount"] ?? 0) as int;
    final int target = (data["targetCount"] ?? 1) as int;
    final int newCount = current + increment;
    final bool nowDone = newCount >= target;

    final Map<String, dynamic> updates = <String, dynamic>{
      "currentCount": nowDone ? target : newCount,
    };

    if (nowDone) {
      updates["completed"] = true;
      updates["completedAt"] = FieldValue.serverTimestamp();
    }

    await ref.set(updates, SetOptions(merge: true));

    if (nowDone) {
      await _awardChallengeXp(data["xpReward"] as int? ?? 75);
      debugPrint(
          "[WeeklyChallenges] ✅ Challenge '${data['title']}' completed!");
    }
  }

  Future<void> _awardChallengeXp(int amount) async {
    try {
      await userRef.set(
        <String, dynamic>{"xp": FieldValue.increment(amount)},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint("[WeeklyChallenges] _awardChallengeXp failed: $e");
    }
  }

  Future<void> _checkMoodStreak(DateTime weekStart) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await userRef
          .collection("weekly_challenges")
          .where("weekStartDate",
              isEqualTo: Timestamp.fromDate(weekStart))
          .where("defId", isEqualTo: "mood_streak_3")
          .where("completed", isEqualTo: false)
          .get();

      if (snap.docs.isEmpty) return;
      final doc = snap.docs.first;

      // Fetch this week's mood logs and count consecutive days
      final QuerySnapshot<Map<String, dynamic>> moodSnap = await userRef
          .collection("mood_logs")
          .where("createdAt",
              isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
          .get();

      final Set<String> moodDays = moodSnap.docs.map((d) {
        final Timestamp? ts = d.data()["createdAt"] as Timestamp?;
        if (ts == null) return "";
        return _dayKey(ts.toDate());
      }).where((s) => s.isNotEmpty).toSet();

      int streak = 0;
      int maxStreak = 0;
      DateTime cursor = weekStart;
      final DateTime today = DateTime.now();
      while (!cursor.isAfter(today)) {
        if (moodDays.contains(_dayKey(cursor))) {
          streak++;
          if (streak > maxStreak) maxStreak = streak;
        } else {
          streak = 0;
        }
        cursor = cursor.add(const Duration(days: 1));
      }

      await _applyIncrement(
          doc.reference, doc.data(), maxStreak - (doc.data()["currentCount"] as int? ?? 0));
    } catch (_) {}
  }

  Future<void> _checkSubjectVariety(DateTime weekStart) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await userRef
          .collection("weekly_challenges")
          .where("weekStartDate",
              isEqualTo: Timestamp.fromDate(weekStart))
          .where("defId", isEqualTo: "multi_subject")
          .where("completed", isEqualTo: false)
          .get();

      if (snap.docs.isEmpty) return;
      final doc = snap.docs.first;

      final QuerySnapshot<Map<String, dynamic>> taskSnap = await userRef
          .collection("tasks")
          .where("completed", isEqualTo: true)
          .where("completedAt",
              isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
          .get();

      final Set<String> subjects = taskSnap.docs
          .map((d) => (d.data()["subject"] ?? "") as String)
          .where((s) => s.isNotEmpty)
          .toSet();

      final int newCount = subjects.length;
      final int oldCount =
          (doc.data()["currentCount"] as int?) ?? 0;
      if (newCount > oldCount) {
        await _applyIncrement(
            doc.reference, doc.data(), newCount - oldCount);
      }
    } catch (_) {}
  }

  // ── Utility ────────────────────────────────────────────────────────────────

  /// Monday of the current ISO week, at midnight UTC.
  DateTime _currentWeekStart() {
    final DateTime now = DateTime.now().toUtc();
    final int daysFromMonday = (now.weekday - DateTime.monday) % 7;
    return DateTime.utc(now.year, now.month, now.day - daysFromMonday);
  }

  String _dayKey(DateTime dt) => "${dt.year}-${dt.month}-${dt.day}";

  /// Deterministically picks 3 challenges from the pool using the
  /// week's start date as a seed, so every user gets the same 3
  /// challenges but they rotate each week.
  List<WeeklyChallengeDef> _selectChallengesForWeek(DateTime weekStart) {
    final int seed =
        weekStart.year * 10000 + weekStart.month * 100 + weekStart.day;
    final Random rng = Random(seed);
    final List<WeeklyChallengeDef> shuffled =
        List<WeeklyChallengeDef>.from(weeklyChallengePool)..shuffle(rng);
    return shuffled.take(3).toList();
  }
}
