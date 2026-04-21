// lib/services/claude_service_study.dart
//
// Extension on ClaudeService adding study-material, flashcard, quiz,
// and AI-tutor methods.  Import alongside claude_service.dart.
//
// All methods follow the same caching + retry pattern as ClaudeService.

import "dart:convert";
import "package:flutter/foundation.dart" show debugPrint;
import "package:http/http.dart" as http;
import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../models/app_models.dart";
import "../models/study_material_models.dart";

// ── Re-exports the same API config used in ClaudeService ─────────────────────

class ClaudeStudyService {
  ClaudeStudyService._();

  static const String _apiKey =
      "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";
  static const String _endpoint =
      "https://api.groq.com/openai/v1/chat/completions";
  static const String _model = "llama-3.3-70b-versatile";

  static const String _systemJson =
      "You are a helpful AI assistant for a student productivity app. "
      "Respond ONLY with valid raw JSON — no markdown fences, no explanation, "
      "no preamble. Do not wrap the JSON in ```json or ``` blocks.";

  static const String _systemTutor =
      "You are an expert, encouraging AI study tutor helping a student learn "
      "and understand their coursework. You are concise, specific, and always "
      "adapt your explanation depth to the student's level. "
      "Keep each response under 200 words unless the student asks for more detail. "
      "When appropriate, use examples, analogies, or step-by-step breakdowns. "
      "Never give generic advice — always reference the specific subject or task.";

  // ── Firestore cache ref ───────────────────────────────────────────────────

  static DocumentReference<Map<String, dynamic>>? get _cacheRef {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("ai_cache")
        .doc("study_results");
  }

  // ── Core HTTP call (shared logic) ─────────────────────────────────────────

  static Future<dynamic> _callJson(String prompt,
      {int maxTokens = 2048, int attempt = 1}) async {
    await Future.delayed(const Duration(milliseconds: 200));
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
                <String, String>{"role": "system", "content": _systemJson},
                <String, String>{"role": "user", "content": prompt},
              ],
              "temperature": 0.65,
              "max_tokens": maxTokens,
              "response_format": <String, String>{"type": "json_object"},
            }),
          )
          .timeout(const Duration(seconds: 40));
    } catch (e) {
      debugPrint("[StudyService] ❌ Network error attempt $attempt: $e");
      rethrow;
    }

    if (response.statusCode == 429) {
      if (attempt >= 4) {
        throw Exception("Rate limit exceeded after $attempt retries.");
      }
      final int wait = 10 * (1 << (attempt - 1));
      debugPrint("[StudyService] ⏳ 429 — waiting ${wait}s (retry $attempt)");
      await Future.delayed(Duration(seconds: wait));
      return _callJson(prompt, maxTokens: maxTokens, attempt: attempt + 1);
    }

    if (response.statusCode != 200) {
      throw Exception("HTTP ${response.statusCode}: ${response.body}");
    }

    final Map<String, dynamic> data =
        jsonDecode(response.body) as Map<String, dynamic>;
    final String text =
        (data["choices"] as List<dynamic>).first["message"]["content"] as String;
    return jsonDecode(text);
  }

  static Future<String> _callText(
    List<Map<String, String>> messages, {
    int maxTokens = 512,
    int attempt = 1,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
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
                  "content": _systemTutor
                },
                ...messages,
              ],
              "temperature": 0.75,
              "max_tokens": maxTokens,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint("[StudyService] ❌ Text call error attempt $attempt: $e");
      rethrow;
    }

    if (response.statusCode == 429) {
      if (attempt >= 4) throw Exception("Rate limit exceeded.");
      final int wait = 10 * (1 << (attempt - 1));
      await Future.delayed(Duration(seconds: wait));
      return _callText(messages, maxTokens: maxTokens, attempt: attempt + 1);
    }

    if (response.statusCode != 200) {
      throw Exception("HTTP ${response.statusCode}: ${response.body}");
    }

    final Map<String, dynamic> data =
        jsonDecode(response.body) as Map<String, dynamic>;
    return (data["choices"] as List<dynamic>).first["message"]["content"]
        as String;
  }

  // ── Cache helpers ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _getCache(
    String key, {
    int maxAgeHours = 24,
  }) async {
    try {
      final ref = _cacheRef;
      if (ref == null) return null;
      final snap = await ref.get();
      if (!snap.exists) return null;
      final data = snap.data() ?? <String, dynamic>{};
      if (!data.containsKey(key)) return null;
      final ts = data["${key}_cachedAt"] as Timestamp?;
      if (ts == null) return null;
      if (DateTime.now().difference(ts.toDate()).inHours >= maxAgeHours) {
        return null;
      }
      return Map<String, dynamic>.from(data[key] as Map);
    } catch (_) {
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
    } catch (_) {}
  }

  // ── Flashcard generation ──────────────────────────────────────────────────

  /// Generates [count] flashcards for [subject] based on [content].
  /// [content] should be the task description, topic name, or key bullet points.
  static Future<List<FlashCard>> generateFlashcards({
    required String subject,
    required String content,
    int count = 10,
    String difficulty = "medium",
    UserProfile? profile,
  }) async {
    debugPrint("[StudyService] 🃏 generateFlashcards() — $subject ($count cards)");

    final String cacheKey =
        "fc_${subject.hashCode}_${content.hashCode}_${count}_$difficulty";
    final cached = await _getCache(cacheKey, maxAgeHours: 48);
    if (cached != null && cached["cards"] != null) {
      final List<dynamic> raw = cached["cards"] as List<dynamic>;
      return _parseCards(raw, subject);
    }

    final String profileContext = profile != null
        ? "Student study focus: ${profile.studyFocus}/5. "
          "Personality: ${profile.personalityType.name}."
        : "";

    final String prompt =
        """You are an expert educational content designer creating flashcards for a student.

Subject: "$subject"
Content / topic to cover: "$content"
Number of flashcards: $count
Difficulty level: $difficulty
$profileContext

Create EXACTLY $count flashcards. Each card must:
- Front: A clear, specific question or term (not too broad).
- Back: A concise, accurate answer (1–3 sentences maximum).
- Hint: A one-word or one-phrase clue (optional but helpful).

Rules:
- Cover a variety of concepts — don't repeat similar questions.
- Match the $difficulty difficulty: 
  • easy = basic definitions and recall
  • medium = understanding and application
  • hard = analysis, comparison, and edge cases
- Make questions specific to "$subject" — no generic study advice.

Return JSON:
{
  "cards": [
    {"front": "string", "back": "string", "hint": "string"},
    ...
  ]
}""";

    try {
      final dynamic raw = await _callJson(prompt, maxTokens: 3000);
      final List<dynamic> cards = (raw is Map && raw["cards"] is List)
          ? raw["cards"] as List<dynamic>
          : <dynamic>[];

      await _setCache(cacheKey, <String, dynamic>{"cards": cards});

      debugPrint(
          "[StudyService] ✅ generateFlashcards() — ${cards.length} cards");
      return _parseCards(cards, subject);
    } catch (e) {
      debugPrint("[StudyService] ❌ generateFlashcards() failed: $e");
      return <FlashCard>[];
    }
  }

  static List<FlashCard> _parseCards(List<dynamic> raw, String subject) {
    return raw.asMap().entries.map((MapEntry<int, dynamic> entry) {
      final Map<String, dynamic> m =
          Map<String, dynamic>.from(entry.value as Map);
      return FlashCard.fromMap(
        "gen_${entry.key}",
        <String, dynamic>{
          "front": m["front"] ?? "",
          "back": m["back"] ?? "",
          "hint": m["hint"] ?? "",
          "subject": subject,
          "mastery": "unseen",
          "reviewCount": 0,
          "consecutiveCorrect": 0,
        },
      );
    }).where((FlashCard c) => c.front.isNotEmpty && c.back.isNotEmpty).toList();
  }

  // ── Quiz generation ───────────────────────────────────────────────────────

  /// Generates a mixed quiz for [subject] / [content].
  /// [types] selects which question types to include.
  static Future<List<QuizQuestion>> generateQuiz({
    required String subject,
    required String content,
    int questionCount = 10,
    List<QuestionType> types = const <QuestionType>[
      QuestionType.mcq,
      QuestionType.trueFalse,
    ],
    String difficulty = "medium",
    int playerLevel = 1,
  }) async {
    debugPrint(
        "[StudyService] 📝 generateQuiz() — $subject ($questionCount Qs)");

    final String cacheKey =
        "quiz_${subject.hashCode}_${content.hashCode}_$questionCount";
    final cached = await _getCache(cacheKey, maxAgeHours: 24);
    if (cached != null && cached["questions"] != null) {
      return _parseQuestions(
          cached["questions"] as List<dynamic>, subject);
    }

    final String typeList = types
        .map((QuestionType t) => switch (t) {
              QuestionType.mcq => "mcq",
              QuestionType.trueFalse => "trueFalse",
              QuestionType.shortAnswer => "shortAnswer",
            })
        .join(", ");

    final String prompt =
        """You are an expert assessment designer for a student productivity app.

Subject: "$subject"
Content to assess: "$content"
Total questions: $questionCount
Question types to use: $typeList
Difficulty: $difficulty
Student level: $playerLevel

QUESTION TYPE RULES:
- "mcq": 4 answer options (A/B/C/D), exactly one correct. options array must have 4 strings.
- "trueFalse": options must be exactly ["True", "False"]. correctAnswer must be "True" or "False".
- "shortAnswer": no options array needed (empty list). correctAnswer is a 1–2 sentence model answer.

Distribute types roughly evenly across the $questionCount questions.

Each question must:
- Be specific to "$subject" and the content provided.
- Have a clear, unambiguous correct answer.
- Include a 1–2 sentence explanation WHY that answer is correct.
- Have a difficulty matching "$difficulty".

Return JSON:
{
  "questions": [
    {
      "type": "mcq|trueFalse|shortAnswer",
      "question": "string",
      "options": ["A. ...", "B. ...", "C. ...", "D. ..."],
      "correctAnswer": "string (full text of correct option for mcq, 'True'/'False' for tf, model answer for short)",
      "explanation": "string",
      "difficulty": "$difficulty"
    }
  ]
}""";

    try {
      final dynamic raw = await _callJson(prompt, maxTokens: 4000);
      final List<dynamic> questions =
          (raw is Map && raw["questions"] is List)
              ? raw["questions"] as List<dynamic>
              : <dynamic>[];

      await _setCache(
          cacheKey, <String, dynamic>{"questions": questions});

      debugPrint(
          "[StudyService] ✅ generateQuiz() — ${questions.length} questions");
      return _parseQuestions(questions, subject);
    } catch (e) {
      debugPrint("[StudyService] ❌ generateQuiz() failed: $e");
      return <QuizQuestion>[];
    }
  }

  static List<QuizQuestion> _parseQuestions(
      List<dynamic> raw, String subject) {
    return raw
        .map((dynamic e) {
          try {
            final Map<String, dynamic> m =
                Map<String, dynamic>.from(e as Map);
            // Ensure subject is set
            m["subject"] = subject;
            return QuizQuestion.fromMap(m);
          } catch (_) {
            return null;
          }
        })
        .whereType<QuizQuestion>()
        .where((QuizQuestion q) => q.question.isNotEmpty)
        .toList();
  }

  // ── Study material generation ─────────────────────────────────────────────

  /// Generates a structured study material (summary, reviewer, or guide).
  static Future<StudyMaterial?> generateStudyMaterial({
    required StudyMaterialType type,
    required String subject,
    required String content,
    String taskId = "",
    String taskName = "",
    UserProfile? profile,
  }) async {
    debugPrint(
        "[StudyService] 📄 generateStudyMaterial(${type.name}) — $subject");

    final String cacheKey =
        "material_${type.name}_${subject.hashCode}_${content.hashCode}";
    final cached = await _getCache(cacheKey, maxAgeHours: 48);
    if (cached != null && cached["content"] != null) {
      return StudyMaterial(
        id: "cached",
        type: type,
        subject: subject,
        title: (cached["title"] ?? "$subject ${_typeLabel(type)}") as String,
        content: cached["content"] as String,
        taskId: taskId,
        taskName: taskName,
        wordCount: (cached["wordCount"] ?? 0) as int,
        createdAt: DateTime.now(),
      );
    }

    final String typeInstr = switch (type) {
      StudyMaterialType.summary =>
        "Write a concise summary (300–500 words) covering the most important concepts. "
        "Use short paragraphs. Include a 'Key Takeaways' bullet list at the end (3–5 points).",
      StudyMaterialType.reviewer =>
        "Write a comprehensive reviewer (600–900 words) organized by topic. "
        "Include: Overview section, Key Concepts with definitions, Important formulas or rules (if applicable), "
        "Common mistakes to avoid, and a Quick Review checklist at the end.",
      StudyMaterialType.studyGuide =>
        "Create a structured study guide (800–1200 words). "
        "Include: Learning Objectives, Core Concepts explained in plain language, "
        "Step-by-step procedures or processes (where relevant), Examples with worked solutions, "
        "Memory tricks or mnemonics, and a Self-Assessment section with 3 practice questions.",
    };

    final String prompt =
        """You are an expert educational content writer creating a ${_typeLabel(type)} for a student.

Subject: "$subject"
Content / topic: "$content"
${taskName.isNotEmpty ? 'Task context: "$taskName"' : ""}
${profile != null ? "Student level: studyFocus ${profile.studyFocus}/5, personality ${profile.personalityType.name}" : ""}

INSTRUCTIONS:
$typeInstr

Use clear headings (e.g. ## Heading), bullet points, and numbered lists where appropriate.
Write in plain English — no unnecessary jargon.
Be specific to "$subject" — not generic study advice.

Return JSON:
{
  "title": "string (specific title for this material)",
  "content": "string (the full formatted content using markdown-style headings and lists)",
  "wordCount": integer
}""";

    try {
      final dynamic raw = await _callJson(prompt, maxTokens: 2500);
      if (raw is! Map) return null;

      final String matContent = (raw["content"] ?? "") as String;
      if (matContent.isEmpty) return null;

      final String title =
          (raw["title"] ?? "$subject ${_typeLabel(type)}") as String;
      final int wordCount = (raw["wordCount"] ?? 0) as int;

      await _setCache(cacheKey, <String, dynamic>{
        "title": title,
        "content": matContent,
        "wordCount": wordCount,
      });

      debugPrint("[StudyService] ✅ generateStudyMaterial() succeeded.");
      return StudyMaterial(
        id: "gen_${DateTime.now().millisecondsSinceEpoch}",
        type: type,
        subject: subject,
        title: title,
        content: matContent,
        taskId: taskId,
        taskName: taskName,
        wordCount: wordCount,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint("[StudyService] ❌ generateStudyMaterial() failed: $e");
      return null;
    }
  }

  // ── AI Tutor chat ─────────────────────────────────────────────────────────

  /// Sends the conversation history to the tutor model and returns the reply.
  /// [context] is injected as an extra system note about the current task/subject.
  static Future<String> chatWithTutor({
    required List<TutorMessage> history,
    required String userMessage,
    String subject = "",
    String taskContext = "",
    UserProfile? profile,
    int playerLevel = 1,
  }) async {
    debugPrint("[StudyService] 💬 chatWithTutor() — \"${userMessage.substring(0, userMessage.length.clamp(0, 60))}...\"");

    // Build conversation messages (last 10 turns to save tokens)
    final List<Map<String, String>> messages = history
        .where((TutorMessage m) => !m.isLoading)
        .toList()
        .reversed
        .take(20)
        .toList()
        .reversed
        .map((TutorMessage m) => m.toApiMessage())
        .toList();

    // Add the new user message
    messages.add(<String, String>{"role": "user", "content": userMessage});

    // Build context prefix injected as first user message if history is empty
    if (history.isEmpty && (subject.isNotEmpty || taskContext.isNotEmpty)) {
      final String ctx = <String>[
        if (subject.isNotEmpty) "The student is studying: $subject.",
        if (taskContext.isNotEmpty) "Task context: $taskContext.",
        if (profile != null)
          "Student profile: study focus ${profile.studyFocus}/5, "
          "${profile.personalityType.name}, Level $playerLevel.",
        "Adapt your explanations to this context.",
      ].join(" ");

      // Prepend as a user/assistant exchange to set context
      messages.insertAll(0, <Map<String, String>>[
        <String, String>{"role": "user", "content": ctx},
        <String, String>{
          "role": "assistant",
          "content":
              "Got it! I'll tailor my help specifically to $subject. What would you like to explore?"
        },
      ]);
    }

    try {
      final String reply =
          await _callText(messages, maxTokens: 600);
      debugPrint("[StudyService] ✅ chatWithTutor() replied.");
      return reply.trim();
    } catch (e) {
      debugPrint("[StudyService] ❌ chatWithTutor() failed: $e");
      return "I'm having trouble connecting right now. Please try again in a moment — "
          "and in the meantime, try re-reading the last section you studied!";
    }
  }

  // ── Adaptive quiz feedback ────────────────────────────────────────────────

  /// After a quiz, generates personalised feedback and a study recommendation.
  static Future<Map<String, dynamic>> generateQuizFeedback({
    required QuizResult result,
    required UserProfile profile,
  }) async {
    debugPrint(
        "[StudyService] 🏆 generateQuizFeedback() — ${result.percentage}%");

    final List<Map<String, dynamic>> wrongAnswers = result.answers
        .where((QuizAnswerRecord a) => !a.isCorrect)
        .map((QuizAnswerRecord a) => <String, dynamic>{
              "question": a.question,
              "yourAnswer": a.userAnswer,
              "correct": a.correctAnswer,
            })
        .toList();

    final String prompt =
        """A student just completed a quiz. Provide specific, encouraging feedback.

Subject: "${result.subject}"
Score: ${result.percentage}% (${result.correctCount}/${result.totalQuestions} correct)
Time taken: ${result.durationSeconds ~/ 60}m ${result.durationSeconds % 60}s
Questions answered incorrectly (up to 5): ${jsonEncode(wrongAnswers.take(5).toList())}
Student profile: focus ${profile.studyFocus}/5, ${profile.personalityType.name}

Return JSON:
{
  "headline": "string (one punchy congratulations or encouragement line referencing their score)",
  "strengthMessage": "string (what they clearly know well, if score ≥ 60%)",
  "gapMessage": "string (the main knowledge gap identified from wrong answers)",
  "nextStep": "string (ONE specific action: review a concept, make flashcards, etc.)",
  "xpEarned": integer (50 for ≥80%, 30 for ≥60%, 15 for <60%)
}""";

    try {
      final dynamic raw = await _callJson(prompt);
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}

    // Fallback
    return <String, dynamic>{
      "headline": result.percentage >= 70
          ? "Great work! ${result.percentage}% — you're getting there! 🎉"
          : "Keep going! ${result.percentage}% — every attempt builds understanding.",
      "strengthMessage": "",
      "gapMessage": "Review the questions you missed and re-read those sections.",
      "nextStep":
          "Create flashcards for the ${wrongAnswers.length} questions you missed.",
      "xpEarned": result.percentage >= 80
          ? 50
          : result.percentage >= 60
              ? 30
              : 15,
    };
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _typeLabel(StudyMaterialType t) => switch (t) {
        StudyMaterialType.summary => "Summary",
        StudyMaterialType.reviewer => "Reviewer",
        StudyMaterialType.studyGuide => "Study Guide",
      };
}
