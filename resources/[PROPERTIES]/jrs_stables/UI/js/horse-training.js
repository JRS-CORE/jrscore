/* JRS horse abilities and explicit call selection in the original stable slots. */
(() => {
  'use strict';
  let payload={}, owned=null, model=null, pending=false;
  const text=key=>payload.translations?.[key] || key;
  const number=value=>{const el=document.createElement('bdi');el.dir='ltr';el.textContent=String(value);return el;};
  const button=(label,action,row)=>{
    const el=document.createElement('button');el.type='button';el.className='horse-action-slot';
    el.dataset.horseAction=action;el.textContent=label;
    el.addEventListener('click',async event=>{
      event.stopPropagation();if(pending)return;
      pending=true;update();
      try{
        const resource=typeof GetParentResourceName==='function'?GetParentResourceName():'jrs_stables';
        const response=await fetch(`https://${resource}/horseAction`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,id:row.id})});
        const result=await response.json();
        if(result?.ok && ['select','call','revive'].includes(action) && result.data){
          merge(result.data,action==='select'||action==='call');
        }
      }catch(error){console.error('Horse action failed',error);}
      finally{pending=false;update();}
    });return el;
  };
  function merge(row,selected=false){
    for(const item of payload.myHorsesData || []){
      if(selected)item.selected=Number(item.id)===Number(row.id)?1:0;
      if(Number(item.id)===Number(row.id))Object.assign(item,row);
    }
    if(owned && Number(owned.id)===Number(row.id))owned={...owned,...row};
    update();
  }
  const statRow=(key,stats)=>{
    const wrap=document.createElement('div');wrap.className='horse-ability';
    const label=document.createElement('div');label.className='horse-ability-label';
    const title=document.createElement('span');title.textContent=text(key==='health'?'horseHealth':'horseStamina');
    const value=document.createElement('strong');value.dir='ltr';value.textContent=`${stats.value} / 10`;
    label.append(title,value);wrap.append(label);
    const meter=document.createElement('div');meter.className='horse-ability-meter';meter.setAttribute('role','meter');
    meter.setAttribute('aria-label',title.textContent);meter.setAttribute('aria-valuemin','0');meter.setAttribute('aria-valuemax','10');meter.setAttribute('aria-valuenow',String(stats.value));
    for(let i=1;i<=10;i++){const tick=document.createElement('span');tick.className=i<=stats.value?'filled':i<=stats.max?'available':'locked';meter.append(tick);}wrap.append(meter);
    const detail=document.createElement('small');detail.append(`${text('horseCeiling')}: `,number(`${stats.max}/10`),` · ${text('horseTraining')}: `,number(`${stats.percent}%`));wrap.append(detail);
    return wrap;
  };
  function render(row,mode){
    const card=document.createElement('section');card.className='horse-abilities';card.dataset.mode=mode;
    const stats=row.training;if(!stats)return card;
    const heading=document.createElement('div');heading.className='horse-ability-heading';
    const name=document.createElement('strong');name.textContent=mode==='catalog'?text('horsePurchaseStats'):row.name;
    const level=document.createElement('span');level.append(`${text('horseLevel')}: `,number(`${stats.level} / 4`));
    heading.append(name,level);card.append(heading,statRow('health',stats.health),statRow('stamina',stats.stamina));
    if(mode==='owned'){
      const dead=!!row.needsRevive || Number(row.dead)===1 || Number(row.writhe)===1;
      const notice=document.createElement('p');notice.className='horse-state';notice.textContent=dead?text('horseDead'):Number(row.selected)===1?text('horseSelected'):text('horseTrainingHint');card.append(notice);
      if(!dead){
        const condition=document.createElement('small');condition.className='horse-core';condition.textContent=`${text('horseCore')}: ${text('horseHealth')} ${Math.round(row.health??100)}% · ${text('horseStamina')} ${Math.round(row.stamina??100)}%`;card.append(condition);
      }
      const actions=document.createElement('div');actions.className='horse-action-slots';
      if(dead)actions.append(button(`${text('horseRevive')} ${row.name} — $${stats.revivePrice}`,'revive',row));
      else{
        actions.append(button(Number(row.selected)===1?text('horseSelected'):text('horseSelect'),'select',row),button(text('horseCall'),'call',row));
        const health=button(text('horseTrainHealth'),'trainHealth',row),stamina=button(text('horseTrainStamina'),'trainStamina',row);
        health.disabled=stats.health.percent>=100;stamina.disabled=stats.stamina.percent>=100;actions.append(health,stamina);
        if(Number(row.selected)===1)actions.firstElementChild.disabled=true;
      }
      for(const el of actions.children)if(pending)el.disabled=true;
      card.append(actions);
    }
    return card;
  }
  function update(){
    const main=document.querySelector('.main[data-v-e43cd170]');if(!main)return;
    let anchor,row,mode;
    if(window.JrsStableFamily==='horse' && owned){
      const title=main.querySelector(`.panel-title[data-horse-id="${Number(owned.id)}"]`);
      const container=title?.closest('.container[data-v-a9a889c0]');
      anchor=container?.querySelector('.mb');row=owned;mode='owned';
      if(container){
        const sale=container.querySelector('.panel-myhorse button:last-child');
        if(sale)sale.disabled=!!owned.needsRevive || Number(owned.dead)===1 || Number(owned.writhe)===1;
      }
    }else if(window.JrsStableFamily==='horse' && model){
      anchor=main.querySelector(`.panel-shop[data-horse-model="${CSS.escape(model)}"]`);
      for(const breed of payload.shopData || [])if(breed.colors?.[model])row=breed.colors[model];
      mode='catalog';
    }
    const signature=JSON.stringify([mode,row,pending,payload.language]);
    for(const card of main.querySelectorAll('.horse-abilities')){
      const correct=mode==='owned'?card.parentElement===anchor:card.previousElementSibling===anchor;
      if(!anchor || !row || !correct || card.dataset.signature!==signature)card.remove();
    }
    if(!anchor || !row?.training || main.querySelector('.horse-abilities'))return;
    const card=render(row,mode);card.dataset.signature=signature;
    if(mode==='owned')anchor.prepend(card);else anchor.after(card);
  }
  window.JrsHorsePreview=row=>{
    owned={...row,...(payload.myHorsesData || []).find(item=>Number(item.id)===Number(row.id))};model=null;queueMicrotask(update);
  };
  window.JrsHorseCatalogPreview=value=>{model=value;owned=null;queueMicrotask(update);};
  window.addEventListener('message',event=>{
    const data=event.data;if(!data || typeof data!=='object')return;
    if(data.action==='show'){payload=data;owned=null;model=null;queueMicrotask(update);}
    else if(data.action==='hide'){payload={};owned=null;model=null;pending=false;}
    else if(data.action==='horse:status' && data.row)merge(data.row);
    else if(data.action==='horse:selected' && data.row)merge(data.row,true);
  });
  const start=()=>new MutationObserver(update).observe(document.getElementById('app'),{childList:true,subtree:true});
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start);else start();
})();
