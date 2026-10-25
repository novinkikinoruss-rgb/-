'use client';
import {useRef,useState} from 'react';
import type {MobilePhoto} from '../lib/driver-mobile';
export function MobilePhotoList({photos,read}:{photos:MobilePhoto[];read:(id:string)=>Promise<{base64:string}>}){
 const dialog=useRef<HTMLDialogElement>(null);const [photo,setPhoto]=useState(''),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 return <><div className="driver-actions">{photos.map((p,i)=><button type="button" className="button secondary" key={p.id} disabled={busy} onClick={async()=>{setBusy(true);setError('');try{const result=await read(p.id);setPhoto('data:image/jpeg;base64,'+result.base64.replace(/\s/g,''));dialog.current?.showModal()}catch(e){setError((e as Error).message)}finally{setBusy(false)}}}>{p.kind==='receipt'?'Чек':p.kind==='repair'?'Ремонт':'Документ'} {i+1}</button>)}</div>{error&&<p role="alert">{error}</p>}<dialog ref={dialog} className="service-editor" onClose={()=>setPhoto('')}><div className="driver-card driver-photo"><button className="button" type="button" onClick={()=>dialog.current?.close()}>Закрыть фото</button>{photo&&<img src={photo} alt="Сохранённая фотография"/>}</div></dialog></>
}
