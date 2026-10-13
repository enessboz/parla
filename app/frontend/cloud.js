"use strict";

/* Cloud models: Ayarlar → "Bulut modeller". API key per provider, live model list (recommended first),
   "default" / test buttons. Models appear in the normal model list and the chat picker as "☁️ Provider · model". */

const cloudUi = { state: null };

async function refreshCloud() {
  const box = $("#cloud-providers");
  if (!box) return;
  try {
    cloudUi.state = await (await fetch("/api/cloud")).json();
  } catch {
    box.replaceChildren(elm("p", { class: "muted" }, "Bulut ayarları alınamadı."));
    return;
  }
  renderCloud();
}

function cloudRow(p) {
  const msg = elm("div", { class: "muted small", role: "status" }, "");
  const keyInput = elm("input", { type: "password", placeholder: p.configured ? "Anahtar kayıtlı ✓ (değiştirmek için yeni anahtarı yapıştır)" : `${p.label} API anahtarı`,
    autocomplete: "off", spellcheck: "false" });
  const save = elm("button", { type: "button", class: "primary small", onclick: async () => {
    msg.textContent = "Kaydediliyor…";
    const r = await fetch("/api/cloud/key", { method: "PUT", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider: p.id, key: keyInput.value }) });
    if (!r.ok) { msg.textContent = "Kaydedilemedi."; return; }
    cloudUi.state = await r.json();
    renderCloud();
    if (typeof refreshModels === "function") refreshModels();
  } }, "Kaydet");
  const remove = p.configured && elm("button", { type: "button", class: "ghost small danger", onclick: async () => {
    if (!confirm(`${p.label} anahtarı kaldırılsın mı?`)) return;
    await fetch("/api/cloud/key", { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ provider: p.id, key: "" }) });
    await refreshCloud();
    if (typeof refreshModels === "function") refreshModels();
  } }, "Anahtarı kaldır");

  const rows = [elm("div", { class: "cloud-line" }, elm("strong", {}, p.label), keyInput, save, remove)];
  if (p.configured) {
    const rec = new Set(p.recommended);
    const rest = p.models.filter((m) => !rec.has(m));
    const select = elm("select", { "aria-label": `${p.label} modeli` },
      elm("optgroup", { label: "Önerilen" }, ...p.recommended.map((m) => elm("option", { value: m }, m))),
      rest.length ? elm("optgroup", { label: "Tüm modeller" }, ...rest.map((m) => elm("option", { value: m }, m))) : "");
    select.value = p.default_model && p.models.includes(p.default_model) ? p.default_model : (p.recommended[0] || "");
    const id = () => `${p.id}:${select.value}`;
    const act = async (path, body, method = "PUT") => {
      const r = await fetch(path, { method, headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      return r;
    };
    rows.push(elm("div", { class: "cloud-line" }, select,
      elm("button", { type: "button", class: "ghost small", onclick: async () => {
        const r = await act("/api/llm/default", { model: id() });
        msg.textContent = r.ok ? `✓ Varsayılan model: ${p.label} · ${select.value}` : "Ayarlanamadı.";
        if (typeof refreshModels === "function") refreshModels();
      } }, "Varsayılan yap"),
      elm("button", { type: "button", class: "ghost small", onclick: async () => {
        msg.textContent = "Test ediliyor…";
        const r = await (await act("/api/cloud/test", { model: id() }, "POST")).json();
        msg.textContent = r.ok ? `✅ ${p.label} · ${select.value}: ${r.text}` : `❌ ${r.error}`;
      } }, "Bağlantıyı test et")));
  }
  rows.push(msg);
  return elm("div", { class: "cloud-provider" }, ...rows);
}

function renderCloud() {
  $("#cloud-providers").replaceChildren(...cloudUi.state.providers.map(cloudRow));
}

document.addEventListener("DOMContentLoaded", refreshCloud);
document.querySelector('[data-view="settings"]')?.addEventListener("click", refreshCloud);
