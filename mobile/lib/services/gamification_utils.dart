// ── XP gain calculator ─────────────────────────────────────────────────────────

/// Returns the XP earned for [eventType].
///
/// [streakDays] enables the streak multiplier:
///   • 3–6 day streak → 1.2× base
///   • 7+ day streak  → 1.5× base
///
/// This makes streaks feel meaningful without changing the base economy.
int calculateXpGain(
  String eventType, {
  String? difficulty,
  int pomodoros = 0,
  int streakDays = 0,
}) {
  final int base = _baseXp(eventType, difficulty: difficulty, pomodoros: pomodoros);
  if (base == 0) return 0;
  final double multiplier = streakDays >= 7
      ? 1.5
      : streakDays >= 3
          ? 1.2
          : 1.0;
  return (base * multiplier).round();
}

int _baseXp(String eventType, {String? difficulty, int pomodoros = 0}) {
  if (eventType == "task_completed") {
    return difficulty == "hard"
        ? 50
        : difficulty == "medium"
            ? 35
            : 20;
  }
  if (eventType == "mood_logged") return 5;
  if (eventType == "insight_posted") return 10;
  // study_session: 5 XP per completed Pomodoro, minimum 5 XP for any session.
  if (eventType == "study_session") return pomodoros > 0 ? pomodoros * 5 : 5;
  // weekly_challenge_completed: flat reward regardless of difficulty.
  if (eventType == "weekly_challenge") return 75;
  return 0;
}

// ── XP tier ───────────────────────────────────────────────────────────────────

/// Discrete tier derived from [level].
/// Drives how the AI calibrates task suggestions and Pomodoro targets.
enum XpTier {
  /// Levels 1–3: student is still forming habits.
  beginner,

  /// Levels 4–7: consistent engagement, ready for more challenge.
  developing,

  /// Levels 8–14: strong patterns, benefits from stretch goals.
  proficient,

  /// Level 15+: high-performer, push toward mastery-level tasks.
  advanced,
}

/// Returns the [XpTier] for a given level.
XpTier xpTierFromLevel(int level) {
  if (level >= 15) return XpTier.advanced;
  if (level >= 8) return XpTier.proficient;
  if (level >= 4) return XpTier.developing;
  return XpTier.beginner;
}

/// Human-readable label for the tier.
String xpTierLabel(XpTier tier) {
  return switch (tier) {
    XpTier.beginner   => "Beginner",
    XpTier.developing => "Developing",
    XpTier.proficient => "Proficient",
    XpTier.advanced   => "Advanced",
  };
}

/// Suggested minimum Pomodoro count per session, scaled by tier.
int suggestedPomodorosForTier(XpTier tier) {
  return switch (tier) {
    XpTier.beginner   => 1,
    XpTier.developing => 2,
    XpTier.proficient => 3,
    XpTier.advanced   => 4,
  };
}

/// Prompt modifier injected into AI calls so Claude adjusts its suggestions
/// to match the student's current capability level.
String aiDifficultyContextForTier(XpTier tier) {
  return switch (tier) {
    XpTier.beginner =>
      "The student is a BEGINNER (Level 1–3). "
      "Keep step counts at 3–4, Pomodoro targets at 1–2, "
      "and emphasise gentle, approachable language. "
      "Avoid suggesting complex or multi-day plans.",

    XpTier.developing =>
      "The student is DEVELOPING (Level 4–7). "
      "Suggest 4–5 steps, 2–3 Pomodoros, and introduce "
      "slightly more challenging methods like active recall. "
      "Acknowledge their growing consistency.",

    XpTier.proficient =>
      "The student is PROFICIENT (Level 8–14). "
      "Push for 5 steps, 3–4 Pomodoros, and deeper techniques "
      "like interleaved practice or the Feynman method. "
      "Set stretch goals and highlight areas for mastery.",

    XpTier.advanced =>
      "The student is an ADVANCED learner (Level 15+). "
      "Aim for 4–5+ Pomodoros, high-difficulty framing, and "
      "mastery-oriented strategies. Treat them as a self-directed "
      "learner and challenge them to optimise for long-term retention.",
  };
}

// ── Integer sqrt (used for level calculation) ──────────────────────────────────

int sqrtFloor(int value) {
  if (value <= 0) return 0;
  int x = value;
  int y = (x + 1) ~/ 2;
  while (y < x) {
    x = y;
    y = (x + value ~/ x) ~/ 2;
  }
  return x;
}
