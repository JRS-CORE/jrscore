'use strict';
const $=id=>document.getElementById(id);
const words={
 en:{console:'Buy and sell goods',center:'Center',close:'Close',back:'Back',mouse:'Click a product to choose its quantity',search:'Search products...',empty:'No products available in this category',drag:'Drag the title to move the panel.',escape:'Esc · Close',input:'PRODUCT QUANTITY',cancel:'Cancel',confirm:'Confirm',add:'Save quantity',buy:'Buy',sell:'Sell',quantity:'Quantity',checkout:'Confirm purchase',checkoutSell:'Confirm sale',cash:'Cash',gold:'Gold',selected:'Selected items',basket:'Basket',totalPay:'Total to pay',totalReceive:'Total to receive',price:'Unit price',available:'Available',inBasket:'Selected',unlimited:'Up to 500',invalid:'Enter a whole number from 0 to the available quantity.',noSelection:'Select a product first.',noMoney:'You do not have enough money for this basket.',unavailable:'This store is currently unavailable.',StoreInUse:'The store is busy. Try again.',failed:'The operation could not be completed.',network:'The request could not be sent.',saved:'Quantity saved',completed:'Completed',partial:'Some products could not be processed. Review the basket.',tooMany:'Choose no more than 50 products per transaction.',food:'Food',tools:'Tools',meds:'Medical supplies',drinks:'Drinks',bait:'Bait',fish:'Fish',butcher:'Animal products',Valentine:'Valentine Store',Rhodes:'Rhodes Store',Strawberry:'Strawberry Store',Blackwater:'Blackwater Store',Armadillo:'Armadillo Store',Tumbleweed:'Tumbleweed Store',StDenis:'Saint Denis Store',Vanhorn:'Van Horn Store',Wapiti:'Wapiti Store',BlackwaterFishing:'Blackwater Fishing Store',ValentineButcher:'Valentine Butcher',BlackwaterButcher:'Blackwater Butcher',SaintDenisButcher:'Saint Denis Butcher'},
 ar:{console:'شراء وبيع الأغراض',center:'توسيط',close:'إغلاق',back:'رجوع',mouse:'اضغط على الغرض لتحديد الكمية',search:'ابحث عن غرض...',empty:'لا توجد أغراض متاحة في هذا القسم',drag:'اسحب العنوان لتحريك الواجهة.',escape:'Esc · إغلاق',input:'كمية الغرض',cancel:'إلغاء',confirm:'تأكيد',add:'حفظ الكمية',buy:'شراء',sell:'بيع',quantity:'الكمية',checkout:'تأكيد الشراء',checkoutSell:'تأكيد البيع',cash:'الأموال',gold:'الذهب',selected:'الأغراض المحددة',basket:'السلة',totalPay:'الإجمالي المطلوب',totalReceive:'الإجمالي المستلم',price:'سعر الوحدة',available:'المتاح',inBasket:'الكمية المحددة',unlimited:'حتى 500',invalid:'أدخل عددًا صحيحًا من صفر إلى الكمية المتاحة.',noSelection:'حدد غرضًا أولًا.',noMoney:'لا تملك الرصيد الكافي لإتمام السلة.',unavailable:'هذا المتجر غير متاح حاليًا.',StoreInUse:'المتجر مشغول. حاول مجددًا.',failed:'تعذّر إتمام العملية.',network:'تعذّر إرسال الطلب.',saved:'تم حفظ الكمية',completed:'تمت العملية',partial:'تعذّرت عملية بعض الأغراض. راجع السلة.',tooMany:'اختر 50 غرضًا كحد أقصى في العملية الواحدة.',food:'المأكولات',tools:'الأدوات',meds:'المستلزمات الطبية',drinks:'المشروبات',bait:'الطعوم',fish:'الأسماك',butcher:'منتجات الحيوانات',Valentine:'متجر فالنتاين',Rhodes:'متجر رودس',Strawberry:'متجر ستروبيري',Blackwater:'متجر بلاك ووتر',Armadillo:'متجر أرماديلو',Tumbleweed:'متجر تمبلويد',StDenis:'متجر سان دينيس',Vanhorn:'متجر فان هورن',Wapiti:'متجر وابيتي',BlackwaterFishing:'متجر الصيد في بلاك ووتر',ValentineButcher:'جزّار فالنتاين',BlackwaterButcher:'جزّار بلاك ووتر',SaintDenisButcher:'جزّار سان دينيس'}
};
let state=null,lang='en',mode='buy',category='',dialog=null,pending=false,cart={buy:{},sell:{}},requestSequence=0,toastTimer;
const t=key=>words[lang][key]||words.en[key]||key;
const num=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2});
const isolate=v=>'\u2066'+v+'\u2069';
const amount=(value,currency)=>isolate((currency==='gold'?num(value)+' '+t('gold'):'$ '+num(value)));
const icons={food:'inventory',tools:'tools',meds:'health',drinks:'inventory',bait:'inventory',fish:'inventory',butcher:'inventory'};
function artwork(name,category,className){
 const image=document.createElement('img'),filename=window.JRSProductImages?.[name];image.alt='';image.className=className;
 image.src=filename?'products/'+encodeURIComponent(filename):`img/jrs_admin_${icons[category]||'inventory'}.png`;
 image.addEventListener('error',()=>{image.src='img/jrs_admin_inventory.png';},{once:true});return image;
}
async function post(name,data={}){
 try{const response=await fetch(`https://${typeof GetParentResourceName==='function'?GetParentResourceName():'jrs_stores'}/${name}`,{method:'POST',headers:{'Content-Type':'application/json; charset=UTF-8'},body:JSON.stringify({token:state?.token,...data})});if(!response.ok)throw Error();return await response.json();}
 catch{return {ok:false,error:'network'};}
}
function setLanguage(value){
 lang=value==='ar'?'ar':'en';document.documentElement.lang=lang;document.documentElement.dir=lang==='ar'?'rtl':'ltr';
 document.querySelectorAll('[data-text]').forEach(el=>el.textContent=t(el.dataset.text));$('languageBadge').textContent=lang==='ar'?'العربية':'English';$('search').placeholder=t('search');
}
function toast(key){$('toast').textContent=t(key);$('toast').hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>{$('toast').hidden=true;},4000);}
const data=()=>state.data;
function products(){return data().products[mode]||[];}
function totals(){
 let cash=0,gold=0,count=0;
 for(const row of products()){const qty=cart[mode][row.key]||0;count+=qty;const total=Math.floor(row.price*qty*100+1e-8)/100;if(row.currency==='gold')gold+=total;else cash+=total;}
 return {cash:Math.round(cash*100)/100,gold:Math.round(gold*100)/100,count};
}
function renderBalances(){
 $('balances').replaceChildren();const values=[['money',t('cash'),amount(data().money,'cash')],['gold',t('gold'),num(data().gold)],['inventory',t('selected'),num(totals().count)]];
 for(const [icon,label,value]of values){const tile=document.createElement('div');tile.className='store-balance';const image=document.createElement('img');image.src=`img/jrs_admin_${icon}.png`;image.alt='';const copy=document.createElement('span'),small=document.createElement('small'),strong=document.createElement('strong');small.textContent=label;strong.textContent=value;strong.dir='ltr';copy.append(small,strong);tile.append(image,copy);$('balances').append(tile);}
}
function renderNavigation(){
 $('navigation').replaceChildren();const categories=data().categories||[];$('navigation').style.setProperty('--store-tabs',Math.max(1,categories.length));
 for(const row of categories){const button=document.createElement('button');button.type='button';button.className='tab';button.dataset.category=row.id;button.disabled=!!dialog||pending;button.setAttribute('aria-selected',String(category===row.id));const label=document.createElement('strong');label.textContent=words[lang][row.id]||row.label;button.append(artwork(null,row.id,'admin-farm-thumb'),label);button.addEventListener('click',()=>{category=row.id;$('search').value='';$('list').scrollTop=0;render();});$('navigation').append(button);}
 $('buyMode').hidden=!data().buyEnabled;$('sellMode').hidden=!data().sellEnabled;
 for(const id of ['buy','sell']){$(id+'Mode').setAttribute('aria-pressed',String(mode===id));$(id+'Mode').disabled=pending||!!dialog;}
}
function renderList(){
 const scroll=$('list').scrollTop,query=$('search').value.trim().toLocaleLowerCase();
 const rows=products().filter(row=>row.category===category&&`${row.label} ${row.name} ${row.desc}`.toLocaleLowerCase().includes(query));
 $('list').replaceChildren();$('count').textContent=rows.length;$('empty').hidden=rows.length>0;
 rows.forEach((row,i)=>{
  const button=document.createElement('button');button.type='button';button.className='option';button.dataset.key=row.key;button.disabled=pending||!!dialog||(row.max<=0&&!cart[mode][row.key]);
  const index=document.createElement('span');index.className='option-index';index.textContent=String(i+1).padStart(2,'0');
  const copy=document.createElement('span');copy.className='option-copy';const label=document.createElement('strong'),desc=document.createElement('small');label.className='option-label';desc.className='option-desc';label.textContent=row.label;
  desc.textContent=`${row.desc?row.desc+'\n':''}${t('price')}: ${amount(row.price,row.currency)} · ${t('available')}: ${num(row.max)}`;copy.append(label,desc);
  const selected=document.createElement('span');selected.className='store-selected';selected.textContent=(cart[mode][row.key]||0)>0?'× '+num(cart[mode][row.key]):'+';
  button.append(index,artwork(row.name,row.category,'admin-tool-image'),copy,selected);button.addEventListener('click',()=>openDialog(row));$('list').append(button);
 });$('list').scrollTop=scroll;
}
function renderCheckout(){
 const value=totals();$('basketCount').textContent=`${t('basket')}: ${num(value.count)}`;
 $('basketTotal').textContent=`${t(mode==='buy'?'totalPay':'totalReceive')}: ${amount(value.cash,'cash')}${value.gold?' + '+amount(value.gold,'gold'):''}`;
 $('checkout').textContent=t(mode==='buy'?'checkout':'checkoutSell');$('checkout').disabled=pending||!!dialog||value.count===0;
}
function render(){
 if(!state)return;setLanguage(data().language);
 if(mode==='buy'&&!data().buyEnabled)mode='sell';if(mode==='sell'&&!data().sellEnabled)mode='buy';
 if(!data().categories.some(row=>row.id===category))category=data().categories[0]?.id||'';
 $('title').textContent=words[lang][data().id]||data().title;
 $('subtitle').textContent=t(mode)+' · '+(words[lang][category]||data().categories.find(row=>row.id===category)?.label||'');
 renderBalances();renderNavigation();renderList();renderCheckout();renderDialog(false);
}
function openDialog(row){if(pending||dialog)return;dialog=row;$('inputValue').value=String(cart[mode][row.key]||1);$('inputError').textContent='';render();renderDialog(true);}
function parseQuantity(){return Number($('inputValue').value.trim().replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-1776)));}
function renderDialog(focus){
 $('modal').hidden=!dialog;if(!dialog)return;$('inputIcon').src=artwork(dialog.name,dialog.category,'').src;$('inputTitle').textContent=dialog.label;
 $('inputHelp').textContent=`${dialog.desc?dialog.desc+'\n':''}${t('price')}: ${amount(dialog.price,dialog.currency)}\n${t('available')}: ${num(dialog.max)}`;
 summary();if(focus){$('inputValue').focus();$('inputValue').select();document.querySelector('.admin-dialog-body').scrollTop=0;}
}
function summary(){if(!dialog)return;const qty=parseQuantity();$('inputSummary').textContent=`${t(mode==='buy'?'totalPay':'totalReceive')}: ${amount(Number.isFinite(qty)&&qty>=0?Math.floor(qty*dialog.price*100+1e-8)/100:0,dialog.currency)}`;}
function dismiss(){dialog=null;render();}
$('inputValue').addEventListener('input',summary);
$('inputForm').addEventListener('submit',event=>{
 event.preventDefault();if(!dialog||pending)return;const qty=parseQuantity();
 if(!Number.isFinite(qty)||!Number.isInteger(qty)||qty<0||qty>Math.min(500,dialog.max)||!$('inputValue').value.trim()){$('inputError').textContent=t('invalid');return;}
 if(qty>0)cart[mode][dialog.key]=qty;else delete cart[mode][dialog.key];dismiss();
});
$('cancelInput').addEventListener('click',dismiss);
for(const id of ['buy','sell'])$(id+'Mode').addEventListener('click',()=>{if(!pending&&!dialog){mode=id;$('search').value='';$('list').scrollTop=0;render();}});
$('search').addEventListener('input',()=>{$('list').scrollTop=0;renderList();});
$('checkout').addEventListener('click',async()=>{
 if(pending||dialog||!state)return;const items=Object.entries(cart[mode]).filter(([,quantity])=>quantity>0).map(([key,quantity])=>({key,quantity}));
 if(items.length>50){toast('tooMany');return;}if(!items.length){toast('noSelection');return;}
 const value=totals();if(mode==='buy'&&(value.cash>data().money||value.gold>data().gold)){toast('noMoney');return;}
 const oldToken=state.token,oldMode=mode;pending=true;render();
 const result=await post('storeCheckout',{mode,items,requestId:`${oldToken}:${Date.now()}:${++requestSequence}`});
 pending=false;if(!state||state.token!==oldToken)return;
 if(result.ok){for(const key of result.successful||[])delete cart[oldMode][key];if(result.data)state.data=result.data;toast(result.errors?.length?'partial':'completed');}
 else toast(result.error||'failed');render();
});
$('close').addEventListener('click',()=>state&&post('storeClose'));
document.addEventListener('keydown',event=>{
 if(event.key==='Escape'&&state){event.preventDefault();if(dialog)dismiss();else post('storeClose');}
 if(dialog&&event.key==='Tab'){
  const fields=Array.from($('inputForm').querySelectorAll('input,button')).filter(el=>!el.disabled&&!el.hidden),first=fields[0],last=fields.at(-1);
  if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}
  else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}
 }
});
window.addEventListener('message',event=>{
 const next=event.data;if(!next||typeof next!=='object')return;
 if(next.action==='store:close'){$('panel').hidden=true;$('panel').setAttribute('aria-hidden','true');state=null;dialog=null;pending=false;return;}
 if(next.action==='store:open'&&next.data){
  const fresh=state?.token!==next.token;state=next;
  if(fresh){cart={buy:{},sell:{}};mode=next.data.buyEnabled?'buy':'sell';category=next.data.categories[0]?.id||'';dialog=null;pending=false;$('search').value='';$('list').scrollTop=0;$('toast').hidden=true;}
  for(const action of ['buy','sell']){const keys=new Set((next.data.products[action]||[]).map(row=>row.key));for(const key of Object.keys(cart[action]))if(!keys.has(key))delete cart[action][key];}
  $('panel').hidden=false;$('panel').setAttribute('aria-hidden','false');render();
 }
});
// Same drag, centering and wheel behaviour as the admin menu.
const shell=$('adminShell'),header=$('adminHeader');let drag=null;
function movePanel(x,y){shell.style.setProperty('left',`${Math.max(0,Math.min(x,innerWidth-shell.offsetWidth))}px`,'important');shell.style.setProperty('top',`${Math.max(0,Math.min(y,innerHeight-shell.offsetHeight))}px`,'important');shell.style.setProperty('transform','none','important');}
function center(){shell.style.removeProperty('left');shell.style.removeProperty('top');shell.style.removeProperty('transform');}
header.addEventListener('pointerdown',event=>{if(event.button!==0||dialog||event.target.closest('button,input,a'))return;const b=shell.getBoundingClientRect();drag={id:event.pointerId,dx:event.clientX-b.left,dy:event.clientY-b.top};header.setPointerCapture(event.pointerId);event.preventDefault();});
header.addEventListener('pointermove',event=>{if(drag?.id===event.pointerId)movePanel(event.clientX-drag.dx,event.clientY-drag.dy);});
header.addEventListener('pointerup',event=>{if(drag?.id===event.pointerId){header.releasePointerCapture(event.pointerId);drag=null;}});header.addEventListener('pointercancel',()=>{drag=null;});
header.addEventListener('dblclick',event=>{if(!event.target.closest('button'))center();});$('positionReset').addEventListener('click',center);
window.addEventListener('resize',()=>{if(shell.style.transform==='none'&&state){const b=shell.getBoundingClientRect();movePanel(b.left,b.top);}});
shell.addEventListener('wheel',event=>{if(!state||event.ctrlKey||!event.deltaY)return;const pane=dialog?document.querySelector('.admin-dialog-body'):$('list');if(pane.scrollHeight<=pane.clientHeight||pane.contains(event.target)||event.target.closest('input,textarea,select'))return;event.preventDefault();pane.scrollTop+=event.deltaY*(event.deltaMode===1?24:event.deltaMode===2?pane.clientHeight:1);},{passive:false});
setLanguage('en');post('storeReady');
