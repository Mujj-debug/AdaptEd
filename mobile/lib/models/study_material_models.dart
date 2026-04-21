// lib/models/study_material_models.dart
//
// New models for the AI Study Hub feature set:
//   • FlashCard         — generated card with spaced-repetition tracking
//   • QuizQuestion      — MCQ / True-False / Short-Answer question
//   • QuizResult        — scored result of a completed quiz session
//   • StudyMaterial     — AI-generated summary, reviewer, or study guide
//   • TutorMessage      — one message in the AI tutor chat thread

import "package:cloud_firestore/cloud_firestore.dart";

// ── Enums ─────────────────────────────────────────────────────────────────────

enum QuestionType { mcq, trueFalse, shortAnswer }

enum StudyMaterialType { summary, reviewer, studyGuide }

enum CardMastery {
  /// Not yet reviewed.
  unseen,

  /// Seen but not yet confident.
  learning,

  /// Student answered correctly twice in a row.
  mastered,
}

// ── FlashCard ─────────────────────────────────────────────────────────────────

class FlashCard {
  FlashCard({
    required this.id,
    required this.front,
    required this.back,
    required this.subject,
    this.hint = "",
    this.mastery = CardMastery.unseen,
    this.nextReviewAt,
    this.reviewCount = 0,
    this.consecutiveCorrect = 0,
  });

  factory FlashCard.fromMap(String id, Map<String, dynamic> data) {
    return FlashCard(
      id: id,
      front: (data["front"] ?? "") as String,
      back: (data["back"] ?? "") as String,
      subject: (data["subject"] ?? "") as String,
      hint: (data["hint"] ?? "") as String,
      mastery:
          CardMastery.values.byName((data["mastery"] ?? "unseen") as String),
      nextReviewAt: (data["nextReviewAt"] as Timestamp?)?.toDate(),
      reviewCount: (data["reviewCount"] ?? 0) as int,
      consecutiveCorrect: (data["consecutiveCorrect"] ?? 0) as int,
    );
  }

  final String id;

  /// Question / term shown on the front.
  final String front;

  /// Answer / definition shown on the back.
  final String back;

  final String subject;

  /// Optional hint shown before revealing the answer.
  final String hint;

  final CardMastery mastery;
  final DateTime? nextReviewAt;
  final int reviewCount;

  /// Consecutive correct answers — 2 in a row → mastered.
  final int consecutiveCorrect;

  Map<String, dynamic> toMap() => <String, dynamic>{
        "front": front,
        "back": back,
        "subject": subject,
        "hint": hint,
        "mastery": mastery.name,
        if (nextReviewAt != null)
          "nextReviewAt": Timestamp.fromDate(nextReviewAt!),
        "reviewCount": reviewCount,
        "consecutiveCorrect": consecutiveCorrect,
      };

  FlashCard copyWith({
    CardMastery? mastery,
    DateTime? nextReviewAt,
    int? reviewCount,
    int? consecutiveCorrect,
  }) =>
      FlashCard(
        id: id,
        front: front,
        back: back,
        subject: subject,
        hint: hint,
        mastery: mastery ?? this.mastery,
        nextReviewAt: nextReviewAt ?? this.nextReviewAt,
        reviewCount: reviewCount ?? this.reviewCount,
        consecutiveCorrect: consecutiveCorrect ?? this.consecutiveCorrect,
      );
}

// ── QuizQuestion ──────────────────────────────────────────────────────────────

class QuizQuestion {
  QuizQuestion({
    required this.type,
    required this.question,
    required this.correctAnswer,
    required this.explanation,
    required this.subject,
    this.options = const <String>[],
    this.difficulty = "medium",
  });

  factory QuizQuestion.fromMap(Map<String, dynamic> data) {
    return QuizQuestion(
      type: QuestionType.values.byName(
          (data["type"] ?? "mcq") as String),
      question: (data["question"] ?? "") as String,
      correctAnswer: (data["correctAnswer"] ?? "") as String,
      explanation: (data["explanation"] ?? "") as String,
      subject: (data["subject"] ?? "") as String,
      options: ((data["options"] ?? <dynamic>[]) as List<dynamic>)
          .map((dynamic e) => "$e")
          .toList(),
      difficulty: (data["difficulty"] ?? "medium") as String,
    );
  }

  final QuestionType type;
  final String question;
  final String correctAnswer;
  final String explanation;
  final String subject;

  /// Non-empty only for [QuestionType.mcq] — includes the correct answer.
  final List<String> options;
  final String difficulty;

  Map<String, dynamic> toMap() => <String, dynamic>{
        "type": type.name,
        "question": question,
        "correctAnswer": correctAnswer,
        "explanation": explanation,
        "subject": subject,
        "options": options,
        "difficulty": difficulty,
      };
}

// ── QuizResult ────────────────────────────────────────────────────────────────

class QuizResult {
  QuizResult({
    required this.totalQuestions,
    required this.correctCount,
    required this.subject,
    required this.completedAt,
    required this.answers,
    required this.durationSeconds,
  });

  final int totalQuestions;
  final int correctCount;
  final String subject;
  final DateTime completedAt;
  final List<QuizAnswerRecord> answers;
  final int durationSeconds;

  double get score =>
      totalQuestions > 0 ? correctCount / totalQuestions : 0.0;
  int get percentage => (score * 100).round();

  String get grade {
    if (percentage >= 90) return "A";
    if (percentage >= 80) return "B";
    if (percentage >= 70) return "C";
    if (percentage >= 60) return "D";
    return "F";
  }
}

class QuizAnswerRecord {
  QuizAnswerRecord({
    required this.question,
    required this.userAnswer,
    required this.correctAnswer,
    required this.isCorrect,
    required this.explanation,
  });

  final String question;
  final String userAnswer;
  final String correctAnswer;
  final bool isCorrect;
  final String explanation;
}

// ── StudyMaterial ─────────────────────────────────────────────────────────────

class StudyMaterial {
  StudyMaterial({
    required this.id,
    required this.type,
    required this.subject,
    required this.title,
    required this.content,
    required this.createdAt,
    this.taskId = "",
    this.taskName = "",
    this.wordCount = 0,
  });

  factory StudyMaterial.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return StudyMaterial(
      id: doc.id,
      type: StudyMaterialType.values.byName(
          (data["type"] ?? "summary") as String),
      subject: (data["subject"] ?? "") as String,
      title: (data["title"] ?? "") as String,
      content: (data["content"] ?? "") as String,
      taskId: (data["taskId"] ?? "") as String,
      taskName: (data["taskName"] ?? "") as String,
      wordCount: (data["wordCount"] ?? 0) as int,
      createdAt:
          (data["createdAt"] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  final String id;
  final StudyMaterialType type;
  final String subject;
  final String title;
  final String content;
  final String taskId;
  final String taskName;
  final int wordCount;
  final DateTime createdAt;

  String get typeLabel => switch (type) {
        StudyMaterialType.summary => "Summary",
        StudyMaterialType.reviewer => "Reviewer",
        StudyMaterialType.studyGuide => "Study Guide",
      };

  String get typeEmoji => switch (type) {
        StudyMaterialType.summary => "📋",
        StudyMaterialType.reviewer => "📖",
        StudyMaterialType.studyGuide => "🗺️",
      };

  Map<String, dynamic> toMap() => <String, dynamic>{
        "type": type.name,
        "subject": subject,
        "title": title,
        "content": content,
        "taskId": taskId,
        "taskName": taskName,
        "wordCount": wordCount,
        "createdAt": FieldValue.serverTimestamp(),
      };
}

// ── TutorMessage ──────────────────────────────────────────────────────────────

class TutorMessage {
  TutorMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.isLoading = false,
  });

  /// "user" | "assistant"
  final String role;
  final String content;
  final DateTime timestamp;

  /// True while the AI is generating a response (placeholder message).
  final bool isLoading;

  bool get isUser => role == "user";

  Map<String, String> toApiMessage() =>
      <String, String>{"role": role, "content": content};
}
