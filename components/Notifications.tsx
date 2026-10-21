'use client';
import {createContext,useContext,useState,useRef,useEffect,type ReactNode} from 'react';
import {Check,AlertCircle,Info,X} from 'lucide-react';
type Notice={id:number;message:string;kind:'success'|'error'|'info'};
const Context=createContext<(message:string,kind?:Notice['kind'])=>void>(()=>{});
export const useNotice=()=>useContext(Context);
export function Notifications({children}:{children:ReactNode}){
  const [items,setItems]=useState<Notice[]>([]);const timers=useRef<ReturnType<typeof setTimeout>[]>([]);const nextId=useRef(0);
  useEffect(()=>()=>timers.current.forEach(clearTimeout),[]);
  function notify(message:string,kind:Notice['kind']='success'){
    const id=++nextId.current;setItems(previous=>[...previous.slice(-3),{id,message,kind}]);
    // Errors stay until explicitly dismissed; success is also in the activity log.
    if(kind!=='error')timers.current.push(setTimeout(()=>setItems(previous=>previous.filter(item=>item.id!==id)),6000));
  }
  return <Context.Provider value={notify}>{children}<div className="toasts" aria-label="Оповещения">{items.map(item=><div key={item.id} className={`toast ${item.kind}`} role={item.kind==='error'?'alert':'status'}><span className="toast-icon">{item.kind==='success'?<Check size={19}/>:item.kind==='error'?<AlertCircle size={19}/>:<Info size={19}/>}</span><div><strong>{item.kind==='success'?'Готово':item.kind==='error'?'Не удалось выполнить':'Обратите внимание'}</strong><p>{item.message}</p></div><button onClick={()=>setItems(previous=>previous.filter(i=>i.id!==item.id))} aria-label="Закрыть оповещение"><X size={16}/></button></div>)}</div></Context.Provider>;
}
