import "dart:math";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_database/firebase_database.dart";
import "package:flutter/foundation.dart" show debugPrint;

import "../models/app_models.dart";
import "subject_stats.dart";
import "ai_analytics.dart" as analytics;
import "assessment_ai.dart";
import "claude_service.dart";
import "demo_seed_service.dart";
import "gamification_utils.dart";
import "weekly_challenge_service.dart";

class FirestoreRepository with WeeklyChallengeService {
  FirestoreRepository(this.uid)
      : _db = FirebaseFirestore.instance,
        _rtdb = FirebaseDatabase.instance.ref();

  @override
  final String uid;
  final FirebaseFirestore _db;
  final DatabaseReference _rtdb;

  @override
  FirebaseFirestore get db => _db;

  DocumentReference<Map<String, dynamic>> get _userRef =>
      _db.collection("users").doc(uid);

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream =
      _userRef.snapshots().asBroadcastStream();

  // ── Firestore Streams ────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> watchUserMeta() =>
      _userDocStream.map((DocumentSnapshot<Map<String, dynamic>> s) =>
          s.data() ?? <String, dynamic>{});

  Stream<UserProfile> watchProfile() =>
      _userDocStream.map((DocumentSnapshot<Map<String, dynamic>> s) =>
          UserProfile.fromMap(s.data() ?? <String, dynamic>{}));

  Stream<GamificationState> watchGamification() =>
      _userDocStream.map((DocumentSnapshot<Map<String, dynamic>> s) =>
          GamificationState.fromMap(s.data()));

  Stream<List<TaskItem>> watchTasks() {
    return _userRef
        .collection("tasks")
        .orderBy("createdAt", descending: true)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) =>
            s.docs.map(TaskItem.fromDoc).toList());
  }

  Stream<List<MoodLog>> watchMoods() {
    return _userRef
        .collection("mood_logs")
        .orderBy("createdAt", descending: true)
        .limit(20)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) =>
            s.docs.map(MoodLog.fromDoc).toList());
  }

  Stream<List<StudySession>> watchSessions() {
    return _userRef
        .collection("study_sessions")
        .orderBy("completedAt", descending: true)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) =>
            s.docs.map(StudySession.fromDoc).toList());
  }

  Stream<List<StudyStrategy>> watchStrategies() {
    return _rtdb
        .child("strategies")
        .orderByChild("createdAt")
        .onValue
        .map((DatabaseEvent event) {
      final DataSnapshot snap = event.snapshot;
      if (!snap.exists || snap.value == null) return <StudyStrategy>[];
      final Map<String, dynamic> all = Map<String, dynamic>.from(
          snap.value! as Map);
      final List<StudyStrategy> list = <StudyStrategy>[];
      all.forEach((String key, dynamic value) {
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(value as Map);
        list.add(StudyStrategy.fromRtdb(key, data));
      });
      // Sort newest first (RTDB orderByChild is ascending)
      list.sort((StudyStrategy a, StudyStrategy b) =>
          (b.id).compareTo(a.id));
      return list;
    });
  }

  // ── Active Session ────────────────────────────────────────────────────────────
  // Single-document persistence layer. Enables session resume after app kill.

  Stream<ActiveSession?> watchActiveSession() {
    return _userRef
        .collection("active_session")
        .doc("current")
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> s) {
      if (!s.exists || s.data() == null) return null;
      return ActiveSession.fromMap(s.data()!);
    });
  }

  /// Call from FocusModeScreen when the student taps "Start Session".
  Future<void> startActiveSession({
    required String taskId,
    required String taskName,
    required String subject,
    required int plannedMinutes,
    required int pomodorosTarget,
  }) async {
    await _userRef.collection("active_session").doc("current").set(
      ActiveSession(
        taskId: taskId,
        taskName: taskName,
        subject: subject,
        plannedMinutes: plannedMinutes,
        pomodorosTarget: pomodorosTarget,
        pomodorosCompleted: 0,
        startedAt: DateTime.now(),
        state: "running",
      ).toMap(),
    );
  }

  /// Call each time a Pomodoro completes — persists progress immediately.
  Future<void> incrementActiveSessionPomodoro() async {
    try {
      await _userRef
          .collection("active_session")
          .doc("current")
          .update(<String, dynamic>{
        "pomodorosCompleted": FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint("[ActiveSession] incrementPomodoro failed: $e");
    }
  }

  /// Call when the session ends (normally or abandoned).
  /// Moves data to study_sessions, deletes the active doc, awards XP.
  Future<void> completeActiveSession({
    required int actualMinutes,
    required int feltDifficulty,
    String midSessionMood = "neutral",
    String note = "",
    List<MidCheckIn> checkIns = const <MidCheckIn>[],
    String? aiSessionSummary,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _userRef.collection("active_session").doc("current").get();
    if (!snap.exists || snap.data() == null) return;

    final ActiveSession active = ActiveSession.fromMap(snap.data()!);

    await logStudySession(
      taskId: active.taskId,
      taskName: active.taskName,
      subject: active.subject,
      plannedMinutes: active.plannedMinutes,
      actualMinutes: actualMinutes,
      pomodorosCompleted: active.pomodorosCompleted,
      feltDifficulty: feltDifficulty,
      startedAt: active.startedAt,
      midSessionMood: midSessionMood,
      note: note,
      checkIns: checkIns,
      aiSessionSummary: aiSessionSummary,
    );

    await _userRef
        .collection("active_session")
        .doc("current")
        .delete();
  }

  // ── Writes ───────────────────────────────────────────────────────────────────

  Future<void> saveProfile(UserProfile profile) async {
    await _userRef.set(profile.toMap(), SetOptions(merge: true));
  }

  Future<void> saveUsername(String username) async {
    await _userRef.set(<String, dynamic>{
      "username": username,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> completeAssessment(
      {required Map<String, dynamic> answers}) async {
    final Map<String, dynamic> analysis = await generateAiAnalysis(answers);
    final UserProfile profile = buildProfileFromAssessment(answers);

    final List<InsightCardData> initialInsights =
        await analytics.generateInsights(
      profile: profile,
      moods: <MoodLog>[],
      tasks: <TaskItem>[],
      thoughtsShared: 0,
    );

    // Single consolidated "insights" field — no runtimeInsights duplicate.
    await _userRef.set(<String, dynamic>{
      ...profile.toMap(),
      "hasCompletedAssessment": true,
      "assessmentAnswers": answers,
      "aiAnalysis": analysis,
      "insights":
          initialInsights.map((InsightCardData c) => c.toMap()).toList(),
      "insightsUpdatedAt": FieldValue.serverTimestamp(),
      "behaviorAnalytics": BehaviorAnalytics().toMap(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await ensureWeeklyChallengesAssigned();
  }

  Future<void> retryAssessmentAnalysis({
    required Map<String, dynamic> answers,
  }) async {
    final Map<String, dynamic> analysis = await generateAiAnalysis(answers);
    await _userRef.set(<String, dynamic>{
      "aiAnalysis": analysis,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> addTask({
    required String name,
    required String description,
    required String subject,
    required DateTime deadline,
    required Difficulty difficulty,
    required Workload workload,
    required UserProfile profile,
    required List<MoodLog> moods,
    List<TaskItem> existingTasks = const <TaskItem>[],
    List<StudySession> sessions = const <StudySession>[],
  }) async {
    final DocumentReference<Map<String, dynamic>> ref =
        _userRef.collection("tasks").doc();

    await ref.set(<String, dynamic>{
      "name": name,
      "description": description,
      "subject": subject,
      "deadline": Timestamp.fromDate(deadline),
      "difficulty": difficulty.name,
      "workload": workload.name,
      "completed": false,
      "priorityScore": 0,
      "priorityLabel": "Quick Task",
      "priorityReason": "Calculating...",
      "createdAt": FieldValue.serverTimestamp(),
    });

    // Build subject context for AI injection
    final Map<String, SubjectStats> subjectStats =
        SubjectStatsCalculator.compute(
      tasks: existingTasks,
      sessions: sessions,
    );
    final String subjectContext =
        SubjectStatsCalculator.buildPromptContext(subjectStats);

    Map<String, dynamic> taskAnalysis;
    try {
      taskAnalysis = await ClaudeService.analyzeTask(
        title: name,
        description: description,
        subject: subject,
        profile: profile,
        existingTasks: existingTasks,
        subjectContext: subjectContext,
      );
    } catch (_) {
      taskAnalysis = _fallbackTaskAnalysis(difficulty, workload);
    }

    final Map<String, dynamic> priority = analytics.calculatePriorityLocally(
      deadline: deadline,
      difficulty: difficulty,
      workload: workload,
      profile: profile,
      moods: moods,
    );

    final String aiDifficulty =
        (taskAnalysis["difficulty"] ?? difficulty.name) as String;
    final String aiWorkload =
        (taskAnalysis["workload"] ?? workload.name) as String;

    final List<Map<String, String>> resources =
        _parseResources(taskAnalysis["suggestedResources"]);

    await ref.set(<String, dynamic>{
      "priorityScore": priority["score"] ?? 0,
      "priorityLabel": priority["label"] ?? "Quick Task",
      "priorityReason":
          priority["reason"] ?? "Suggested using current profile.",
      "difficulty": aiDifficulty,
      "workload": aiWorkload,
      "aiEstimatedMinutes": taskAnalysis["estimatedMinutes"] ?? 60,
      "aiPomodoroSessions": taskAnalysis["pomodoroSessions"] ?? 2,
      "aiBreakStrategy": taskAnalysis["breakStrategy"] ?? "",
      "aiMentalLoad": taskAnalysis["mentalLoad"] ?? "Medium",
      "aiFocusLevel": taskAnalysis["focusLevel"] ?? "Sustained",
      "aiBestTime": taskAnalysis["bestTime"] ?? "Flexible",
      "aiMethod": taskAnalysis["method"] ?? "",
      "aiSteps": taskAnalysis["steps"] ?? <String>[],
      "aiStudyTips": taskAnalysis["studyTips"] ?? <String>[],
      "aiSuggestedResources": resources,
      "aiProductivityAdvice": taskAnalysis["productivityAdvice"] ?? "",
      "aiOverlapWarning": taskAnalysis["overlapWarning"],
    }, SetOptions(merge: true));

    await _updateBehaviorAnalytics(taskCreated: true);
    await _checkAndAwardBadges();
    await _refreshInsightsIfStale();
  }

  Future<void> deleteTask(String taskId) async {
    await _userRef.collection("tasks").doc(taskId).delete();
  }

  Future<int> deleteCompletedTasks() async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _userRef
        .collection("tasks")
        .where("completed", isEqualTo: true)
        .get();
    final WriteBatch batch = _db.batch();
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    return snap.docs.length;
  }

  Future<void> saveAutoDeleteSetting({required bool enabled}) async {
    await _userRef.set(<String, dynamic>{
      "autoDeleteCompletedTasks": enabled,
    }, SetOptions(merge: true));
  }

  Future<void> autoCleanupIfDue() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await _userRef.get();
      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
      final bool enabled =
          (data["autoDeleteCompletedTasks"] ?? false) as bool;
      if (!enabled) return;

      final Timestamp? lastCleanup =
          data["lastAutoCleanupDate"] as Timestamp?;
      final DateTime now = DateTime.now();

      if (lastCleanup != null) {
        final DateTime last = lastCleanup.toDate();
        final bool isSunday = now.weekday == DateTime.sunday;
        final bool sevenDaysPassed = now.difference(last).inDays >= 7;
        if (!isSunday && !sevenDaysPassed) return;
      }

      await deleteCompletedTasks();
      await _userRef.set(<String, dynamic>{
        "lastAutoCleanupDate": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> reanalyzeTask({
    required TaskItem task,
    required UserProfile profile,
    required List<MoodLog> moods,
    required List<TaskItem> existingTasks,
    List<StudySession> sessions = const <StudySession>[],
  }) async {
    final Map<String, SubjectStats> subjectStats =
        SubjectStatsCalculator.compute(
      tasks: existingTasks,
      sessions: sessions,
    );

    Map<String, dynamic> taskAnalysis;
    try {
      taskAnalysis = await ClaudeService.analyzeTask(
        title: task.name,
        description: task.description,
        subject: task.subject,
        profile: profile,
        existingTasks:
            existingTasks.where((TaskItem t) => t.id != task.id).toList(),
        subjectContext:
            SubjectStatsCalculator.buildPromptContext(subjectStats),
      );
    } catch (_) {
      return;
    }

    final Map<String, dynamic> priority = analytics.calculatePriorityLocally(
      deadline: task.deadline,
      difficulty: task.difficulty,
      workload: task.workload,
      profile: profile,
      moods: moods,
    );

    final List<Map<String, String>> resources =
        _parseResources(taskAnalysis["suggestedResources"]);

    await _userRef.collection("tasks").doc(task.id).set(<String, dynamic>{
      "priorityScore": priority["score"] ?? 0,
      "priorityLabel": priority["label"] ?? "Quick Task",
      "priorityReason":
          priority["reason"] ?? "Suggested using current profile.",
      "aiEstimatedMinutes": taskAnalysis["estimatedMinutes"] ?? 60,
      "aiPomodoroSessions": taskAnalysis["pomodoroSessions"] ?? 2,
      "aiBreakStrategy": taskAnalysis["breakStrategy"] ?? "",
      "aiBestTime": taskAnalysis["bestTime"] ?? "Flexible",
      "aiMethod": taskAnalysis["method"] ?? "",
      "aiSteps": taskAnalysis["steps"] ?? <String>[],
      "aiStudyTips": taskAnalysis["studyTips"] ?? <String>[],
      "aiSuggestedResources": resources,
      "aiProductivityAdvice": taskAnalysis["productivityAdvice"] ?? "",
      "aiOverlapWarning": taskAnalysis["overlapWarning"],
    }, SetOptions(merge: true));
  }

  Future<void> completeTask(TaskItem task) async {
    if (task.completed) return;
    await _userRef.collection("tasks").doc(task.id).set(<String, dynamic>{
      "completed": true,
      "completedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _awardXp("task_completed", difficulty: task.difficulty.name);
    await _touchDailyActivity();
    await _updateBehaviorAnalytics(taskCompleted: true);
    await _checkAndAwardBadges(completedTask: task);
    await incrementChallengeProgress(
      eventType: "task_completed",
      difficulty: task.difficulty.name,
      subject: task.subject,
    );
    await _updateProfileFromBehavior();
    await _userRef.set(<String, dynamic>{
      "weeklySummaryUpdatedAt": null,
    }, SetOptions(merge: true));
    await _refreshInsightsIfStale();
  }

  Future<void> logMood({
    required MoodEmoji mood,
    required String activity,
    required String note,
  }) async {
    await _userRef.collection("mood_logs").add(<String, dynamic>{
      "mood": mood.name,
      "activity": activity,
      "note": note,
      "createdAt": FieldValue.serverTimestamp(),
    });
    await _awardXp("mood_logged");
    await _touchDailyActivity();
    await _updateBehaviorAnalytics(moodLogged: true, moodType: mood.name);
    await _checkAndAwardBadges(moodLogged: true);
    await incrementChallengeProgress(eventType: "mood_logged");
    await _updateProfileFromBehavior();
    await _refreshInsightsIfStale();
  }

  Future<void> logStudySession({
    required String taskId,
    required String taskName,
    required String subject,
    required int plannedMinutes,
    required int actualMinutes,
    required int pomodorosCompleted,
    required int feltDifficulty,
    required DateTime startedAt,
    String midSessionMood = "neutral",
    String note = "",
    List<MidCheckIn> checkIns = const <MidCheckIn>[],
    String? aiSessionSummary,
  }) async {
    await _userRef.collection("study_sessions").add(<String, dynamic>{
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
    });

    await _awardXp("study_session", pomodoros: pomodorosCompleted);
    await _touchDailyActivity();
    await _updateBehaviorAnalytics(
      sessionCompleted: true,
      sessionMinutes: actualMinutes,
      sessionSubject: subject,
      sessionFeltDifficulty: feltDifficulty,
    );
    await _checkAndAwardBadges(
      sessionCompleted: true,
      sessionPomodoros: pomodorosCompleted,
    );
    final bool isDeep = pomodorosCompleted >= 3;
    await incrementChallengeProgress(
      eventType: "study_session",
      pomodoroCount: pomodorosCompleted,
      isDeepSession: isDeep,
    );
    await _refreshInsightsIfStale();
  }

  Future<void> addStrategy({
    required String title,
    required String category,
    required String summary,
    required List<String> steps,
    required String evidence,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> userSnap =
        await _userRef.get();
    final String username =
        ((userSnap.data() ?? <String, dynamic>{})["username"] ?? "Anonymous")
            as String;

    await _rtdb.child("strategies").push().set(<String, dynamic>{
      "title": title,
      "category": category,
      "summary": summary,
      "steps": steps,
      "evidence": evidence,
      "authorUsername": username,
      "authorUid": uid,
      "isSystem": false,
      "reactions": 0,
      "createdAt": ServerValue.timestamp,
    });

    await _awardXp("insight_posted");
    await incrementChallengeProgress(eventType: "insight_posted");
    await _checkAndAwardBadges(cardPosted: true);
  }

  Future<List<InsightCardData>> generateInsights({
    required UserProfile profile,
    required List<MoodLog> moods,
    required List<TaskItem> tasks,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> snap = await _userRef.get();
    final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};

    final Timestamp? lastUpdated =
        data["insightsUpdatedAt"] as Timestamp?;
    if (lastUpdated != null) {
      final Duration age = DateTime.now().difference(lastUpdated.toDate());
      if (age.inHours < 6) {
        final List<dynamic> cached =
            (data["insights"] as List<dynamic>?) ?? <dynamic>[];
        if (cached.isNotEmpty) {
          return cached
              .map((dynamic e) =>
                  InsightCardData.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
      }
    }

    final BehaviorAnalytics behaviorData = BehaviorAnalytics.fromMap(
      data["behaviorAnalytics"] as Map<String, dynamic>?,
    );

    final List<InsightCardData> fresh =
        await analytics.generateBehaviorInsights(
      profile: profile,
      moods: moods,
      tasks: tasks,
      analytics: behaviorData,
    );

    if (fresh.isNotEmpty) {
      await _userRef.set(<String, dynamic>{
        "insights":
            fresh.map((InsightCardData c) => c.toMap()).toList(),
        "insightsUpdatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    return fresh;
  }

  Future<Map<String, dynamic>> forceRefreshWeeklySummary({
    required List<TaskItem> tasks,
    required List<MoodLog> moods,
  }) async {
    await _userRef.set(<String, dynamic>{
      "weeklySummaryUpdatedAt": null,
    }, SetOptions(merge: true));
    return getWeeklySummary(tasks: tasks, moods: moods);
  }

  Future<Map<String, dynamic>> getWeeklySummary({
    required List<TaskItem> tasks,
    required List<MoodLog> moods,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> snap = await _userRef.get();
    final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};

    final Timestamp? ts = data["weeklySummaryUpdatedAt"] as Timestamp?;
    if (ts != null) {
      final DateTime cacheDate = ts.toDate();
      final DateTime today = DateTime.now();
      final bool sameDay = cacheDate.year == today.year &&
          cacheDate.month == today.month &&
          cacheDate.day == today.day;
      if (sameDay && data["weeklySummary"] != null) {
        return Map<String, dynamic>.from(
            data["weeklySummary"] as Map<dynamic, dynamic>);
      }
    }

    final BehaviorAnalytics behaviorData = BehaviorAnalytics.fromMap(
      data["behaviorAnalytics"] as Map<String, dynamic>?,
    );

    final Map<String, dynamic> summary =
        await ClaudeService.generateWeeklySummary(
      tasks: tasks,
      moods: moods,
      analytics: behaviorData,
    );

    if (summary.isNotEmpty) {
      await _userRef.set(<String, dynamic>{
        "weeklySummary": summary,
        "weeklySummaryUpdatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    return summary;
  }

  /// Clears pendingBadges after the celebration UI has shown them.
  Future<void> clearPendingBadges() async {
    await _userRef.set(
      <String, dynamic>{"pendingBadges": <String>[]},
      SetOptions(merge: true),
    );
  }

  Future<void> seedDemoData() async {
    await seedDemoDataLocally(_userRef, _db);
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  Future<void> _refreshInsightsIfStale() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await _userRef.get();
      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
      final Timestamp? lastUpdated =
          data["insightsUpdatedAt"] as Timestamp?;
      if (lastUpdated != null) {
        final Duration age = DateTime.now().difference(lastUpdated.toDate());
        if (age.inHours < 6) return;
      }

      final UserProfile profile = UserProfile.fromMap(data);
      final BehaviorAnalytics behaviorData = BehaviorAnalytics.fromMap(
        data["behaviorAnalytics"] as Map<String, dynamic>?,
      );

      final QuerySnapshot<Map<String, dynamic>> moodSnap =
          await _userRef.collection("mood_logs").limit(20).get();
      final List<MoodLog> moods = moodSnap.docs.map(MoodLog.fromDoc).toList();

      final QuerySnapshot<Map<String, dynamic>> taskSnap =
          await _userRef.collection("tasks").get();
      final List<TaskItem> tasks =
          taskSnap.docs.map(TaskItem.fromDoc).toList();

      final List<InsightCardData> fresh =
          await analytics.generateBehaviorInsights(
        profile: profile,
        moods: moods,
        tasks: tasks,
        analytics: behaviorData,
      );

      if (fresh.isNotEmpty) {
        await _userRef.set(<String, dynamic>{
          "insights":
              fresh.map((InsightCardData c) => c.toMap()).toList(),
          "insightsUpdatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _updateBehaviorAnalytics({
    bool taskCreated = false,
    bool taskCompleted = false,
    bool moodLogged = false,
    bool cardPosted = false,
    String? moodType,
    int? insightWordCount,
    bool sessionCompleted = false,
    int sessionMinutes = 0,
    String? sessionSubject,
    int sessionFeltDifficulty = 0,
  }) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await _userRef.get();
      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
      final Map<String, dynamic> beh = Map<String, dynamic>.from(
          (data["behaviorAnalytics"] as Map<dynamic, dynamic>?) ??
              <String, dynamic>{});

      final Map<String, dynamic> updates = <String, dynamic>{};

      if (taskCreated) {
        updates["behaviorAnalytics.totalTasksCreated"] =
            FieldValue.increment(1);
        updates["behaviorAnalytics.studyPeakHour"] = DateTime.now().hour;
      }

      if (taskCompleted) {
        updates["behaviorAnalytics.totalTasksCompleted"] =
            FieldValue.increment(1);
      }

      if (taskCreated || taskCompleted) {
        final int created = ((beh["totalTasksCreated"] ?? 0) as int) +
            (taskCreated ? 1 : 0);
        final int completed = ((beh["totalTasksCompleted"] ?? 0) as int) +
            (taskCompleted ? 1 : 0);
        final double rate =
            created > 0 ? (completed / created).clamp(0.0, 1.0) : 0.0;
        updates["behaviorAnalytics.taskCompletionRate"] = rate;
      }

      if (moodLogged) {
        updates["behaviorAnalytics.totalMoodsLogged"] =
            FieldValue.increment(1);
        if (moodType != null) {
          updates["behaviorAnalytics.moodTrend"] = moodType == "happy"
              ? "positive"
              : moodType == "sad"
                  ? "negative"
                  : "neutral";
        }
      }

      if (cardPosted) {
        updates["behaviorAnalytics.totalCardsPosted"] =
            FieldValue.increment(1);
        if (insightWordCount != null) {
          final int prevCount = (beh["totalCardsPosted"] ?? 0) as int;
          final int prevAvg = (beh["avgInsightWordCount"] ?? 0) as int;
          final int newAvg = prevCount == 0
              ? insightWordCount
              : ((prevAvg * prevCount + insightWordCount) / (prevCount + 1))
                  .round();
          updates["behaviorAnalytics.avgInsightWordCount"] = newAvg;
        }
      }

      if (sessionCompleted) {
        updates["behaviorAnalytics.totalSessionsCompleted"] =
            FieldValue.increment(1);
        updates["behaviorAnalytics.totalSessionMinutes"] =
            FieldValue.increment(sessionMinutes);
        updates["behaviorAnalytics.studyPeakHour"] = DateTime.now().hour;

        if (sessionFeltDifficulty > 0) {
          final int prevSessions =
              (beh["totalSessionsCompleted"] ?? 0) as int;
          final double prevAvg =
              ((beh["avgFeltDifficulty"] ?? 0.0) as num).toDouble();
          final double newAvg = prevSessions == 0
              ? sessionFeltDifficulty.toDouble()
              : (prevAvg * prevSessions + sessionFeltDifficulty) /
                  (prevSessions + 1);
          updates["behaviorAnalytics.avgFeltDifficulty"] = newAvg;
        }

        if (sessionSubject != null && sessionSubject.isNotEmpty) {
          final Map<dynamic, dynamic> existing =
              (beh["subjectSessionMinutes"] as Map<dynamic, dynamic>?) ??
                  <dynamic, dynamic>{};
          final Map<String, int> updated = <String, int>{};
          existing.forEach(
              (dynamic k, dynamic v) => updated["$k"] = (v ?? 0) as int);
          updated[sessionSubject] =
              (updated[sessionSubject] ?? 0) + sessionMinutes;
          updates["behaviorAnalytics.subjectSessionMinutes"] = updated;
        }
      }

      if (updates.isNotEmpty) {
        await _userRef.update(updates);
      }
    } catch (_) {}
  }

  Future<void> _awardXp(String eventType,
      {String? difficulty, int pomodoros = 0}) async {
    // Read current streak to apply multiplier
    int streakDays = 0;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _userRef.get();
      streakDays =
          ((snap.data() ?? <String, dynamic>{})["streakDays"] ?? 0) as int;
    } catch (_) {}

    final int gain = calculateXpGain(
      eventType,
      difficulty: difficulty,
      pomodoros: pomodoros,
      streakDays: streakDays,
    );
    if (gain == 0) return;

    try {
      await _userRef.set(<String, dynamic>{
        "xp": FieldValue.increment(gain),
      }, SetOptions(merge: true));

      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _userRef.get();
      final int newXp =
          ((snap.data() ?? <String, dynamic>{})["xp"] ?? 0) as int;
      final int newLevel = sqrt(newXp / 100).floor() + 1;
      await _userRef.set(<String, dynamic>{
        "level": newLevel,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("[XP] _awardXp failed: $e");
    }
  }

  Future<void> _checkAndAwardBadges({
    TaskItem? completedTask,
    bool moodLogged = false,
    bool cardPosted = false,
    bool sessionCompleted = false,
    int sessionPomodoros = 0,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> snap = await _userRef.get();
    final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};

    final List<String> badges =
        ((data["badges"] ?? <dynamic>[]) as List<dynamic>)
            .map((dynamic e) => "$e")
            .toList();
    final Set<String> earned = badges.toSet();

    final QuerySnapshot<Map<String, dynamic>> taskSnap =
        await _userRef.collection("tasks").get();
    final List<Map<String, dynamic>> allTasks =
        taskSnap.docs.map((d) => d.data()).toList();
    final List<Map<String, dynamic>> completedTasks =
        allTasks.where((t) => (t["completed"] ?? false) as bool).toList();

    final Map<String, dynamic> beh =
        (data["behaviorAnalytics"] as Map<dynamic, dynamic>?)
            ?.map((k, v) => MapEntry("$k", v)) ??
        <String, dynamic>{};

    final List<String> toAward = <String>[];

    if (!earned.contains("getting_started") && completedTasks.isNotEmpty) {
      toAward.add("getting_started");
    }
    if (!earned.contains("early_bird") && completedTask != null) {
      if (DateTime.now().hour < 9) toAward.add("early_bird");
    }
    if (!earned.contains("night_owl") && completedTask != null) {
      if (DateTime.now().hour >= 22) toAward.add("night_owl");
    }
    if (!earned.contains("on_fire")) {
      final int streak = (data["streakDays"] ?? 0) as int;
      if (streak >= 7) toAward.add("on_fire");
    }
    if (!earned.contains("speed_runner") && completedTask != null) {
      final Timestamp? created = completedTasks
          .where((t) => t["name"] == completedTask.name)
          .map((t) => t["createdAt"] as Timestamp?)
          .firstOrNull;
      if (created != null) {
        final Duration age = DateTime.now().difference(created.toDate());
        if (age.inHours <= 24) toAward.add("speed_runner");
      }
    }
    if (!earned.contains("deep_thinker")) {
      final bool hasHard = allTasks.any((t) => t["difficulty"] == "hard");
      if (hasHard) toAward.add("deep_thinker");
    }
    if (!earned.contains("diamond_focus")) {
      final DateTime weekAgo =
          DateTime.now().subtract(const Duration(days: 7));
      final int hardDone = completedTasks.where((t) {
        final Timestamp? ts = t["completedAt"] as Timestamp?;
        return t["difficulty"] == "hard" &&
            ts != null &&
            ts.toDate().isAfter(weekAgo);
      }).length;
      if (hardDone >= 3) toAward.add("diamond_focus");
    }
    if (!earned.contains("bookworm") && allTasks.length >= 10) {
      final Set<String> subjects =
          allTasks.map((t) => (t["subject"] ?? "") as String).toSet();
      if (subjects.length >= 5) toAward.add("bookworm");
    }
    if (!earned.contains("growth_mindset")) {
      final double rate =
          ((beh["taskCompletionRate"] ?? 0.0) as num).toDouble();
      if (rate >= 0.8 && allTasks.length >= 5) toAward.add("growth_mindset");
    }
    // strategy_sharer: contributed to the library
    if (!earned.contains("strategy_sharer") && cardPosted) {
      toAward.add("strategy_sharer");
    }
    if (!earned.contains("balanced")) {
      final QuerySnapshot<Map<String, dynamic>> moodSnap =
          await _userRef.collection("mood_logs").get();
      final Set<String> moodDays = moodSnap.docs.map((d) {
        final Timestamp? ts = d.data()["createdAt"] as Timestamp?;
        if (ts == null) return "";
        final DateTime dt = ts.toDate();
        return "${dt.year}-${dt.month}-${dt.day}";
      }).where((s) => s.isNotEmpty).toSet();
      final Set<String> taskDays = completedTasks.map((t) {
        final Timestamp? ts = t["completedAt"] as Timestamp?;
        if (ts == null) return "";
        final DateTime dt = ts.toDate();
        return "${dt.year}-${dt.month}-${dt.day}";
      }).where((s) => s.isNotEmpty).toSet();
      final int bothDays = moodDays.intersection(taskDays).length;
      if (bothDays >= 5) toAward.add("balanced");
    }
    if (!earned.contains("resilient") &&
        (moodLogged || completedTask != null)) {
      final QuerySnapshot<Map<String, dynamic>> moodSnap =
          await _userRef.collection("mood_logs").get();
      final Set<String> moodDays = moodSnap.docs.map((d) {
        final Timestamp? ts = d.data()["createdAt"] as Timestamp?;
        if (ts == null) return "";
        final DateTime dt = ts.toDate();
        return "${dt.year}-${dt.month}-${dt.day}";
      }).where((s) => s.isNotEmpty).toSet();
      final bool hardTaskDayMatch = completedTasks.any((t) {
        if (t["difficulty"] != "hard") return false;
        final Timestamp? ts = t["completedAt"] as Timestamp?;
        if (ts == null) return false;
        final DateTime dt = ts.toDate();
        final String day = "${dt.year}-${dt.month}-${dt.day}";
        return moodDays.contains(day);
      });
      if (hardTaskDayMatch) toAward.add("resilient");
    }
    if (!earned.contains("perfect_week")) {
      final DateTime weekStart =
          DateTime.now().subtract(const Duration(days: 7));
      final List<Map<String, dynamic>> dueTasks = allTasks.where((t) {
        final Timestamp? deadline = t["deadline"] as Timestamp?;
        if (deadline == null) return false;
        return deadline.toDate().isAfter(weekStart) &&
            deadline.toDate().isBefore(
                DateTime.now().add(const Duration(days: 1)));
      }).toList();
      if (dueTasks.isNotEmpty &&
          dueTasks.every((t) => (t["completed"] ?? false) as bool)) {
        toAward.add("perfect_week");
      }
    }
    if (!earned.contains("focused_learner") && sessionCompleted) {
      final int totalSessions =
          (beh["totalSessionsCompleted"] ?? 0) as int;
      if (totalSessions + 1 >= 5) toAward.add("focused_learner");
    }
    if (!earned.contains("deep_session") &&
        sessionCompleted &&
        sessionPomodoros >= 3) {
      toAward.add("deep_session");
    }

    if (toAward.isNotEmpty) {
      final List<String> updated = <String>{...earned, ...toAward}.toList();
      // Write both badges (permanent record) and pendingBadges (for celebration UI)
      final List<String> existingPending =
          ((data["pendingBadges"] ?? <dynamic>[]) as List<dynamic>)
              .map((dynamic e) => "$e")
              .toList();
      final List<String> newPending =
          <String>{...existingPending, ...toAward}.toList();
      await _userRef.set(
        <String, dynamic>{
          "badges": updated,
          "pendingBadges": newPending,
        },
        SetOptions(merge: true),
      );
    }
  }

  Future<void> _updateProfileFromBehavior() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await _userRef.get();
      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};

      final Timestamp? lastUpdated =
          data["profileAutoUpdatedAt"] as Timestamp?;
      if (lastUpdated != null) {
        final Duration age = DateTime.now().difference(lastUpdated.toDate());
        if (age.inDays < 7) return;
      }

      final Map<String, dynamic> beh =
          (data["behaviorAnalytics"] as Map<dynamic, dynamic>?)
              ?.map((k, v) => MapEntry("$k", v)) ??
          <String, dynamic>{};

      final int totalTasks = (beh["totalTasksCreated"] ?? 0) as int;
      final int totalMoods = (beh["totalMoodsLogged"] ?? 0) as int;
      if (totalTasks < 3 && totalMoods < 3) return;

      final Map<String, dynamic> updates = <String, dynamic>{};
      final List<ProfileChangeLogEntry> changeLogs =
          <ProfileChangeLogEntry>[];

      final double rate =
          ((beh["taskCompletionRate"] ?? 0.0) as num).toDouble();
      if (totalTasks >= 5) {
        final int currentFocus = (data["studyFocus"] ?? 3) as int;
        final int newFocus = rate >= 0.8
            ? (currentFocus + 1).clamp(1, 5)
            : rate <= 0.3
                ? (currentFocus - 1).clamp(1, 5)
                : currentFocus;
        if (newFocus != currentFocus) {
          updates["studyFocus"] = newFocus;
          changeLogs.add(ProfileChangeLogEntry(
            field: "studyFocus",
            fromValue: currentFocus,
            toValue: newFocus,
            reason: rate >= 0.8
                ? "Your task completion rate reached ${(rate * 100).round()}% this week."
                : "Your task completion rate dropped to ${(rate * 100).round()}% — adjusted to a lighter pace.",
            changedAt: DateTime.now(),
          ));
        }
      }

      final String moodTrend = (beh["moodTrend"] ?? "neutral") as String;
      if (totalMoods >= 5) {
        final int currentRest = (data["restImportance"] ?? 3) as int;
        final int newRest = moodTrend == "negative"
            ? (currentRest + 1).clamp(1, 5)
            : moodTrend == "positive"
                ? (currentRest - 1).clamp(1, 5)
                : currentRest;
        if (newRest != currentRest) {
          updates["restImportance"] = newRest;
          changeLogs.add(ProfileChangeLogEntry(
            field: "restImportance",
            fromValue: currentRest,
            toValue: newRest,
            reason: moodTrend == "negative"
                ? "Your recent moods suggest you may need more rest."
                : "Your mood has been consistently positive — rest balance looks good.",
            changedAt: DateTime.now(),
          ));
        }
      }

      final int? peakHour = beh["studyPeakHour"] as int?;
      if (peakHour != null && totalTasks >= 5) {
        final String newPref = peakHour < 12
            ? "morning"
            : peakHour >= 18
                ? "night"
                : "flexible";
        updates["productivityPreference"] = newPref;
      }

      if (updates.isNotEmpty) {
        updates["profileAutoUpdatedAt"] = FieldValue.serverTimestamp();
        await _userRef.set(updates, SetOptions(merge: true));

        // Write change logs as a subcollection
        if (changeLogs.isNotEmpty) {
          final WriteBatch batch = _db.batch();
          for (final ProfileChangeLogEntry entry in changeLogs) {
            final DocumentReference<Map<String, dynamic>> ref =
                _userRef.collection("profile_change_log").doc();
            batch.set(ref, entry.toMap());
          }
          await batch.commit();
        }
      }
    } catch (_) {}
  }

  Future<void> _touchDailyActivity() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await _userRef.get();
      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
      final Timestamp? ts = data["lastActiveDate"] as Timestamp?;
      final DateTime now = DateTime.now();
      int streak = (data["streakDays"] ?? 0) as int;

      if (ts == null) {
        streak = 1;
      } else {
        final DateTime prev =
            DateTime(ts.toDate().year, ts.toDate().month, ts.toDate().day);
        final DateTime today = DateTime(now.year, now.month, now.day);
        final int gap = today.difference(prev).inDays;

        if (gap == 0) {
          if (streak < 1) streak = 1;
          // Already counted today — do not call incrementDailyActiveChallenge again
          await _userRef.set(<String, dynamic>{
            "streakDays": streak,
            "lastActiveDate": FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return;
        } else if (gap == 1) {
          streak += 1;
        } else {
          streak = 1;
        }
      }

      await _userRef.set(<String, dynamic>{
        "streakDays": streak,
        "lastActiveDate": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await incrementDailyActiveChallenge();
    } catch (e) {
      debugPrint("[Streak] _touchDailyActivity failed: $e");
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  List<Map<String, String>> _parseResources(dynamic raw) {
    if (raw == null) return <Map<String, String>>[];
    return (raw as List<dynamic>).map((dynamic e) {
      final Map<String, dynamic> m = Map<String, dynamic>.from(e as Map);
      return <String, String>{
        "title": (m["title"] ?? "") as String,
        "url": (m["url"] ?? "") as String,
      };
    }).toList();
  }

  Map<String, dynamic> _fallbackTaskAnalysis(
      Difficulty difficulty, Workload workload) {
    return <String, dynamic>{
      "difficulty": difficulty.name,
      "workload": workload.name,
      "estimatedMinutes": 60,
      "pomodoroSessions": 2,
      "breakStrategy": "Take a 5-minute break after each 25-minute session.",
      "mentalLoad": "Medium",
      "focusLevel": "Sustained",
      "bestTime": "Flexible",
      "method": "Break the task into smaller steps and use timed focus sessions.",
      "steps": <String>[
        "Clarify the goal and gather materials",
        "Start with the hardest part first",
        "Take short breaks every 25 minutes",
        "Review your work",
        "Summarize what you learned",
      ],
      "studyTips": <String>[
        "Use the Pomodoro technique: 25 min focus, 5 min break",
        "Eliminate phone distractions before starting",
        "Write a quick outline before diving in",
      ],
      "suggestedResources": <Map<String, String>>[
        <String, String>{
          "title": "Khan Academy",
          "url": "https://www.khanacademy.org"
        },
      ],
      "productivityAdvice":
          "Take it one step at a time. Starting is always the hardest part.",
      "overlapWarning": null,
    };
  }
}
