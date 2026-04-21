import "package:cloud_firestore/cloud_firestore.dart";

import "../models/app_models.dart";

Future<void> seedDemoDataLocally(
  DocumentReference<Map<String, dynamic>> userRef,
  FirebaseFirestore db,
) async {
  await userRef.set(<String, dynamic>{
    "personalityType": "introvert",
    "productivityPreference": "night",
    "socialEnergy": 3,
    "studyFocus": 4,
    "restImportance": 4,
    "creativity": 3,
    "physicalActivity": 2,
    "xp": 245,
    "level": 2,
    "streakDays": 3,
    "badges": <String>["getting_started", "focused_learner"],
    "postsCount": 0,
    "updatedAt": FieldValue.serverTimestamp(),
    "lastActiveDate": FieldValue.serverTimestamp(),
    "behaviorAnalytics": BehaviorAnalytics(
      studyPeakHour: 20,
      totalTasksCreated: 2,
      totalTasksCompleted: 1,
      totalMoodsLogged: 2,
      totalCardsPosted: 0,
      taskCompletionRate: 0.5,
      moodTrend: "positive",
      totalSessionsCompleted: 3,
      totalSessionMinutes: 75,
      avgFeltDifficulty: 3.0,
      subjectSessionMinutes: <String, int>{
        "Mathematics": 50,
        "Biology": 25,
      },
    ).toMap(),
  }, SetOptions(merge: true));

  final WriteBatch batch = db.batch();

  // Task 1 — pending, hard
  batch.set(userRef.collection("tasks").doc(), <String, dynamic>{
    "name": "Math revision: derivatives",
    "description":
        "Review chain rule, product rule, and practice 10 derivative problems from the textbook.",
    "subject": "Mathematics",
    "deadline": Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
    "difficulty": "hard",
    "workload": "high",
    "completed": false,
    "priorityScore": 78,
    "priorityLabel": "High Priority",
    "priorityReason": "Deadline is near and workload is high.",
    "aiEstimatedMinutes": 90,
    "aiPomodoroSessions": 3,
    "aiBreakStrategy": "25 min focus, 5 min break × 3, then 15 min long break.",
    "aiBestTime": "Evening",
    "aiMethod": "Active recall + practice problems",
    "aiSteps": <String>[
      "Review chain rule with 3 example problems",
      "Practice product rule with textbook exercises",
      "Attempt 5 mixed derivative problems",
      "Check answers and note mistakes",
      "Re-do incorrect problems from scratch",
    ],
    "aiStudyTips": <String>[
      "Write out each rule before applying it",
      "Use past exam questions for the last 2 problems",
      "Take a 5-min break every 25 minutes",
    ],
    "aiProductivityAdvice":
        "You tend to focus best in the evening — save this for after dinner.",
    "aiSuggestedResources": <Map<String, String>>[
      <String, String>{
        "title": "Khan Academy — Derivatives",
        "url": "https://www.khanacademy.org/math/calculus-1/cs1-derivatives-definition-and-basic-rules"
      },
    ],
    "createdAt": FieldValue.serverTimestamp(),
  });

  // Task 2 — pending, medium
  batch.set(userRef.collection("tasks").doc(), <String, dynamic>{
    "name": "Biology flashcards",
    "description":
        "Create and review flashcards for Chapter 7: Cell Division and Mitosis.",
    "subject": "Biology",
    "deadline": Timestamp.fromDate(DateTime.now().add(const Duration(days: 3))),
    "difficulty": "medium",
    "workload": "medium",
    "completed": false,
    "priorityScore": 52,
    "priorityLabel": "Needs Early Start",
    "priorityReason": "Deadline in 3 days — start soon.",
    "aiEstimatedMinutes": 45,
    "aiPomodoroSessions": 2,
    "aiBreakStrategy": "25 min focus, 5 min break × 2.",
    "aiBestTime": "Flexible",
    "aiMethod": "Spaced repetition with flashcards",
    "aiSteps": <String>[
      "Read Chapter 7 once for overview",
      "Create one flashcard per key term",
      "Self-test with cards face-down",
      "Mark cards you got wrong and repeat",
    ],
    "aiStudyTips": <String>[
      "Use an app like Anki to schedule reviews automatically",
      "Draw the mitosis phases from memory",
    ],
    "aiProductivityAdvice": "Flashcard creation is low-effort — great for when energy is low.",
    "aiSuggestedResources": <Map<String, String>>[
      <String, String>{
        "title": "Anki — Flashcard App",
        "url": "https://apps.ankiweb.net"
      },
    ],
    "createdAt": FieldValue.serverTimestamp(),
  });

  // Mood logs
  batch.set(userRef.collection("mood_logs").doc(), <String, dynamic>{
    "mood": "happy",
    "activity": "study",
    "note": "Focused session worked well.",
    "createdAt": FieldValue.serverTimestamp(),
  });

  batch.set(userRef.collection("mood_logs").doc(), <String, dynamic>{
    "mood": "neutral",
    "activity": "rest",
    "note": "Short break helped.",
    "createdAt": FieldValue.serverTimestamp(),
  });

  await batch.commit();

  // Seed study sessions separately (need task IDs — use placeholder)
  final WriteBatch sessionBatch = db.batch();

  sessionBatch.set(userRef.collection("study_sessions").doc(), <String, dynamic>{
    "taskId": "",
    "taskName": "Math revision: derivatives",
    "subject": "Mathematics",
    "plannedMinutes": 90,
    "actualMinutes": 50,
    "pomodorosCompleted": 2,
    "feltDifficulty": 4,
    "startedAt": Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 1, hours: 2))),
    "completedAt": Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 1, hours: 1))),
    "midSessionMood": "neutral",
    "note": "Got through chain rule and product rule.",
  });

  sessionBatch.set(userRef.collection("study_sessions").doc(), <String, dynamic>{
    "taskId": "",
    "taskName": "Biology flashcards",
    "subject": "Biology",
    "plannedMinutes": 45,
    "actualMinutes": 25,
    "pomodorosCompleted": 1,
    "feltDifficulty": 2,
    "startedAt": Timestamp.fromDate(
        DateTime.now().subtract(const Duration(hours: 3))),
    "completedAt": Timestamp.fromDate(
        DateTime.now().subtract(const Duration(hours: 2, minutes: 30))),
    "midSessionMood": "happy",
    "note": "Created 20 flashcards.",
  });

  sessionBatch.set(userRef.collection("study_sessions").doc(), <String, dynamic>{
    "taskId": "",
    "taskName": "Math revision: derivatives",
    "subject": "Mathematics",
    "plannedMinutes": 90,
    "actualMinutes": 25,
    "pomodorosCompleted": 1,
    "feltDifficulty": 3,
    "startedAt": Timestamp.fromDate(
        DateTime.now().subtract(const Duration(minutes: 40))),
    "completedAt": Timestamp.fromDate(
        DateTime.now().subtract(const Duration(minutes: 10))),
    "midSessionMood": "neutral",
    "note": "Quick warm-up session.",
  });

  await sessionBatch.commit();
}
