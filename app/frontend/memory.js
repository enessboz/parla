"use strict";

/* The conversation partner's memory (Ayarlar → 🧠) and the "AI starts the chat" button of the empty chat. */

async function refreshMemory() {
  const box = $("#memory-list");
  if (!box) return;
  let data;
  try { data = await (await fetch("/api/memory")).json(); } catch { return; }
  renderMemory(data.notes);
}

function renderMemory(notes) {
  const box = $("#memory-list");
  if (!notes.length) {
    box.replaceChildren(ModelCards.h("p", { class: "muted" }, "Henüz bir şey yok. Serbest sohbet ettikçe burası dolar."));
    return;
  }
  box.replaceChildren(...notes.map((n) => ModelCards.h("div", { class: "memory-note" },
    ModelCards.h("span", {}, n.text),
    ModelCards.h("button", { type: "button", class: "ghost small danger", title: "Bu notu unut", onclick: async () => {
      renderMemory((await (await fetch(`/api/memory/${n.id}`, { method: "DELETE" })).json()).notes);
    } }, "✕"))));
}

$("#memory-clear")?.addEventListener("click", async () => {
  if (!confirm("Konuşma partnerinin senin hakkında hatırladığı her şey silinsin mi?")) return;
  renderMemory((await (await fetch("/api/memory", { method: "DELETE" })).json()).notes);
});

$("#memory-form")?.addEventListener("submit", async (e) => {
  e.preventDefault();
  const text = $("#memory-input").value.trim();
  if (!text) return;
  $("#memory-input").value = "";
  renderMemory((await (await fetch("/api/memory", { method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text }) })).json()).notes);
});

/** The AI speaks first in a free conversation. */
function startFreeChat() {
  location.hash = "#/conversation";
  resetChat();
  player.unlock();
  const clientId = startTurn(null);
  socket.send(JSON.stringify({ type: "start_chat", client_id: clientId, speak: voiceReplies() }));
}

document.addEventListener("click", (e) => {
  if (e.target.closest("[data-start-chat]")) startFreeChat();
});

document.addEventListener("DOMContentLoaded", refreshMemory);
