'use client';
import {useEffect,useState,useRef} from 'react';
import {Activity,CheckCircle2,RefreshCw,Database,Globe,SearchCheck} from 'lucide-react';
import {db} from '../lib/supabase';
type State='checking'|'ok'|'configured'|'error'|'unconfigured'|'login';
type Health={site:State;database:State;inn:State};
export function SystemStatus(){
  const [health,setHealth]=useState<Health>({site:'checking',database:db?'checking':'unconfigured',inn:'checking'}),[open,setOpen]=useState(false),[checked,setChecked]=useState('');
  const running=useRef(false);const mounted=useRef(true);
  async function check(){
    if(running.current)return;running.current=true;
    try{
      let site:State='error',inn:State='error',database:State=db?'error':'unconfigured';
      try{const response=await fetch('/api/health',{cache:'no-store',signal:AbortSignal.timeout(8000)});const data=await response.json();if(response.ok&&data.status==='ok'){site='ok';inn=data.innConfigured?'configured':'unconfigured';}}catch{}
      if(db)try{const {data,error:authError}=await db.auth.getUser();if(authError||!data.user)database='login';else{const {error}=await db.rpc('respectlogistic_read_workspace');database=error?'error':'ok';}}catch{database='error';}
      if(mounted.current){setHealth({site,database,inn});setChecked(new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'}));}
    }finally{running.current=false;}
  }
  useEffect(()=>{mounted.current=true;void check();const timer=setInterval(()=>void check(),60000);const refresh=()=>void check();const innResult=(event:Event)=>setHealth(previous=>({...previous,inn:(event as CustomEvent).detail==='ok'?'ok':'error'}));window.addEventListener('online',refresh);window.addEventListener('respectlogistic:session',refresh);window.addEventListener('respectlogistic:inn',innResult);return()=>{mounted.current=false;clearInterval(timer);window.removeEventListener('online',refresh);window.removeEventListener('respectlogistic:session',refresh);window.removeEventListener('respectlogistic:inn',innResult);};},[]);
  const all=health.site==='ok'&&health.database==='ok'&&health.inn==='ok';const failed=Object.values(health).includes('error');
  const label=all?'Все системы подключены':failed?'Есть ошибка подключения':health.site==='checking'?'Проверка систем':!db?'Сайт работает · деморежим':'Сайт работает · настройка';
  const stateLabel=(state:State)=>({checking:'Проверяем…',ok:'Подключено',configured:'Ключ настроен',error:'Не отвечает',unconfigured:'Не настроено',login:'Необходим вход'}[state]);
  return <div className="system-status"><button className={`system-trigger ${all?'healthy':failed?'degraded':'partial'}`} aria-expanded={open} onClick={()=>setOpen(!open)}><span className="live-dot"/><span>{label}</span><Activity size={15}/></button>{open&&<section className="system-popover" aria-label="Состояние подключений"><h3>Состояние систем</h3><div><Globe size={16}/><span>Сайт</span><strong>{stateLabel(health.site)}</strong></div><div><Database size={16}/><span>База данных</span><strong>{stateLabel(health.database)}</strong></div><div><SearchCheck size={16}/><span>Сервис ИНН</span><strong>{stateLabel(health.inn)}</strong></div><p>Сервис ИНН проверяется при запросе реквизитов. {checked&&`Проверка сайта и базы: ${checked}.`}</p><button className="button secondary" onClick={()=>void check()}><RefreshCw size={14}/>Проверить сейчас</button>{all&&<CheckCircle2 size={16}/>}</section>}</div>;
}
