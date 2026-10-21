'use client';
import {useEffect,useRef,type ReactNode} from 'react';
import {X} from 'lucide-react';
export function Modal({title,children,onClose,busy=false}:{title:string;children:ReactNode;onClose:()=>void;busy?:boolean}){
  const ref=useRef<HTMLDialogElement>(null);const close=useRef(onClose);close.current=onClose;
  useEffect(()=>{const dialog=ref.current,previous=document.activeElement as HTMLElement|null;dialog?.showModal();return()=>{dialog?.close();previous?.focus();};},[]);
  return <dialog ref={ref} className="modal" aria-labelledby="modal-title" onCancel={e=>{e.preventDefault();if(!busy)close.current();}}><header className="modal-heading"><div><span className="eyebrow">Рабочее пространство</span><h2 id="modal-title">{title}</h2></div><button className="icon-button" disabled={busy} aria-label="Закрыть окно" onClick={onClose}><X/></button></header>{children}</dialog>;
}
