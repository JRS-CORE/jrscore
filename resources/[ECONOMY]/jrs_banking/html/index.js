'use strict';
const $ = id => document.getElementById(id);
const words = {
  en: {
    console:'Accounts, savings and safebox', center:'Center', close:'Close', back:'Back',
    mouse:'Click an option to continue', search:'Search bank options or branches...', empty:'No matching options',
    drag:'Drag the title to move the panel.', escape:'Esc · Close', input:'BANK TRANSACTION', cancel:'Cancel', confirm:'Confirm',
    overview:'Overview', cash:'Cash', gold:'Gold', accounts:'Other accounts', vault:'Safebox',
    cashBalance:'Cash balance', goldBalance:'Gold balance', slots:'Safebox slots',
    dcash:'Deposit cash', wcash:'Withdraw cash', dgold:'Deposit gold', wgold:'Withdraw gold',
    dcashHelp:'Move cash from your wallet into this bank account.', wcashHelp:'Withdraw cash from this account into your wallet.',
    dgoldHelp:'Deposit gold from your wallet into this bank account.', wgoldHelp:'Withdraw gold from this account into your wallet.',
    openVault:'Open safebox', openVaultHelp:'Store and withdraw items using your bank inventory.',
    upgrade:'Buy safebox slots', upgradeHelp:'Add storage slots to this branch’s safebox.',
    accountsHelp:'Transfer money from your account in another branch to this bank.',
    transfer:'Transfer to this branch', from:'From', to:'To', balance:'Balance', fee:'Transfer fee', received:'Amount received',
    amount:'Amount', quantity:'Number of slots', price:'Price per slot', total:'Total cost', remaining:'Available to buy',
    afterUpgrade:'Slots after purchase', noAccounts:'No other bank accounts yet.', noAccountsHelp:'Visit another branch to open an account.',
    invalid:'Enter a positive amount with no more than two decimal places.', integerOnly:'Enter a positive whole number.',
    insufficient:'The amount exceeds the displayed account balance.', maxSlots:'The requested slots exceed this bank’s limit.',
    buySlots:'Buy safebox slots first.', unavailable:'This option is currently unavailable.',
    network:'The request could not be sent. Try again.', confirmTransfer:'Confirm transfer',
    branch_Valentine:'Valentine Bank', branch_Blackwater:'Blackwater Bank', branch_SaintDenis:'Saint Denis Bank', branch_Rhodes:'Rhodes Bank'
  },
  ar: {
    console:'الحسابات والمدخرات والخزنة', center:'توسيط', close:'إغلاق', back:'رجوع',
    mouse:'اضغط على الخيار للمتابعة', search:'ابحث عن خيار أو فرع...', empty:'لا توجد خيارات مطابقة',
    drag:'اسحب العنوان لتحريك الواجهة.', escape:'Esc · إغلاق', input:'عملية بنكية', cancel:'إلغاء', confirm:'تأكيد',
    overview:'الرئيسية', cash:'الأموال', gold:'الذهب', accounts:'الحسابات الأخرى', vault:'الخزنة',
    cashBalance:'الرصيد النقدي', goldBalance:'رصيد الذهب', slots:'خانات الخزنة',
    dcash:'إيداع أموال', wcash:'سحب أموال', dgold:'إيداع ذهب', wgold:'سحب ذهب',
    dcashHelp:'أودع الأموال من محفظتك في حساب هذا الفرع.', wcashHelp:'اسحب الأموال من حساب هذا الفرع إلى محفظتك.',
    dgoldHelp:'أودع الذهب من محفظتك في حساب هذا الفرع.', wgoldHelp:'اسحب الذهب من حساب هذا الفرع إلى محفظتك.',
    openVault:'فتح الخزنة', openVaultHelp:'إيداع وسحب الأغراض من مخزون البنك.',
    upgrade:'شراء خانات للخزنة', upgradeHelp:'أضف خانات تخزين لخزنتك في هذا الفرع.',
    accountsHelp:'حوّل الأموال من حسابك في فرع آخر إلى هذا الفرع.',
    transfer:'تحويل إلى هذا الفرع', from:'من', to:'إلى', balance:'الرصيد', fee:'رسوم التحويل', received:'المبلغ المستلم',
    amount:'المبلغ', quantity:'عدد الخانات', price:'سعر الخانة', total:'التكلفة الإجمالية', remaining:'الخانات المتاحة للشراء',
    afterUpgrade:'الخانات بعد الشراء', noAccounts:'لا توجد حسابات أخرى حاليًا.', noAccountsHelp:'زر فرعًا آخر لفتح حساب فيه.',
    invalid:'أدخل مبلغًا أكبر من صفر، بمنزلتين عشريتين كحد أقصى.', integerOnly:'أدخل عددًا صحيحًا أكبر من صفر.',
    insufficient:'المبلغ أكبر من الرصيد المعروض للحساب.', maxSlots:'عدد الخانات المطلوب يتجاوز حد البنك.',
    buySlots:'اشترِ خانات للخزنة أولًا.', unavailable:'هذا الخيار غير متاح حاليًا.',
    network:'تعذّر إرسال الطلب. حاول مرة أخرى.', confirmTransfer:'تأكيد التحويل',
    branch_Valentine:'بنك فالنتاين', branch_Blackwater:'بنك بلاك ووتر', branch_SaintDenis:'بنك سان دينيس', branch_Rhodes:'بنك رودس'
  }
};
let state=null, lang='en', section='overview', dialog=null, pending=false, toastTimer=null;
const icons={overview:'home',cash:'money',gold:'gold',accounts:'records',vault:'inventory',dcash:'money',wcash:'money',dgold:'gold',wgold:'gold',upgrade:'inventory',openVault:'inventory',transfer:'records'};
const t=key=>words[lang][key]||words.en[key]||key;
const branch=name=>words[lang]['branch_'+name]||(name===state?.name?String(state.title||name):String(name));
const number=value=>Number(value||0).toLocaleString('en-US',{maximumFractionDigits:2});
const isolate=value=>'\u2066'+value+'\u2069';
const cash=value=>isolate('$ '+number(value));
const ratio=(used,max)=>isolate(`${number(used)} / ${number(max)}`);
const img=(key,className)=>{const el=document.createElement('img');el.src=`img/jrs_admin_${icons[key]||'records'}.png`;el.alt='';el.className=className;return el;};
async function post(name,data={}) {
  try {
    const response=await fetch(`https://${typeof GetParentResourceName==='function'?GetParentResourceName():'jrs_banking'}/${name}`,{
      method:'POST',headers:{'Content-Type':'application/json; charset=UTF-8'},body:JSON.stringify({token:state?.token,...data})
    });
    if (!response.ok) throw new Error('Request failed');
    return await response.json();
  } catch {return {ok:false,error:'network'};}
}
function toast(key){$('toast').textContent=t(key);$('toast').hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>{$('toast').hidden=true;},4000);}
function setLanguage(value){
  lang=value==='ar'?'ar':'en';document.documentElement.lang=lang;document.documentElement.dir=lang==='ar'?'rtl':'ltr';
  for(const el of document.querySelectorAll('[data-text]')) el.textContent=t(el.dataset.text);
  $('languageBadge').textContent=lang==='ar'?'العربية':'English';$('search').placeholder=t('search');
  $('navigation').ariaLabel=t('overview');
}
function tabs(){return ['overview','cash',...(state.goldEnabled?['gold']:[]),...(state.transferEnabled?['accounts']:[]),...(state.vaultEnabled||state.upgradeEnabled?['vault']:[])];}
function renderNavigation(){
  $('navigation').replaceChildren();const values=tabs();$('navigation').style.setProperty('--bank-tabs',values.length);
  for(const id of values){
    const button=document.createElement('button');button.type='button';button.className='tab';button.dataset.section=id;
    button.setAttribute('aria-selected',String(id===section));button.disabled=!!dialog||pending;
    const label=document.createElement('strong');label.textContent=t(id);button.append(img(id,'admin-farm-thumb'),label);
    button.addEventListener('click',()=>navigate(id));$('navigation').append(button);
  }
}
function navigate(id){
  if(dialog||pending||!tabs().includes(id))return;
  section=id;$('search').value='';$('list').scrollTop=0;render();
}
function renderBalances(){
  $('balances').replaceChildren();
  const values=[['cash',t('cashBalance'),cash(state.money)],...(state.goldEnabled?[['gold',t('goldBalance'),number(state.gold)]]:[]),...(state.vaultEnabled||state.upgradeEnabled?[['vault',t('slots'),ratio(state.slots,state.maxSlots)]]:[])];
  $('balances').style.gridTemplateColumns=`repeat(${values.length},minmax(0,1fr))`;
  for(const [id,label,value] of values){
    const tile=document.createElement('div');tile.className='bank-balance';
    const copy=document.createElement('span');copy.className='bank-balance-copy';const small=document.createElement('small'),strong=document.createElement('strong');
    small.textContent=label;strong.textContent=value;strong.dir='ltr';copy.append(small,strong);tile.append(img(id,''),copy);$('balances').append(tile);
  }
}
function rows(){
  const result=[];
  if(section==='overview'||section==='cash')for(const id of ['dcash','wcash'])result.push({id,label:t(id),desc:t(id+'Help')});
  if(state.goldEnabled&&(section==='overview'||section==='gold'))for(const id of ['dgold','wgold'])result.push({id,label:t(id),desc:t(id+'Help')});
  if(state.transferEnabled&&section==='overview')result.push({id:'accounts',label:t('accounts'),desc:t('accountsHelp')});
  if(section==='accounts'&&state.transferEnabled){
    for(const account of state.accounts||[])result.push({id:'transfer',from:account.name,label:branch(account.name),desc:`${t('balance')}: ${cash(account.money)} · ${t('fee')}: ${number((1-state.feeMultiplier)*100)}%`,balance:Number(account.money)||0,disabled:Number(account.money)<=0});
    if(!result.length)result.push({id:'accounts',label:t('noAccounts'),desc:t('noAccountsHelp'),disabled:true});
  }
  if(section==='overview'||section==='vault'){
    if(state.vaultEnabled)result.push({id:'openVault',label:t('openVault'),desc:`${t('openVaultHelp')}\n${t('slots')}: ${ratio(state.slots,state.maxSlots)}`});
    if(state.upgradeEnabled)result.push({id:'upgrade',label:t('upgrade'),desc:`${t('price')}: ${cash(state.slotPrice)} · ${t('remaining')}: ${number(Math.max(0,state.maxSlots-state.slots))}`,disabled:state.slots>=state.maxSlots});
  }
  return result;
}
function renderList(){
  const scroll=$('list').scrollTop,query=$('search').value.trim().toLocaleLowerCase(),items=rows().filter(r=>`${r.label} ${r.desc}`.toLocaleLowerCase().includes(query));
  $('list').replaceChildren();$('count').textContent=items.length;$('empty').hidden=items.length>0;
  items.forEach((row,i)=>{
    const button=document.createElement('button');button.type='button';button.className='option';button.dataset.action=row.id;if(row.from)button.dataset.from=row.from;
    button.disabled=!!row.disabled||!!dialog||pending;
    const index=document.createElement('span');index.className='option-index';index.textContent=String(i+1).padStart(2,'0');
    const copy=document.createElement('span');copy.className='option-copy';const label=document.createElement('strong'),desc=document.createElement('small');
    label.className='option-label';desc.className='option-desc';label.textContent=row.label;desc.textContent=row.desc;copy.append(label,desc);
    const arrow=document.createElement('span');arrow.className='option-arrow';arrow.textContent='›';button.append(index,img(row.id,'admin-tool-image'),copy,arrow);
    button.addEventListener('click',()=>select(row));$('list').append(button);
  });$('list').scrollTop=scroll;
}
function render(){
  if(!state)return;
  if(!tabs().includes(section))section='overview';
  $('title').textContent=branch(state.name);$('subtitle').textContent=t(section);$('back').hidden=section==='overview';$('back').disabled=!!dialog||pending;
  renderBalances();renderNavigation();renderList();renderDialog(false);
}
async function select(row){
  if(pending||dialog||row.disabled)return;
  if(row.id==='accounts'){navigate('accounts');return;}
  if(row.id==='openVault'){
    pending=true;render();const result=await post('bankVault');pending=false;
    if(!result.ok){toast(result.error);render();}return;
  }
  dialog={...row,token:state.token};$('inputValue').value='';$('inputError').textContent='';
  render();renderDialog(true);
}
function integerAction(){return ['upgrade','dgold','wgold'].includes(dialog?.id);}
function renderDialog(focus){
  $('modal').hidden=!dialog;if(!dialog)return;
  $('inputIcon').src=img(dialog.id,'').src;
  $('inputTitle').textContent=dialog.id==='transfer'?t('transfer'):t(dialog.id);
  $('inputHelp').textContent=dialog.id==='transfer'?`${t('from')}: ${branch(dialog.from)}\n${t('to')}: ${branch(state.name)}\n${t('balance')}: ${cash(dialog.balance)}\n${t('fee')}: ${number((1-state.feeMultiplier)*100)}%`:t(dialog.id+'Help');
  $('amountLabel').textContent=t(dialog.id==='upgrade'?'quantity':'amount');
  $('inputValue').inputMode=integerAction()?'numeric':'decimal';$('inputValue').placeholder=t(dialog.id==='upgrade'?'quantity':'amount');
  $('submitInput').textContent=t(dialog.id==='transfer'?'confirmTransfer':'confirm');$('submitInput').disabled=pending;
  summary();if(focus){$('inputValue').focus();document.querySelector('.admin-dialog-body').scrollTop=0;}
}
function parseAmount(){
  // Accept Arabic and Persian digits, decimal separator, and ordinary Latin input.
  const raw=$('inputValue').value.trim().replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-1776)).replace(/٫/g,'.');
  return {raw,value:Number(raw)};
}
function summary(){
  if(!dialog)return;
  const {value}=parseAmount(),amount=Number.isFinite(value)&&value>0?value:0;
  let text='';
  if(dialog.id==='upgrade')text=`${t('price')}: ${cash(state.slotPrice)}\n${t('total')}: ${cash(amount*state.slotPrice)}\n${t('afterUpgrade')}: ${ratio(state.slots+amount,state.maxSlots)}`;
  if(dialog.id==='transfer')text=`${t('received')}: ${cash(Math.floor(amount*state.feeMultiplier*100+1e-8)/100)}\n${t('fee')}: ${cash(amount-Math.floor(amount*state.feeMultiplier*100+1e-8)/100)}`;
  $('inputSummary').textContent=text;$('inputSummary').hidden=!text;
}
function dismiss(){dialog=null;$('inputError').textContent='';render();}
$('inputValue').addEventListener('input',summary);
$('inputForm').addEventListener('submit',async event=>{
  event.preventDefault();if(!dialog||pending)return;
  const {raw,value}=parseAmount();const integer=integerAction();let error='';
  if(!/^(?:\d+(?:\.\d{1,2})?)$/.test(raw)||!Number.isFinite(value)||value<=0||value>10000000)error='invalid';
  else if(integer&&!Number.isInteger(value))error='integerOnly';
  else if(dialog.id==='upgrade'&&state.slots+value>state.maxSlots)error='maxSlots';
  else if(dialog.id==='wcash'&&value>state.money||dialog.id==='wgold'&&value>state.gold||dialog.id==='transfer'&&value>dialog.balance)error='insufficient';
  if(error){$('inputError').textContent=t(error);return;}
  const request={action:dialog.id,amount:value,from:dialog.from,token:dialog.token};
  pending=true;render();const result=await post('bankSubmit',request);pending=false;
  if(!result.ok&&dialog){$('inputError').textContent=t(result.error);render();}
});
$('cancelInput').addEventListener('click',()=>{if(!pending)dismiss();});
$('back').addEventListener('click',()=>navigate('overview'));
$('search').addEventListener('input',()=>{$('list').scrollTop=0;renderList();});
async function close(){if(!state)return;await post('bankClose');}
$('close').addEventListener('click',close);
document.addEventListener('keydown',event=>{
  if(event.key==='Escape'&&state){event.preventDefault();if(dialog&&!pending)dismiss();else close();}
  if(dialog&&event.key==='Tab'){
    const fields=Array.from($('inputForm').querySelectorAll('input,button')).filter(el=>!el.disabled&&!el.hidden);
    const first=fields[0],last=fields.at(-1);
    if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}
    else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}
  }
});
window.addEventListener('message',event=>{
  const data=event.data;if(!data||typeof data!=='object')return;
  if(data.action==='bank:close'){
    $('panel').hidden=true;$('panel').setAttribute('aria-hidden','true');state=null;dialog=null;pending=false;return;
  }
  if(data.action==='bank:open'){
    const fresh=state?.token!==data.token;
    state=data;pending=false;setLanguage(data.language);
    if(fresh){section='overview';dialog=null;$('search').value='';$('list').scrollTop=0;$('toast').hidden=true;}
    $('panel').hidden=false;$('panel').setAttribute('aria-hidden','false');render();
  }
});
// Reuse the admin panel's mouse drag, centering and wheel behaviour.
const shell=$('adminShell'),header=$('adminHeader');let drag=null;
function movePanel(x,y){shell.style.setProperty('left',`${Math.max(0,Math.min(x,innerWidth-shell.offsetWidth))}px`,'important');shell.style.setProperty('top',`${Math.max(0,Math.min(y,innerHeight-shell.offsetHeight))}px`,'important');shell.style.setProperty('transform','none','important');}
function center(){shell.style.removeProperty('left');shell.style.removeProperty('top');shell.style.removeProperty('transform');}
header.addEventListener('pointerdown',event=>{if(event.button!==0||dialog||event.target.closest('button,input,a'))return;const b=shell.getBoundingClientRect();drag={id:event.pointerId,dx:event.clientX-b.left,dy:event.clientY-b.top};header.setPointerCapture(event.pointerId);event.preventDefault();});
header.addEventListener('pointermove',event=>{if(drag?.id===event.pointerId)movePanel(event.clientX-drag.dx,event.clientY-drag.dy);});
header.addEventListener('pointerup',event=>{if(drag?.id===event.pointerId){header.releasePointerCapture(event.pointerId);drag=null;}});
header.addEventListener('pointercancel',()=>{drag=null;});
header.addEventListener('dblclick',event=>{if(!event.target.closest('button'))center();});$('positionReset').addEventListener('click',center);
window.addEventListener('resize',()=>{if(shell.style.transform==='none'&&state){const b=shell.getBoundingClientRect();movePanel(b.left,b.top);}});
shell.addEventListener('wheel',event=>{
  if(!state||event.ctrlKey||!event.deltaY)return;const pane=dialog?document.querySelector('.admin-dialog-body'):$('list');
  if(pane.scrollHeight<=pane.clientHeight||pane.contains(event.target)||event.target.closest('input,textarea,select'))return;
  event.preventDefault();pane.scrollTop+=event.deltaY*(event.deltaMode===1?24:event.deltaMode===2?pane.clientHeight:1);
},{passive:false});
setLanguage('en');post('bankReady');
