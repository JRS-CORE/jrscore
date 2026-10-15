'use strict';
const $ = id => document.getElementById(id);
const strings = {
  en: { console:'Players, permissions and server tools', back:'Back', close:'Close', center:'Center', home:'Overview', search:'Search options or players…', empty:'No matching options.', more:'Show more', mouse:'Click an option to continue', escape:'Esc · Close', input:'Action details', cancel:'Cancel', confirm:'Confirm', invalid:'Enter a valid value using the shown format.', copied:'Copied to clipboard.', failed:'Could not send the action. Try again.', section:'Current menu', options:'Options', available:'Available', language:'Language', sections:'Sections', drag:'Drag the title to move the panel.', menu:'Administration menu', actions:'Available actions' },
  ar: { console:'اللاعبون والصلاحيات وأدوات السيرفر', back:'رجوع', close:'إغلاق', center:'توسيط', home:'الرئيسية', search:'ابحث عن خيار أو لاعب…', empty:'لا توجد خيارات مطابقة.', more:'عرض المزيد', mouse:'اضغط على الخيار للمتابعة', escape:'Esc · إغلاق', input:'تفاصيل الإجراء', cancel:'إلغاء', confirm:'تأكيد', invalid:'أدخل قيمة صحيحة بالصيغة الموضحة.', copied:'تم النسخ.', failed:'تعذر إرسال الإجراء. حاول مجددًا.', section:'القائمة الحالية', options:'الخيارات', available:'المتاح', language:'اللغة', sections:'الأقسام', drag:'اسحب العنوان لتحريك اللوحة.', menu:'قائمة الإدارة', actions:'الإجراءات المتاحة' }
};
let language = 'en', state = null, limit = 80, pending = false;
const text = value => String(value ?? '').replace(/<br\s*\/?\s*>/gi, '\n').replace(/<[^>]*>/g, '').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
const t = key => strings[language][key];
const sectionImages = {home:'home',administration:'badge',boost:'health',database:'records',teleport:'compass',devtools:'tools'};
const iconKeys = new Set(['home','badge','health','records','compass','tools','weapon','horse','wagon','money','gold','inventory','binoculars','ammo']);
let selectedIcon = 'badge';
const iconName = key => `jrs_admin_${iconKeys.has(key) ? key : 'badge'}`;
function makeImage(name, className) {
  const img = document.createElement('img'); img.src = `img/${name}.png`; img.alt = ''; img.className = className; img.draggable = false;
  return img;
}
function setLanguage(code) {
  language = code === 'ar' ? 'ar' : 'en';
  document.documentElement.lang = language;
  document.documentElement.dir = language === 'ar' ? 'rtl' : 'ltr';
  document.querySelectorAll('[data-text]').forEach(el => el.textContent = t(el.dataset.text));
  $('search').placeholder = t('search');
  $('close').ariaLabel = language === 'ar' ? 'إغلاق' : 'Close';
  $('languageBadge').textContent = language === 'ar' ? 'العربية' : 'English';
  $('metricLanguage').textContent = $('languageBadge').textContent;
  $('positionReset').ariaLabel = t('center');
  $('search').ariaLabel = t('search');
  $('navigation').ariaLabel = t('sections');
  $('list').ariaLabel = t('options');
}
function toast(message) { $('toast').textContent = message; $('toast').hidden = false; setTimeout(() => $('toast').hidden = true, 3000); }
async function post(name, data = {}) {
  const parent = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'jrs_admin';
  try {
    const response = await fetch(`https://${parent}/${name}`, { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ token:state?.token, ...data }) });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return await response.json();
  } catch { toast(t('failed')); return { ok:false }; }
}
function renderList() {
  const scrollTop = $('list').scrollTop;
  const query = $('search').value.trim().toLocaleLowerCase();
  const rows = (state?.elements || []).filter(row => `${text(row.label)} ${text(row.desc)}`.toLocaleLowerCase().includes(query));
  $('count').textContent = `${rows.length}`;
  $('list').replaceChildren();
  $('empty').hidden = rows.length > 0;
  $('more').hidden = rows.length <= limit;
  const elements = state?.elements || [];
  $('metricSection').textContent = text(state?.subtitle) || t('home');
  $('metricOptions').textContent = String(elements.length);
  $('metricAvailable').textContent = String(elements.filter(row => !row.disabled).length);
  for (const row of rows.slice(0, limit)) {
    const button = document.createElement('button'); button.className = 'option slot'; button.type = 'button';
    button.disabled = row.disabled || state.busy || pending;
    const number = document.createElement('span'); number.className = 'option-index'; number.textContent = String(row.index).padStart(2,'0');
    const copy = document.createElement('span'); copy.className = 'option-copy meta';
    const label = document.createElement('b'); label.className = 'option-label'; label.textContent = text(row.label);
    const desc = document.createElement('small'); desc.className = 'option-desc muted'; desc.textContent = text(row.desc);
    const arrow = document.createElement('span'); arrow.className = 'option-arrow'; arrow.textContent = '›';
    const icon = row.icon || sectionImages[state?.section] || 'badge';
    copy.append(label,desc); button.append(number,makeImage(iconName(icon),'admin-tool-image'),copy,arrow);
    button.addEventListener('click', async () => { if(pending) return; selectedIcon = icon; pending = true; renderList(); await post('adminSelect',{index:row.index}); pending = false; renderList(); });
    $('list').append(button);
  }
  $('list').scrollTop = scrollTop;
}
function renderNavigation() {
  $('navigation').replaceChildren();
  const navigation = Array.isArray(state?.navigation) ? [{id:'home',label:t('home'),desc:''},...state.navigation] : [];
  for (const row of navigation) {
    const button = document.createElement('button'); button.type = 'button';
    button.className = `tab${row.id === state.section ? ' active' : ''}`;
    button.setAttribute('aria-selected',String(row.id === state.section));
    button.disabled = !!state.input || !!state.busy || pending;
    button.dataset.section = row.id; button.title = text(row.label); button.ariaLabel = text(row.label);
    if (row.id === state.section) button.setAttribute('aria-current','page');
    const copy = document.createElement('span'); copy.className = 'admin-farm-card-body';
    const label = document.createElement('strong'); label.textContent = text(row.label);
    const desc = document.createElement('small'); desc.textContent = text(row.desc);
    copy.append(label,desc); button.append(makeImage(iconName(sectionImages[row.id]),'admin-farm-thumb'),copy);
    button.addEventListener('click',async () => {
      if (pending) return; pending = true; renderList(); renderNavigation();
      await post('adminNavigate',{section:row.id}); pending = false; renderList(); renderNavigation();
    });
    $('navigation').append(button);
  }
}
function renderInput(focus) {
  const data = state?.input;
  $('modal').hidden = !data;
  if (!data) return;
  $('inputIcon').src = `img/${iconName(selectedIcon)}.png`;
  $('inputTitle').textContent = text(data.title);
  $('inputHelp').textContent = text(data.help);
  $('inputValue').hidden = data.multiline;
  $('inputArea').hidden = !data.multiline;
  const field = data.multiline ? $('inputArea') : $('inputValue');
  $('inputValue').type = data.type === 'number' ? 'number' : 'text';
  $('inputValue').step = 'any';
  field.maxLength = 1000; field.placeholder = text(data.placeholder);
  $('submitInput').textContent = text(data.button) || t('confirm');
  if (focus) { field.value = ''; $('inputError').textContent = ''; field.focus(); document.querySelector('.admin-dialog-body').scrollTop = 0; }
}
window.addEventListener('message', event => {
  const data = event.data;
  if (!data || typeof data !== 'object') return;
  if (data.type === 'jrsLanguage') { setLanguage(data.language); renderNavigation(); return; }
  if (data.action === 'admin:close') { $('panel').hidden = true; $('panel').setAttribute('aria-hidden','true'); state = null; pending = false; return; }
  if (data.action === 'admin:open') {
    const changed = data.token !== state?.token;
    const newInput = !!data.input && (!state?.input || changed);
    state = data; pending = false; setLanguage(data.language);
    $('panel').hidden = false; $('panel').setAttribute('aria-hidden','false'); $('title').textContent = text(data.title) || 'JRS ADMIN'; $('subtitle').textContent = text(data.subtitle);
    $('back').disabled = !data.canBack || !!data.input || data.busy;
    if (changed) { $('search').value = ''; limit = 80; $('list').scrollTop = 0; $('toast').hidden = true; }
    renderList(); renderNavigation(); renderInput(newInput); return;
  }
  if (Object.prototype.hasOwnProperty.call(data,'string')) copyToClipboard(String(data.string));
});
async function copyToClipboard(value) {
  try { await navigator.clipboard.writeText(value); toast(t('copied')); }
  catch {
    const el = document.createElement('textarea'); el.value = value; document.body.append(el); el.select();
    const copied = document.execCommand('copy'); el.remove(); if(copied) toast(t('copied'));
  }
}
$('close').addEventListener('click', () => post('adminClose'));
$('back').addEventListener('click', () => post('adminBack'));
$('search').addEventListener('input', () => {limit = 80; $('list').scrollTop = 0; renderList();});
$('more').addEventListener('click', () => {limit += 80; renderList();});
$('cancelInput').addEventListener('click', () => post('adminInput',{cancelled:true}));
$('inputForm').addEventListener('submit', async event => {
  event.preventDefault(); if (!state?.input || pending) return;
  const field = state.input.multiline ? $('inputArea') : $('inputValue');
  const value = field.value.trim();
  let valid = !!value && (state.input.type !== 'number' || Number.isFinite(Number(value)));
  if (valid && state.input.pattern) {
    try { valid = new RegExp(`^(?:${state.input.pattern})$`, 'u').test(value); }
    catch { valid = false; }
  }
  if (!valid) { $('inputError').textContent = t('invalid'); return; }
  pending = true; $('submitInput').disabled = true;
  await post('adminInput',{value}); pending = false; $('submitInput').disabled = false;
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && state) { event.preventDefault(); post(state.input ? 'adminInput':'adminClose', state.input ? {cancelled:true}:{}); }
});
// Header drag follows the supplied panel behaviour without changing NUI focus.
let drag = null;
const shell = $('adminShell'), header = $('adminHeader');
function movePanel(x,y) {
  const width = shell.offsetWidth, height = shell.offsetHeight;
  shell.style.setProperty('left',`${Math.max(0,Math.min(x,window.innerWidth-width))}px`,'important');
  shell.style.setProperty('top',`${Math.max(0,Math.min(y,window.innerHeight-height))}px`,'important');
  shell.style.setProperty('transform','none','important');
}
function centerPanel() { shell.style.removeProperty('left'); shell.style.removeProperty('top'); shell.style.removeProperty('transform'); }
header.addEventListener('pointerdown',event => {
  if (event.button !== 0 || state?.input || event.target.closest('button,input,textarea,a')) return;
  const box = shell.getBoundingClientRect(); drag = {id:event.pointerId,dx:event.clientX-box.left,dy:event.clientY-box.top};
  header.setPointerCapture(event.pointerId); event.preventDefault();
});
header.addEventListener('pointermove',event => { if (drag?.id === event.pointerId) movePanel(event.clientX-drag.dx,event.clientY-drag.dy); });
header.addEventListener('pointerup',event => { if (drag?.id === event.pointerId) { header.releasePointerCapture(event.pointerId); drag = null; } });
header.addEventListener('pointercancel',()=> { drag = null; });
header.addEventListener('dblclick',event => { if (!event.target.closest('button')) centerPanel(); });
$('positionReset').addEventListener('click',centerPanel);
window.addEventListener('resize',()=> { if (shell.style.transform === 'none' && !shell.closest('[hidden]')) { const box = shell.getBoundingClientRect(); movePanel(box.left,box.top); } });
setLanguage('en');
post('adminReady');

// Wheel over the panel also reaches the active list; nested text areas keep native scrolling.
shell.addEventListener('wheel', event => {
  if (!state || $('panel').hidden || event.ctrlKey || !event.deltaY) return;
  const pane = state.input ? document.querySelector('.admin-dialog-body') : $('list');
  if (pane.scrollHeight <= pane.clientHeight) return;
  let target = event.target instanceof Element ? event.target : null;
  if (target?.closest('textarea,select,input[type=number]')) return;
  if (pane.contains(target)) return;
  const amount = event.deltaY * (event.deltaMode === 1 ? 24 : event.deltaMode === 2 ? pane.clientHeight : 1);
  event.preventDefault(); pane.scrollTop += amount;
}, {passive:false});
