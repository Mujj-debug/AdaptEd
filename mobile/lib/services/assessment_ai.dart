import "../models/app_models.dart";
import "claude_service.dart";

// ─── AI analysis (Claude-powered) ────────────────────────────────────────────

/// Sends the user's full assessment answers to Claude and returns a rich
/// psychographic profile including study style, energy type, risk analysis,
/// personalised strategy, and productivity identity.
///
/// Previously a local rule/if-else engine — now powered by Claude.
Future<Map<String, dynamic>> generateAiAnalysis(Map<String, dynamic> answers) {
  return ClaudeService.generateAssessmentAnalysis(answers);
}

// ─── Profile builder (kept local — pure data mapping, no AI needed) ───────────

/// Maps raw assessment slider/choice values to a [UserProfile].
/// This is intentionally deterministic and does NOT call the API.
UserProfile buildProfileFromAssessment(Map<String, dynamic> a) {
  final int socialEnergy = (a["social_after_interaction_energy"] ?? 3) as int;
  final int morning = (a["energy_morning_productive"] ?? 3) as int;
  final int night = (a["energy_night_productive"] ?? 3) as int;
  final ProductivityPreference pref = morning - night >= 2
      ? ProductivityPreference.morning
      : night - morning >= 2
          ? ProductivityPreference.night
          : ProductivityPreference.flexible;
  return UserProfile(
    personalityType: socialEnergy <= 2 ? PersonalityType.introvert : PersonalityType.extrovert,
    productivityPreference: pref,
    socialEnergy: socialEnergy,
    studyFocus: (a["focus_duration"] ?? 3) as int,
    restImportance: 6 - ((a["rest_guilt_when_resting"] ?? 3) as int),
    creativity: (a["thinking_idea_frequency"] ?? 3) as int,
    physicalActivity: (a["lifestyle_exercise_frequency"] ?? 3) as int,
  );
}

// ─── Local classifiers (kept as reference / offline fallback) ─────────────────

String classifyEnergyType(Map<String, dynamic> a) {
  final int morning = (a["energy_morning_productive"] ?? 3) as int;
  final int night = (a["energy_night_productive"] ?? 3) as int;
  if (morning - night >= 2) return "Morning-focused";
  if (night - morning >= 2) return "Night-focused";
  return "Inconsistent";
}

String classifyStudyStyle(Map<String, dynamic> a) {
  final int focus = (a["focus_duration"] ?? 3) as int;
  final int distraction = (a["focus_distraction_frequency"] ?? 3) as int;
  final String style = (a["focus_study_style"] ?? "Random / inconsistent") as String;
  if (focus >= 4 && distraction <= 2 && style == "Long deep sessions") return "Deep Focus";
  if (focus <= 2 && distraction >= 4) return "Easily Distracted";
  return "Short Burst";
}

String classifyRecovery(Map<String, dynamic> a) {
  final int rested = (a["rest_sleep_quality"] ?? 3) as int;
  final String sleep = (a["rest_sleep_hours"] ?? "7-8 hours") as String;
  final int drained = (a["focus_post_study_drain"] ?? 3) as int;
  if (rested <= 2 && (sleep == "Less than 5 hours" || sleep == "5-6 hours") && drained >= 4) {
    return "Burnout Risk";
  }
  if (rested >= 4 && (sleep == "7-8 hours" || sleep == "9+ hours")) return "Well-Rested";
  return "Under-recovered";
}

String classifySocialType(Map<String, dynamic> a) {
  final int socialEnergy = (a["social_after_interaction_energy"] ?? 3) as int;
  final String workPref = (a["social_work_preference"] ?? "Depends") as String;
  if (socialEnergy <= 2 || workPref == "Alone") return "Introverted";
  if (socialEnergy >= 4 || workPref == "With others") return "Extroverted";
  return "Ambivert";
}

String classifyThinkingStyle(Map<String, dynamic> a) {
  final int structure = (a["thinking_structure_preference"] ?? 3) as int;
  final String solving = (a["thinking_problem_style"] ?? "Mix both") as String;
  if (structure >= 4 || solving == "Follow clear steps") return "Structured";
  if (structure <= 2 || solving == "Experiment freely") return "Creative";
  return "Hybrid";
}
