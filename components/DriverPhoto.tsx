'use client';
import {useEffect,useRef,useState} from 'react';
// OCR is local to the device; images and recognised text are not sent to an OCR provider.
export function DriverPhoto({onReady,documentPhoto=false}:{onReady:(base64:string)=>void;documentPhoto?:boolean}){
 const [source,setSource]=useState<File|null>(null),[turn,setTurn]=useState(0),[preview,setPreview]=useState(''),[error,setError]=useState(''),[checking,setChecking]=useState(false),[confirmed,setConfirmed]=useState(false);
 const prepared=useRef('');const generation=useRef(0);
 useEffect(()=>{const version=++generation.current;onReady('');setConfirmed(false);setError('');prepared.current='';setPreview('');setChecking(false);if(!source)return;
 setChecking(true);
 void (async()=>{let worker:Awaited<ReturnType<typeof import('tesseract.js')['createWorker']>>|undefined;
 try{
 if(!source.type.startsWith('image/')||source.size>25*1024*1024)throw Error('Выберите фотографию до 25 МБ');
 const bitmap=await createImageBitmap(source,{imageOrientation:'from-image'});const canvas=document.createElement('canvas');
 try{if(Math.min(bitmap.width,bitmap.height)<700)throw Error('Мало деталей. Поднесите камеру ближе и переснимите документ');
 const scale=Math.min(1,2200/Math.max(bitmap.width,bitmap.height));const w=Math.round(bitmap.width*scale),h=Math.round(bitmap.height*scale);canvas.width=turn%2?h:w;canvas.height=turn%2?w:h;
 const ctx=canvas.getContext('2d');if(!ctx)throw Error('Не удалось открыть фото');ctx.translate(canvas.width/2,canvas.height/2);ctx.rotate(turn*Math.PI/2);ctx.drawImage(bitmap,-w/2,-h/2,w,h);
 }finally{bitmap.close()}
 let encoded=canvas.toDataURL('image/jpeg',.9);if(encoded.length>2796231)encoded=canvas.toDataURL('image/jpeg',.75);if(encoded.length>2796231)throw Error('Фото слишком большое. Переснимите ближе к документу');
 if(version!==generation.current)return;setPreview(encoded);
 if(documentPhoto){const {createWorker}=await import('tesseract.js');worker=await createWorker('rus+eng',1,{workerPath:'/ocr/worker.min.js',corePath:'/ocr',langPath:'/ocr',gzip:true});
 const result=await worker.recognize(encoded);const letters=result.data.text.replace(/[^\p{L}\p{N}]/gu,'');
 if(letters.length<20||result.data.confidence<45)throw Error('Текст плохо читается или фото перевёрнуто. Поверните его либо переснимите без бликов, в фокусе');}
 if(version===generation.current)prepared.current=encoded.split(',')[1];
 }catch(e){if(version===generation.current)setError((e as Error).message)}finally{await worker?.terminate();if(version===generation.current)setChecking(false)}
 })();return()=>{generation.current++};
 },[source,turn,documentPhoto]);
 return <div className="driver-photo"><label className="field">{documentPhoto?'Фото документа':'Фото'}<input type="file" accept="image/*" capture="environment" onChange={e=>{setTurn(0);setSource(e.target.files?.[0]||null)}}/></label>{preview&&<><img src={preview} alt="Проверьте весь документ и направление текста"/><button className="button secondary" type="button" disabled={checking} onClick={()=>setTurn(t=>(t+1)%4)}>Повернуть на 90°</button></>}{checking&&<p role="status">Проверяем фотографию…</p>}{error&&<p role="alert" className="driver-alert error">{error}</p>}{preview&&!checking&&!error&&<label className="driver-check"><input type="checkbox" checked={confirmed} onChange={e=>{setConfirmed(e.target.checked);onReady(e.target.checked?prepared.current:'')}}/>Все края и поля видны, текст чёткий и расположен правильно</label>}<p className="hint">{documentPhoto?'Проверка текста помогает выявить плохой снимок. Перед загрузкой проверьте все поля и края документа.':'Снимите весь чек или ремонтируемый узел без бликов.'}</p></div>
}
