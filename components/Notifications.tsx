'use client';
import {createContext,useContext,useState,useRef,useEffect,type ReactNode} from 'react';
import {Check,AlertCircle,Info,X,Bell} from 'lucide-react';
type Notice={id:number;message:string;kind:'success'|'error'|'info';time:string};
const HistoryContext=createContext<{items:Notice[];unread:number;read:()=>void}>({items:[],unread:0,read:()=>{}});
export function useFeedback(){const [value,setValue]=useState('');const notify=useNotice();return [value,(message:string)=>{setValue(message);if(message)notify(message)}] as const;}
export function NotificationBell(){
 const {items,unread,read}=useContext(HistoryContext);const [open,setOpen]=useState(false);const area=useRef<HTMLDivElement>(null);
 useEffect(()=>{if(!open)return;function close(e:PointerEvent){if(!area.current?.contains(e.target as Node))setOpen(false)}function escape(e:KeyboardEvent){if(e.key==='Escape')setOpen(false)}document.addEventListener('pointerdown',close);document.addEventListener('keydown',escape);return()=>{document.removeEventListener('pointerdown',close);document.removeEventListener('keydown',escape)}},[open]);
 return <div className="notification-center" ref={area}><button type="button" className="icon-button notification-bell" aria-label={'Оповещения'+(unread?' · непрочитанных: '+unread:'')} aria-expanded={open} aria-controls="notification-history" onClick={()=>{setOpen(!open);if(!open)read()}}><Bell size={18}/>{unread>0&&<span className="notification-count">{unread>9?'9+':unread}</span>}</button>{open&&<section id="notification-history" className="notification-history" aria-label="Последние оповещения"><header><strong>Оповещения</strong><button type="button" className="icon-button" aria-label="Закрыть историю оповещений" onClick={()=>setOpen(false)}><X size={16}/></button></header><p className="hint">Последние действия в текущем сеансе</p>{!items.length?<p className="empty">Здесь появятся результаты ваших действий.</p>:items.map(item=><article className={item.kind} key={item.id}><span className="toast-icon">{item.kind==='success'?<Check size={17}/>:item.kind==='error'?<AlertCircle size={17}/>:<Info size={17}/>}</span><div><p>{item.message}</p><small>{item.time}</small></div></article>)}</section>}</div>
}
const Context=createContext<(message:string,kind?:Notice['kind'])=>void>(()=>{});
export const useNotice=()=>useContext(Context);
export function Notifications({children}:{children:ReactNode}){
  const [items,setItems]=useState<Notice[]>([]),[history,setHistory]=useState<Notice[]>([]),[unread,setUnread]=useState(0);const timers=useRef<ReturnType<typeof setTimeout>[]>([]);const nextId=useRef(0);
  useEffect(()=>()=>timers.current.forEach(clearTimeout),[]);
  function notify(message:string,kind:Notice['kind']='success'){
    const id=++nextId.current,item={id,message,kind,time:new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})};setItems(previous=>[...previous.slice(-3),item]);setHistory(previous=>[item,...previous].slice(0,20));setUnread(n=>n+1);
    // Errors stay until explicitly dismissed; success is also in the activity log.
    if(kind!=='error')timers.current.push(setTimeout(()=>setItems(previous=>previous.filter(item=>item.id!==id)),6000));
  }
  useEffect(()=>{const reset=()=>{setItems([]);setHistory([]);setUnread(0)};window.addEventListener('respectlogistic:notifications-reset',reset);return()=>window.removeEventListener('respectlogistic:notifications-reset',reset)},[]);
  return <Context.Provider value={notify}><HistoryContext.Provider value={{items:history,unread,read:()=>setUnread(0)}}>{children}<div className="toasts" aria-label="Оповещения">{items.map(item=><div key={item.id} className={`toast ${item.kind}`} role={item.kind==='error'?'alert':'status'}><span className="toast-icon">{item.kind==='success'?<Check size={19}/>:item.kind==='error'?<AlertCircle size={19}/>:<Info size={19}/>}</span><div><strong>{item.kind==='success'?'Готово':item.kind==='error'?'Не удалось выполнить':'Обратите внимание'}</strong><p>{item.message}</p></div><button onClick={()=>setItems(previous=>previous.filter(i=>i.id!==item.id))} aria-label="Закрыть оповещение"><X size={16}/></button></div>)}</div></HistoryContext.Provider></Context.Provider>;
}
