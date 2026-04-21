import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "../services/firestore_repository.dart";

// ══════════════════════════════════════════════════════════════════════════════
// AUTH SCREEN  (login / register — unchanged)
// ══════════════════════════════════════════════════════════════════════════════

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _loading = false;
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _username = TextEditingController();
  String? _error;
  bool _awaitingVerification = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isLogin) {
        final UserCredential cred =
            await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text.trim(),
        );
        if (cred.user != null && !cred.user!.emailVerified) {
          await FirebaseAuth.instance.signOut();
          setState(() {
            _error =
                "Email not verified. Please check your inbox and click the link, then log in again.";
          });
        }
      } else {
        final String username = _username.text.trim();
        if (username.isEmpty) {
          setState(() {
            _error = "Please enter a display name.";
            _loading = false;
          });
          return;
        }
        if (username.length < 3) {
          setState(() {
            _error = "Display name must be at least 3 characters.";
            _loading = false;
          });
          return;
        }

        final UserCredential cred =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text.trim(),
        );

        await cred.user?.updateDisplayName(username);
        if (cred.user != null) {
          await FirestoreRepository(cred.user!.uid).saveUsername(username);
        }

        try {
          await cred.user?.sendEmailVerification();
          setState(() => _awaitingVerification = true);
        } catch (sendError) {
          setState(() =>
              _error = "Account created but verification email failed: $sendError");
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = "$e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_awaitingVerification) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.mark_email_unread_outlined,
                        size: 64, color: Colors.deepPurple),
                    const SizedBox(height: 16),
                    Text("Check your inbox",
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(
                      "We sent a verification link to ${_email.text.trim()}.\n\n"
                      "Click the link in that email, then come back here and log in.",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => setState(() {
                        _awaitingVerification = false;
                        _isLogin = true;
                      }),
                      child: const Text("Go to Login"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.school_outlined,
                      size: 48, color: Colors.deepPurple),
                  const SizedBox(height: 8),
                  Text(
                    _isLogin ? "Welcome back" : "Create your account",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: "Password",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  if (!_isLogin) ...<Widget>[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _username,
                      decoration: const InputDecoration(
                        labelText: "Display name",
                        hintText: "How others will see you",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                  ],
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(_error!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: Text(_loading
                          ? "Please wait..."
                          : (_isLogin ? "Log in" : "Create Account")),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _isLogin = !_isLogin;
                              _error = null;
                            }),
                    child: Text(_isLogin
                        ? "New here? Register"
                        : "Already registered? Log in"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ASSESSMENT — DATA MODEL
// ══════════════════════════════════════════════════════════════════════════════

/// A single high-signal onboarding question (always choice-based for speed).
class _Q {
  const _Q(this.id, this.emoji, this.prompt, this.options);
  final String id;
  final String emoji;
  final String prompt;
  final List<String> options;
}

/// The 5 high-signal questions.  Each maps cleanly to a profiling dimension.
///
/// DB schema produced (users/{uid} document):
///   study_peak_time          → string  (raw answer)
///   focus_session_length     → string  (raw answer)
///   study_challenge          → string  (raw answer)
///   work_style               → string  (raw answer)
///   recovery_style           → string  (raw answer)
///
///   — Legacy-compatible keys written alongside so buildProfileFromAssessment
///     continues to work without changes to other layers —
///   energy_morning_productive  → int 1-5
///   energy_night_productive    → int 1-5
///   focus_duration             → int 1-5
///   social_after_interaction_energy → int 1-5
///   social_work_preference     → string
///   focus_distraction_frequency → int 1-5
///   motivation_routine_consistency → int 1-5
///   focus_study_style          → string
///   rest_guilt_when_resting    → int 1-5
///   lifestyle_exercise_frequency → int 1-5
///   rest_sleep_quality         → int 1-5
///
/// Subjects sub-collection  users/{uid}/subjects/{slug}:
///   name                 → string
///   strengthScore        → int   0-100  (neutral start: 50)
///   completionRate       → double 0.0-1.0
///   totalMinutes         → int
///   totalTasksCreated    → int
///   totalTasksCompleted  → int
///   lastStudiedAt        → Timestamp?
///   createdAt            → Timestamp

const List<_Q> _kQuestions = <_Q>[
  _Q(
    "study_peak_time",
    "🕐",
    "When do you focus best?",
    <String>[
      "Morning (6 am – 12 pm)",
      "Afternoon (12 pm – 5 pm)",
      "Evening (5 pm – 9 pm)",
      "Night (9 pm+)",
    ],
  ),
  _Q(
    "focus_session_length",
    "⏱️",
    "How long can you study before needing a break?",
    <String>[
      "Under 20 minutes",
      "20 – 30 minutes",
      "30 – 50 minutes",
      "50 + minutes",
    ],
  ),
  _Q(
    "study_challenge",
    "🎯",
    "What is your biggest study challenge?",
    <String>[
      "Staying focused",
      "Getting started",
      "Being consistent",
      "Understanding the material",
    ],
  ),
  _Q(
    "work_style",
    "🧑‍💻",
    "You study best when:",
    <String>[
      "Alone in silence",
      "Alone with music",
      "With study partners",
      "It depends on the task",
    ],
  ),
  _Q(
    "recovery_style",
    "🔋",
    "After a study session, you recover by:",
    <String>[
      "Taking a short walk",
      "Resting or napping",
      "Switching to a different subject",
      "Socializing with others",
    ],
  ),
];

/// Common subjects shown as quick-pick chips on the subject step.
const List<String> _kCommonSubjects = <String>[
  "Mathematics",
  "Physics",
  "Chemistry",
  "Biology",
  "History",
  "English",
  "Filipino",
  "Computer Science",
  "Economics",
  "Philosophy",
  "Statistics",
  "Literature",
  "Psychology",
  "Engineering",
];

// ══════════════════════════════════════════════════════════════════════════════
// ASSESSMENT ONBOARDING SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class AssessmentOnboardingScreen extends StatefulWidget {
  const AssessmentOnboardingScreen({super.key, required this.repo});
  final FirestoreRepository repo;

  @override
  State<AssessmentOnboardingScreen> createState() =>
      _AssessmentOnboardingScreenState();
}

class _AssessmentOnboardingScreenState
    extends State<AssessmentOnboardingScreen> {
  // step 0 = welcome splash
  // steps 1-5 = one question each
  // step 6 = subject picker
  int _step = 0;

  final Map<String, String> _answers = <String, String>{};
  final List<String> _selectedSubjects = <String>[];
  final TextEditingController _customSubjectCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  static const int _totalContentSteps = 6; // questions(5) + subjects(1)

  @override
  void dispose() {
    _customSubjectCtrl.dispose();
    super.dispose();
  }

  // ── Answer → legacy-compatible map ─────────────────────────────────────────

  Map<String, dynamic> _buildCompatibleAnswers() {
    final Map<String, dynamic> map = Map<String, dynamic>.from(_answers);

    // 1. Peak time → morning/night productivity scales
    switch (_answers["study_peak_time"]) {
      case "Morning (6 am – 12 pm)":
        map["energy_morning_productive"] = 5;
        map["energy_night_productive"] = 1;
        map["energy_peak_time"] = "Morning";
      case "Afternoon (12 pm – 5 pm)":
        map["energy_morning_productive"] = 3;
        map["energy_night_productive"] = 2;
        map["energy_peak_time"] = "Afternoon";
      case "Evening (5 pm – 9 pm)":
        map["energy_morning_productive"] = 2;
        map["energy_night_productive"] = 4;
        map["energy_peak_time"] = "Night";
      case "Night (9 pm+)":
        map["energy_morning_productive"] = 1;
        map["energy_night_productive"] = 5;
        map["energy_peak_time"] = "Night";
    }

    // 2. Session length → focus_duration scale (1–5)
    map["focus_duration"] = switch (_answers["focus_session_length"]) {
      "Under 20 minutes" => 1,
      "20 – 30 minutes"  => 2,
      "30 – 50 minutes"  => 4,
      "50 + minutes"     => 5,
      _                  => 3,
    };
    map["focus_study_style"] = (map["focus_duration"] as int) >= 4
        ? "Long deep sessions"
        : "Short bursts (Pomodoro)";

    // 3. Study challenge → distraction / motivation signals
    map["focus_distraction_frequency"] =
        _answers["study_challenge"] == "Staying focused" ? 4 : 2;
    map["motivation_routine_consistency"] =
        _answers["study_challenge"] == "Being consistent" ? 2 : 3;

    // 4. Work style → social energy
    map["social_after_interaction_energy"] = switch (_answers["work_style"]) {
      "With study partners"       => 4,
      "It depends on the task"    => 3,
      _                           => 2, // alone variants
    };
    map["social_work_preference"] = switch (_answers["work_style"]) {
      "With study partners"    => "With others",
      "It depends on the task" => "Depends",
      _                        => "Alone",
    };

    // 5. Recovery style → rest / exercise signals
    map["rest_guilt_when_resting"] =
        _answers["recovery_style"] == "Resting or napping" ? 2 : 3;
    map["lifestyle_exercise_frequency"] =
        _answers["recovery_style"] == "Taking a short walk" ? 4 : 2;
    map["rest_sleep_quality"] = 3; // neutral — not assessed at onboarding

    // Subject list stored alongside answers for AI context
    map["subjects"] = _selectedSubjects;

    return map;
  }

  // ── Subject helpers ─────────────────────────────────────────────────────────

  void _toggleSubject(String subject) {
    setState(() {
      if (_selectedSubjects.contains(subject)) {
        _selectedSubjects.remove(subject);
      } else {
        _selectedSubjects.add(subject);
      }
    });
  }

  void _addCustomSubject() {
    final String val = _customSubjectCtrl.text.trim();
    if (val.isEmpty) return;
    final String capitalised =
        val[0].toUpperCase() + val.substring(1).toLowerCase();
    if (_selectedSubjects.contains(capitalised)) {
      _customSubjectCtrl.clear();
      return;
    }
    setState(() {
      _selectedSubjects.add(capitalised);
      _customSubjectCtrl.clear();
    });
  }

  // ── Save ────────────────────────────────────────────────────────────────────

  Future<void> _finish() async {
    if (_selectedSubjects.isEmpty) {
      setState(() => _error = "Please add at least one subject.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final Map<String, dynamic> compatible = _buildCompatibleAnswers();
      await widget.repo.completeAssessment(answers: compatible);

      // Seed subject tracking documents
      // users/{uid}/subjects/{slug} — one doc per subject
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final WriteBatch batch = FirebaseFirestore.instance.batch();
        for (final String subject in _selectedSubjects) {
          final String slug =
              subject.toLowerCase().replaceAll(RegExp(r"\s+"), "_");
          final DocumentReference<Map<String, dynamic>> ref = FirebaseFirestore
              .instance
              .collection("users")
              .doc(uid)
              .collection("subjects")
              .doc(slug);
          batch.set(
            ref,
            <String, dynamic>{
              "name": subject,
              // Profiling dimensions (read-only, updated by behavior engine)
              "strengthScore": 50,         // 0–100; neutral start
              "completionRate": 0.0,        // completed / created
              "totalMinutes": 0,            // accumulated study time
              "totalTasksCreated": 0,
              "totalTasksCompleted": 0,
              "lastStudiedAt": null,
              "createdAt": FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      }
    } catch (e) {
      if (mounted) setState(() => _error = "Something went wrong. Please try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _goNext() {
    if (_step >= 1 && _step <= 5) {
      final String qId = _kQuestions[_step - 1].id;
      if (!_answers.containsKey(qId)) return; // must select before proceeding
    }
    setState(() => _step += 1);
  }

  void _goBack() {
    if (_step > 0) setState(() => _step -= 1);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_step == 0) return _buildWelcome(context);
    if (_step >= 1 && _step <= 5) return _buildQuestion(context, _step - 1);
    return _buildSubjectPicker(context);
  }

  // ── Step 0: Welcome splash ──────────────────────────────────────────────────

  Widget _buildWelcome(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text("🎓", style: TextStyle(fontSize: 64)),
                const SizedBox(height: 24),
                Text(
                  "Let's set up your profile",
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  "5 quick questions + your subjects.\n"
                  "We'll personalise your task priorities,\n"
                  "focus sessions, and study insights.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15, color: Colors.grey.shade600, height: 1.5),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _pillBadge("⏱️  Under 2 min"),
                    const SizedBox(width: 8),
                    _pillBadge("🔒  Private"),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => setState(() => _step = 1),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text("Let's go →",
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pillBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: Colors.deepPurple.shade700,
              fontWeight: FontWeight.w500)),
    );
  }

  // ── Steps 1-5: Questions ────────────────────────────────────────────────────

  Widget _buildQuestion(BuildContext context, int qi) {
    final _Q q = _kQuestions[qi];
    final int stepNumber = qi + 1; // 1-indexed
    final String? selected = _answers[q.id];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Progress
              Row(
                children: <Widget>[
                  Text(
                    "Step $stepNumber of $_totalContentSteps",
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Text(
                    "$stepNumber / $_totalContentSteps",
                    style: TextStyle(
                        fontSize: 12, color: Colors.deepPurple.shade400),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: stepNumber / _totalContentSteps,
                  minHeight: 6,
                  backgroundColor: Colors.deepPurple.shade50,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.deepPurple.shade400),
                ),
              ),
              const SizedBox(height: 32),
              // Emoji + question
              Text(q.emoji, style: const TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(
                q.prompt,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold, height: 1.3),
              ),
              const SizedBox(height: 24),
              // Options
              Expanded(
                child: ListView.separated(
                  itemCount: q.options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, int i) {
                    final String option = q.options[i];
                    final bool isSelected = selected == option;
                    return _OptionTile(
                      label: option,
                      selected: isSelected,
                      onTap: () =>
                          setState(() => _answers[q.id] = option),
                    );
                  },
                ),
              ),
              // Navigation
              Row(
                children: <Widget>[
                  if (stepNumber > 1)
                    OutlinedButton(
                      onPressed: _goBack,
                      child: const Text("Back"),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: selected != null ? _goNext : null,
                    child: Text(stepNumber == 5 ? "Next: Subjects →" : "Next →"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 6: Subject picker ──────────────────────────────────────────────────

  Widget _buildSubjectPicker(BuildContext context) {
    // Subjects from common list that aren't already selected
    final List<String> unselected = _kCommonSubjects
        .where((String s) => !_selectedSubjects.contains(s))
        .toList();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Progress
              Row(
                children: <Widget>[
                  Text(
                    "Step 6 of $_totalContentSteps",
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Text(
                    "6 / $_totalContentSteps",
                    style: TextStyle(
                        fontSize: 12, color: Colors.deepPurple.shade400),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 1.0,
                  minHeight: 6,
                  backgroundColor: Colors.deepPurple.shade50,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.deepPurple.shade400),
                ),
              ),
              const SizedBox(height: 32),
              const Text("📚", style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(
                "What subjects are you studying?",
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                "Select all that apply. We'll track your performance per subject.",
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),

              // Selected subjects
              if (_selectedSubjects.isNotEmpty) ...<Widget>[
                Text("Selected",
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.deepPurple.shade700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedSubjects
                      .map(
                        (String s) => Chip(
                          label: Text(s),
                          backgroundColor: Colors.deepPurple.shade100,
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () =>
                              setState(() => _selectedSubjects.remove(s)),
                          labelStyle: TextStyle(
                              color: Colors.deepPurple.shade800,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
              ],

              // Quick-pick chips
              if (unselected.isNotEmpty) ...<Widget>[
                Text("Quick pick",
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: unselected
                      .map(
                        (String s) => ActionChip(
                          label: Text(s),
                          onPressed: () => _toggleSubject(s),
                          backgroundColor: Colors.grey.shade100,
                          labelStyle:
                              const TextStyle(fontSize: 13),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
              ],

              // Custom subject input
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _customSubjectCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: "Add another subject…",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addCustomSubject(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _addCustomSubject,
                    icon: const Icon(Icons.add),
                    tooltip: "Add subject",
                  ),
                ],
              ),

              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],

              const Spacer(),

              // Navigation
              Row(
                children: <Widget>[
                  OutlinedButton(
                    onPressed: _saving ? null : _goBack,
                    child: const Text("Back"),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : () {
                            if (_selectedSubjects.isEmpty) {
                              setState(() => _error =
                                  "Please select at least one subject.");
                              return;
                            }
                            _finish();
                          },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text("Finish setup 🎉",
                            style: TextStyle(fontSize: 15)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple.shade50 : Colors.white,
          border: Border.all(
            color: selected
                ? Colors.deepPurple.shade400
                : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: selected
                      ? Colors.deepPurple.shade700
                      : Colors.black87,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded,
                  color: Colors.deepPurple.shade400, size: 22),
          ],
        ),
      ),
    );
  }
}
