"use strict";

/* Hands-free conversation ("🎙 Eller serbest"): the mic opens by itself when the app is silent, the utterance is
   sent after a pause, the reply is spoken, then the mic opens again. The pause before sending is adjustable and
   grows when you have only said a few words so far (a thinking pause is not the end of your turn).
   Uses the normal recorder/turn code of app.js; "Eller serbest" off = push-to-talk as before. */

const hf = {
  on: false,
  state: "idle",        // idle | starting | listening | sending
  timer: 0,
  startedAt: 0,
  lastVoice: 0,
  voiceMs: 0,
  lastTick: 0,
  floor: 0,
  calibrated: false,
  calibSamples: [],
};

const HF_NO_SPEECH_MS = 15000;
const hfBtn = $("#handsfree-btn");
const hfPause = $("#handsfree-pause");

function hfStored(key, fallback) {
  try { return localStorage.getItem(key) ?? fallback; } catch { return fallback; }
}
function hfSave(key, value) {
  try { localStorage.setItem(key, value); } catch {}
}

if (hfPause) {
  hfPause.value = hfStored("hfPause", "1800");
  hfPause.addEventListener("change", () => hfSave("hfPause", hfPause.value));
}

function hfBusy() {
  return Boolean(chat.turn || chat.speaking || player.playing || recorder.media);
}

function hfLevel() {
  const a = recorder.analyser;
  if (!a) return 0;
  const buf = new Float32Array(a.fftSize);
  a.getFloatTimeDomainData(buf);
  let sum = 0;
  for (const v of buf) sum += v * v;
  return Math.sqrt(sum / buf.length);
}

function hfSetHint(text) {
  if (hf.on && text) talkHint.textContent = text;
}

async function hfBegin() {
  hf.state = "starting";
  await pressTalk();
  if (!recorder.media) { hf.state = "idle"; return; }  // permission denied or released meanwhile
  hf.state = "listening";
  hf.startedAt = hf.lastTick = performance.now();
  hf.lastVoice = 0;
  hf.voiceMs = 0;
  hf.calibrated = false;
  hf.calibSamples = [];
  hfSetHint("🎙 Dinliyorum… (konuşmayı bitirince otomatik gönderilir)");
}

async function hfSend() {
  hf.state = "sending";
  await releaseTalk(true);
  hf.state = "idle";
}

async function hfCancelSilent() {
  hf.state = "sending";
  await recorder.stop();  // nothing was said: drop the recording
  hf.state = "idle";
}

function hfMonitor() {
  const now = performance.now();
  const level = hfLevel();
  const dt = now - hf.lastTick;
  hf.lastTick = now;

  // The first half second is the room's noise level; speech has to be clearly above it.
  if (!hf.calibrated) {
    hf.calibSamples.push(level);
    if (now - hf.startedAt >= 500) {
      const avg = hf.calibSamples.reduce((a, b) => a + b, 0) / Math.max(1, hf.calibSamples.length);
      hf.floor = avg;
      hf.calibrated = true;
    }
    return;
  }
  const threshold = Math.max(0.02, hf.floor * 3);
  if (level > threshold) {
    hf.lastVoice = now;
    hf.voiceMs += dt;
    hfSetHint("🎙 Seni duyuyorum…");
    return;
  }
  if (hf.lastVoice) {
    // A few words so far? Give a thinking pause more room.
    const pause = Number(hfPause?.value || 1800) + (hf.voiceMs < 1500 ? 700 : 0);
    if (now - hf.lastVoice > pause) hfSend();
  } else if (now - hf.startedAt > HF_NO_SPEECH_MS) {
    hfCancelSilent();
  }
}

function hfTick() {
  if (!hf.on) return;
  if (talkBtn.disabled || !onConversationPage()) return;
  if (hf.state === "listening" && recorder.media) return hfMonitor();
  if (hf.state === "listening" && !recorder.media) hf.state = "idle";  // stopped by something else
  if (hf.state === "idle" && !hfBusy()) hfBegin();
}

function hfToggle(force) {
  hf.on = typeof force === "boolean" ? force : !hf.on;
  hfBtn.setAttribute("aria-pressed", String(hf.on));
  hfBtn.classList.toggle("on", hf.on);
  clearInterval(hf.timer);
  if (hf.on) {
    player.unlock();
    hf.state = "idle";
    hf.timer = setInterval(hfTick, 100);
    hfTick();
  } else {
    if (recorder.media) recorder.stop();
    hf.state = "idle";
    updateTalkHint();
  }
}

hfBtn?.addEventListener("click", () => hfToggle());
// Pressing the talk button / typing by hand pauses nothing: the loop just waits until the app is idle again.
