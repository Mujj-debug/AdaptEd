import "dart:convert";
import "package:flutter/foundation.dart" show debugPrint;
import "package:http/http.dart" as http;
import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../models/app_models.dart";
import "gamification_utils.dart";

class ClaudeService {
  ClaudeService._();

  // !! REPLACE THIS with your Groq key — never commit the real value !!
  static const String _apiKey = "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";
  static const String _endpoint =
      "https://api.groq.com/openai/v1/chat/completions";
  static const String _model = "llama-3.3-70b-versatile";

  static const String _systemJson =
      "You are a helpful AI assistant for a student productivity app. "
      "Respond ONLY with valid raw JSON — no markdown fences, no explanation, "
      "no preamble. Do not wrap the JSON in ```json or ``` blocks.";

  // ── Firestore cache ref ────────────────────────────────────────────────────

  static DocumentReference<Map<String, dynamic>>? get _cacheRef {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("ai_cache")
        .doc("results");
  }

  // ── Core HTTP call ─────────────────────────────────────────────────────────

  static Future<dynamic> _call(String prompt, {int attempt = 1}) async {
    await Future.delayed(const Duration(milliseconds: 300));

    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_endpoint),
            headers: <String, String>{
              "Content-Type": "application/json",
              "Authorization": "Bearer $_apiKey",
            },
            body: jsonEncode(<String, dynamic>{
              "model": _model,
              "messages": <Map<String, String>>[
                <String, String>{
                  "role": "system",
                  "content": _systemJson,
                },
                <String, String>{
                  "role": "user",
                  "content": prompt,
                },
              ],
              "temperature": 0.7,
              "max_tokens": 2048,
              "response_format": <String, String>{"type": "json_object"},
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (networkError) {
      debugPrint(
          "[GroqService] ❌ Network error on attempt $attempt: $networkError");
      rethrow;
    }

    // ── Rate limit: retry up to 4 times with exponential backoff ─────────────
    if (response.statusCode == 429) {
      if (attempt >= 4) {
        throw Exception("Groq rate limit exceeded after $attempt attempts.");
      }
      // Exponential backoff: 10s, 20s, 40s
      final int waitSeconds = 10 * (1 << (attempt - 1));
      debugPrint(
        "[GroqService] ⏳ Rate limited (429). "
        "Waiting ${waitSeconds}s before retry ${attempt + 1}/4...",
      );
      await Future.delayed(Duration(seconds: waitSeconds));
      return _call(prompt, attempt: attempt + 1);
    }

    if (response.statusCode != 200) {
      debugPrint(
          "[GroqService] ❌ HTTP ${response.statusCode}: ${response.body}");
      throw Exception(
          "Groq API error ${response.statusCode}: ${response.body}");
    }

    // ── Parse response ─────────────────────────────────────────────────────
    try {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final String text =
          (data["choices"] as List<dynamic>).first["message"]["content"]
              as String;

      debugPrint(
        "[GroqService] ✅ Response preview: "
        "${text.substring(0, text.length.clamp(0, 200))}",
      );

      return jsonDecode(text);
    } catch (parseError) {
      debugPrint(
          "[GroqService] ❌ Parse error: $parseError\nRaw: ${response.body}");
      rethrow;
    }
  }

  // ── Cache helpers ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _getCache(
    String key, {
    int maxAgeHours = 6,
  }) async {
    try {
      final ref = _cacheRef;
      if (ref == null) return null;
      final snap = await ref.get();
      if (!snap.exists) return null;
      final data = snap.data() ?? {};
      if (!data.containsKey(key)) return null;
      final ts = data["${key}_cachedAt"] as Timestamp?;
      if (ts == null) return null;
      final age = DateTime.now().difference(ts.toDate());
      if (age.inHours >= maxAgeHours) return null;
      debugPrint(
          "[GroqService] 📦 Cache hit for '$key' (${age.inMinutes}m old)");
      return Map<String, dynamic>.from(data[key] as Map);
    } catch (e) {
      debugPrint("[GroqService] ⚠️ Cache read failed: $e");
      return null;
    }
  }

  static Future<void> _setCache(String key, dynamic value) async {
    try {
      final ref = _cacheRef;
      if (ref == null) return;
      await ref.set(<String, dynamic>{
        key: value,
        "${key}_cachedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint("[GroqService] 💾 Cached '$key'");
    } catch (e) {
      debugPrint("[GroqService] ⚠️ Cache write failed: $e");
    }
  }

  // ── Task analysis ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> analyzeTask({
    required String title,
    required String description,
    required String subject,
    required UserProfile profile,
    List<TaskItem> existingTasks = const <TaskItem>[],
    int playerLevel = 1,
    String subjectContext = "",
  }) async {
    debugPrint("[GroqService] 🔍 analyzeTask() — \"$title\" (level $playerLevel)");

    // Cache key is tier-scoped so students who level up get fresh advice.
    final XpTier tier = xpTierFromLevel(playerLevel);
    final String cacheKey = "task_${title.hashCode}_${tier.name}";
    final cached = await _getCache(cacheKey, maxAgeHours: 24);
    if (cached != null) return cached;

    try {
      final Map<String, dynamic> result = (await _call(
        _taskPrompt(title, description, subject, profile, existingTasks,
            playerLevel: playerLevel, subjectContext: subjectContext),
      )) as Map<String, dynamic>;
      await _setCache(cacheKey, result);
      return result;
    } catch (e) {
      debugPrint("[GroqService] ❌ analyzeTask() failed: $e — using fallback.");
      return _taskFallback();
    }
  }

  static String _taskPrompt(
    String title,
    String description,
    String subject,
    UserProfile profile,
    List<TaskItem> existingTasks, {
    int playerLevel = 1,
    String subjectContext = "",
  }) {
    final List<Map<String, dynamic>> otherTasks = existingTasks
        .where((TaskItem t) => !t.completed && t.name != title)
        .take(10)
        .map((TaskItem t) => <String, dynamic>{
              "name": t.name,
              "subject": t.subject,
              "difficulty": t.difficulty.name,
              "workload": t.workload.name,
              "dueInDays":
                  t.deadline.difference(DateTime.now()).inDays.clamp(0, 999),
            })
        .toList();

    // XP tier context — calibrates step complexity, Pomodoro targets, and tone.
    final XpTier tier = xpTierFromLevel(playerLevel);
    final String tierContext = aiDifficultyContextForTier(tier);
    final int suggestedPomodoros = suggestedPomodorosForTier(tier);

    return """You are an AI study assistant for a student productivity app.
Analyze this student task and return a detailed, specific JSON study plan.

Task title: "$title"
Task description: "$description"
Subject: "$subject"
Student productivity preference: "${profile.productivityPreference.name}"
Student study focus level (1-5): ${profile.studyFocus}
Student personality: "${profile.personalityType.name}"
Student XP level: $playerLevel (${xpTierLabel(tier)} tier)

CALIBRATION INSTRUCTION — IMPORTANT:
$tierContext
The minimum suggested Pomodoros for this student is $suggestedPomodoros.

Other active tasks this student currently has:
${otherTasks.isEmpty ? "None" : jsonEncode(otherTasks)}
${subjectContext.isNotEmpty ? "\nSubject performance context:\n$subjectContext" : ""}

Return a JSON object with EXACTLY these fields — all required:
{
  "difficulty": one of "easy", "medium", or "hard",
  "workload": one of "low", "medium", or "high",
  "estimatedMinutes": integer (realistic total study time for THIS specific task),
  "pomodoroSessions": integer (how many 25-min focus sessions — minimum $suggestedPomodoros for this student's tier),
  "breakStrategy": string (specific advice on when/how to take breaks for THIS task),
  "mentalLoad": one of "Low", "Medium", or "High",
  "focusLevel": one of "Light", "Sustained", or "Deep",
  "bestTime": one of "Morning", "Evening", or "Flexible",
  "method": string (1-2 sentences — the BEST study method for THIS specific task and subject, appropriate to the student's ${xpTierLabel(tier)} level),
  "steps": array of exactly 5 strings (concrete specific steps for THIS task — complexity calibrated to ${xpTierLabel(tier)} level),
  "studyTips": array of exactly 3 strings (practical tips tailored to this subject and task),
  "suggestedResources": array of 2-4 objects each with "title" (string) and "url" (real URL or empty string),
  "productivityAdvice": string (1-2 sentences referencing the student's personality, preference, and Level $playerLevel progress),
  "overlapWarning": string or null (if any existing task conflicts with or is very similar to this one, describe the overlap — otherwise null)
}

IMPORTANT:
- steps and tips must be SPECIFIC to "$title" in "$subject" — not generic placeholders.
- pomodoroSessions must match estimatedMinutes AND be at least $suggestedPomodoros.
- overlapWarning should only be non-null if there is a genuine conflict or heavy overlap with existing tasks.""";
  }

  // ── Insight generation ─────────────────────────────────────────────────────

  static Future<List<InsightCardData>> generateInsights({
    required UserProfile profile,
    required List<MoodLog> moods,
    required List<TaskItem> tasks,
    int thoughtsShared = 0,
  }) async {
    debugPrint("[GroqService] 🔍 generateInsights() called.");

    final cached = await _getCache("insights", maxAgeHours: 6);
    if (cached != null && cached["list"] != null) {
      final List<dynamic> raw = cached["list"] as List<dynamic>;
      return raw
          .map((dynamic e) =>
              InsightCardData.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    try {
      final Map<String, dynamic> profileMap =
          Map<String, dynamic>.from(profile.toMap())..remove("updatedAt");

      final String prompt =
          """Generate 3-5 personalized insights for this student based on real data.
Every insight MUST cite at least one specific number. Be direct and specific — no vague language.

Profile: ${jsonEncode(profileMap)}
Recent moods: ${jsonEncode(moods.map((MoodLog m) => {"mood": m.mood.name, "activity": m.activity}).toList())}
Tasks: ${jsonEncode(tasks.map((TaskItem t) => {"name": t.name, "subject": t.subject, "difficulty": t.difficulty.name, "completed": t.completed}).toList())}
Learning cards shared: $thoughtsShared

Return a JSON object:
{"insights": [{ "title": "3-5 word title", "message": "1-2 sentence insight referencing actual data", "why": "concrete explanation with specific numbers" }]}""";

      final dynamic raw = await _call(prompt);

      List<dynamic> list = <dynamic>[];
      if (raw is Map && raw["insights"] is List) {
        list = raw["insights"] as List<dynamic>;
      } else if (raw is List) {
        list = raw;
      }

      await _setCache("insights", <String, dynamic>{"list": list});

      debugPrint(
          "[GroqService] ✅ generateInsights() returned ${list.length} insights.");
      return list
          .map((dynamic e) =>
              InsightCardData.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint("[GroqService] ❌ generateInsights() failed: $e");
      return <InsightCardData>[];
    }
  }

  // ── Assessment analysis ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> generateAssessmentAnalysis(
    Map<String, dynamic> answers,
  ) async {
    debugPrint("[GroqService] 🔍 generateAssessmentAnalysis() called.");

    final cached = await _getCache("assessment", maxAgeHours: 72);
    if (cached != null) return cached;

    try {
      final String prompt =
          """You are a productivity psychologist analyzing a student's self-assessment.
Based on the answers below, build a detailed psychographic profile.

Assessment answers: ${jsonEncode(answers)}

Return a JSON object with EXACTLY these fields — all required:
{
  "userProfileSummary": string (2-3 sentences summarizing this student's unique learning personality — be specific to their answers),
  "energyType": one of "Morning-focused", "Night-focused", or "Inconsistent",
  "studyStyle": one of "Deep Focus", "Short Burst", or "Easily Distracted",
  "recoveryProfile": one of "Well-Rested", "Under-recovered", or "Burnout Risk",
  "socialEnergyType": one of "Introverted", "Extroverted", or "Ambivert",
  "thinkingStyle": one of "Structured", "Creative", or "Hybrid",
  "riskAnalysis": array of exactly 2 strings (specific risks for THIS student based on their answers),
  "riskReasoning": string (clear explanation of why these are risks, referencing their actual responses),
  "personalizedStrategy": array of exactly 3 strings (concrete, actionable strategies — not generic advice),
  "idealDayStructure": array of exactly 3 strings (morning block, afternoon block, evening block — specific to their energy and preference),
  "productivityIdentity": string (short catchy label e.g. "Night Owl Deep Thinker" or "Structured Morning Sprinter")
}""";

      final Map<String, dynamic> result =
          (await _call(prompt)) as Map<String, dynamic>;

      await _setCache("assessment", result);

      debugPrint(
        "[GroqService] ✅ generateAssessmentAnalysis() — "
        "identity: ${result['productivityIdentity']}",
      );
      return result;
    } catch (e) {
      debugPrint("[GroqService] ❌ generateAssessmentAnalysis() failed: $e");
      return <String, dynamic>{
        "userProfileSummary": "Analysis unavailable. Please try again later.",
        "analysisError": true,
      };
    }
  }

  // ── Behavior insights ──────────────────────────────────────────────────────

  static Future<List<InsightCardData>> generateBehaviorInsights({
    required UserProfile profile,
    required List<MoodLog> moods,
    required List<TaskItem> tasks,
    required BehaviorAnalytics analytics,
  }) async {
    debugPrint("[GroqService] 🔍 generateBehaviorInsights() called.");

    final cached = await _getCache("behavior_insights", maxAgeHours: 6);
    if (cached != null && cached["list"] != null) {
      final List<dynamic> raw = cached["list"] as List<dynamic>;
      return raw
          .map((dynamic e) =>
              InsightCardData.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    try {
      final Map<String, dynamic> profileMap =
          Map<String, dynamic>.from(profile.toMap())..remove("updatedAt");

      // ── Heatmap summary: top 3 peak hours ───────────────────────────────
      final List<Map<String, dynamic>> heatmapSummary = analytics
          .topPeakHours(n: 3)
          .map((HeatmapSlot s) => <String, dynamic>{
                "hour": s.label,
                "minutes": s.sessionMinutes,
                "sessions": s.sessionCount,
                if (s.avgMoodScore != null)
                  "avgMoodScore": s.avgMoodScore!.toStringAsFixed(1),
              })
          .toList();

      // ── Mood-productivity summary ────────────────────────────────────────
      final MoodProductivityCorrelation corr = analytics.moodProductivity;
      final Map<String, dynamic> moodCorrSummary = <String, dynamic>{
        "happyAvgPomodoros": corr.happyAvgPomodoros.toStringAsFixed(1),
        "neutralAvgPomodoros": corr.neutralAvgPomodoros.toStringAsFixed(1),
        "sadAvgPomodoros": corr.sadAvgPomodoros.toStringAsFixed(1),
        "happyCompletionRate":
            "${(corr.happyCompletionRate * 100).round()}%",
        "neutralCompletionRate":
            "${(corr.neutralCompletionRate * 100).round()}%",
        "sadCompletionRate":
            "${(corr.sadCompletionRate * 100).round()}%",
        "bestMoodForStudy": corr.bestMoodForStudy ?? "insufficient data",
        "totalSamples":
            corr.happySamples + corr.neutralSamples + corr.sadSamples,
      };

      final String prompt =
          """You are a behavioral AI coach for a student productivity app.
Generate exactly 5 prescriptive, data-driven insights.

STRICT RULES:
- Every insight MUST cite at least one specific number from the data below.
- Do NOT use phrases like "it seems", "you might", or "perhaps". Be assertive.
- Each insight must cover a DIFFERENT area — no repetition.
- Every insight MUST include an "actionItem": a single, concrete next step the student can take TODAY. Start it with a verb (e.g. "Schedule", "Break down", "Log").
- Set "urgency" to one of: "info", "positive", "warning", "critical".
  • "critical" = risk of burnout or falling behind.
  • "warning" = a pattern worth addressing soon.
  • "positive" = celebrating a real win with specific numbers.
  • "info" = neutral guidance.
- Set "category" to one of: "general", "mood", "productivity", "peakHours", "taskCompletion", "social", "risk".

STUDENT DATA:
- Task completion rate: ${(analytics.taskCompletionRate * 100).toStringAsFixed(0)}% (${analytics.totalTasksCompleted} of ${analytics.totalTasksCreated} created tasks done)
- Mood trend: ${analytics.moodTrend} across ${analytics.totalMoodsLogged} total mood logs
- Consecutive sad moods (most recent): ${analytics.consecutiveSadMoods}
- Task adjustment recommended by system: ${analytics.taskAdjustmentRecommended}
- Cards posted: ${analytics.totalCardsPosted} (avg ${analytics.avgInsightWordCount} words each)
- Total sessions: ${analytics.totalSessionsCompleted}, total study minutes: ${analytics.totalSessionMinutes}
- Avg felt difficulty: ${analytics.avgFeltDifficulty.toStringAsFixed(1)}/5
- Personality: ${profileMap["personalityType"]}, prefers ${profileMap["productivityPreference"]}
- Study focus level: ${profileMap["studyFocus"]}/5, Social energy: ${profileMap["socialEnergy"]}/5
- Recent moods (last 10): ${jsonEncode(moods.take(10).map((MoodLog m) => <String, String>{"mood": m.mood.name, "activity": m.activity}).toList())}
- Active tasks: ${jsonEncode(tasks.where((TaskItem t) => !t.completed).map((TaskItem t) => <String, dynamic>{"name": t.name, "subject": t.subject, "difficulty": t.difficulty.name, "workload": t.workload.name}).toList())}
- Completed tasks: ${jsonEncode(tasks.where((TaskItem t) => t.completed).map((TaskItem t) => <String, dynamic>{"name": t.name, "subject": t.subject, "difficulty": t.difficulty.name}).toList())}

PEAK HOUR HEATMAP (top 3 windows by study minutes):
${jsonEncode(heatmapSummary)}

MOOD → PRODUCTIVITY CORRELATION:
${jsonEncode(moodCorrSummary)}

COVER THESE 5 AREAS (one insight each):
1. Task completion → what the ${(analytics.taskCompletionRate * 100).toStringAsFixed(0)}% rate means and the ONE thing to do about it
2. Mood & productivity link → use the mood-correlation data to explain WHEN the student performs best and why
3. Peak hours → use the heatmap to tell the student EXACTLY when to schedule hard tasks
4. Session quality → use total minutes, session count, and avg difficulty to give a specific improvement
5. Risk or opportunity → if taskAdjustmentRecommended is true, flag burnout risk; otherwise surface the single biggest growth opportunity

Return JSON:
{"insights": [{
  "title": "3-5 word title",
  "message": "1-2 assertive sentences with specific numbers",
  "why": "concrete explanation referencing exact numbers from the data",
  "actionItem": "single concrete next step starting with a verb",
  "urgency": "info|positive|warning|critical",
  "category": "general|mood|productivity|peakHours|taskCompletion|social|risk"
}]}""";

      final dynamic raw = await _call(prompt);

      List<dynamic> list = <dynamic>[];
      if (raw is Map && raw["insights"] is List) {
        list = raw["insights"] as List<dynamic>;
      } else if (raw is List) {
        list = raw;
      }

      await _setCache("behavior_insights", <String, dynamic>{"list": list});

      debugPrint(
          "[GroqService] ✅ generateBehaviorInsights() returned ${list.length} insights.");
      return list
          .map((dynamic e) =>
              InsightCardData.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint("[GroqService] ❌ generateBehaviorInsights() failed: $e");
      return <InsightCardData>[];
    }
  }

  // ── Weekly summary ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> generateWeeklySummary({
    required List<TaskItem> tasks,
    required List<MoodLog> moods,
    required BehaviorAnalytics analytics,
  }) async {
    debugPrint("[GroqService] 🔍 generateWeeklySummary() called.");

    // Cache weekly summary for 24 hours — no need to regenerate more often
    final cached = await _getCache("weekly_summary", maxAgeHours: 24);
    if (cached != null) return cached;

    try {
      final List<Map<String, dynamic>> weekTasks = tasks
          .where((TaskItem t) =>
              DateTime.now().difference(t.deadline).inDays.abs() <= 7)
          .map((TaskItem t) => <String, dynamic>{
                "name": t.name,
                "subject": t.subject,
                "difficulty": t.difficulty.name,
                "completed": t.completed,
              })
          .toList();

      final List<Map<String, dynamic>> weekMoods = moods
          .where((MoodLog m) =>
              DateTime.now().difference(m.createdAt).inDays <= 7)
          .map((MoodLog m) =>
              <String, dynamic>{"mood": m.mood.name, "activity": m.activity})
          .toList();

      final int weekCompleted =
          weekTasks.where((Map<String, dynamic> t) => t["completed"] == true).length;
      final int weekTotal = weekTasks.length;

      final String prompt =
          """Summarize this student's week for a productivity app dashboard.
Be specific, encouraging, and reference actual numbers. Keep it concise.

This week's tasks: ${jsonEncode(weekTasks)} ($weekCompleted of $weekTotal completed)
This week's moods: ${jsonEncode(weekMoods)}
Overall completion rate: ${(analytics.taskCompletionRate * 100).toStringAsFixed(0)}%
Mood trend: ${analytics.moodTrend}

Return a JSON object with EXACTLY these fields:
{
  "headline": string (one punchy sentence summarizing their week — reference actual numbers, e.g. "You crushed 3 of 4 tasks this week"),
  "wins": array of exactly 2 strings (specific things that went well this week — not generic),
  "focusNextWeek": string (one specific, actionable suggestion for next week based on their data),
  "weekScore": integer from 1-10 (overall week performance score based on completion rate and mood)
}""";

      final Map<String, dynamic> result =
          (await _call(prompt)) as Map<String, dynamic>;

      await _setCache("weekly_summary", result);

      debugPrint("[GroqService] ✅ generateWeeklySummary() succeeded.");
      return result;
    } catch (e) {
      debugPrint("[GroqService] ❌ generateWeeklySummary() failed: $e");
      return <String, dynamic>{};
    }
  }

  // ── Session summary ────────────────────────────────────────────────────────

  /// Generates a short 2–3 sentence session summary using the Groq API.
  /// Falls back to a local summary if the API call fails.
  static Future<String> generateSessionSummary({
    required String taskName,
    required String subject,
    required int pomodorosCompleted,
    required int actualMinutes,
    required int plannedMinutes,
    required int feltDifficulty,
    required List<MidCheckIn> checkIns,
    required UserProfile profile,
  }) async {
    debugPrint("[GroqService] 🔍 generateSessionSummary() — \"$taskName\"");

    final String checkInSummary = checkIns.isEmpty
        ? "No mid-session check-ins recorded."
        : checkIns
            .map((MidCheckIn c) =>
                "After Pomodoro ${c.atPomodoro}: mood=${c.mood}"
                "${c.note.isNotEmpty ? ', note="${c.note}"' : ''}")
            .join("; ");

    final String prompt =
        """You are a supportive study coach. Write a short, specific session summary.

Session data:
- Task: "$taskName" ($subject)
- Pomodoros completed: $pomodorosCompleted
- Actual duration: $actualMinutes min (planned: $plannedMinutes min)
- Felt difficulty: $feltDifficulty/5
- Mid-session check-ins: $checkInSummary
- Student profile: ${profile.productivityPreference.name} learner, study focus ${profile.studyFocus}/5

Rules:
- Exactly 2–3 sentences.
- Reference actual numbers (Pomodoros, minutes, difficulty).
- Be encouraging but honest — if they only did half the planned time, acknowledge it briefly.
- End with one concrete tip for the next session.

Return JSON: { "summary": "string" }""";

    try {
      final Map<String, dynamic> result =
          (await _call(prompt)) as Map<String, dynamic>;
      final String summary = (result["summary"] ?? "") as String;
      if (summary.isEmpty) throw Exception("Empty summary returned");
      debugPrint("[GroqService] ✅ generateSessionSummary() succeeded.");
      return summary;
    } catch (e) {
      debugPrint("[GroqService] ❌ generateSessionSummary() failed: $e — using fallback.");
      return _sessionSummaryFallback(
        pomodorosCompleted: pomodorosCompleted,
        actualMinutes: actualMinutes,
        plannedMinutes: plannedMinutes,
        feltDifficulty: feltDifficulty,
      );
    }
  }

  static String _sessionSummaryFallback({
    required int pomodorosCompleted,
    required int actualMinutes,
    required int plannedMinutes,
    required int feltDifficulty,
  }) {
    final String effort = feltDifficulty >= 4
        ? "a challenging"
        : feltDifficulty <= 2
            ? "a smooth"
            : "a solid";
    final String timeNote = actualMinutes >= plannedMinutes
        ? "You hit your planned duration."
        : "You studied for $actualMinutes of $plannedMinutes planned minutes — every bit counts.";
    return "You completed $pomodorosCompleted Pomodoro${pomodorosCompleted == 1 ? '' : 's'} "
        "in $actualMinutes minutes — $effort session. "
        "$timeNote "
        "Next time, try to start with the hardest part first to build momentum.";
  }

  // ── Fallback ───────────────────────────────────────────────────────────────

  static Map<String, dynamic> _taskFallback() => <String, dynamic>{
        "difficulty": "medium",
        "workload": "medium",
        "estimatedMinutes": 60,
        "pomodoroSessions": 2,
        "breakStrategy":
            "Take a 5-minute break after each 25-minute session. After 2 sessions, take a longer 15-minute break.",
        "mentalLoad": "Medium",
        "focusLevel": "Sustained",
        "bestTime": "Flexible",
        "method":
            "Break the task into smaller steps and use timed focus sessions.",
        "steps": <String>[
          "Clarify the goal and gather all required materials",
          "Start with the most difficult or unfamiliar part first",
          "Take a short break every 25 minutes (Pomodoro technique)",
          "Review your progress and adjust your approach if needed",
          "Summarize the key takeaways once you finish",
        ],
        "studyTips": <String>[
          "Use the Pomodoro technique: 25 min focus, 5 min break",
          "Eliminate phone distractions before starting",
          "Write a quick outline before diving in",
        ],
        "suggestedResources": <Map<String, String>>[
          <String, String>{
            "title": "Khan Academy",
            "url": "https://www.khanacademy.org",
          },
          <String, String>{
            "title": "YouTube Educational Search",
            "url":
                "https://www.youtube.com/results?search_query=study+guide",
          },
        ],
        "productivityAdvice":
            "Take it one step at a time. Starting is always the hardest part — "
            "once you begin, momentum builds naturally.",
        "overlapWarning": null,
      };
}
