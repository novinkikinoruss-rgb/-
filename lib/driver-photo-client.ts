export const PHOTO_TIMEOUT_MS=45000;
export async function processDriverPhoto(file:File,turn:number,documentPhoto:boolean,signal:AbortSignal,onMessage:(message:{progress?:string;value?:number;preview?:string})=>void,timeout=PHOTO_TIMEOUT_MS):Promise<string>{
 if(file.size<=0||file.size>25*1024*1024)throw Error('Выберите фотографию до 25 МБ');
 if(!file.type.startsWith('image/')&&!/\.(heic|heif|jpe?g|png|webp)$/i.test(file.name))throw Error('Выберите фото HEIC, JPEG, PNG или WebP');
 return new Promise((resolve,reject)=>{
  const worker=new Worker('/photo/prepare-worker.js');let ended=false;
  const finish=(error?:Error,result?:string)=>{if(ended)return;ended=true;clearTimeout(timer);signal.removeEventListener('abort',abort);worker.terminate();error?reject(error):resolve(result!)};
  const abort=()=>finish(new DOMException('Проверка отменена','AbortError'));
  const timer=setTimeout(()=>finish(Error('Проверка заняла слишком много времени. Повторите проверку или сделайте новое фото камерой.')),timeout);
  if(signal.aborted){abort();return}signal.addEventListener('abort',abort,{once:true});
  worker.onerror=()=>finish(Error('Не удалось обработать фото. Повторите проверку или выберите JPEG.'));
  worker.onmessage=({data})=>{if(data.error)finish(Error(data.error));else if(data.result)finish(undefined,data.result);else onMessage(data)};
  file.arrayBuffer().then(bytes=>{if(!ended)worker.postMessage({bytes,type:file.type,name:file.name,turn,documentPhoto},[bytes])}).catch(()=>finish(Error('Не удалось прочитать выбранное фото. Сохраните его на телефон и выберите повторно.')));
 });
}
