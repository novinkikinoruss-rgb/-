'use client';
import {useEffect,useRef,useState} from 'react';
import {Search,LoaderCircle} from 'lucide-react';
import {validInn} from '../lib/domain';
import {db} from '../lib/supabase';
import type {CompanyDetails} from '../lib/company-lookup';
export function CompanySearch({onSelect}:{onSelect:(company:CompanyDetails)=>void}){
 const [query,setQuery]=useState(''),[items,setItems]=useState<CompanyDetails[]>([]),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 const active=useRef<AbortController|null>(null);
 useEffect(()=>()=>active.current?.abort(),[]);
 function reset(){active.current?.abort();active.current=null;setBusy(false);setItems([]);setMessage('')}
 async function search(){
  reset();if(!validInn(query.trim())){setMessage('Введите корректный ИНН организации из 10 цифр');return}
  const controller=new AbortController();active.current=controller;setBusy(true);
  try{
   const session=db?await db.auth.getSession():null;
   if(controller.signal.aborted)return;
   const r=await fetch('/api/company',{method:'POST',headers:{'Content-Type':'application/json',...(session?.data.session?{Authorization:'Bearer '+session.data.session.access_token}:{})},body:JSON.stringify({query:query.trim()}),signal:AbortSignal.any([controller.signal,AbortSignal.timeout(15000)])});
   const result=await r.json();if(controller.signal.aborted)return;
   if(!r.ok)throw Error(result.error||'Не удалось найти организацию');
   setItems(result.suggestions);if(!result.suggestions.length)setMessage('Организации не найдены. Проверьте ИНН.');
  }catch(e){if(!controller.signal.aborted)setMessage(e instanceof Error?e.message:'Не удалось выполнить поиск')}
  finally{if(active.current===controller){setBusy(false);active.current=null}}
 }
 return <div className="company-search"><div className="inn-lookup"><label className="field">Поиск по ИНН в Чекко<input value={query} inputMode="numeric" maxLength={10} placeholder="ИНН организации: 10 цифр" autoComplete="off" onChange={e=>{reset();setQuery(e.target.value.replace(/\D/g,''))}} onKeyDown={e=>{if(e.key==='Enter'){e.preventDefault();void search()}}}/></label><button type="button" className="button secondary" disabled={busy} onClick={()=>void search()}>{busy?<LoaderCircle className="spin" size={16}/>:<Search size={16}/>}Найти в Чекко</button></div><p className="hint">Выберите организацию — реквизиты заполнятся автоматически. Сохранение после проверки.</p><div aria-live="polite">{busy&&<p className="hint">Ищем организацию…</p>}{message&&<p className="form-error" role="status">{message}</p>}</div>{!!items.length&&<div className="company-search-results" role="group" aria-label="Организации Чекко">{items.map((item,i)=><button type="button" key={item.inn+item.kpp+i} onClick={()=>{reset();onSelect(item);setQuery(item.inn)}}><strong>{item.name}</strong><span>ИНН {item.inn} · КПП {item.kpp||'—'}</span><span>{item.legalAddress}</span><small>Выбрать и заполнить →</small></button>)}</div>}</div>
}
