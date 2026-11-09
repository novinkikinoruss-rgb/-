'use client';
import {createContext,useCallback,useContext,useEffect,useRef,useState,type ReactNode} from 'react';
import {db} from '../lib/supabase';

type Setting=Record<string,unknown>;
type Value={values:Record<string,unknown>;loaded:boolean;status:'idle'|'loading'|'saving'|'saved'|'error';error:string;update:(key:string,change:(previous:Setting)=>Setting)=>void;retry:()=>void};
const Context=createContext<Value|null>(null);
const object=(value:unknown):Setting=>value&&typeof value==='object'&&!Array.isArray(value)?value as Setting:{};
export function UiPreferencesProvider({children}:{children:ReactNode}){
 const [values,setValues]=useState<Record<string,unknown>>({}),[loaded,setLoaded]=useState(!db),[status,setStatus]=useState<Value['status']>('idle'),[error,setError]=useState('');
 const owner=useRef<string|null>(null),generation=useRef(0),revision=useRef(0),current=useRef<Record<string,unknown>>({}),ready=useRef(!db);
 const pending=useRef(new Map<string,{value:Setting;revision:number}>()),timer=useRef<ReturnType<typeof setTimeout>|null>(null),worker=useRef<object|null>(null),requests=useRef(new Set<AbortController>()),alive=useRef(true);
 const load=useCallback(async(id:string)=>{
  if(!db||pending.current.size)return;const version=generation.current,readRevision=revision.current,controller=new AbortController();requests.current.add(controller);setStatus('loading');
  try{
   const {data,error}=await db.rpc('respectlogistic_read_ui_settings').abortSignal(controller.signal);
   if(!alive.current||version!==generation.current||owner.current!==id)return;
   if(error)throw error;
   // A local edit made while a focus refresh was in progress stays authoritative.
   if(!pending.current.size&&readRevision===revision.current){current.current=object(data);setValues(current.current);}
   ready.current=true;setLoaded(true);setError('');setStatus(pending.current.size?'saving':'saved');
  }catch{if(alive.current&&version===generation.current&&owner.current===id){setError('Не удалось загрузить настройки из базы.');setStatus('error');}}
  finally{requests.current.delete(controller);}
 },[]);
 const flushRef=useRef<()=>void>(()=>{});
 const flush=useCallback(async()=>{
  if(timer.current){clearTimeout(timer.current);timer.current=null;}
  const id=owner.current;if(!db||!id||!ready.current||worker.current||!pending.current.size)return;
  const version=generation.current,identity={};worker.current=identity;setError('');setStatus('saving');let failed=false;
  const batch=[...pending.current.entries()];
  try{
   for(const [key,entry] of batch){
    if(!alive.current||version!==generation.current||owner.current!==id)return;
    const controller=new AbortController();requests.current.add(controller);
    try{
     const {error}=await db.rpc('respectlogistic_save_ui_setting',{p_owner:id,p_key:key,p_value:entry.value}).abortSignal(controller.signal);
     if(error)throw error;
     if(version===generation.current&&owner.current===id&&pending.current.get(key)?.revision===entry.revision)pending.current.delete(key);
    }finally{requests.current.delete(controller);}
   }
  }catch{failed=true;if(alive.current&&version===generation.current){setError('Настройки не сохранены в базе. Проверьте соединение и повторите.');setStatus('error');}}
  finally{
   if(worker.current===identity)worker.current=null;
   if(alive.current&&version===generation.current&&!failed){
    setStatus(pending.current.size?'saving':'saved');
    if(pending.current.size)timer.current=setTimeout(()=>flushRef.current(),600);
   }
  }
 },[]);
 flushRef.current=()=>void flush();
 const update=useCallback((key:string,change:(previous:Setting)=>Setting)=>{
  if(db&&(!owner.current||!ready.current))return;
  const next=change(object(current.current[key]));current.current={...current.current,[key]:next};setValues(current.current);
  if(!db)return;pending.current.set(key,{value:next,revision:++revision.current});setStatus('saving');setError('');
  if(timer.current)clearTimeout(timer.current);timer.current=setTimeout(()=>flushRef.current(),600);
 },[]);
 const retry=useCallback(()=>{if(pending.current.size)flushRef.current();else if(owner.current)void load(owner.current);},[load]);
 useEffect(()=>{
  alive.current=true;if(!db)return()=>{alive.current=false;};
  const {data:{subscription}}=db.auth.onAuthStateChange((_event,session)=>{
   const id=session?.user.id||null;if(id===owner.current)return;
   generation.current++;owner.current=id;ready.current=false;setLoaded(false);current.current={};setValues({});setError('');setStatus(id?'loading':'idle');
   if(timer.current){clearTimeout(timer.current);timer.current=null;}pending.current.clear();worker.current=null;
   for(const controller of requests.current)controller.abort();requests.current.clear();
   // Auth callbacks must release the SDK lock before another API call starts.
   if(id)setTimeout(()=>{if(owner.current===id)void load(id);},0);
  });
  const refresh=()=>{if(owner.current&&!pending.current.size&&!worker.current&&document.visibilityState!=='hidden')void load(owner.current);};
  const online=()=>{if(pending.current.size)flushRef.current();else refresh();};
  window.addEventListener('focus',refresh);window.addEventListener('online',online);document.addEventListener('visibilitychange',refresh);
  return()=>{alive.current=false;generation.current++;owner.current=null;ready.current=false;worker.current=null;subscription.unsubscribe();if(timer.current)clearTimeout(timer.current);for(const controller of requests.current)controller.abort();window.removeEventListener('focus',refresh);window.removeEventListener('online',online);document.removeEventListener('visibilitychange',refresh);};
 },[load]);
 return <Context.Provider value={{values,loaded,status,error,update,retry}}>{children}</Context.Provider>;
}
export function useUiPreferences(){const value=useContext(Context);if(!value)throw new Error('UiPreferencesProvider is missing');return value;}
