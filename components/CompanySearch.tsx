'use client';
import {useEffect,useRef,useState} from 'react';
import {Search,LoaderCircle} from 'lucide-react';
import {db} from '../lib/supabase';
import type {CompanyDetails} from '../lib/company-lookup';
export function CompanySearch({onSelect}:{onSelect:(company:CompanyDetails)=>void}){
 const [query,setQuery]=useState(''),[items,setItems]=useState<CompanyDetails[]>([]),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 const active=useRef<AbortController|null>(null);
 useEffect(()=>()=>active.current?.abort(),[]);
 function reset(){active.current?.abort();active.current=null;setBusy(false);setItems([]);setMessage('')}
 async function search(){
  reset();if(query.trim().length<3){setMessage('Введите не менее 3 символов');return}
  const controller=new AbortController();active.current=controller;setBusy(true);
  try{
   const session=db?await db.auth.getSession():null;
   if(controller.signal.aborted)return;
   const r=await fetch('/api/company',{method:'POST',headers:{'Content-Type':'application/json',...(session?.data.session?{Authorization:'Bearer '+session.data.session.access_token}:{})},body:JSON.stringify({query:query.trim()}),signal:AbortSignal.any([controller.signal,AbortSignal.timeout(15000)])});
   const result=await r.json();if(controller.signal.aborted)return;
   if(!r.ok)throw Error(result.error||'Не удалось найти организацию');
   setItems(result.suggestions);if(!result.suggestions.length)setMessage('Организации не найдены. Уточните название или ИНН.');
  }catch(e){if(!controller.signal.aborted)setMessage(e instanceof Error?e.message:'Не удалось выполнить поиск')}
  finally{if(active.current===controller){setBusy(false);active.current=null}}
 }
 return <div className="company-search"><div className="inn-lookup"><label className="field">Поиск организации в DaData<input value={query} maxLength={200} placeholder="Название или ИНН организации" autoComplete="off" onChange={e=>{reset();setQuery(e.target.value)}} onKeyDown={e=>{if(e.key==='Enter'){e.preventDefault();void search()}}}/></label><button type="button" className="button secondary" disabled={busy} onClick={()=>void search()}>{busy?<LoaderCircle className="spin" size={16}/>:<Search size={16}/>}Найти в DaData</button></div><p className="hint">Выберите организацию — реквизиты заполнятся автоматически. Сохранение после проверки.</p><div aria-live="polite">{busy&&<p className="hint">Ищем организацию…</p>}{message&&<p className="form-error" role="status">{message}</p>}</div>{!!items.length&&<div className="company-search-results" role="group" aria-label="Организации DaData">{items.map((item,i)=><button type="button" key={item.inn+item.kpp+i} onClick={()=>{reset();onSelect(item);setQuery(item.name)}}><strong>{item.name}</strong><span>ИНН {item.inn} · КПП {item.kpp||'—'}</span><span>{item.legalAddress}</span><small>Выбрать и заполнить →</small></button>)}</div>}</div>
}
