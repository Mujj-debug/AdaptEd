// ══════════════════════════════════════════════════════════════════════════════
// FILE 1: lib/screens/screens.dart  (REPLACE existing file)
// ══════════════════════════════════════════════════════════════════════════════

export "ai_study_hub_screen.dart";
export "ai_tutor_screen.dart";
export "auth_onboarding_screen2.dart";
export "dashboard_screen.dart";
export "flashcard_screen.dart";
export "focus_mode_screen.dart";
export "gamification_screen.dart";
export "insights_screen.dart";
export "profile_screen.dart";
export "quiz_screen.dart";
export "strategy_library_screen.dart";
export "study_material_viewer_screen.dart";
export "tasks_screen.dart";

// ══════════════════════════════════════════════════════════════════════════════
// FILE 2: app.dart nav patch
//
// In AppShell._AppShellState, add the AI Study Hub as tab index 5.
// Paste this snippet inside the _pages list in AppShell.build():
// ══════════════════════════════════════════════════════════════════════════════

/*
NAVIGATION INTEGRATION — AppShell (_AppShellState)
─────────────────────────────────────────────────────────────────────────────
Add the AI Study Hub tab to the BottomNavigationBar / NavigationBar.

Step 1: In _pages list, add at index 5:
  AiStudyHubScreen(
    profile: profile,
    tasks: tasks,
    repo: repo,
  ),

Step 2: In NavigationBar destinations, add:
  NavigationDestination(
    icon: Icon(Icons.auto_awesome_outlined),
    selectedIcon: Icon(Icons.auto_awesome_rounded),
    label: "Study Hub",
  ),

Step 3: Update _tab guard so it accepts index 5.

Step 4: From TaskScreen task cards, pass a deep-link:
  // Inside task detail → "Study with AI" button:
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => AiStudyHubScreen(
      profile: profile,
      tasks: tasks,
      repo: repo,
      preselectedTask: task,  // <— pre-selects this task
    ),
  ));
─────────────────────────────────────────────────────────────────────────────
*/

// ══════════════════════════════════════════════════════════════════════════════
// FILE 3: lib/models/models.dart  (barrel, if you have one)
// ══════════════════════════════════════════════════════════════════════════════

/*
Add to your models barrel (or import directly in each screen):
  export "study_material_models.dart";
*/
