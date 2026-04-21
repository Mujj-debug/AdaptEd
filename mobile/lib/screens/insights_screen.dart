import "package:flutter/material.dart";

import "../design_tokens.dart";
import "../models/app_models.dart";
import "../services/firestore_repository.dart";

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    required this.profile,
    required this.tasks,
    required this.moods,
    required this.sessions,
    required this.repo,
    required this.userMeta,
  });
  final UserProfile profile;
  final List<TaskItem> tasks;
  final List<MoodLog> moods;
  final List<StudySession> sessions;
  final FirestoreRepository repo;
  final Map<String, dynamic> userMeta;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool _retryingAssessment = false;
  bool _loadingWeeklySummary = false;
  bool _refreshingWeeklySummary = false;
  bool _retrySucceeded = false;
  Map<String, dynamic> _weeklySummary = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _loadWeeklySummary();
  }

  Future<void> _loadWeeklySummary() async {
    setState(() => _loadingWeeklySummary = true);
    try {
      final Map<String, dynamic> summary = await widget.repo.getWeeklySummary(
        tasks: widget.tasks,
        moods: widget.moods,
      );
      if (mounted) setState(() => _weeklySummary = summary);
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loadingWeeklySummary = false);
    }
  }

  Future<void> _forceRefreshWeeklySummary() async {
    if (_refreshingWeeklySummary) return;
    setState(() => _refreshingWeeklySummary = true);
    try {
      final Map<String, dynamic> summary =
          await widget.repo.forceRefreshWeeklySummary(
        tasks: widget.tasks,
        moods: widget.moods,
      );
      if (mounted) setState(() => _weeklySummary = summary);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Weekly summary refreshed ✓")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Refresh failed — check your connection.")),
      );
    } finally {
      if (mounted) setState(() => _refreshingWeeklySummary = false);
    }
  }

  Future<void> _retryAssessmentAnalysis() async {
    final Map<String, dynamic>? answers =
        widget.userMeta["assessmentAnswers"] is Map
            ? Map<String, dynamic>.from(widget.userMeta["assessmentAnswers"] as Map)
            : null;
    if (answers == null) return;
    setState(() => _retryingAssessment = true);
    try {
      await widget.repo.retryAssessmentAnalysis(answers: answers);
      if (mounted) setState(() => _retrySucceeded = true);
    } finally {
      if (mounted) setState(() => _retryingAssessment = false);
    }
  }

  bool _assessmentFailed(Map<String, dynamic> aiAnalysis) {
    if (_retrySucceeded) return false;
    if (aiAnalysis.isEmpty) return false;
    if (aiAnalysis["analysisError"] == true) return true;
    return !aiAnalysis.containsKey("productivityIdentity");
  }

  String _completionRate() {
    if (widget.tasks.isEmpty) return "—";
    final int done = widget.tasks.where((TaskItem t) => t.completed).length;
    return "${((done / widget.tasks.length) * 100).round()}%";
  }

  String _peakHour(Map<String, dynamic>? beh) {
    final int? h = beh?["studyPeakHour"] as int?;
    if (h == null) return "—";
    final String period = h < 12 ? "AM" : "PM";
    final int h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return "$h12 $period";
  }

  String _moodTrend(Map<String, dynamic>? beh) {
    final String trend = (beh?["moodTrend"] ?? "neutral") as String;
    return switch (trend) {
      "positive" => "😊 Positive",
      "negative" => "😔 Needs care",
      _ => "😐 Neutral",
    };
  }

  String _formatMinutes(int mins) {
    if (mins < 60) return "${mins}m";
    final int h = mins ~/ 60;
    final int m = mins % 60;
    return m > 0 ? "${h}h ${m}m" : "${h}h";
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> aiAnalysis = widget.userMeta["aiAnalysis"] is Map
        ? Map<String, dynamic>.from(widget.userMeta["aiAnalysis"] as Map)
        : <String, dynamic>{};

    final Map<String, dynamic>? behRaw = widget.userMeta["behaviorAnalytics"] is Map
        ? Map<String, dynamic>.from(widget.userMeta["behaviorAnalytics"] as Map)
        : null;
    final BehaviorAnalytics beh = BehaviorAnalytics.fromMap(behRaw);

    final List<dynamic> runtimeRaw =
        (widget.userMeta["insights"] as List<dynamic>?) ?? <dynamic>[];
    final List<InsightCardData> runtimeCards = <InsightCardData>[];
    for (final dynamic e in runtimeRaw) {
      if (e is Map) {
        runtimeCards.add(InsightCardData.fromMap(Map<String, dynamic>.from(e)));
      }
    }

    final bool analysisIsBroken = _assessmentFailed(aiAnalysis);

    final List<InsightCardData> allInsights = <InsightCardData>[
      ...runtimeCards,
      if (aiAnalysis.isNotEmpty && !analysisIsBroken)
        InsightCardData(
          title: "Your Productivity Identity",
          message: (aiAnalysis["productivityIdentity"] ?? "Identity pending")
              as String,
          why: (aiAnalysis["userProfileSummary"] ??
              "Based on your full assessment data.") as String,
        ),
    ];

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: const Text("AI Insights")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: <Widget>[
          // ── Assessment error banner ──────────────────────────────────────
          if (analysisIsBroken) ...<Widget>[
            LocketCard(
              color: kPink.withOpacity(0.3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text("Assessment analysis incomplete",
                      style: TextStyle(fontWeight: FontWeight.w800, color: kError)),
                  const SizedBox(height: 4),
                  const Text(
                    "Your profile analysis failed during onboarding "
                    "(likely a rate limit). Tap below to retry.",
                    style: TextStyle(color: kDark, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  _retryingAssessment
                      ? const Row(children: <Widget>[
                          SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: kOrange)),
                          SizedBox(width: 8),
                          Text("Retrying analysis...", style: kSubtitle),
                        ])
                      : DarkPillButton(
                          onPressed: _retryAssessmentAnalysis,
                          label: "Retry Assessment Analysis",
                          icon: Icons.replay_rounded,
                        ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── AI Profile Identity hero card ────────────────────────────────
          if (aiAnalysis.isNotEmpty && !analysisIsBroken) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFF2D1B69), Color(0xFF1A1041)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: const Color(0xFF5B4EFF).withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: kOrange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                        Icon(Icons.psychology_rounded, color: kOrange, size: 12),
                        SizedBox(width: 5),
                        Text("YOUR AI PROFILE", style: TextStyle(color: kOrange, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    (aiAnalysis["productivityIdentity"] ?? "—") as String,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (aiAnalysis["userProfileSummary"] ?? "") as String,
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Weekly Summary ──────────────────────────────────────────────
          Row(children: <Widget>[
            const Expanded(child: SectionHeader(title: "This Week")),
            if (_refreshingWeeklySummary)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kOrange))
            else
              GestureDetector(
                onTap: _forceRefreshWeeklySummary,
                child: const PillBadge(color: kOrangeSoft, label: "Refresh", icon: Icons.refresh),
              ),
          ]),
          const SizedBox(height: 8),
          if (_loadingWeeklySummary)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: <Widget>[
                BouncingDots(),
                SizedBox(width: 10),
                Text("Generating weekly summary...", style: kCaption),
              ]),
            )
          else if (_weeklySummary.isNotEmpty) ...<Widget>[
            LocketCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(children: <Widget>[
                    const Text("📋 ", style: TextStyle(fontSize: 16)),
                    Expanded(child: Text(
                      (_weeklySummary["headline"] ?? "") as String,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kDark),
                    )),
                    if (_weeklySummary["weekScore"] != null)
                      PillBadge(color: kOrange.withOpacity(0.15), label: "${_weeklySummary['weekScore']}/10"),
                  ]),
                  if (_weeklySummary["wins"] != null) ...<Widget>[
                    const SizedBox(height: 12),
                    const Text("Wins this week", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kOrange)),
                    const SizedBox(height: 4),
                    ...(_weeklySummary["wins"] as List<dynamic>).map(
                      (dynamic w) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(children: <Widget>[
                          const Text("✅ ", style: TextStyle(fontSize: 12)),
                          Expanded(child: Text("$w", style: const TextStyle(fontSize: 12, color: kDark))),
                        ]),
                      ),
                    ),
                  ],
                  if (_weeklySummary["focusNextWeek"] != null) ...<Widget>[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: kYellow.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        const Text("🎯 ", style: TextStyle(fontSize: 13)),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          const Text("Next week focus", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kDark)),
                          Text((_weeklySummary["focusNextWeek"] ?? "") as String, style: const TextStyle(fontSize: 12, color: kMuted)),
                        ])),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // ── Behavior Analytics stats ─────────────────────────────────────
          const SizedBox(height: 16),
          const SectionHeader(title: "Behavior Analytics"),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 2.6,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: <Widget>[
              _statTile("Study Peak", _peakHour(behRaw), Icons.schedule, kYellow),
              _statTile("Completion", _completionRate(), Icons.check_circle_outline, kGreen),
              _statTile("Mood Trend", _moodTrend(behRaw), Icons.mood, kBlue),
              _statTile("Focus Time", beh.totalSessionMinutes > 0 ? _formatMinutes(beh.totalSessionMinutes) : "—", Icons.timer_outlined, kPink),
              _statTile("Sessions", beh.totalSessionsCompleted > 0 ? "${beh.totalSessionsCompleted}" : "—", Icons.self_improvement, kSage),
              _statTile("Cards Shared", "${beh.totalCardsPosted}", Icons.share_outlined, kOrangeSoft),
            ],
          ),

          // ── Session difficulty trend ─────────────────────────────────────
          if (beh.totalSessionsCompleted >= 3) ...<Widget>[
            const SizedBox(height: 8),
            LocketCard(
              child: Row(children: <Widget>[
                Container(width: 38, height: 38,
                  decoration: BoxDecoration(color: kPink.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.trending_up_rounded, color: kDark, size: 18)),
                const SizedBox(width: 14),
                const Expanded(child: Text("Avg Session Difficulty", style: TextStyle(fontSize: 13, color: kMuted))),
                PillBadge(color: kOrangeSoft, label: "${beh.avgFeltDifficulty.toStringAsFixed(1)} / 5"),
              ]),
            ),
          ],

          // ── AI Profile rows ──────────────────────────────────────────────
          if (aiAnalysis.isNotEmpty && !analysisIsBroken) ...<Widget>[
            const SizedBox(height: 16),
            const SectionHeader(title: "Your Learning Profile"),
            const SizedBox(height: 8),
            _profileRow("Energy Type", (aiAnalysis["energyType"] ?? "—") as String, Icons.bolt_rounded),
            _profileRow("Study Style", (aiAnalysis["studyStyle"] ?? "—") as String, Icons.menu_book_rounded),
            _profileRow("Recovery", (aiAnalysis["recoveryProfile"] ?? "—") as String, Icons.bedtime_outlined),
            _profileRow("Social Energy", (aiAnalysis["socialEnergyType"] ?? "—") as String, Icons.people_rounded),
            _profileRow("Thinking Style", (aiAnalysis["thinkingStyle"] ?? "—") as String, Icons.lightbulb_outline),
          ],

          // ── Ideal Day Structure ──────────────────────────────────────────
          if (aiAnalysis["idealDayStructure"] != null) ...<Widget>[
            const SizedBox(height: 16),
            const SectionHeader(title: "Your Ideal Day"),
            const SizedBox(height: 10),
            Row(
              children: <Map<String, dynamic>>[
                <String, dynamic>{"label": "🌅 Morning", "index": 0, "color": kYellow},
                <String, dynamic>{"label": "☀️ Afternoon", "index": 1, "color": kOrangeSoft},
                <String, dynamic>{"label": "🌙 Evening", "index": 2, "color": kBlue},
              ].map((Map<String, dynamic> block) {
                final List<dynamic> structure = aiAnalysis["idealDayStructure"] as List<dynamic>;
                final int idx = block["index"] as int;
                final String content = idx < structure.length ? structure[idx] as String : "—";
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: <BoxShadow>[BoxShadow(color: kDark.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(block["label"] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kDark)),
                      const SizedBox(height: 4),
                      Text(content, style: kCaption),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ],

          // ── Personalized Strategy ────────────────────────────────────────
          if (aiAnalysis["personalizedStrategy"] != null) ...<Widget>[
            const SizedBox(height: 16),
            const SectionHeader(title: "Your AI Strategy"),
            const SizedBox(height: 8),
            ...(aiAnalysis["personalizedStrategy"] as List<dynamic>).asMap().entries.map(
              (MapEntry<int, dynamic> e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LocketCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(12)),
                      child: Center(child: Text("${e.key + 1}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text("${e.value}", style: const TextStyle(fontSize: 13, color: kDark))),
                  ]),
                ),
              ),
            ),
          ],

          // ── Future-You Simulator (full view) ────────────────────────────
          const SizedBox(height: 16),
          const SectionHeader(title: "Future-You Simulator"),
          const SizedBox(height: 10),
          _FutureYouFullCard(
              tasks: widget.tasks, sessions: widget.sessions),

          // ── Smart Energy Mapping ─────────────────────────────────────────
          const SizedBox(height: 16),
          const SectionHeader(title: "Smart Energy Mapping"),
          const SizedBox(height: 10),
          _SmartEnergyFullCard(profile: widget.profile),

          // ── Risk Alerts ──────────────────────────────────────────────────
          if (aiAnalysis["riskAnalysis"] != null) ...<Widget>[
            const SizedBox(height: 16),
            const SectionHeader(title: "Risk Alerts"),
            const SizedBox(height: 4),
            if (aiAnalysis["riskReasoning"] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text((aiAnalysis["riskReasoning"] ?? "") as String, style: kCaption),
              ),
            ...(aiAnalysis["riskAnalysis"] as List<dynamic>).map(
              (dynamic r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LocketCard(
                  color: kPink.withOpacity(0.15),
                  padding: const EdgeInsets.all(14),
                  child: Row(children: <Widget>[
                    const Icon(Icons.warning_amber_rounded, color: kOrange, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text("$r", style: const TextStyle(fontSize: 13, color: kDark))),
                  ]),
                ),
              ),
            ),
          ],

          // ── AI Insight cards ─────────────────────────────────────────────
          if (allInsights.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Row(children: <Widget>[
              const Expanded(child: SectionHeader(title: "AI Insights")),
              const SizedBox(width: 8),
              const PillBadge(color: kOrangeSoft, label: "Auto-updated"),
            ]),
            const SizedBox(height: 8),
            ...allInsights.map(
              (InsightCardData card) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LocketCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Row(children: <Widget>[
                      const Icon(Icons.auto_awesome, color: kOrange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(card.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kDark))),
                    ]),
                    const SizedBox(height: 8),
                    Text(card.message, style: const TextStyle(fontSize: 13, color: kDark)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: kOrangeSoft, borderRadius: BorderRadius.circular(12)),
                      child: Row(children: <Widget>[
                        const Icon(Icons.info_outline_rounded, size: 14, color: kOrange),
                        const SizedBox(width: 6),
                        Expanded(child: Text("Why: ${card.why}", style: const TextStyle(fontSize: 12, color: kMuted))),
                      ]),
                    ),
                    if (card.actionItem.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: kYellow.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          const Text("🎯 ", style: TextStyle(fontSize: 13)),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                            const Text("Try this", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kDark)),
                            const SizedBox(height: 2),
                            Text(card.actionItem, style: const TextStyle(fontSize: 12, color: kDark)),
                          ])),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ],

          if (allInsights.isEmpty && !analysisIsBroken)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  const BouncingDots(),
                  const SizedBox(height: 16),
                  const Text("Generating your insights...", style: kSubtitle),
                  const SizedBox(height: 8),
                  const Text("This only takes a moment.", style: kCaption),
                ]),
              ),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: <Widget>[
        Icon(icon, size: 18, color: kDark.withOpacity(0.6)),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(label, style: kCaption),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kDark), overflow: TextOverflow.ellipsis),
          ],
        )),
      ]),
    );
  }

  Widget _profileRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LocketCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: <Widget>[
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: kOrangeSoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: kOrange),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: kCaption)),
          Flexible(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kDark), textAlign: TextAlign.end)),
        ]),
      ),
    );
  }
}

// ── Future-You Simulator full card ────────────────────────────────────────────

class _FutureYouFullCard extends StatelessWidget {
  const _FutureYouFullCard({required this.tasks, required this.sessions});
  final List<TaskItem> tasks;
  final List<StudySession> sessions;

  @override
  Widget build(BuildContext context) {
    final List<_FutureYouEntry> entries = _buildEntries();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1E3A5F), Color(0xFF0F2040)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.auto_graph_rounded, color: Color(0xFF60A5FA), size: 18),
              SizedBox(width: 8),
              Text(
                "Academic Forecast",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            "Predicted impact of your current study habits",
            style: TextStyle(fontSize: 12, color: Color(0xFF6B8CAE)),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const Text(
              "No data yet — complete tasks and study sessions to unlock your personal forecast.",
              style: TextStyle(color: Color(0xFFCDD5E0), fontSize: 13, height: 1.5),
            )
          else
            ...entries.map(
              (_FutureYouEntry e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: e.color.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(e.icon, color: e.color, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(e.headline,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(e.detail,
                              style: const TextStyle(
                                  color: Color(0xFF6B8CAE), fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: <Widget>[
                Icon(Icons.info_outline_rounded,
                    size: 13, color: Color(0xFF6B8CAE)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Predictions update as your habits evolve. Keep studying!",
                    style: TextStyle(fontSize: 11, color: Color(0xFF6B8CAE)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_FutureYouEntry> _buildEntries() {
    final DateTime now = DateTime.now();
    final int total = tasks.length;
    final int completed = tasks.where((TaskItem t) => t.completed).length;
    final double completionRate = total > 0 ? completed / total : 0.0;
    final int overdue = tasks
        .where((TaskItem t) => !t.completed && t.deadline.isBefore(now))
        .length;
    final DateTime weekAgo = now.subtract(const Duration(days: 7));
    final Set<String> daySet = sessions
        .where((StudySession s) => s.completedAt.isAfter(weekAgo))
        .map((StudySession s) =>
            "${s.completedAt.year}-${s.completedAt.month}-${s.completedAt.day}")
        .toSet();
    final int daysStudied = daySet.length;

    if (tasks.isEmpty && sessions.isEmpty) return <_FutureYouEntry>[];

    final List<_FutureYouEntry> entries = <_FutureYouEntry>[];

    if (daysStudied >= 5 && completionRate >= 0.75) {
      entries.add(_FutureYouEntry(
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF34D399),
        headline: "Mastery on track in ~3 weeks",
        detail: "Your consistency puts you in the top study tier",
      ));
      entries.add(_FutureYouEntry(
        icon: Icons.task_alt_rounded,
        color: const Color(0xFF60A5FA),
        headline: "27% fewer overdue tasks predicted",
        detail: "Based on your current completion trend",
      ));
    } else if (daysStudied >= 3 && completionRate >= 0.5) {
      entries.add(_FutureYouEntry(
        icon: Icons.show_chart_rounded,
        color: const Color(0xFF60A5FA),
        headline: "Steady progress — good momentum",
        detail: "Add 2 more study days/week to accelerate",
      ));
      if (overdue > 0) {
        entries.add(_FutureYouEntry(
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFFBBF24),
          headline: "$overdue overdue task${overdue > 1 ? 's' : ''} at risk",
          detail: "Address these to protect your completion rate",
        ));
      }
    } else if (overdue >= 3) {
      entries.add(_FutureYouEntry(
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFFB7185),
        headline: "40% chance of task pile-up next week",
        detail: "Catch up on $overdue overdue tasks to break this pattern",
      ));
      entries.add(_FutureYouEntry(
        icon: Icons.lightbulb_outline_rounded,
        color: const Color(0xFF60A5FA),
        headline: "1 session/day can reverse this trend",
        detail: "Small consistent effort beats large infrequent sessions",
      ));
    } else {
      entries.add(_FutureYouEntry(
        icon: Icons.rocket_launch_rounded,
        color: const Color(0xFF60A5FA),
        headline: "Build to 3 sessions/week for results",
        detail: "${((completionRate * 100).round())}% completion — keep pushing",
      ));
    }

    return entries;
  }
}

class _FutureYouEntry {
  const _FutureYouEntry({
    required this.icon,
    required this.color,
    required this.headline,
    required this.detail,
  });
  final IconData icon;
  final Color color;
  final String headline;
  final String detail;
}

// ── Smart Energy Mapping full card ────────────────────────────────────────────

class _SmartEnergyFullCard extends StatelessWidget {
  const _SmartEnergyFullCard({required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final String pref = profile.productivityPreference.name;
    final List<_EnergyBlock> blocks = _buildBlocks(pref);

    return LocketCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            "Optimised for your study rhythm",
            style: TextStyle(fontSize: 12, color: kMuted),
          ),
          const SizedBox(height: 14),
          ...blocks.map((_EnergyBlock b) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: <Widget>[
                    Text(b.dot, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(b.label,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: kDark)),
                          Text(b.description,
                              style: const TextStyle(
                                  fontSize: 11, color: kMuted)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: kOrangeSoft,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(b.time,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: kDark)),
                    ),
                  ],
                ),
              )),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: kOrangeSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.psychology_outlined,
                    size: 14, color: kOrange),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Schedule heavy tasks in your Deep Focus window for best results.",
                    style: TextStyle(
                        fontSize: 11,
                        color: kDark.withOpacity(0.75)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_EnergyBlock> _buildBlocks(String pref) {
    if (pref == "morning") {
      return const <_EnergyBlock>[
        _EnergyBlock(dot: "🟢", label: "Deep Focus", time: "6am – 12pm",
            description: "Best for hard tasks, complex problems"),
        _EnergyBlock(dot: "🟡", label: "Light Study", time: "2pm – 5pm",
            description: "Review, flashcards, light reading"),
        _EnergyBlock(dot: "🔴", label: "Avoid Heavy Tasks", time: "9pm – 6am",
            description: "Rest and recovery window"),
      ];
    } else if (pref == "night") {
      return const <_EnergyBlock>[
        _EnergyBlock(dot: "🟢", label: "Deep Focus", time: "9pm – 1am",
            description: "Best for hard tasks, complex problems"),
        _EnergyBlock(dot: "🟡", label: "Light Study", time: "6pm – 9pm",
            description: "Review, flashcards, light reading"),
        _EnergyBlock(dot: "🔴", label: "Avoid Heavy Tasks", time: "Before 2pm",
            description: "Low energy window for you"),
      ];
    } else {
      return const <_EnergyBlock>[
        _EnergyBlock(dot: "🟢", label: "Deep Focus", time: "Peak hours",
            description: "Your flexible peak — track it over time"),
        _EnergyBlock(dot: "🟡", label: "Light Study", time: "Off-peak",
            description: "Review, flashcards, light reading"),
        _EnergyBlock(dot: "🔴", label: "Avoid Heavy Tasks", time: "Late night",
            description: "Protect your sleep and recovery"),
      ];
    }
  }
}

class _EnergyBlock {
  const _EnergyBlock({
    required this.dot,
    required this.label,
    required this.time,
    required this.description,
  });
  final String dot;
  final String label;
  final String time;
  final String description;
}
