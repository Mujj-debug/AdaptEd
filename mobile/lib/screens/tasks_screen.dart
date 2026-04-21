import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:url_launcher/url_launcher.dart";

import "../design_tokens.dart";
import "../models/app_models.dart";
import "../services/firestore_repository.dart";
import "focus_mode_screen.dart";

// ══════════════════════════════════════════════════════════════════════════════
// LAYER 2 — TASK INTELLIGENCE
//
// Changes in this file:
//  1. AUTO-TRIGGER: AI analysis fires immediately on every task save.
//     No manual "Analyze" step — the moment the user taps "Add & Analyze",
//     the repo.addTask() pipeline runs: priority calc → AI analysis → Firestore
//     write, all in one awaited call. A loading snackbar shows during analysis.
//
//  2. CONFLICT DETECTION: _detectConflicts() runs locally (zero network cost)
//     BEFORE the task is saved. Three signal types are checked:
//       a. Deadline collision  — another active task due ±24 h of new deadline
//       b. Subject overload    — 3+ pending tasks for the same subject
//       c. Dense window        — 3+ active tasks due within ±36 h of deadline
//     If conflicts are found, a warning dialog lets the user decide to proceed
//     or cancel — never blocks silently.
//
//  3. SUBJECT-AWARE AI: Subject selection is now a dropdown populated from
//     the user's onboarded subjects (users/{uid}/subjects). When a subject is
//     chosen its strength score and completion rate are loaded from Firestore
//     and appended to the task description before the AI call, so the AI can
//     adapt tone and difficulty accordingly:
//       • Low strength (< 40)   → AI uses foundational language, more steps
//       • High strength (> 70)  → AI uses advanced framing, fewer basics
//       • Low completion rate   → AI flags consistency risk in advice
//
// Firestore paths read in this layer (read-only):
//   users/{uid}/subjects/{slug}
//     name              : string
//     strengthScore     : int    0–100
//     completionRate    : double 0.0–1.0
//     totalTasksCompleted : int
//     totalTasksCreated   : int
// ══════════════════════════════════════════════════════════════════════════════

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ── Subject data loaded from Firestore ────────────────────────────────────────

class _SubjectData {
  const _SubjectData({
    required this.name,
    required this.strengthScore,
    required this.completionRate,
    required this.totalTasksCreated,
  });

  final String name;
  final int strengthScore;       // 0–100
  final double completionRate;   // 0.0–1.0
  final int totalTasksCreated;

  /// Tone hint injected into the AI prompt based on this subject's performance.
  String get aiContextNote {
    final List<String> notes = <String>[];
    if (strengthScore < 40) {
      notes.add(
          "This student struggles with $name (strength score: $strengthScore/100). "
          "Use foundational language, break steps into smaller chunks, and be encouraging.");
    } else if (strengthScore > 70) {
      notes.add(
          "This student is strong in $name (strength score: $strengthScore/100). "
          "Use advanced framing, skip basics, and challenge with deeper approaches.");
    }
    if (totalTasksCreated >= 3 && completionRate < 0.5) {
      notes.add(
          "Their $name task completion rate is ${(completionRate * 100).toInt()}% "
          "— flag consistency risk and include a short motivational note.");
    }
    return notes.join(" ");
  }

  factory _SubjectData.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return _SubjectData(
      name: (d["name"] ?? doc.id) as String,
      strengthScore: (d["strengthScore"] ?? 50) as int,
      completionRate:
          ((d["completionRate"] ?? 0.0) as num).toDouble(),
      totalTasksCreated: (d["totalTasksCreated"] ?? 0) as int,
    );
  }
}

// ── Conflict detection ─────────────────────────────────────────────────────────

class _ConflictResult {
  const _ConflictResult(this.warnings);
  final List<String> warnings;
  bool get hasConflicts => warnings.isNotEmpty;
}

_ConflictResult _detectConflicts({
  required DateTime newDeadline,
  required String subject,
  required List<TaskItem> existingTasks,
}) {
  final List<String> warnings = <String>[];
  final List<TaskItem> active =
      existingTasks.where((TaskItem t) => !t.completed).toList();

  // ── a. Deadline collision: another active task due within ±24 h ───────────
  final List<TaskItem> collisions = active.where((TaskItem t) {
    return t.deadline.difference(newDeadline).inHours.abs() <= 24;
  }).toList();
  if (collisions.isNotEmpty) {
    final String names =
        collisions.take(2).map((TaskItem t) => '"${t.name}"').join(", ");
    final String extra =
        collisions.length > 2 ? " and ${collisions.length - 2} more" : "";
    warnings.add(
        "⚠️ Deadline collision: $names$extra ${collisions.length == 1 ? 'is' : 'are'} "
        "due around the same time. You may be overloaded that day.");
  }

  // ── b. Subject overload: 3+ pending tasks in the same subject ────────────
  final int sameSubjectCount = active
      .where((TaskItem t) =>
          t.subject.trim().toLowerCase() == subject.trim().toLowerCase())
      .length;
  if (sameSubjectCount >= 3) {
    warnings.add(
        "📚 Subject overload: you already have $sameSubjectCount pending "
        "$subject tasks. Consider completing one before adding more.");
  }

  // ── c. Dense window: 3+ active tasks due within ±36 h of new deadline ────
  final DateTime windowStart =
      newDeadline.subtract(const Duration(hours: 36));
  final DateTime windowEnd = newDeadline.add(const Duration(hours: 36));
  final int denseCount = active.where((TaskItem t) {
    return t.deadline.isAfter(windowStart) &&
        t.deadline.isBefore(windowEnd);
  }).length;
  if (denseCount >= 3) {
    warnings.add(
        "📅 Dense schedule: $denseCount tasks are due within 3 days of this "
        "deadline. Consider redistributing your workload.");
  }

  return _ConflictResult(warnings);
}

// ══════════════════════════════════════════════════════════════════════════════
// TASKS SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class TasksScreen extends StatefulWidget {
  const TasksScreen({
    super.key,
    required this.tasks,
    required this.profile,
    required this.moods,
    required this.repo,
    required this.userMeta,
  });

  final List<TaskItem> tasks;
  final UserProfile profile;
  final List<MoodLog> moods;
  final FirestoreRepository repo;
  final Map<String, dynamic> userMeta;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  @override
  void initState() {
    super.initState();
    widget.repo.autoCleanupIfDue();
  }

  bool get _autoDeleteEnabled =>
      (widget.userMeta["autoDeleteCompletedTasks"] ?? false) as bool;

  Future<void> _toggleAutoDelete(bool value) async {
    await widget.repo.saveAutoDeleteSetting(enabled: value);
  }

  Future<void> _deleteAllCompleted() async {
    final int count = widget.tasks.where((TaskItem t) => t.completed).length;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No completed tasks to delete.")),
      );
      return;
    }

    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Delete completed tasks?"),
            content: Text(
              "This will permanently delete $count completed "
              "task${count == 1 ? '' : 's'}. "
              "Your XP, streak, and AI data are already saved and won't be affected.",
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Delete"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;
    final int deleted = await widget.repo.deleteCompletedTasks();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            "Deleted $deleted completed task${deleted == 1 ? '' : 's'}."),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showTaskSettings() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setModalState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: kMuted.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Task Settings",
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: kMuted.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    title: const Text("Auto-delete completed tasks"),
                    subtitle: const Text(
                      "Every Sunday at midnight, completed tasks are removed "
                      "automatically. Your XP and AI data are always kept.",
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _autoDeleteEnabled,
                    onChanged: (bool val) async {
                      await _toggleAutoDelete(val);
                      setModalState(() {});
                      setState(() {});
                    },
                    activeColor: kOrange,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteAllCompleted();
                    },
                    icon: const Icon(Icons.delete_sweep, color: Colors.red),
                    label: const Text(
                      "Delete all completed tasks now",
                      style: TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── FAB handler — conflict detection → save → AI auto-trigger ───────────────

  Future<void> _handleAddTask() async {
    final _NewTaskData? task = await showDialog<_NewTaskData>(
      context: context,
      builder: (_) => const _AddTaskDialog(),
    );
    if (task == null || !mounted) return;

    // ── Step 1: Run conflict detection (local, zero network cost) ────────────
    final _ConflictResult conflicts = _detectConflicts(
      newDeadline: task.deadline,
      subject: task.subject,
      existingTasks: widget.tasks,
    );

    if (conflicts.hasConflicts && mounted) {
      final bool proceed = await showDialog<bool>(
            context: context,
            builder: (_) => _ConflictDialog(conflicts: conflicts),
          ) ??
          false;
      if (!proceed) return;
    }

    if (!mounted) return;

    // ── Step 2: AI auto-triggers immediately — show feedback ─────────────────
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: <Widget>[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 10),
            Text("AI is analyzing your task…"),
          ],
        ),
        duration: Duration(seconds: 4),
      ),
    );

    try {
      // ── Step 3: Build subject-enriched description for AI context ──────────
      //
      // Subject performance context is appended to the description so the AI
      // can adapt its tone and step depth without any API schema changes.
      // Format:
      //   [Subject AI Context: <tone_hint>]
      //
      // This note is stripped from the visible task description in the UI
      // (TaskItem.description is used for display; the enriched string goes
      // only to the AI prompt via repo.addTask → analyzeTask).
      final String enrichedDescription =
          task.subjectContextNote.isNotEmpty
              ? "${task.description}\n\n[Subject AI Context: ${task.subjectContextNote}]"
              : task.description;

      await widget.repo.addTask(
        name: task.name,
        description: enrichedDescription,
        subject: task.subject,
        deadline: task.deadline,
        difficulty: Difficulty.medium, // AI overrides this after analysis
        workload: Workload.medium,     // AI overrides this after analysis
        profile: widget.profile,
        moods: widget.moods,
        existingTasks: widget.tasks,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Task added and AI study guide generated ✅"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Failed to add task. Check your connection and try again."),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<TaskItem> sorted = widget.tasks.toList()
      ..sort((TaskItem a, TaskItem b) =>
          b.priorityScore.compareTo(a.priorityScore));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Tasks & AI Study Assistant"),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: "Task settings",
            onPressed: _showTaskSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _handleAddTask,
        child: const Icon(Icons.add),
      ),
      body: sorted.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SunMascot(size: 100),
                    const SizedBox(height: 16),
                    const Text(
                      "No tasks yet.",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kDark),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Tap + to add your first task.\nAI will analyze it automatically.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kMuted),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: sorted.length,
              itemBuilder: (_, int i) {
                final TaskItem t = sorted[i];
                return _TaskCard(task: t, repo: widget.repo, profile: widget.profile);
              },
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CONFLICT WARNING DIALOG
// ══════════════════════════════════════════════════════════════════════════════

class _ConflictDialog extends StatelessWidget {
  const _ConflictDialog({required this.conflicts});
  final _ConflictResult conflicts;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 22),
          SizedBox(width: 8),
          Text("Scheduling Conflicts"),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            "We detected potential scheduling conflicts for this task:",
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          ...conflicts.warnings.map(
            (String w) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Text(w, style: const TextStyle(fontSize: 13)),
              ),
            ),
          ),
          const Text(
            "Do you still want to add this task?",
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Add Anyway"),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ADD TASK DIALOG — subject-aware, subjects from Firestore
// ══════════════════════════════════════════════════════════════════════════════

class _NewTaskData {
  _NewTaskData({
    required this.name,
    required this.description,
    required this.subject,
    required this.deadline,
    this.subjectContextNote = "",
  });

  final String name;
  final String description;
  final String subject;
  final DateTime deadline;

  /// Subject-aware context note appended to the AI description.
  /// Generated from _SubjectData.aiContextNote when a known subject is picked.
  final String subjectContextNote;
}

class _AddTaskDialog extends StatefulWidget {
  const _AddTaskDialog();

  @override
  State<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<_AddTaskDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();

  DateTime _deadline = DateTime.now().add(const Duration(days: 1));
  _SubjectData? _selectedSubject;
  String? _customSubject; // used if subjects list is empty or user picks "Other"

  late Future<List<_SubjectData>> _subjectsFuture;

  @override
  void initState() {
    super.initState();
    _subjectsFuture = _loadSubjects();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Load subjects from users/{uid}/subjects ordered by name.
  Future<List<_SubjectData>> _loadSubjects() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return <_SubjectData>[];
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection("users")
          .doc(uid)
          .collection("subjects")
          .orderBy("name")
          .get();
      return snap.docs.map(_SubjectData.fromDoc).toList();
    } catch (_) {
      return <_SubjectData>[];
    }
  }

  String get _effectiveSubject =>
      _selectedSubject?.name ?? _customSubject ?? "";

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.auto_awesome, color: kOrange, size: 20),
          SizedBox(width: 8),
          Text("Add Task"),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // AI auto-trigger notice
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kOrangeSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.auto_awesome,
                      size: 14, color: kOrange),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "AI will instantly analyze your task and build a "
                      "personalized study guide — no extra steps needed.",
                      style: TextStyle(
                          fontSize: 11, color: kOrange),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Task name
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: "Task name *",
                hintText: "e.g. Math revision: derivatives",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            // Description
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Description *",
                hintText:
                    "Describe what this task involves — the more detail, "
                    "the better the AI guide.",
                hintStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),

            // ── Subject picker (from Firestore subjects) ──────────────────
            FutureBuilder<List<_SubjectData>>(
              future: _subjectsFuture,
              builder: (_, AsyncSnapshot<List<_SubjectData>> snap) {
                final List<_SubjectData> subjects = snap.data ?? <_SubjectData>[];

                if (snap.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 52,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }

                if (subjects.isEmpty) {
                  // Fallback: free-text if no subjects were seeded
                  return TextField(
                    onChanged: (val) =>
                        setState(() => _customSubject = val.trim()),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: "Subject *",
                      hintText: "e.g. Mathematics, Biology",
                      border: OutlineInputBorder(),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DropdownButtonFormField<_SubjectData>(
                      value: _selectedSubject,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "Subject *",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.book_outlined, size: 18),
                      ),
                      items: subjects
                          .map(
                            (_SubjectData s) =>
                                DropdownMenuItem<_SubjectData>(
                              value: s,
                              child: Text(s.name),
                            ),
                          )
                          .toList(),
                      onChanged: (_SubjectData? s) =>
                          setState(() => _selectedSubject = s),
                    ),
                    // Show subject performance badge when selected
                    if (_selectedSubject != null) ...<Widget>[
                      const SizedBox(height: 8),
                      _SubjectPerformanceBadge(data: _selectedSubject!),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 10),

            // Deadline picker
            OutlinedButton.icon(
              onPressed: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate:
                      DateTime.now().add(const Duration(days: 365)),
                  initialDate: _deadline,
                );
                if (picked != null) setState(() => _deadline = picked);
              },
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(
                  "Deadline: ${DateFormat.yMMMd().format(_deadline)}"),
            ),

            const SizedBox(height: 6),
            Text(
              "Difficulty and workload are auto-detected by AI from your description.",
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () {
            final String subject = _effectiveSubject;
            if (_name.text.trim().isEmpty ||
                _description.text.trim().isEmpty ||
                subject.isEmpty) return;

            Navigator.pop(
              context,
              _NewTaskData(
                name: _name.text.trim(),
                description: _description.text.trim(),
                subject: subject,
                deadline: _deadline,
                subjectContextNote:
                    _selectedSubject?.aiContextNote ?? "",
              ),
            );
          },
          child: const Text("Add & Analyze"),
        ),
      ],
    );
  }
}

// ── Subject performance badge shown inside dialog ─────────────────────────────

class _SubjectPerformanceBadge extends StatelessWidget {
  const _SubjectPerformanceBadge({required this.data});
  final _SubjectData data;

  Color get _strengthColor {
    if (data.strengthScore >= 70) return Colors.green;
    if (data.strengthScore >= 40) return Colors.orange;
    return Colors.red;
  }

  String get _strengthLabel {
    if (data.strengthScore >= 70) return "Strong";
    if (data.strengthScore >= 40) return "Developing";
    return "Needs work";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _strengthColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _strengthColor.withOpacity(0.25)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.bar_chart, size: 14, color: _strengthColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              "${data.name}: $_strengthLabel  •  "
              "${(data.completionRate * 100).toInt()}% completion rate",
              style: TextStyle(fontSize: 12, color: _strengthColor),
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _strengthColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              "${data.strengthScore}/100",
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _strengthColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TASK CARD (unchanged display logic, conflict warning banner already in
// TaskItem.aiOverlapWarning from the AI layer)
// ══════════════════════════════════════════════════════════════════════════════

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.repo, required this.profile});
  final TaskItem task;
  final FirestoreRepository repo;
  final UserProfile profile;

  Color _priorityColor(String label) {
    return switch (label) {
      "High Priority" || "Start First" => kError,
      "Heavy Load" => const Color(0xFFD97706),
      "Needs Early Start" || "Next" => kOrange,
      _ => kMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final bool hasAiData =
        task.aiMethod.isNotEmpty || task.aiSteps.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        leading: task.completed
            ? const Icon(Icons.check_circle, color: Colors.green)
            : CircleAvatar(
                radius: 16,
                backgroundColor:
                    _priorityColor(task.priorityLabel).withOpacity(0.12),
                child: Text(
                  task.priorityLabel[0],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _priorityColor(task.priorityLabel),
                  ),
                ),
              ),
        title: Text(
          task.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            decoration:
                task.completed ? TextDecoration.lineThrough : null,
            color: task.completed ? Colors.grey : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              "${task.subject} • Due ${DateFormat.yMMMd().format(task.deadline)}",
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color:
                        _priorityColor(task.priorityLabel).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    task.priorityLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: _priorityColor(task.priorityLabel),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    task.priorityReason,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (task.description.isNotEmpty) ...<Widget>[
                  Text(
                    // Strip the AI context note from the visible description
                    task.description.contains("[Subject AI Context:")
                        ? task.description
                            .substring(
                                0,
                                task.description
                                    .indexOf("\n\n[Subject AI Context:"))
                            .trim()
                        : task.description,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                ],

                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: <Widget>[
                    _chip(
                        "${_capitalize(task.difficulty.name)} difficulty",
                        Colors.purple),
                    _chip(
                        "${_capitalize(task.workload.name)} workload",
                        Colors.blue),
                    if (task.aiEstimatedMinutes > 0)
                      _chip("~${task.aiEstimatedMinutes} min",
                          Colors.teal),
                    if (task.aiBestTime.isNotEmpty)
                      _chip("Best: ${task.aiBestTime}", Colors.orange),
                    if (task.aiPomodoroSessions > 0)
                      _chip(
                          "🍅 ${task.aiPomodoroSessions} "
                          "pomodoro${task.aiPomodoroSessions > 1 ? 's' : ''}",
                          Colors.red),
                  ],
                ),

                // Overlap / conflict warning banner
                if (task.aiOverlapWarning != null &&
                    task.aiOverlapWarning!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kYellow.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kOrange.withOpacity(0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(Icons.warning_amber,
                            size: 16, color: kOrange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                "Scheduling conflict",
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: kOrange),
                              ),
                              Text(
                                task.aiOverlapWarning!,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (!hasAiData) ...<Widget>[
                  const SizedBox(height: 12),
                  const Row(
                    children: <Widget>[
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text(
                        "AI study guide generating…",
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],

                if (hasAiData) ...<Widget>[
                  const SizedBox(height: 14),
                  const Divider(),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.auto_awesome,
                          size: 16, color: kOrange),
                      const SizedBox(width: 6),
                      Text(
                        "AI Study Assistant",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kDark,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (task.aiMethod.isNotEmpty) ...<Widget>[
                    _sectionLabel("Recommended Method"),
                    Text(task.aiMethod,
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 10),
                  ],

                  if (task.aiBreakStrategy.isNotEmpty) ...<Widget>[
                    _sectionLabel("Break Strategy"),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kOrangeSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text("🍅 ",
                              style: TextStyle(fontSize: 14)),
                          Expanded(
                            child: Text(
                              task.aiBreakStrategy,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: kDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (task.aiProductivityAdvice.isNotEmpty) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kOrangeSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text("💬 ",
                              style: TextStyle(fontSize: 14)),
                          Expanded(
                            child: Text(
                              task.aiProductivityAdvice,
                              style: const TextStyle(
                                fontSize: 12,
                                color: kDark,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (task.aiSteps.isNotEmpty) ...<Widget>[
                    _sectionLabel("Step-by-Step Guide"),
                    ...task.aiSteps.asMap().entries.map(
                          (MapEntry<int, String> e) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: <Widget>[
                                Container(
                                  width: 20,
                                  height: 20,
                                  margin: const EdgeInsets.only(
                                      right: 8, top: 1),
                                  decoration: BoxDecoration(
                                    color: kDark,
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "${e.key + 1}",
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(e.value,
                                      style: const TextStyle(
                                          fontSize: 13)),
                                ),
                              ],
                            ),
                          ),
                        ),
                    const SizedBox(height: 10),
                  ],

                  if (task.aiStudyTips.isNotEmpty) ...<Widget>[
                    _sectionLabel("Study Tips"),
                    ...task.aiStudyTips.map(
                      (String tip) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text("✅ ",
                                style: TextStyle(fontSize: 13)),
                            Expanded(
                              child: Text(tip,
                                  style:
                                      const TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (task.aiSuggestedResources.isNotEmpty) ...<Widget>[
                    _sectionLabel("Suggested Resources"),
                    ...task.aiSuggestedResources.map(
                      (Map<String, String> r) => InkWell(
                        onTap: r["url"] != null && r["url"]!.isNotEmpty
                            ? () async {
                                final Uri uri =
                                    Uri.parse(r["url"]!);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri,
                                      mode: LaunchMode
                                          .externalApplication);
                                }
                              }
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                r["url"] != null &&
                                        r["url"]!.isNotEmpty
                                    ? Icons.open_in_new
                                    : Icons.book_outlined,
                                size: 14,
                                color: kOrange,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  r["title"] ?? "",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: r["url"] != null &&
                                            r["url"]!.isNotEmpty
                                        ? kOrange
                                        : null,
                                    decoration: r["url"] != null &&
                                            r["url"]!.isNotEmpty
                                        ? TextDecoration.underline
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],

                // Focus Mode
                if (!task.completed && hasAiData) ...<Widget>[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push<bool>(
                          context,
                          MaterialPageRoute<bool>(
                            builder: (_) =>
                                FocusModeScreen(task: task, repo: repo, profile: profile),
                          ),
                        );
                      },
                      icon: const Icon(Icons.timer_outlined,
                          size: 16, color: kOrange),
                      label: const Text(
                        "Start Focus Session",
                        style: TextStyle(color: kOrange),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: kOrange.withOpacity(0.3)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],

                // Mark as Done
                if (!task.completed) ...<Widget>[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => repo.completeTask(task),
                      icon: const Icon(Icons.check),
                      label: const Text("Mark as Done"),
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.green),
                    ),
                  ),
                ],

                // Delete
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final bool confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text("Delete task?"),
                              content: Text(
                                task.completed
                                    ? "Delete \"${task.name}\"? Your XP and AI data are already saved."
                                    : "Delete \"${task.name}\"? This cannot be undone.",
                              ),
                              actions: <Widget>[
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text("Cancel"),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red),
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text("Delete"),
                                ),
                              ],
                            ),
                          ) ??
                          false;
                      if (confirm) await repo.deleteTask(task.id);
                    },
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 16),
                    label: const Text("Delete task",
                        style:
                            TextStyle(color: Colors.red, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.shade200),
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color.shade700),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: Colors.grey,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
