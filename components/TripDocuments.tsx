'use client';
import {useState} from 'react';
import {FileText,Download,FolderOpen,ExternalLink} from 'lucide-react';
import {db} from '../lib/supabase';
import {prepareTripFile} from '../lib/trip-file-client';
import {accountingKinds,accountingStatuses,downloadAccounting,type AccountingDocument} from '../lib/accounting';
export type TripFile={id:string;trip_id:string;file_name:string;doc_type:string;storage_path:string;mime_type:string;file_size:number};
export type DriveExport={trip_id:string;state:string;folder_url:string|null;error:string|null};
export const documentKinds:Record<string,string>={ttn:'ТТН / накладная',waybill:'Путевой лист',ticket:'Талон',upd:'УПД',registry:'Реестр',invoice:'Счёт',other:'Другой документ'};
export async function sendTripToDrive(tripId:string){
 if(!db)return;const {data}=await db.auth.getSession();
 if(!data.session)return;
 const response=await fetch('/api/trip-drive',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+data.session.access_token},body:JSON.stringify({tripId}),signal:AbortSignal.timeout(110000)});
 const result=await response.json();if(!response.ok)throw Error(result.message||'Не удалось отправить документы на Диск');return result;
}
export function TripDocuments({accountingDocuments=[],tripId,files,confirmed,completed,archive,onChanged}:{accountingDocuments?:AccountingDocument[];tripId:string;files:TripFile[];confirmed:boolean;completed:boolean;archive?:DriveExport;onChanged:()=>Promise<void>}){
 const [kind,setKind]=useState('ttn'),[busy,setBusy]=useState(false),[error,setError]=useState(''),[downloading,setDownloading]=useState<string|null>(null);
 const folderUrl=archive?.folder_url&&/^https:\/\/drive\.google\.com\/drive\/folders\/[a-zA-Z0-9_-]+(?:[/?#].*)?$/.test(archive.folder_url)?archive.folder_url:null;
 async function upload(file:File){
  if(!db||busy)return;setBusy(true);setError('');
  try{
   const prepared=await prepareTripFile(file);
   const {data}=await db.auth.getSession();if(!data.session)throw Error('Войдите в CRM повторно');
   const body=new FormData();body.set('tripId',tripId);body.set('uploadId',crypto.randomUUID());body.set('kind',kind);body.set('file',prepared.blob,prepared.name);
   await new Promise<void>((resolve,reject)=>{
    const xhr=new XMLHttpRequest();xhr.open('POST','/api/trip-files');xhr.setRequestHeader('Authorization','Bearer '+data.session!.access_token);xhr.timeout=120000;
    xhr.onload=()=>{let result;try{result=JSON.parse(xhr.responseText)}catch{reject(Error('Сервер не завершил загрузку. Повторите попытку'));return}if(xhr.status>=200&&xhr.status<300&&result.saved)resolve();else reject(Error(result.message||'Не удалось сохранить документ'))};
    xhr.onerror=()=>reject(Error('Соединение прервано во время загрузки. Повторите попытку'));
    xhr.ontimeout=()=>reject(Error('Загрузка заняла слишком много времени. Повторите попытку'));
    xhr.onabort=()=>reject(Error('Загрузка отменена'));xhr.send(body);
   });
   await onChanged();
  }catch(e){setError((e as Error).message||'Не удалось загрузить документ')}finally{setBusy(false)}
 }
 async function open(file:TripFile){
  if(!db||downloading)return;setError('');setDownloading(file.id);
  try{
   if(file.storage_path.startsWith('shift:')){
    const result=await db.rpc('respectlogistic_driver_file',{p_id:file.id});if(result.error)throw Error(result.error.message);
    const bytes=Uint8Array.from(atob(result.data.base64.replace(/\s/g,'')),c=>c.charCodeAt(0));
    const url=URL.createObjectURL(new Blob([bytes],{type:'image/jpeg'}));
    const link=document.createElement('a');link.href=url;link.download=file.file_name;document.body.appendChild(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
   }else{
    const r=await db.storage.from('respectlogistic-trip-documents').createSignedUrl(file.storage_path,300,{download:file.file_name});
    if(r.error)throw Error(r.error.message);
    const link=document.createElement('a');link.href=r.data.signedUrl;link.download=file.file_name;document.body.appendChild(link);link.click();link.remove();
   }
  }catch(e){setError((e as Error).message||'Не удалось скачать документ. Повторите попытку')}finally{setDownloading(null)}
 }
 async function confirm(){
  if(!db||busy)return;setBusy(true);setError('');
  try{const r=await db.rpc('respectlogistic_confirm_trip_documents',{p_trip_id:tripId});if(r.error)throw Error(r.error.message);await onChanged();if(completed){await sendTripToDrive(tripId);await onChanged()}}
  catch(e){setError((e as Error).message)}finally{setBusy(false)}
 }
 async function retry(){setBusy(true);setError('');try{await sendTripToDrive(tripId);await onChanged()}catch(e){setError((e as Error).message)}finally{setBusy(false)}}
 return <div className="trip-document-strip">
  <span className={'document-badge '+(!files.length?'missing':confirmed?'complete':'partial')}>{!files.length?'Нет документов от водителя':confirmed?'Комплект подтверждён':'Проверьте комплект документов'}</span>
  {(!!files.length||folderUrl)&&<div className="trip-document-attachments" role="group" aria-label="Документы рейса">
   <div className="trip-document-files">{files.map(f=><button className="trip-document-file" key={f.id} disabled={downloading!==null} aria-label={'Скачать '+(documentKinds[f.doc_type]||'документ')+': '+f.file_name} title={'Скачать '+f.file_name} onClick={()=>void open(f)}>
    <span className="trip-document-file-icon"><FileText size={20} aria-hidden="true"/></span>
    <span className="trip-document-file-info"><strong>{documentKinds[f.doc_type]||'Документ'}</strong><span>{f.file_name}</span></span>
    <span className="trip-document-download"><Download size={15} aria-hidden="true"/>{downloading===f.id?'Загрузка…':'Скачать'}</span>
   </button>)}</div>
   {folderUrl&&<a className="trip-document-folder" href={folderUrl} target="_blank" rel="noopener noreferrer" title="Открыть папку документов этого рейса на Google Диске"><FolderOpen size={19} aria-hidden="true"/><span>Папка на Google Диске</span><ExternalLink size={14} aria-hidden="true"/></a>}
  </div>}
  {!!accountingDocuments.length&&<div className="accounting-trip-documents"><span>Бухгалтерия:</span>{accountingDocuments.map(d=><button className="text-button" key={d.id} title="Скачать сохранённую печатную форму" onClick={()=>downloadAccounting(d)}>{accountingKinds[d.kind]} {d.number} · {accountingStatuses[d.status]}</button>)}</div>}
  <select aria-label="Тип документа" value={kind} disabled={busy} onChange={e=>setKind(e.target.value)}>{Object.entries(documentKinds).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select>
  <label className={'button secondary compact '+(busy?'disabled':'')}>{busy?'Обработка…':'Загрузить документ'}<input className="trip-file-input" type="file" disabled={busy} aria-label="Загрузить документ любого формата до 10 МБ" onChange={e=>{const input=e.currentTarget,f=input.files?.[0];if(f)void upload(f).finally(()=>{input.value=''})}}/></label>
  {!!files.length&&!confirmed&&<button className="button secondary compact" disabled={busy} onClick={()=>void confirm()}>Комплект полный</button>}
  {confirmed&&completed&&<span className="trip-archive-status">{archive?.state==='complete'&&folderUrl?'Документы сохранены на Google Диске':archive?.state==='awaiting_connection'?'Google Диск: ожидается подключение':archive?.state==='error'?'Ошибка отправки на Диск':archive?.state==='processing'?'Отправка на Диск…':'В очереди на Google Диск'}{archive?.error&&<small>{archive.error}</small>}{['error','pending','awaiting_connection'].includes(archive?.state||'pending')&&<button className="text-button" disabled={busy} onClick={()=>void retry()}>Отправить</button>}</span>}
  {error&&<span className="trip-document-error" role="alert">{error}</span>}
 </div>
}
