# AdaptEd

**An AI-powered adaptive study companion built with Flutter and Firebase.**

AdaptEd tracks how you study, learns your habits, and dynamically adjusts task priorities, scheduling, and study content to fit your actual productivity patterns — not a generic routine.

---

## Table of Contents

1. [Overview](#overview)
2. [Core Features](#core-features)
3. [AI System & Adaptive Logic](#ai-system--adaptive-logic)
4. [Tech Stack](#tech-stack)
5. [Project Structure](#project-structure)
6. [Setup & Installation](#setup--installation)
7. [Current Status](#current-status)
8. [Known Issues](#known-issues)
9. [Planned Improvements](#planned-improvements)

---

## Overview

AdaptEd is a student-facing mobile application designed for learners who need more than a to-do list. After a one-time onboarding assessment, the system builds a `UserProfile` capturing personality type, preferred productivity window, creativity level, rest habits, and physical activity. This profile is then fed into every AI decision — from how a task is prioritized to what time of day the app recommends tackling it.

The study tools (flashcards, quizzes, AI tutor, study materials) are all generated on-demand by an LLM using the context of the student's active task and subject. There is no static content — everything is personalized per session.

---

## Core Features

### Onboarding & Assessment
- Multi-step assessment covering personality, productivity patterns, energy type, rest habits, and learning style
- AI analysis via Groq (Llama 3.3 70B) produces a `productivityIdentity`, `idealDayStructure`, and subject-level recommendations
- Assessment results are persisted to Firestore and immediately influence all downstream features
- Email/password authentication with email verification gate before accessing the app

### Task Management
- Add tasks with subject, deadline, difficulty (easy/medium/hard), and workload (light/moderate/heavy)
- Each task is immediately analyzed by the AI upon creation:
  - Estimated study time in minutes
  - Recommended Pomodoro session count
  - Best time of day to tackle the task (based on user profile)
  - Break strategy, study method, step-by-step plan, and productivity tips
  - Scheduling conflict detection (`aiOverlapWarning`) if the deadline overlaps with existing high-priority tasks
- Priority score (0–100) calculated locally using deadline urgency, difficulty, workload, and current mood
- Priority labels: `High Priority`, `Heavy Load`, `Needs Early Start`, `Next`, `Quick Task`
- Tasks display a conflict warning banner inline when the AI detects scheduling pressure
- Per-subject performance tracking via `SubjectStats` — completion rate and a 0–100 strength score feed back into AI prompts for future tasks in the same subject

### AI Study Hub
Central access point (Tab 2) for all AI-powered study tools, each contextualized to the student's currently selected task:

| Tool | Description |
|---|---|
| **Flashcards** | AI generates N cards (configurable difficulty: easy/medium/hard). Full-screen flip animation with swipe-based spaced repetition — missed cards cycle back automatically |
| **Practice Quiz** | MCQ, True/False, and Short Answer mixed quiz. 5–20 questions, difficulty selectable. AI feedback card after completion highlights knowledge gaps and next steps |
| **AI Tutor** | Free-form chat with an LLM tutor scoped to the active task's subject and description |
| **Study Materials** | On-demand generation of a Topic Summary, full Reviewer, or Study Guide document |

### Focus Mode (Pomodoro Timer)
- Configurable work duration: 15, 25, or 45 minutes (selected before session start)
- Full Pomodoro lifecycle: work → short break (5 min) → work → long break (15 min after 4 rounds)
- SunMascot mascot walks during work, rests during breaks for ambient motivation
- Mid-session check-in prompt fires after the 2nd Pomodoro (mood + difficulty)
- Session persisted to Firestore as `active_session` — resume banner appears on Dashboard if app is closed mid-session
- AI-generated session summary on completion (via `ClaudeService.generateWeeklySummary`)
- Post-session XP award and behavioral analytics update

### AI Insights
- Cached insight cards stored in Firestore (`insights` field) and refreshed every 6 hours or when triggered by a new task, completed task, or logged mood
- Weekly summary card (mood trends, productivity patterns, subject analysis)
- `BehaviorAnalytics` model tracks: total tasks created/completed, study peak hour, mood frequency, hourly heatmap, session subjects
- Assessment error detection with direct retry flow accessible from the Dashboard banner

### Gamification
- XP earned for: task completion, mood logging, Pomodoro rounds, study sessions, flashcard mastery, quiz performance, sharing thoughts
- XP breakpoints: streaks tracked with daily activity touchpoints
- Badge system (15+ badge types) unlocked by behavioral milestones (e.g., first task, 3-day streak, first quiz)
- Badge unlock notification banner shown globally across tabs
- Weekly Challenges: 3 randomly assigned challenges per week from a pool of 10 challenge types. Progress tracked per action. Dashboard shows a compact challenge strip with mini progress bars

### Dashboard
- Header: SunMascot + XP level pill
- Streak and daily stats row
- Weekly challenge strip (up to 3 active challenges with tap-to-XP navigation)
- Assessment error warning card (if AI profile needs attention)
- Today's Priority card: highest-priority pending task with direct Focus Session and Study Session entry points
- Future-You Simulator: text predictions based on completion rate and study frequency
- Mood quick-log: emoji picker, fires `+5 XP` on log
- Smart Energy Map: time-block recommendations (Deep Focus / Light Study / Avoid) derived from `productivityPreference`
- Today's Focus block: sessions completed today with total minutes and Pomodoro count
- Most recent mood log

### Strategy Library
- Shared community board (Firebase Realtime Database)
- Cards contain a title, body, and optional tags
- Full CRUD for own cards; read-only view for community cards

### Profile
- Displays AI-inferred profile attributes with the note that they update automatically as the user studies
- `profile_change_log` subcollection tracks when and why profile fields were updated by the AI
- Account settings: username update, password reset email, account deletion

---

## AI System & Adaptive Logic

### Model & API
- **Provider**: Groq Cloud  
- **Model**: `llama-3.3-70b-versatile`  
- **Services**: `claude_service.dart` (task analysis, insights, weekly summary), `claude_service_study.dart` (flashcards, quizzes, tutor, study materials)
- Retry logic with exponential backoff on all Groq calls; all features have local fallback implementations if the API is unavailable

### How Adaptation Works

```
User completes assessment
        ↓
UserProfile built (personality, productivity window, creativity, rest, activity)
        ↓
User adds a task
        ↓
AI analyzes: deadline pressure × difficulty × workload × subject history × profile
        ↓
Priority score + study guide + conflict warnings written to Firestore
        ↓
User completes a Pomodoro / logs mood / finishes a quiz
        ↓
BehaviorAnalytics updated (hourly heatmap, peak hour, session count, mood frequency)
        ↓
InsightCards regenerated every 6h using updated behavioral data
        ↓
Profile fields may be nudged by AI analysis of sessions (logged in profile_change_log)
```

### Conflict Detection
`deadline_conflict_detector.dart` — standalone utility that scans the current task list and flags overlapping deadlines or scheduling pressure, feeding this into the AI prompt for the new task being added.

### Subject Intelligence
`subject_stats.dart` computes per-subject metrics across all tasks and sessions:
- Completion rate
- Strength score (0–100)
- Average felt difficulty

These are injected as structured context into AI prompts, so the LLM knows that a student is historically weak in a subject and can adjust study recommendations accordingly.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x (Dart ≥ 3.3) |
| Auth | Firebase Authentication (email/password + verification) |
| Primary DB | Cloud Firestore |
| Realtime DB | Firebase Realtime Database (Strategy Library) |
| AI | Groq API — Llama 3.3 70B via HTTP (`http` package) |
| State | `StreamBuilder` + `StatefulWidget` (no external state manager) |
| Navigation | Tab-based `IndexedStack` + `Navigator.push` for sub-flows |
| Font | NotoColorEmoji (bundled asset) |
| Localization | `intl` package (date formatting) |

---

## Project Structure

```
mobile/
├── lib/
│   ├── main.dart                        # Firebase init + app entry
│   ├── app.dart                         # AppShell, auth gate, onboarding gate,
│   │                                    # WelcomeSplash, MainAppShell, nav bar
│   ├── design_tokens.dart               # Full design system — colors, typography,
│   │                                    # shared widgets (LocketCard, PillBadge,
│   │                                    # SunMascot, DarkPillButton, StatPill…)
│   │
│   ├── models/
│   │   ├── app_models.dart              # UserProfile, TaskItem, MoodLog,
│   │   │                               # StudySession, GamificationState,
│   │   │                               # BehaviorAnalytics, InsightCardData,
│   │   │                               # ActiveSession, StudyStrategy, etc.
│   │   ├── study_material_models.dart   # FlashCard, QuizQuestion, QuizResult,
│   │   │                               # StudyMaterialType, QuizAnswerRecord
│   │   └── weekly_challenge_models.dart # WeeklyChallenge, WeeklyChallengeDef,
│   │                                    # weeklyChallengePool constant
│   │
│   ├── services/
│   │   ├── firestore_repository.dart    # All Firestore reads/writes — single
│   │   │                               # source of truth for data operations
│   │   ├── claude_service.dart          # Task analysis, insight generation,
│   │   │                               # weekly summary, session summaries
│   │   ├── claude_service_study.dart    # Flashcard, quiz, tutor, study material
│   │   │                               # generation via Groq
│   │   ├── ai_analytics.dart            # Priority calculation, insight card
│   │   │                               # generation, behavior analytics engine
│   │   ├── assessment_ai.dart           # Assessment answer → UserProfile builder
│   │   ├── deadline_conflict_detector.dart # Scheduling overlap detection
│   │   ├── subject_stats.dart           # Per-subject strength score calculator
│   │   ├── weekly_challenge_service.dart # Challenge assignment, progress tracking
│   │   ├── gamification_utils.dart      # Badge unlock logic, XP thresholds
│   │   └── demo_seed_service.dart       # Development seed data
│   │
│   └── screens/
│       ├── auth_onboarding_screen.dart  # Login / sign-up screen
│       ├── auth_onboarding_screen2.dart # SunMascot splash (Splash 1),
│       │                               # WelcomeSplash (Splash 2),
│       │                               # Assessment onboarding flow
│       ├── dashboard_screen.dart        # Home tab — AI daily card, challenge
│       │                               # strip, Future-You, mood log, energy map
│       ├── tasks_screen.dart            # Task list, add task form, subject filter,
│       │                               # AI task card expansion, bulk actions
│       ├── ai_study_hub_screen.dart     # Study Hub tab — flashcards, quiz,
│       │                               # tutor, materials, quick launch
│       ├── flashcard_screen.dart        # AI flashcard generator + spaced repeat
│       ├── quiz_screen.dart             # AI quiz (MCQ/T-F/Short) + AI feedback
│       ├── ai_tutor_screen.dart         # LLM chat tutor scoped to task
│       ├── study_material_viewer_screen.dart # AI-generated docs viewer
│       ├── focus_mode_screen.dart       # Pomodoro timer + mid-session check-in
│       │                               # + configurable duration + SunMascot
│       ├── insights_screen.dart         # AI insight cards, weekly summary,
│       │                               # behavior analytics display
│       ├── gamification_screen.dart     # XP, badges, weekly challenges
│       ├── strategy_library_screen.dart # Community strategy board (RTDB)
│       ├── profile_screen.dart          # Profile attributes, change log, settings
│       └── screens.dart                 # Barrel export
│
├── fonts/
│   └── NotoColorEmoji.ttf
├── pubspec.yaml
└── google-services.json                 # Not committed — required for Firebase
```

---

## Setup & Installation

### Prerequisites
- Flutter SDK ≥ 3.3.0
- Dart ≥ 3.3.0
- A Firebase project with **Authentication**, **Cloud Firestore**, and **Realtime Database** enabled
- A [Groq API key](https://console.groq.com)

### Steps

1. **Clone the repository**
   ```bash
   git clone <repo-url>
   cd Locket/mobile
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   - Download `google-services.json` from your Firebase console and place it in `android/app/`
   - For web or iOS, follow the platform-specific FlutterFire setup

4. **Set the Groq API key**

   Open `lib/services/claude_service.dart` and replace the placeholder:
   ```dart
   static const String _apiKey = 'YOUR_GROQ_API_KEY';
   ```
   > ⚠️ **Do not commit your API key.** Before deploying, migrate this to a remote config or secrets manager.

5. **Run the app**
   ```bash
   flutter run
   # or target a specific device:
   flutter run -d chrome
   flutter run -d android
   ```

### Firestore Security Rules
Each user's data is scoped to their UID. The Realtime Database `/strategies` path is publicly readable, write-authenticated.

---

## Current Status

| Feature | Status |
|---|---|
| Auth (email/password + verification) | ✅ Complete |
| Assessment onboarding | ✅ Complete |
| Splash 1 (loading) + Splash 2 (post-login welcome) | ✅ Complete |
| Task CRUD + AI analysis on creation | ✅ Complete |
| Priority scoring + conflict detection | ✅ Complete |
| Dashboard with challenge strip + energy map | ✅ Complete |
| Focus Mode (Pomodoro, configurable, mascot) | ✅ Complete |
| Mid-session check-in | ✅ Complete |
| AI Study Hub (flashcards, quiz, tutor, materials) | ✅ Complete |
| AI Insights + weekly summary | ✅ Complete |
| Gamification (XP, badges, weekly challenges) | ✅ Complete |
| Strategy Library (community board, RTDB) | ✅ Complete |
| Profile + change log | ✅ Complete |
| Behavioral analytics (heatmap data collection) | ✅ Complete |
| Task editing (post-creation) | ❌ Not implemented — delete and re-add |
| Visual heatmap on Insights screen | ❌ Data collected, chart not rendered |
| Push notifications | ❌ Not implemented |
| Offline support | ❌ No local caching — requires active connection |

---

## Known Issues

- **`ParentDataWidget` render errors** — Visible in debug console on certain nested layouts. No user-facing impact; tracked for fix in a future layout refactor.
- **Hero tag conflict** — Multiple `Hero` widgets sharing the same tag across overlapping routes. Benign in current navigation setup.
- **Groq API key is hardcoded** — `claude_service.dart` line 1. Must be externalized before any production deployment.
- **Task editing** — Users must delete and recreate a task to change any field.

---

## Planned Improvements

- **Visual heatmap** — Render the existing `hourlyHeatmap` data in `BehaviorAnalytics` as an interactive chart on the Insights screen
- **Task editing** — Inline edit form for deadline, difficulty, and description without losing AI analysis
- **Post-assessment profile reveal** — A dedicated screen showing the student's `productivityIdentity` and `idealDayStructure` immediately after onboarding, before the dashboard
- **Push notifications** — Deadline reminders and streak protection alerts
- **Offline mode** — Local cache for tasks and insights with sync-on-reconnect
- **Groq key migration** — Move to Firebase Remote Config or a lightweight backend proxy to avoid client-side key exposure
