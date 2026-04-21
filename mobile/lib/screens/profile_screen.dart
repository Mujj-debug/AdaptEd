import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "../design_tokens.dart";
import "../models/app_models.dart";
import "../services/firestore_repository.dart";

String _cap(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.profile, required this.repo});
  final UserProfile profile;
  final FirestoreRepository repo;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<ProfileChangeLogEntry> _changeLog = <ProfileChangeLogEntry>[];
  bool _loadingLog = true;

  @override
  void initState() {
    super.initState();
    _loadChangeLog();
  }

  Future<void> _loadChangeLog() async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection("users")
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .collection("profile_change_log")
          .orderBy("changedAt", descending: true)
          .limit(5)
          .get();
      setState(() {
        _changeLog = snap.docs.map((doc) {
          return ProfileChangeLogEntry.fromMap(doc.data());
        }).toList();
        _loadingLog = false;
      });
    } catch (_) {
      setState(() => _loadingLog = false);
    }
  }

  Future<void> _logout() async {
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: kSurface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22)),
            title: const Text("Log out?",
                style: TextStyle(fontWeight: FontWeight.w800, color: kDark)),
            content: const Text(
              "You will be signed out and returned to the login screen.",
              style: TextStyle(color: kMuted),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel",
                    style: TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: kError,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Log out",
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    await FirebaseAuth.instance.signOut();
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SettingsSheet(repo: widget.repo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    final UserProfile p = widget.profile;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text("Profile"),
        backgroundColor: kBg,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: <Widget>[
          // ── User info card ─────────────────────────────────────────────────
          LocketCard(
            child: Row(
              children: <Widget>[
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: kOrangeSoft,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      (user?.displayName ?? user?.email ?? "?")[0]
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: kOrange,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        user?.displayName ?? "User",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: kDark,
                        ),
                      ),
                      if (user?.email != null)
                        Text(
                          user!.email!,
                          style: kSubtitle,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Your Learning Profile ──────────────────────────────────────────
          const SectionHeader(title: "Your Learning Profile"),
          const SizedBox(height: 8),
          LocketCard(
            color: kOrangeSoft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: <Widget>[
                const Icon(Icons.psychology_rounded, size: 14, color: kOrange),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "AI-inferred from your behavior — updates automatically as you study.",
                    style: TextStyle(fontSize: 11, color: kDark, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _readOnlyRow("Personality", _cap(p.personalityType.name)),
          _readOnlyRow("Productivity", _cap(p.productivityPreference.name)),
          _labelRow("Study Focus", studyFocusLabel(p.studyFocus)),
          _labelRow("Rest Importance", restImportanceLabel(p.restImportance)),
          _labelRow("Creativity", creativityLabel(p.creativity)),
          _labelRow(
              "Physical Activity", physicalActivityLabel(p.physicalActivity)),

          // ── Why did this change? ───────────────────────────────────────────
          if (!_loadingLog && _changeLog.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            const SectionHeader(title: "Recent Changes"),
            const SizedBox(height: 8),
            ..._changeLog.map((ProfileChangeLogEntry entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LocketCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _fieldLabel(entry.field),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: kDark),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.reason,
                          style: kSubtitle,
                        ),
                      ],
                    ),
                  ),
                )),
          ],

          const SizedBox(height: 24),

          // ── Account Settings ───────────────────────────────────────────────
          GestureDetector(
            onTap: _openSettings,
            child: LocketCard(
              child: Row(
                children: <Widget>[
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: kBlue.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.settings_outlined, color: kDark, size: 18),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text("Account Settings",
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, color: kDark)),
                        Text("Username, password, account options",
                            style: kSubtitle),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: kMuted, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Logout ─────────────────────────────────────────────────────────
          GestureDetector(
            onTap: _logout,
            child: LocketCard(
              color: kPink.withOpacity(0.2),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: kError.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.logout_rounded, color: kError, size: 18),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text("Log out",
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: kError)),
                      Text("Return to the login screen",
                          style: TextStyle(fontSize: 12, color: kMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fieldLabel(String field) {
    return switch (field) {
      "studyFocus"     => "Study Focus updated",
      "restImportance" => "Rest Importance updated",
      "creativity"     => "Creativity updated",
      _                => "${_cap(field)} updated",
    };
  }

  /// Read-only chip row for enum labels.
  Widget _readOnlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(label,
                style: kSubtitle),
          ),
          PillBadge(color: kOrangeSoft, label: value),
        ],
      ),
    );
  }

  /// Read-only semantic label row — shows the human-readable field meaning.
  Widget _labelRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(label,
                style: kSubtitle),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kDark),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Settings bottom sheet ──────────────────────────────────────────────────────

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.repo});
  final FirestoreRepository repo;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  final TextEditingController _usernameCtrl = TextEditingController();
  bool _savingUsername = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveUsername() async {
    final String val = _usernameCtrl.text.trim();
    if (val.isEmpty) return;
    setState(() => _savingUsername = true);
    try {
      await widget.repo.saveUsername(val);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Username updated.")),
      );
    } finally {
      if (mounted) setState(() => _savingUsername = false);
    }
  }

  Future<void> _changePassword() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) return;
    await FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Password reset email sent. Check your inbox.")),
    );
  }

  Future<void> _deleteAccount() async {
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: kSurface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22)),
            title: const Text("Delete account?",
                style: TextStyle(fontWeight: FontWeight.w800, color: kDark)),
            content: const Text(
              "This will permanently delete your account and all your data. "
              "This cannot be undone.",
              style: TextStyle(color: kMuted),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel",
                    style: TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: kError,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Delete",
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;
    try {
      await FirebaseAuth.instance.currentUser?.delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                "Could not delete account. Re-authenticate and try again. ($e)")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 16,
      ),
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
          const SizedBox(height: 20),
          const Text("Account Settings",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: kDark)),
          const SizedBox(height: 20),

          TextField(
            controller: _usernameCtrl,
            style: const TextStyle(fontSize: 14, color: kDark),
            decoration: locketFieldStyle("New username",
                icon: Icons.person_outline_rounded),
          ),
          const SizedBox(height: 12),
          DarkPillButton(
            label: "Save Username",
            loading: _savingUsername,
            onPressed: _saveUsername,
          ),
          const SizedBox(height: 20),

          // Change password
          GestureDetector(
            onTap: _changePassword,
            child: LocketCard(
              child: Row(
                children: <Widget>[
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: kYellow.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.lock_outline_rounded, color: kDark, size: 18),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text("Change Password",
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, color: kDark)),
                        Text("We'll send a reset email",
                            style: kSubtitle),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: kMuted, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Delete account
          GestureDetector(
            onTap: _deleteAccount,
            child: LocketCard(
              color: kPink.withOpacity(0.2),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: kError.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete_forever_rounded, color: kError, size: 18),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text("Delete Account",
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: kError)),
                      Text("This is permanent",
                          style: TextStyle(fontSize: 12, color: kMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}
