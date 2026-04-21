import "dart:math" as math;

import "package:flutter/material.dart";

import "../design_tokens.dart";
import "../models/app_models.dart";
import "../models/weekly_challenge_models.dart";

// ── Badge definitions ──────────────────────────────────────────────────────────

class _BadgeDef {
  const _BadgeDef(this.id, this.emoji, this.name, this.description);
  final String id;
  final String emoji;
  final String name;
  final String description;
}

const List<_BadgeDef> _allBadges = <_BadgeDef>[
  _BadgeDef("getting_started",  "🌱", "Getting Started",    "Complete your first task"),
  _BadgeDef("early_bird",       "🌅", "Early Bird",          "Complete a task before 9 AM"),
  _BadgeDef("night_owl",        "🦉", "Night Owl",           "Complete a task after 10 PM"),
  _BadgeDef("on_fire",          "🔥", "On Fire",             "Maintain a 7-day streak"),
  _BadgeDef("speed_runner",     "⚡", "Speed Runner",        "Complete a task within 24h of creating it"),
  _BadgeDef("deep_thinker",     "🧠", "Deep Thinker",        "Add a task rated 'hard' difficulty"),
  _BadgeDef("diamond_focus",    "💎", "Diamond Focus",       "Complete 3 hard tasks in a week"),
  _BadgeDef("bookworm",         "📚", "Bookworm",            "Add 10 tasks across 5+ subjects"),
  _BadgeDef("perfect_week",     "🎯", "Perfect Week",        "Complete every task due that week"),
  _BadgeDef("balanced",         "🧘", "Balanced",            "Log mood + complete task same day, 5 days"),
  _BadgeDef("growth_mindset",   "📈", "Growth Mindset",      "Task completion rate above 80%"),
  _BadgeDef("resilient",        "🌙", "Resilient",           "Log mood after a hard task"),
  _BadgeDef("focused_learner",  "🎧", "Focused Learner",     "Complete 5 Focus Mode sessions"),
  _BadgeDef("deep_session",     "🏊", "Deep Session",        "Complete a session with 3+ Pomodoros"),
  _BadgeDef("voice",            "🗣",  "Voice",               "Share your first study strategy"),
  _BadgeDef("insight_sharer",   "💡", "Insight Sharer",      "Share 5 strategies to the library"),
  _BadgeDef("community_star",   "🤝", "Community Star",      "Receive 20 total reactions"),
];

class GamificationScreen extends StatelessWidget {
  const GamificationScreen({
    super.key,
    required this.game,
    this.weeklyChallenges = const <WeeklyChallenge>[],
  });

  final GamificationState game;
  final List<WeeklyChallenge> weeklyChallenges;

  @override
  Widget build(BuildContext context) {
    final int level = game.level;
    final int xpAtCurrentLevel = (level - 1) * (level - 1) * 100;
    final int xpAtNextLevel = level * level * 100;
    final double progress = xpAtNextLevel > xpAtCurrentLevel
        ? (game.xp - xpAtCurrentLevel) / (xpAtNextLevel - xpAtCurrentLevel)
        : 1.0;
    final int xpToNext = xpAtNextLevel - game.xp;

    final Set<String> earned = game.badges.toSet();
    final List<_BadgeDef> earnedBadges =
        _allBadges.where((b) => earned.contains(b.id) || earned.contains(b.name)).toList();
    final List<_BadgeDef> lockedBadges =
        _allBadges.where((b) => !earned.contains(b.id) && !earned.contains(b.name)).toList();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: const Text("XP & Badges")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: <Widget>[
          // ── Hero XP ring ─────────────────────────────────────────────────
          Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  CustomPaint(
                    size: const Size(160, 160),
                    painter: _XpRingPainter(progress: progress.clamp(0.0, 1.0)),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        "Level $level",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: kDark,
                        ),
                      ),
                      Text(
                        "${game.xp} XP",
                        style: kSubtitle,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              "$xpToNext XP to Level ${level + 1}",
              style: kCaption,
            ),
          ),
          if (game.streakDays > 0) ...<Widget>[
            const SizedBox(height: 8),
            Center(
              child: PillBadge(
                color: kYellow,
                label: "🔥 ${game.streakDays} day streak",
              ),
            ),
          ],
          const SizedBox(height: 28),

          // ── Weekly challenges ─────────────────────────────────────────────
          const SectionHeader(title: "This Week's Challenges"),
          const SizedBox(height: 10),
          if (weeklyChallenges.isEmpty)
            _emptyChallengesCard()
          else
            ...weeklyChallenges.map(
              (WeeklyChallenge c) => _WeeklyChallengeTile(challenge: c),
            ),
          const SizedBox(height: 28),

          // ── XP reference ──────────────────────────────────────────────────
          const SectionHeader(title: "How to Earn XP"),
          const SizedBox(height: 10),
          _xpReferenceGrid(),
          const SizedBox(height: 28),

          // ── Earned badges ─────────────────────────────────────────────────
          SectionHeader(title: "Badges Earned (${earnedBadges.length})"),
          const SizedBox(height: 10),
          if (earnedBadges.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                "No badges yet — complete tasks, log moods, and use Focus Mode to earn them!",
                style: TextStyle(color: kMuted),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.6,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: earnedBadges.length,
              itemBuilder: (_, int i) => _BadgeTile(badge: earnedBadges[i]),
            ),
          const SizedBox(height: 28),

          // ── Locked badges ─────────────────────────────────────────────────
          SectionHeader(title: "Badges to Unlock (${lockedBadges.length})"),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.6,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: lockedBadges.length,
            itemBuilder: (_, int i) =>
                _BadgeTile(badge: lockedBadges[i], locked: true),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _emptyChallengesCard() {
    return LocketCard(
      color: kOrangeSoft,
      child: Row(
        children: <Widget>[
          const Text("🗓", style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Challenges load automatically at the start of each week. Check back Monday!",
              style: TextStyle(fontSize: 13, color: kDark, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _xpReferenceGrid() {
    final List<(String, String)> items = <(String, String)>[
      ("Easy task done", "+20 XP"),
      ("Medium task done", "+35 XP"),
      ("Hard task done", "+50 XP"),
      ("Mood logged", "+5 XP"),
      ("Pomodoro session", "+5 XP each"),
      ("7-day streak", "+50 XP"),
      ("Weekly challenge", "+75–150 XP"),
      ("Share strategy", "+10 XP"),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 3.4,
      crossAxisSpacing: 10,
      mainAxisSpacing: 8,
      children: items.map(((String, String) e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: kOrangeSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: Text(e.$1,
                    style: const TextStyle(fontSize: 11, color: kDark),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(
                e.$2,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: kOrange),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Weekly challenge tile ─────────────────────────────────────────────────────

class _WeeklyChallengeTile extends StatelessWidget {
  const _WeeklyChallengeTile({required this.challenge});
  final WeeklyChallenge challenge;

  @override
  Widget build(BuildContext context) {
    final bool done = challenge.completed;
    final double pct = challenge.progress;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: kDark.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: done ? kGreen.withOpacity(0.5) : kOrange.withOpacity(0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                _emojiForChallenge(challenge.defId),
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      challenge.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13, color: kDark),
                    ),
                    Text(
                      challenge.description,
                      style: kCaption,
                    ),
                  ],
                ),
              ),
              PillBadge(
                color: done ? kGreen.withOpacity(0.3) : kOrangeSoft,
                label: "+${challenge.xpReward} XP",
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: kDark.withOpacity(0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      done ? kSuccess : kOrange,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                done
                    ? "✅ Done"
                    : "${challenge.currentCount}/${challenge.targetCount}",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: done ? kSuccess : kDark,
                ),
              ),
            ],
          ),
          if (!done && (challenge.targetCount - challenge.currentCount) <= 2 &&
              (challenge.targetCount - challenge.currentCount) > 0) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              "${challenge.targetCount - challenge.currentCount} more to go — you're almost there!",
              style: const TextStyle(
                  fontSize: 11,
                  color: kOrange,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  String _emojiForChallenge(String defId) {
    return weeklyChallengePool
            .where((WeeklyChallengeDef d) => d.id == defId)
            .firstOrNull
            ?.emoji ??
        "🏆";
  }
}

// ── Badge tile ────────────────────────────────────────────────────────────────

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, this.locked = false});
  final _BadgeDef badge;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: badge.description,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: locked ? kBg : kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: locked ? kMuted.withOpacity(0.15) : kOrange.withOpacity(0.2),
          ),
          boxShadow: locked
              ? null
              : <BoxShadow>[
                  BoxShadow(
                    color: kDark.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          children: <Widget>[
            Text(
              badge.emoji,
              style: TextStyle(
                  fontSize: 22,
                  color: locked ? const Color(0x00000000) : null),
            ),
            if (locked)
              const Padding(
                padding: EdgeInsets.only(right: 2),
                child: Icon(Icons.lock_rounded, size: 16, color: kMuted),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                badge.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: locked ? kMuted : kDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── XP ring painter ───────────────────────────────────────────────────────────

class _XpRingPainter extends CustomPainter {
  _XpRingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double radius = (size.width / 2) - 10;
    const double stroke = 12;

    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color = kOrangeSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    final Paint arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: const <Color>[kYellow, kOrange],
      ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_XpRingPainter old) => old.progress != progress;
}
