"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const admin = require("firebase-admin");

admin.initializeApp();

// ─── Gemini helper ─────────────────────────────────────────────────────────────
// API key is hardcoded here for simplicity.
// For production, use: firebase functions:secrets:set GEMINI_API_KEY
// and replace the string below with: process.env.GEMINI_API_KEY
const GEMINI_API_KEY = "AIzaSyAlKQR2tAL0EaL7j8qmuiCWt9HTEWtM69A";

const SYSTEM_JSON =
  "You are a helpful AI assistant for a student productivity app. " +
  "Respond ONLY with valid raw JSON — no markdown fences, no explanation, no preamble. " +
  "Do not wrap the response in ```json or ``` blocks.";

const callGemini = async (prompt) => {
  const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
  const model = genAI.getGenerativeModel({
    model: "gemini-2.0-flash",
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: 2048,
      responseMimeType: "application/json",
    },
  });
  const result = await model.generateContent(`${SYSTEM_JSON}\n\n${prompt}`);
  let text = result.response.text().trim();
  // Strip any leftover fences defensively
  text = text.replace(/^```json\s*/gim, "").replace(/^```\s*/gim, "").replace(/```\s*$/gim, "").trim();
  return JSON.parse(text);
};

// ─── Analyse task via Gemini ───────────────────────────────────────────────────
// Returns the full set of fields expected by TaskItem in app_models.dart:
// difficulty, workload, estimatedMinutes, mentalLoad, focusLevel, bestTime,
// method, steps, studyTips, suggestedResources, productivityAdvice
exports.analyzeTask = onCall(async (request) => {
  const { title, description, subject, productivityPreference, studyFocus, personality } = request.data;

  if (!title || !description) {
    throw new HttpsError("invalid-argument", "title and description are required.");
  }

  const prompt = `You are an AI study assistant for a student productivity app.
Analyze the following student task and return a detailed JSON study plan.

Task title: "${title}"
Task description: "${description}"
Subject: "${subject || "General"}"
Student productivity preference: "${productivityPreference || "flexible"}"
Student study focus level (1-5): ${studyFocus || 3}
Student personality: "${personality || "introvert"}"

Return a JSON object with EXACTLY these fields — all required:
{
  "difficulty": one of "easy", "medium", or "hard",
  "workload": one of "low", "medium", or "high",
  "estimatedMinutes": integer (realistic study time in minutes for THIS specific task),
  "mentalLoad": one of "Low", "Medium", or "High",
  "focusLevel": one of "Light", "Sustained", or "Deep",
  "bestTime": one of "Morning", "Evening", or "Flexible",
  "method": string (1-2 sentences describing the BEST study method for THIS specific task and subject),
  "steps": array of exactly 5 strings (concrete, specific steps to complete THIS task — not generic advice),
  "studyTips": array of exactly 3 strings (practical tips tailored to this subject and task),
  "suggestedResources": array of 2-4 objects, each with "title" (string) and "url" (string — use real known URLs or empty string),
  "productivityAdvice": string (1-2 sentences of personalized motivational advice referencing the student personality and preference)
}

IMPORTANT: The steps and tips must be SPECIFIC to "${title}" in "${subject || "this subject"}", not generic placeholders.`;

  try {
    return await callGemini(prompt);
  } catch (e) {
    console.error("[analyzeTask] Gemini error:", e);
    throw new HttpsError("internal", `Gemini API error: ${e.message}`);
  }
});

// ─── Generate insights via Gemini ──────────────────────────────────────────────
exports.generateInsights = onCall(async (request) => {
  const { profile = {}, moods = [], tasks = [], thoughtsShared = 0 } = request.data;

  const prompt = `You are a student productivity AI.
Generate 3-5 personalized insights for this student based on their real data.

Profile: ${JSON.stringify(profile)}
Recent moods: ${JSON.stringify(moods)}
Tasks: ${JSON.stringify(tasks)}
Learning cards shared: ${thoughtsShared}

Return a JSON ARRAY of 3-5 objects. Each object must have:
- "title": string (3-5 words, specific and punchy)
- "message": string (1-2 sentences, specific to their data — not generic)
- "why": string (concrete explanation referencing their actual numbers and patterns)

Return only the array — no wrapping object.`;

  try {
    const result = await callGemini(prompt);
    // Normalize: function may return array directly or wrapped in { insights: [] }
    if (Array.isArray(result)) return result;
    if (result && Array.isArray(result.insights)) return result.insights;
    return [];
  } catch (e) {
    console.error("[generateInsights] Gemini error:", e);
    throw new HttpsError("internal", `Gemini API error: ${e.message}`);
  }
});

// ─── Generate assessment analysis via Gemini ───────────────────────────────────
exports.generateAssessmentAnalysis = onCall(async (request) => {
  const { answers } = request.data;

  if (!answers) {
    throw new HttpsError("invalid-argument", "answers map is required.");
  }

  const prompt = `You are a productivity psychologist analyzing a student's self-assessment.
Based on the answers below, build a detailed psychographic profile.

Assessment answers: ${JSON.stringify(answers)}

Return a JSON object with EXACTLY these fields — all required:
{
  "userProfileSummary": string (2-3 sentences summarizing this student's unique learning personality),
  "energyType": one of "Morning-focused", "Night-focused", or "Inconsistent",
  "studyStyle": one of "Deep Focus", "Short Burst", or "Easily Distracted",
  "recoveryProfile": one of "Well-Rested", "Under-recovered", or "Burnout Risk",
  "socialEnergyType": one of "Introverted", "Extroverted", or "Ambivert",
  "thinkingStyle": one of "Structured", "Creative", or "Hybrid",
  "riskAnalysis": array of exactly 2 strings (specific risks for this student),
  "riskReasoning": string (explanation of identified risks based on their answers),
  "personalizedStrategy": array of exactly 3 strings (concrete strategies for this student),
  "idealDayStructure": array of exactly 3 strings (morning block, afternoon block, evening block),
  "productivityIdentity": string (short catchy label like "Night Owl Deep Thinker")
}`;

  try {
    return await callGemini(prompt);
  } catch (e) {
    console.error("[generateAssessmentAnalysis] Gemini error:", e);
    throw new HttpsError("internal", `Gemini API error: ${e.message}`);
  }
});

// ─── Recalculate task priority (local logic — no Gemini needed) ───────────────
exports.recalculateTaskPriority = onCall(async (request) => {
  const task = request.data.task;
  const profile = request.data.profile;
  const recentMoods = request.data.recentMoods ?? [];

  const now = new Date();
  const deadline = new Date(task.deadline);
  const hoursUntilDeadline = Math.floor((deadline - now) / (1000 * 60 * 60));

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
  const label = score >= 70 ? "Start First" : score >= 40 ? "Next" : "Later";

  const reasons = [];
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

// ─── Award XP ──────────────────────────────────────────────────────────────────
exports.awardXp = onCall(async (request) => {
  const { eventType, difficulty, userId } = request.data;

  let gain = 0;
  if (eventType === "task_completed") gain = difficulty === "hard" ? 50 : difficulty === "medium" ? 35 : 20;
  else if (eventType === "mood_logged") gain = 5;
  else if (eventType === "insight_posted") gain = 10;

  const ref = admin.firestore().collection("users").doc(userId);
  const snap = await ref.get();
  const data = snap.data() ?? {};
  const xp = (data.xp ?? 0) + gain;
  const level = Math.floor(Math.sqrt(xp / 100)) + 1;
  await ref.set({ xp, level }, { merge: true });
  return { xp, level, gained: gain };
});

// ─── Seed demo data ────────────────────────────────────────────────────────────
exports.seedDemoData = onCall(async (request) => {
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
  }, { merge: true });

  const batch = db.batch();
  for (const task of [
    { name: "Math revision: derivatives", subject: "Mathematics", deadline: new Date(now + 86400000), difficulty: "hard", workload: "high", completed: false, priorityScore: 78, priorityLabel: "Start First", priorityReason: "Deadline is near and workload is high." },
    { name: "Biology flashcards", subject: "Biology", deadline: new Date(now + 3 * 86400000), difficulty: "medium", workload: "medium", completed: false, priorityScore: 52, priorityLabel: "Next", priorityReason: "Deadline is near." },
  ]) {
    batch.set(userRef.collection("tasks").doc(), { ...task, deadline: admin.firestore.Timestamp.fromDate(task.deadline), createdAt: admin.firestore.FieldValue.serverTimestamp() });
  }
  for (const mood of [
    { mood: "happy", activity: "study", note: "Focused session." },
    { mood: "neutral", activity: "rest", note: "Short break helped." },
  ]) {
    batch.set(userRef.collection("mood_logs").doc(), { ...mood, createdAt: admin.firestore.FieldValue.serverTimestamp() });
  }
  await batch.commit();
  return { ok: true };
});

// ─── Nightly insight refresh (scheduled) ──────────────────────────────────────
exports.nightlyInsightRefresh = onSchedule("every day 01:00", async () => {
  const db = admin.firestore();
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const activeUsers = await db.collection("users")
    .where("lastActiveDate", ">=", admin.firestore.Timestamp.fromDate(sevenDaysAgo))
    .get();

  for (const userDoc of activeUsers.docs) {
    try {
      const userRef = userDoc.ref;
      const [taskSnap, moodSnap] = await Promise.all([
        userRef.collection("tasks").limit(20).get(),
        userRef.collection("mood_logs").orderBy("createdAt", "desc").limit(20).get(),
      ]);
      const tasks = taskSnap.docs.map((d) => {
        const data = d.data();
        return { name: data.name, subject: data.subject, difficulty: data.difficulty, completed: data.completed };
      });
      const moods = moodSnap.docs.map((d) => {
        const data = d.data();
        return { mood: data.mood, activity: data.activity };
      });

      const prompt = `Generate 3-5 productivity insights for a student.
Profile: ${JSON.stringify(userDoc.data())}
Recent moods: ${JSON.stringify(moods)}
Tasks: ${JSON.stringify(tasks)}

Return a JSON ARRAY: [{"title":"...","message":"...","why":"..."}]`;

      const insights = await callGemini(prompt);
      await userRef.set({
        runtimeInsights: Array.isArray(insights) ? insights : [],
        runtimeInsightsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    } catch (e) {
      console.error(`Nightly refresh failed for user ${userDoc.id}:`, e);
    }
  }
});
