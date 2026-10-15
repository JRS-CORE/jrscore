const RES = (typeof GetParentResourceName === "function") ? GetParentResourceName() : "jrs_billing";
const TEXT = {
  en: { title: "Bill", player: "Player ID", amount: "Amount ($)", reason: "Reason", cancel: "Cancel", send: "Send bill" },
  ar: { title: "فاتورة", player: "رقم اللاعب", amount: "المبلغ ($)", reason: "السبب", cancel: "إلغاء", send: "إرسال الفاتورة" },
};
const $ = (id) => document.getElementById(id);
const post = (name, data) => fetch(`https://${RES}/${name}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data || {}) }).catch(() => {});

function open(d) {
  const t = TEXT[d.language === "ar" ? "ar" : "en"];
  document.body.classList.toggle("rtl", d.language === "ar");
  $("title").textContent = t.title;
  document.querySelectorAll("[data-t]").forEach((el) => { el.textContent = t[el.dataset.t]; });
  $("amount").max = d.max || 1000;
  $("form").reset();
  $("panel").classList.remove("hidden");
  $("playerId").focus();
}
window.addEventListener("message", (e) => {
  if (e.data.type === "open") open(e.data);
  if (e.data.type === "close") $("panel").classList.add("hidden");
});
$("form").addEventListener("submit", (e) => {
  e.preventDefault();
  post("send", { playerId: $("playerId").value, amount: $("amount").value, reason: $("reason").value.trim() });
});
$("cancel").onclick = () => post("close");
document.addEventListener("keydown", (e) => { if (e.key === "Escape") post("close"); });
