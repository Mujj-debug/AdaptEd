import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "design_tokens.dart";
import "models/app_models.dart";
import "models/weekly_challenge_models.dart";
import "screens/screens.dart";
import "services/firestore_repository.dart";

class AdaptEdApp extends StatelessWidget {
  const AdaptEdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "AdaptEd",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kOrange,
          brightness: Brightness.light,
          surface: kSurface,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: kBg,
          foregroundColor: kDark,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: kDark,
            letterSpacing: -0.3,
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: kDark,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: kDark,
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  FirestoreRepository? _repo;
  String? _currentUid;

  /// Tracks whether we've already shown the welcome splash this session.
  /// Reset to false whenever the user UID changes (new login).
  bool _shownWelcomeSplash = false;
  String? _splashTrackedUid;

  FirestoreRepository _getRepo(String uid) {
    if (_repo == null || _currentUid != uid) {
      _repo = FirestoreRepository(uid);
      _currentUid = uid;
    }
    return _repo!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (_, AsyncSnapshot<User?> authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting &&
            !authSnap.hasData) {
          return const LoadingScreen();
        }
        final User? user = authSnap.data;

        if (user == null) {
          return const AuthScreen();
        }

        if (!user.emailVerified) {
          return _EmailVerificationGate(user: user);
        }

        final FirestoreRepository repo = _getRepo(user.uid);

        // Reset splash flag if this is a new login (uid changed)
        if (_splashTrackedUid != user.uid) {
          _shownWelcomeSplash = false;
          _splashTrackedUid = user.uid;
        }

        return StreamBuilder<Map<String, dynamic>>(
          stream: repo.watchUserMeta(),
          builder: (_, AsyncSnapshot<Map<String, dynamic>> metaSnap) {
            if (metaSnap.data == null &&
                metaSnap.connectionState == ConnectionState.waiting) {
              return const LoadingScreen();
            }

            final Map<String, dynamic> meta =
                metaSnap.data ?? <String, dynamic>{};

            final bool done =
                (meta["hasCompletedAssessment"] ?? false) as bool;

            if (!done) {
              return PopScope(
                canPop: false,
                child: AssessmentOnboardingScreen(repo: repo),
              );
            }

            // ── Splash 2: post-login welcome (once per session) ─────────────
            if (!_shownWelcomeSplash) {
              _shownWelcomeSplash = true;
              final String displayName =
                  user.displayName?.split(' ').first ?? 'there';
              return _WelcomeSplashGate(
                displayName: displayName,
                onComplete: () => setState(() {}),
              );
            }

            return _MainAppShell(
              tab: _tab,
              onTab: (int i) => setState(() => _tab = i),
              repo: repo,
              userMeta: meta,
              currentUid: user.uid,
            );
          },
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WELCOME SPLASH GATE — Splash 2
// Wraps WelcomeSplashScreen and auto-dismisses after 2.5 s, then calls
// onComplete so the parent AppShell re-renders into _MainAppShell.
// ══════════════════════════════════════════════════════════════════════════════

class _WelcomeSplashGate extends StatefulWidget {
  const _WelcomeSplashGate({
    required this.displayName,
    required this.onComplete,
  });
  final String displayName;
  final VoidCallback onComplete;

  @override
  State<_WelcomeSplashGate> createState() => _WelcomeSplashGateState();
}

class _WelcomeSplashGateState extends State<_WelcomeSplashGate> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  Widget build(BuildContext context) =>
      WelcomeSplashScreen(displayName: widget.displayName);
}

// ══════════════════════════════════════════════════════════════════════════════
// EMAIL VERIFICATION GATE
// ══════════════════════════════════════════════════════════════════════════════

class _EmailVerificationGate extends StatefulWidget {
  const _EmailVerificationGate({required this.user});
  final User user;

  @override
  State<_EmailVerificationGate> createState() =>
      _EmailVerificationGateState();
}

class _EmailVerificationGateState extends State<_EmailVerificationGate> {
  bool _resending = false;
  bool _sent = false;
  bool _checking = false;
  String? _checkError;

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await widget.user.sendEmailVerification();
      setState(() => _sent = true);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _checkVerification() async {
    setState(() {
      _checking = true;
      _checkError = null;
    });
    try {
      await widget.user.reload();
      final User? refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed != null && refreshed.emailVerified) {
        await FirebaseAuth.instance.signOut();
      } else {
        setState(() {
          _checkError =
              "Email not verified yet. Please click the link in your inbox first.";
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: <Widget>[
          const FloatingPills(),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: LocketCard(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SunMascot(size: 120),
                      const SizedBox(height: 12),
                      const Text("Verify your email ✉️",
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: kDark,
                              letterSpacing: -0.4)),
                      const SizedBox(height: 10),
                      Text(
                        "We sent a verification link to ${widget.user.email}.\n\n"
                        "Click the link, then press continue. "
                        "You'll be asked to sign in again after verification.",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: kMuted, fontSize: 13, height: 1.6)),
                      const SizedBox(height: 16),
                      LocketBanner.info(
                        "Check your spam folder if you don't see it.",
                      ),
                      const SizedBox(height: 8),
                      if (_sent)
                        LocketBanner.success("Verification email resent!"),
                      if (_checkError != null) ...<Widget>[
                        const SizedBox(height: 8),
                        LocketBanner.error(_checkError!),
                      ],
                      const SizedBox(height: 20),
                      DarkPillButton(
                        label: "I've verified — continue",
                        loading: _checking,
                        onPressed: _checkVerification,
                        icon: Icons.check_circle_outline_rounded,
                      ),
                      const SizedBox(height: 10),
                      OutlinePillButton(
                        label: _resending ? "Sending..." : "Resend email",
                        onPressed: _resending ? null : _resend,
                        icon: Icons.mail_outline_rounded,
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => FirebaseAuth.instance.signOut(),
                        child: const Text("Sign out",
                            style: TextStyle(
                                fontSize: 13,
                                color: kOrange,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN APP SHELL
// ══════════════════════════════════════════════════════════════════════════════

class _MainAppShell extends StatefulWidget {
  const _MainAppShell({
    required this.tab,
    required this.onTab,
    required this.repo,
    required this.userMeta,
    required this.currentUid,
  });

  final int tab;
  final ValueChanged<int> onTab;
  final FirestoreRepository repo;
  final Map<String, dynamic> userMeta;
  final String currentUid;

  @override
  State<_MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<_MainAppShell>
    with WidgetsBindingObserver {
  UserProfile _profile = defaultProfile();
  List<TaskItem> _tasks = <TaskItem>[];
  List<MoodLog> _moods = <MoodLog>[];
  List<StudySession> _sessions = <StudySession>[];
  List<StudyStrategy> _strategies = <StudyStrategy>[];
  List<WeeklyChallenge> _weeklyChallenges = <WeeklyChallenge>[];
  GamificationState _game =
      GamificationState(xp: 0, streakDays: 0, badges: <String>[]);
  ActiveSession? _activeSession;

  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subs.addAll(<StreamSubscription<dynamic>>[
      widget.repo
          .watchProfile()
          .listen((UserProfile p) => setState(() => _profile = p)),
      widget.repo
          .watchTasks()
          .listen((List<TaskItem> t) => setState(() => _tasks = t)),
      widget.repo
          .watchMoods()
          .listen((List<MoodLog> m) => setState(() => _moods = m)),
      widget.repo
          .watchSessions()
          .listen((List<StudySession> s) => setState(() => _sessions = s)),
      widget.repo
          .watchStrategies()
          .listen(
              (List<StudyStrategy> s) => setState(() => _strategies = s)),
      widget.repo
          .watchGamification()
          .listen((GamificationState g) => setState(() => _game = g)),
      widget.repo
          .watchActiveSession()
          .listen(
              (ActiveSession? a) => setState(() => _activeSession = a)),
      widget.repo
          .watchWeeklyChallenges()
          .listen((List<WeeklyChallenge> c) =>
              setState(() => _weeklyChallenges = c)),
    ]);

    widget.repo.ensureWeeklyChallengesAssigned();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final StreamSubscription<dynamic> sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.repo.ensureWeeklyChallengesAssigned();
    }
  }

  // ── Tab indices ────────────────────────────────────────────────────────────
  //
  //  0  Home       — DashboardScreen
  //  1  Tasks      — TasksScreen
  //  2  Study Hub  — AiStudyHubScreen  ← NEW
  //  3  AI         — InsightsScreen
  //  4  Library    — StrategyLibraryScreen
  //  5  XP         — GamificationScreen
  //  6  Profile    — ProfileScreen

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // ── Active session resume banner ─────────────────────────────
            if (_activeSession != null)
              _SessionResumeBanner(
                session: _activeSession!,
                onResume: () => widget.onTab(0),
              ),
            // ── Badge unlock notification ────────────────────────────────
            if (_game.pendingBadges.isNotEmpty)
              _BadgeUnlockBanner(
                badges: _game.pendingBadges,
                onDismiss: () => widget.repo.clearPendingBadges(),
              ),
            Expanded(
              child: IndexedStack(
                index: widget.tab,
                children: <Widget>[
                  // 0 — Home
                  DashboardScreen(
                    profile: _profile,
                    tasks: _tasks,
                    moods: _moods,
                    game: _game,
                    sessions: _sessions,
                    weeklyChallenges: _weeklyChallenges,
                    repo: widget.repo,
                    onStartStudy: () => widget.onTab(2),
                    onGoToXp: () => widget.onTab(5),
                    assessmentFailed: _isAssessmentFailed(widget.userMeta),
                    onGoToInsights: () => widget.onTab(3),
                  ),
                  // 1 — Tasks
                  TasksScreen(
                    tasks: _tasks,
                    profile: _profile,
                    moods: _moods,
                    repo: widget.repo,
                    userMeta: widget.userMeta,
                  ),
                  // 2 — Study Hub (NEW)
                  AiStudyHubScreen(
                    profile: _profile,
                    tasks: _tasks,
                    repo: widget.repo,
                  ),
                  // 3 — AI Insights
                  InsightsScreen(
                    profile: _profile,
                    tasks: _tasks,
                    moods: _moods,
                    sessions: _sessions,
                    repo: widget.repo,
                    userMeta: widget.userMeta,
                  ),
                  // 4 — Strategy Library
                  StrategyLibraryScreen(
                    strategies: _strategies,
                    repo: widget.repo,
                  ),
                  // 5 — XP / Gamification
                  GamificationScreen(
                    game: _game,
                    weeklyChallenges: _weeklyChallenges,
                  ),
                  // 6 — Profile
                  ProfileScreen(profile: _profile, repo: widget.repo),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: kSurface,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: kDark.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                _navItem(0, Icons.home_rounded, Icons.home_outlined, "Home"),
                _navItem(1, Icons.checklist_rounded, Icons.checklist_rtl, "Tasks"),
                // ── NEW Study Hub tab ───────────────────────────────────────
                _navItem(
                  2,
                  Icons.auto_awesome_rounded,
                  Icons.auto_awesome_outlined,
                  "Study",
                  highlight: true,
                ),
                _navItem(3, Icons.auto_awesome, Icons.auto_awesome_outlined, "AI"),
                _navItem(4, Icons.menu_book_rounded, Icons.menu_book_outlined, "Library"),
                _navItem(5, Icons.emoji_events_rounded, Icons.emoji_events_outlined, "XP"),
                _navItem(6, Icons.person_rounded, Icons.person_outline, "Profile"),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(
    int index,
    IconData activeIcon,
    IconData inactiveIcon,
    String label, {
    bool highlight = false,
  }) {
    final bool active = widget.tab == index;

    // The Study Hub tab gets a special orange dot badge when inactive
    // to signal it's a featured feature.
    return GestureDetector(
      onTap: () => widget.onTab(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: active
            ? BoxDecoration(
                color: kOrangeSoft,
                borderRadius: BorderRadius.circular(16),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Icon(
                  active ? activeIcon : inactiveIcon,
                  size: 22,
                  color: active ? kOrange : kMuted,
                ),
                // Orange dot badge on Study Hub when inactive
                if (highlight && !active)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: kOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? kDark : kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns true when AI assessment analysis has an error and needs retry.
  static bool _isAssessmentFailed(Map<String, dynamic> meta) {
    final dynamic aiAnalysis = meta["aiAnalysis"];
    if (aiAnalysis is! Map) return false;
    if ((aiAnalysis as Map).isEmpty) return false;
    if (aiAnalysis["analysisError"] == true) return true;
    return !aiAnalysis.containsKey("productivityIdentity");
  }
}

// ── Active session resume banner ──────────────────────────────────────────────

class _SessionResumeBanner extends StatelessWidget {
  const _SessionResumeBanner({
    required this.session,
    required this.onResume,
  });

  final ActiveSession session;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onResume,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: kOrangeSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kOrange.withOpacity(0.3)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.timer_outlined,
                color: kOrange, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Resume: ${session.taskName}",
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    "${session.pomodorosCompleted}/${session.pomodorosTarget} Pomodoros completed",
                    style: const TextStyle(fontSize: 11, color: kMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: kOrange, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Badge unlock banner ───────────────────────────────────────────────────────

class _BadgeUnlockBanner extends StatelessWidget {
  const _BadgeUnlockBanner({
    required this.badges,
    required this.onDismiss,
  });

  final List<String> badges;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final String label = badges.length == 1
        ? "Badge unlocked: ${badges.first}"
        : "${badges.length} badges unlocked!";

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kYellow.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kYellow.withOpacity(0.6)),
      ),
      child: Row(
        children: <Widget>[
          const Text("🏅", style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kDark),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kDark,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text("Dismiss",
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
