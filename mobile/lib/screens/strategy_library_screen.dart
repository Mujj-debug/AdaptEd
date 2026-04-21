import "package:flutter/material.dart";

import "../design_tokens.dart";
import "../models/app_models.dart";
import "../services/firestore_repository.dart";
import "../services/gamification_utils.dart";

// ── Built-in system strategies ────────────────────────────────────────────────

final List<StudyStrategy> _systemStrategies = <StudyStrategy>[
  StudyStrategy(
    id: "sys_pomodoro",
    title: "Pomodoro Technique",
    category: "Focus",
    summary:
        "Work in focused 25-minute sprints followed by 5-minute breaks. After 4 cycles, take a longer 15–30 minute break.",
    steps: <String>[
      "Choose one task to work on",
      "Set a timer for 25 minutes and work without interruption",
      "When the timer rings, take a 5-minute break",
      "Repeat — after 4 cycles, take a 15–30 minute break",
      "Track completed Pomodoros to measure your output",
    ],
    evidence:
        "Developed by Francesco Cirillo. Research shows time-boxing reduces decision fatigue and improves sustained focus.",
    authorUsername: "System",
    isSystem: true,
  ),
  StudyStrategy(
    id: "sys_spaced_rep",
    title: "Spaced Repetition",
    category: "Memory",
    summary:
        "Review material at increasing intervals to move knowledge into long-term memory.",
    steps: <String>[
      "Create flashcards or notes after your first study session",
      "Review after 1 day",
      "Review again after 3 days",
      "Review after 7 days, then 14 days",
      "Use an app like Anki to automate the schedule",
    ],
    evidence:
        "Based on Ebbinghaus's Forgetting Curve. Proven to be one of the most effective study strategies across subjects.",
    authorUsername: "System",
    isSystem: true,
  ),
  StudyStrategy(
    id: "sys_active_recall",
    title: "Active Recall",
    category: "Memory",
    summary:
        "Test yourself instead of re-reading. Retrieve information from memory to strengthen neural pathways.",
    steps: <String>[
      "Read a section once to understand the content",
      "Close the book and write down everything you remember",
      "Check what you missed and re-read only those parts",
      "Repeat the recall test after a short break",
      "Use past exam questions or quiz yourself out loud",
    ],
    evidence:
        "The 'Testing Effect' is one of the most replicated findings in cognitive psychology (Roediger & Karpicke, 2006).",
    authorUsername: "System",
    isSystem: true,
  ),
  StudyStrategy(
    id: "sys_feynman",
    title: "Feynman Technique",
    category: "Understanding",
    summary:
        "Explain a concept in simple language as if teaching it to a child. Gaps reveal gaps in understanding.",
    steps: <String>[
      "Choose the concept you want to understand",
      "Write it down and explain it in simple words — no jargon",
      "Identify where your explanation breaks down or gets vague",
      "Go back to your notes and fill those gaps",
      "Simplify further until you can explain it without notes",
    ],
    evidence:
        "Used by Nobel-winning physicist Richard Feynman. Leverages the 'Generation Effect' — explaining forces deeper encoding.",
    authorUsername: "System",
    isSystem: true,
  ),
  StudyStrategy(
    id: "sys_mind_map",
    title: "Mind Mapping",
    category: "Organisation",
    summary:
        "Create a visual diagram starting from a central concept, branching into related ideas.",
    steps: <String>[
      "Write the main topic in the centre of a blank page",
      "Draw branches for major subtopics",
      "Add smaller branches for supporting details",
      "Use colours and icons to make patterns memorable",
      "Review and redraw the map from memory after 24 hours",
    ],
    evidence:
        "Popularised by Tony Buzan. Visual organisation activates both verbal and spatial memory systems simultaneously.",
    authorUsername: "System",
    isSystem: true,
  ),
  StudyStrategy(
    id: "sys_cornell",
    title: "Cornell Notes",
    category: "Organisation",
    summary:
        "Divide your page into three sections: notes column, cue column, and a summary at the bottom.",
    steps: <String>[
      "Draw a vertical line ≈30% from the left edge; draw a horizontal line near the bottom",
      "During class/reading: take notes in the large right column",
      "Within 24 hours: write keywords and questions in the left cue column",
      "Cover the right column and use cues to recite from memory",
      "Write a 2–3 sentence summary at the bottom of the page",
    ],
    evidence:
        "Developed at Cornell University. The built-in cue column turns notes into an active recall system.",
    authorUsername: "System",
    isSystem: true,
  ),
  StudyStrategy(
    id: "sys_interleaving",
    title: "Interleaved Practice",
    category: "Focus",
    summary:
        "Mix different topics or problem types in one session instead of blocking by type.",
    steps: <String>[
      "Identify 2–3 related topics or problem types to study",
      "Create a randomised practice set mixing all types",
      "Work through problems without grouping by type",
      "Note which transitions feel most difficult — those need more work",
      "Gradually reduce the randomisation as mastery increases",
    ],
    evidence:
        "Multiple studies show interleaved practice improves long-term retention and transfer, even though it feels harder initially.",
    authorUsername: "System",
    isSystem: true,
  ),
  StudyStrategy(
    id: "sys_elaborative",
    title: "Elaborative Interrogation",
    category: "Understanding",
    summary:
        "For every fact you learn, ask 'Why is this true?' and 'How does this connect to what I already know?'",
    steps: <String>[
      "Read or listen to a new piece of information",
      "Ask: 'Why is this the case?'",
      "Ask: 'How does this connect to something I already know?'",
      "Write a short explanation linking new and existing knowledge",
      "Revisit your explanations a day later and refine them",
    ],
    evidence:
        "Rated highly effective by cognitive scientists. Promotes meaningful encoding over rote memorisation.",
    authorUsername: "System",
    isSystem: true,
  ),
];

// ── Category metadata ─────────────────────────────────────────────────────────

Color _catColor(String cat) => switch (cat) {
      "Focus"         => kOrange,
      "Memory"        => const Color(0xFF2E8B8B),
      "Understanding" => const Color(0xFF5B7DB1),
      "Organisation"  => const Color(0xFFD4853B),
      _               => kMuted,
    };

String _catEmoji(String cat) => switch (cat) {
      "Focus"         => "🎯",
      "Memory"        => "🧠",
      "Understanding" => "💡",
      "Organisation"  => "📋",
      _               => "📖",
    };

// ── Screen ────────────────────────────────────────────────────────────────────

class StrategyLibraryScreen extends StatefulWidget {
  const StrategyLibraryScreen({
    super.key,
    required this.strategies,
    required this.repo,
    this.playerLevel = 1,
  });

  final List<StudyStrategy> strategies;
  final FirestoreRepository repo;

  /// Current player level — used to highlight tier-appropriate strategies.
  final int playerLevel;

  @override
  State<StrategyLibraryScreen> createState() => _StrategyLibraryScreenState();
}

class _StrategyLibraryScreenState extends State<StrategyLibraryScreen>
    with SingleTickerProviderStateMixin {
  String _searchQuery = "";
  String _selectedCategory = "All";
  final TextEditingController _searchCtrl = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<StudyStrategy> get _allStrategies {
    final Set<String> communityIds =
        widget.strategies.map((StudyStrategy s) => s.id).toSet();
    final List<StudyStrategy> system = _systemStrategies
        .where((StudyStrategy s) => !communityIds.contains(s.id))
        .toList();
    return <StudyStrategy>[...system, ...widget.strategies];
  }

  List<String> get _categories {
    final Set<String> cats = <String>{};
    for (final StudyStrategy s in _allStrategies) {
      cats.add(s.category);
    }
    return <String>["All", ...cats.toList()..sort()];
  }

  List<StudyStrategy> get _filtered {
    return _allStrategies.where((StudyStrategy s) {
      final bool catMatch =
          _selectedCategory == "All" || s.category == _selectedCategory;
      final bool queryMatch = _searchQuery.isEmpty ||
          s.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.summary.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.category.toLowerCase().contains(_searchQuery.toLowerCase());
      return catMatch && queryMatch;
    }).toList();
  }

  /// Strategies that match the student's current XP tier.
  List<StudyStrategy> get _recommended {
    final XpTier tier = xpTierFromLevel(widget.playerLevel);
    final Set<String> tierCategories = switch (tier) {
      XpTier.beginner   => <String>{"Focus", "Organisation"},
      XpTier.developing => <String>{"Focus", "Memory"},
      XpTier.proficient => <String>{"Memory", "Understanding"},
      XpTier.advanced   => <String>{"Understanding", "Focus"},
    };
    return _systemStrategies
        .where((StudyStrategy s) => tierCategories.contains(s.category))
        .take(4)
        .toList();
  }

  void _showShareSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ShareStrategySheet(repo: widget.repo),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Strategy Library"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Tab>[
            Tab(text: "Browse"),
            Tab(text: "For You"),
          ],
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: "Share a strategy",
            onPressed: _showShareSheet,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          _BrowseTab(
            filtered: _filtered,
            categories: _categories,
            selectedCategory: _selectedCategory,
            searchCtrl: _searchCtrl,
            searchQuery: _searchQuery,
            onSearchChanged: (String val) =>
                setState(() => _searchQuery = val),
            onCategoryChanged: (String cat) =>
                setState(() => _selectedCategory = cat),
          ),
          _ForYouTab(
            recommended: _recommended,
            communityStrategies: widget.strategies,
            playerLevel: widget.playerLevel,
            onShareTap: _showShareSheet,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showShareSheet,
        icon: const Icon(Icons.share_outlined),
        label: const Text("Share Strategy"),
        backgroundColor: kDark,
        foregroundColor: Colors.white,
      ),
    );
  }
}

// ── Browse tab ────────────────────────────────────────────────────────────────

class _BrowseTab extends StatelessWidget {
  const _BrowseTab({
    required this.filtered,
    required this.categories,
    required this.selectedCategory,
    required this.searchCtrl,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onCategoryChanged,
  });

  final List<StudyStrategy> filtered;
  final List<String> categories;
  final String selectedCategory;
  final TextEditingController searchCtrl;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            controller: searchCtrl,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: "Search strategies...",
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchCtrl.clear();
                        onSearchChanged("");
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        // Category chips
        SizedBox(
          height: 40,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, int i) {
              final String cat = categories[i];
              final bool selected = selectedCategory == cat;
              return FilterChip(
                label: Text(cat),
                selected: selected,
                onSelected: (_) => onCategoryChanged(cat),
                selectedColor: kOrangeSoft,
                checkmarkColor: kOrange,
                labelStyle: TextStyle(
                  color: selected ? kDark : kMuted,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.normal,
                  fontSize: 13,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text("No strategies match your search.",
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: filtered.length,
                  itemBuilder: (_, int i) =>
                      _StrategyCard(strategy: filtered[i]),
                ),
        ),
      ],
    );
  }
}

// ── For You tab ───────────────────────────────────────────────────────────────

class _ForYouTab extends StatelessWidget {
  const _ForYouTab({
    required this.recommended,
    required this.communityStrategies,
    required this.playerLevel,
    required this.onShareTap,
  });

  final List<StudyStrategy> recommended;
  final List<StudyStrategy> communityStrategies;
  final int playerLevel;
  final VoidCallback onShareTap;

  @override
  Widget build(BuildContext context) {
    final XpTier tier = xpTierFromLevel(playerLevel);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: <Widget>[
        // Tier banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF1A1410), Color(0xFF2D2318)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: <Widget>[
              const Text("🎮", style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Level $playerLevel · ${xpTierLabel(tier)}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tierDescription(tier),
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Recommended for tier
        Text(
          "Recommended for Your Level",
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          "These techniques match how ${xpTierLabel(tier)} learners study best.",
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.95,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: recommended.length,
          itemBuilder: (_, int i) =>
              _StrategyGridCard(strategy: recommended[i]),
        ),
        const SizedBox(height: 24),

        // Community strategies
        if (communityStrategies.isNotEmpty) ...<Widget>[
          Text(
            "Shared by Students",
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            "${communityStrategies.length} strategies shared so far.",
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          ...communityStrategies
              .take(5)
              .map((StudyStrategy s) => _StrategyCard(strategy: s)),
        ] else ...<Widget>[
          // Empty state CTA
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kOrangeSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kOrange.withOpacity(0.2)),
            ),
            child: Column(
              children: <Widget>[
                const Text("📖", style: TextStyle(fontSize: 36)),
                const SizedBox(height: 8),
                const Text(
                  "Be the first to share a strategy!",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  "Share what works for you and earn +10 XP.",
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                DarkPillButton(
                  onPressed: onShareTap,
                  label: "Share a Strategy",
                  icon: Icons.share_outlined,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _tierDescription(XpTier tier) => switch (tier) {
        XpTier.beginner   =>
          "Building foundations — focus on structure and consistency.",
        XpTier.developing =>
          "Growing fast — memory techniques will unlock new potential.",
        XpTier.proficient =>
          "Solid habits — time for deeper learning strategies.",
        XpTier.advanced   =>
          "High performer — optimise for mastery and long-term retention.",
      };
}

// ── Strategy grid card (compact, For You tab) ─────────────────────────────────

class _StrategyGridCard extends StatelessWidget {
  const _StrategyGridCard({required this.strategy});
  final StudyStrategy strategy;

  @override
  Widget build(BuildContext context) {
    final Color color = _catColor(strategy.category);
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(_catEmoji(strategy.category),
                    style: const TextStyle(fontSize: 22)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    strategy.category,
                    style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              strategy.title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                strategy.summary,
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StrategyDetailSheet(strategy: strategy),
    );
  }
}

// ── Strategy list card (Browse tab) ──────────────────────────────────────────

class _StrategyCard extends StatelessWidget {
  const _StrategyCard({required this.strategy});
  final StudyStrategy strategy;

  @override
  Widget build(BuildContext context) {
    final Color catColor = _catColor(strategy.category);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: catColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              _catEmoji(strategy.category),
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                strategy.title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                strategy.category,
                style: TextStyle(
                    fontSize: 11,
                    color: catColor,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            strategy.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        children: <Widget>[
          _StrategyDetailBody(strategy: strategy, catColor: catColor),
        ],
      ),
    );
  }
}

// ── Strategy detail (shared between card expand and bottom sheet) ─────────────

class _StrategyDetailSheet extends StatelessWidget {
  const _StrategyDetailSheet({required this.strategy});
  final StudyStrategy strategy;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      builder: (_, ScrollController ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: <Widget>[
              Text(_catEmoji(strategy.category),
                  style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(strategy.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17)),
                    Text(strategy.category,
                        style: TextStyle(
                            color: _catColor(strategy.category),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(strategy.summary,
              style: const TextStyle(fontSize: 13, color: Colors.black87)),
          _StrategyDetailBody(
              strategy: strategy,
              catColor: _catColor(strategy.category)),
        ],
      ),
    );
  }
}

class _StrategyDetailBody extends StatelessWidget {
  const _StrategyDetailBody({
    required this.strategy,
    required this.catColor,
  });

  final StudyStrategy strategy;
  final Color catColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (strategy.steps.isNotEmpty) ...<Widget>[
            const Text(
              "HOW TO USE IT",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            ...strategy.steps.asMap().entries.map(
                  (MapEntry<int, String> e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 22,
                          height: 22,
                          margin: const EdgeInsets.only(right: 10, top: 1),
                          decoration: BoxDecoration(
                            color: catColor,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Center(
                            child: Text(
                              "${e.key + 1}",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(e.value,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          if (strategy.evidence.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.science_outlined,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      strategy.evidence,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!strategy.isSystem) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                const Icon(Icons.person_outline, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  "Shared by @${strategy.authorUsername}",
                  style:
                      const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Share strategy bottom sheet ───────────────────────────────────────────────

class _ShareStrategySheet extends StatefulWidget {
  const _ShareStrategySheet({required this.repo});
  final FirestoreRepository repo;

  @override
  State<_ShareStrategySheet> createState() => _ShareStrategySheetState();
}

class _ShareStrategySheetState extends State<_ShareStrategySheet> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _summaryCtrl = TextEditingController();
  final TextEditingController _stepsCtrl = TextEditingController();
  final TextEditingController _evidenceCtrl = TextEditingController();
  String _category = "Focus";
  bool _saving = false;

  static const List<String> _categories = <String>[
    "Focus",
    "Memory",
    "Understanding",
    "Organisation",
    "General",
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _stepsCtrl.dispose();
    _evidenceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String title = _titleCtrl.text.trim();
    final String summary = _summaryCtrl.text.trim();
    final String stepsRaw = _stepsCtrl.text.trim();
    if (title.isEmpty || summary.isEmpty || stepsRaw.isEmpty) return;

    final List<String> steps = stepsRaw
        .split("\n")
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();

    setState(() => _saving = true);
    try {
      await widget.repo.addStrategy(
        title: title,
        category: _category,
        summary: summary,
        steps: steps,
        evidence: _evidenceCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Strategy shared! +10 XP ✅"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to share strategy: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Share a Study Strategy",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              "Share what works for you and earn +10 XP.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: "Strategy title *",
                hintText: "e.g. Two-Pass Reading Method",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _category,
              items: _categories
                  .map((String c) => DropdownMenuItem<String>(
                      value: c, child: Text(c)))
                  .toList(),
              onChanged: (String? val) =>
                  setState(() => _category = val ?? "Focus"),
              decoration: const InputDecoration(
                labelText: "Category",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _summaryCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Summary *",
                hintText: "One-paragraph overview of the strategy",
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _stepsCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: "Steps (one per line) *",
                hintText: "Step 1\nStep 2\nStep 3",
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _evidenceCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Evidence / Why it works (optional)",
                hintText: "Research, author, or personal experience",
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: DarkPillButton(
                onPressed: _saving ? null : _submit,
                loading: _saving,
                label: "Share Strategy",
                icon: Icons.share_outlined,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
