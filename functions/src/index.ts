import * as admin from "firebase-admin";
import {GoogleGenerativeAI} from "@google/generative-ai";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";

admin.initializeApp();

// ─── Shared types ─────────────────────────────────────────────────────────────

type Difficulty = "easy" | "medium" | "hard";
type Workload = "low" | "medium" | "high";
type ProductivityPreference = "morning" | "night" | "flexible";

interface TaskInput {
  id: string;
  name: string;
  deadline: string;
  difficulty: Difficulty;
  workload: Workload;
}

interface ProfileInput {
  productivityPreference: ProductivityPreference;
}

interface MoodInput {
  mood: "happy" | "neutral" | "sad";
}

interface InsightCard {
  title: string;
  message: string;
  why: string;
}

// ─── Gemini helper ────────────────────────────────────────────────────────────

const SYSTEM_JSON =
  "You are a helpful AI assistant for a student productivity app. " +
  "Respond ONLY with valid raw JSON — no markdown fences, no explanation, no preamble.";

// FIX: Updated from deprecated gemini-1.5-flash to gemini-2.0-flash
const callGemini = async (prompt: string): Promise<any> => {
  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY!);
  const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});
  const result = await model.generateContent(`${SYSTEM_JSON}\n\n${prompt}`);
  const text = result.response.text().trim();
  const clean = text.replace(/^```json\s*/i, "").replace(/```\s*$/i, "").trim();
  return JSON.parse(clean);
};

// ─── Recalculate task priority ────────────────────────────────────────────────

export const recalculateTaskPriority = onCall(async (request: CallableRequest<any>) => {
  const task = request.data.task as TaskInput;
  const profile = request.data.profile as ProfileInput;
  const recentMoods = (request.data.recentMoods ?? []) as MoodInput[];
  const now = new Date();
  const deadline = new Date(task.deadline);
  const hoursUntilDeadline = Math.floor((deadline.getTime() - now.getTime()) / (1000 * 60 * 60));

  let deadlineWeight = 5;
  if (hoursUntilDeadline <= 24) deadlineWeight = 50;
  else if (hoursUntilDeadline <= 72) deadlineWeight = 35;
  else if (hoursUntilDeadline <= 168) deadlineWeight = 20;

  const difficultyWeight = task.difficulty === "hard" ? 20 : task.difficulty === "medium" ? 10 : 5;
  const workloadWeight = task.workload === "high" ? 15 : task.workload === "medium" ? 8 : 3;

  let behaviorWeight = 0;
  const hour = now.getHours();
  if (profile.productivityPreference === "night" && hour >= 18 && task.difficulty === "hard") behaviorWeight += 8;
  if (profile.productivityPreference === "morning" && hour <= 11 && task.difficulty !== "easy") behaviorWeight += 8;
  const sadCount = recentMoods.filter((m) => m.mood === "sad").length;
  if (sadCount >= 2 && task.workload === "high") behaviorWeight -= 5;

  const score = Math.max(0, deadlineWeight + difficultyWeight + workloadWeight + behaviorWeight);
  let label: string;
  if (score >= 70) {
    label = "High Priority";
  } else if (score >= 40) {
    label = (task.workload === "high" || task.difficulty === "hard") ? "Heavy Load" : "Needs Early Start";
  } else {
    label = (task.difficulty === "easy" && task.workload === "low") ? "Quick Task" : "Needs Early Start";
  }
  const reasons: string[] = [];
  if (deadlineWeight >= 35) reasons.push("deadline is near");
  if (difficultyWeight >= 20) reasons.push("difficulty is high");
  if (workloadWeight >= 15) reasons.push("workload is high");
  if (behaviorWeight > 0) reasons.push("timing matches your preference");
  if (behaviorWeight < 0) reasons.push("recent mood suggests a lighter start");

  return {
    score, label,
    reason: reasons.length
      ? `Suggested because ${reasons.slice(0, 2).join(" and ")}.`
      : "Suggested using your current profile and deadlines.",
  };
});

// ─── Generate weekly insights (local) ────────────────────────────────────────

export const generateWeeklyInsights = onCall(async (request: CallableRequest<any>) => {
  const profile = request.data.profile as ProfileInput;
  const moods = (request.data.moods ?? []) as MoodInput[];
  const tasks = (request.data.tasks ?? []) as Array<{completed: boolean}>;
  const insights: InsightCard[] = [];
  const happy = moods.filter((m) => m.mood === "happy").length;
  const sad = moods.filter((m) => m.mood === "sad").length;
  if (moods.length > 0 && happy > sad) {
    insights.push({title: "Positive mood trend", message: "Your logged mood is trending positive this week.", why: `Detected ${happy} positive logs and ${sad} low logs in recent entries.`});
  }
  if (tasks.length > 0) {
    const done = tasks.filter((t) => t.completed).length;
    const rate = Math.round((done / tasks.length) * 100);
    insights.push({title: "Task completion pattern", message: `You completed ${rate}% of tracked tasks.`, why: `Computed from ${done} completed tasks out of ${tasks.length}.`});
  }
  if (profile.productivityPreference === "night") {
    insights.push({title: "Night productivity signal", message: "You may benefit from scheduling deep work in the evening.", why: "Your selected preference is Night."});
  }
  return {insights};
});

// ─── Award XP ─────────────────────────────────────────────────────────────────

export const awardXp = onCall(async (request: CallableRequest<any>) => {
  const eventType = request.data.eventType as string;
  const difficulty = request.data.difficulty as Difficulty | undefined;
  const userId = request.data.userId as string;
  let gain = 0;
  if (eventType === "task_completed") gain = difficulty === "hard" ? 50 : difficulty === "medium" ? 35 : 20;
  else if (eventType === "mood_logged") gain = 5;
  else if (eventType === "insight_posted") gain = 10;
  const ref = admin.firestore().collection("users").doc(userId);
  const snap = await ref.get();
  const data = snap.data() ?? {};
  const xp = (data.xp ?? 0) + gain;
  const level = Math.floor(Math.sqrt(xp / 100)) + 1;
  await ref.set({xp, level}, {merge: true});
  return {xp, level, gained: gain};
});

// ─── Seed demo data ───────────────────────────────────────────────────────────

export const seedDemoData = onCall(async (request: CallableRequest<any>) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in before seeding demo data.");
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const now = Date.now();
  await userRef.set({
    personalityType: "introvert", productivityPreference: "night",
    socialEnergy: 3, studyFocus: 4, restImportance: 4, creativity: 3, physicalActivity: 2,
    xp: 185, level: 2, streakDays: 3, badges: ["Early Starter"],
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastActiveDate: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  const tasks = [
    {name: "Math revision: derivatives", subject: "Mathematics", deadline: new Date(now + 86400000), difficulty: "hard", workload: "high", completed: false, priorityScore: 78, priorityLabel: "High Priority", priorityReason: "Deadline is near and workload is high."},
    {name: "Biology flashcards", subject: "Biology", deadline: new Date(now + 3 * 86400000), difficulty: "medium", workload: "medium", completed: false, priorityScore: 52, priorityLabel: "Needs Early Start", priorityReason: "Deadline in 3 days — start soon."},
    {name: "History reading summary", subject: "History", deadline: new Date(now + 6 * 86400000), difficulty: "easy", workload: "low", completed: true, priorityScore: 26, priorityLabel: "Quick Task", priorityReason: "Suggested using your current profile."},
  ];
  const batch = db.batch();
  for (const task of tasks) {
    batch.set(userRef.collection("tasks").doc(), {...task, deadline: admin.firestore.Timestamp.fromDate(task.deadline), createdAt: admin.firestore.FieldValue.serverTimestamp()});
  }
  for (const mood of [{mood: "happy", activity: "study", note: "Focused session."}, {mood: "neutral", activity: "rest", note: "Short break helped."}, {mood: "happy", activity: "study", note: "Better focus after planning."}]) {
    batch.set(userRef.collection("mood_logs").doc(), {...mood, createdAt: admin.firestore.FieldValue.serverTimestamp()});
  }
  batch.set(userRef.collection("posts").doc(), {insight: "Splitting hard work into two sessions helped me stay consistent.", supportData: "2/3 recent sessions logged as positive mood.", description: "I felt less overwhelmed.", relate: 1, helpful: 2, inspiring: 0, interesting: 1, createdAt: admin.firestore.FieldValue.serverTimestamp()});
  await batch.commit();
  return {ok: true};
});

// ─── Nightly insight refresh ──────────────────────────────────────────────────

export const nightlyInsightRefresh = onSchedule("every day 01:00", async () => {
  const db = admin.firestore();
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const activeUsers = await db.collection("users")
    .where("lastActiveDate", ">=", admin.firestore.Timestamp.fromDate(sevenDaysAgo))
    .get();
  for (const userDoc of activeUsers.docs) {
    try {
      const userRef = userDoc.ref;
      const [taskSnap, moodSnap, postSnap] = await Promise.all([
        userRef.collection("tasks").get(),
        userRef.collection("mood_logs").orderBy("createdAt", "desc").limit(20).get(),
        userRef.collection("posts").get(),
      ]);
      const tasks = taskSnap.docs.map((d) => {const data = d.data(); return {name: data.name, difficulty: data.difficulty, completed: data.completed};});
      const moods = moodSnap.docs.map((d) => {const data = d.data(); return {mood: data.mood, activity: data.activity};});
      const prompt = `Generate 3-5 productivity insights for a student.\nProfile: ${JSON.stringify(userDoc.data())}\nMoods: ${JSON.stringify(moods)}\nTasks: ${JSON.stringify(tasks)}\nThoughts shared: ${postSnap.size}\nReturn a JSON ARRAY: [{"title":"...","message":"...","why":"..."}]`;
      const insights = await callGemini(prompt) as InsightCard[];
      await userRef.set({runtimeInsights: insights, lastInsightRefresh: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    } catch (e) {
      console.error(`Insight refresh failed for user ${userDoc.id}:`, e);
    }
  }
});

// ─── Analyse task via Gemini ──────────────────────────────────────────────────

export const analyzeTask = onCall(async (request: CallableRequest<any>) => {
  const {title, description} = request.data;
  const productivityPreference = request.data.productivityPreference ?? "flexible";
  if (!title || !description) throw new HttpsError("invalid-argument", "title and description are required.");
  const prompt = `Analyze this student task and return a JSON object.\nTask title: "${title}"\nTask description: "${description}"\nStudent's productivity preference: "${productivityPreference}"\n\nReturn JSON with EXACTLY these fields:\n{\n  "difficulty": "easy" | "moderate" | "hard",\n  "estimatedMinutes": <number>,\n  "mentalLoad": "Low" | "Medium" | "High",\n  "focusLevel": "Light" | "Sustained" | "Deep",\n  "bestTime": "Morning" | "Evening" | "Flexible",\n  "method": "<study method recommendation>",\n  "steps": ["<step 1>", "<step 2>", "..."]\n}`;
  try {
    return await callGemini(prompt);
  } catch (e: any) {
    throw new HttpsError("internal", `Gemini API error: ${e.message}`);
  }
});

// ─── Generate insights via Gemini ─────────────────────────────────────────────

export const generateInsights = onCall(async (request: CallableRequest<any>) => {
  const {profile, moods = [], tasks = [], thoughtsShared = 0} = request.data;
  const prompt = `Generate 3-5 productivity insights for a student.\nProfile: ${JSON.stringify(profile)}\nRecent moods: ${JSON.stringify(moods)}\nTasks: ${JSON.stringify(tasks)}\nThoughts shared: ${thoughtsShared}\n\nReturn a JSON ARRAY:\n[{"title":"<3-5 word title>","message":"<1-2 sentence insight>","why":"<data-backed explanation>"}]`;
  try {
    return await callGemini(prompt) as InsightCard[];
  } catch (e: any) {
    throw new HttpsError("internal", `Gemini API error: ${e.message}`);
  }
});

// ─── Generate assessment analysis via Gemini ──────────────────────────────────

export const generateAssessmentAnalysis = onCall(async (request: CallableRequest<any>) => {
  const {answers} = request.data;
  if (!answers) throw new HttpsError("invalid-argument", "answers map is required.");
  const prompt = `You are a productivity psychologist. Analyse a student's self-assessment.\nAnswers: ${JSON.stringify(answers)}\n\nReturn JSON with EXACTLY these fields:\n{\n  "userProfileSummary": "<2-3 sentence summary>",\n  "energyType": "Morning-focused" | "Night-focused" | "Inconsistent",\n  "studyStyle": "Deep Focus" | "Short Burst" | "Easily Distracted",\n  "recoveryProfile": "Well-Rested" | "Under-recovered" | "Burnout Risk",\n  "socialEnergyType": "Introverted" | "Extroverted" | "Ambivert",\n  "thinkingStyle": "Structured" | "Creative" | "Hybrid",\n  "riskAnalysis": ["<risk 1>", "..."],\n  "riskReasoning": "<explanation>",\n  "personalizedStrategy": ["<strategy 1>", "..."],\n  "idealDayStructure": ["<block 1>", "..."],\n  "productivityIdentity": "<short identity label>"\n}`;
  try {
    return await callGemini(prompt);
  } catch (e: any) {
    throw new HttpsError("internal", `Gemini API error: ${e.message}`);
  }
});
