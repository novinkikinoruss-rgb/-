/* Photo decoding, conversion and OCR run off the interface thread. The caller owns a hard deadline and can terminate this worker and its children. */
self.onmessage=async({data:{bytes,type,name,turn,documentPhoto}})=>{
 let bitmap,ocr;
 const progress=(message,value)=>self.postMessage({progress:message,value});
 try{
  progress('Открываем фотографию',.05);
  const source=new Blob([bytes],{type:type||'application/octet-stream'});
  let canvas;
  const heic=/\.(heic|heif)$/i.test(name)||/hei[cf]/i.test(type)||/heic|heix|hevc|hevx|mif1|msf1/.test(new TextDecoder().decode(bytes.slice(8,32)));
  try{bitmap=await createImageBitmap(source,{imageOrientation:'from-image'})}catch(error){if(!heic)throw Error('Не удалось открыть фото. Выберите другой снимок или сделайте новое фото камерой.')}
  if(!bitmap){
   progress('Преобразуем HEIC в JPEG',.12);importScripts('/photo/libheif-bundle.js');const heif=await libheif();const decoder=new heif.HeifDecoder();const images=decoder.decode(new Uint8Array(bytes));
   if(!images.length)throw Error('Не удалось прочитать HEIC. Сделайте новое фото камерой или выберите JPEG.');
   try{const image=images.find(i=>i.is_primary?.())||images[0];const w=image.get_width(),h=image.get_height();if(w*h>32000000)throw Error('Слишком большое разрешение. Сделайте снимок в обычном режиме камеры.');
    const rgba=await new Promise((resolve,reject)=>image.display({data:new Uint8ClampedArray(w*h*4),width:w,height:h},result=>result?resolve(result):reject(Error('Не удалось преобразовать HEIC. Выберите JPEG или переснимите.'))));
    const decoded=new OffscreenCanvas(w,h);decoded.getContext('2d').putImageData(new ImageData(rgba.data,w,h),0,0);bitmap=await createImageBitmap(decoded);
   }finally{images.forEach(i=>i.free?.())}
  }
  if(Math.min(bitmap.width,bitmap.height)<700)throw Error('Мало деталей. Поднесите камеру ближе и переснимите документ.');
  const scale=Math.min(1,2000/Math.max(bitmap.width,bitmap.height)),w=Math.round(bitmap.width*scale),h=Math.round(bitmap.height*scale);
  canvas=new OffscreenCanvas(turn%2?h:w,turn%2?w:h);const ctx=canvas.getContext('2d');ctx.translate(canvas.width/2,canvas.height/2);ctx.rotate(turn*Math.PI/2);ctx.drawImage(bitmap,-w/2,-h/2,w,h);bitmap.close();bitmap=null;
  progress('Подготавливаем фото',.25);let blob;
  for(const quality of [.88,.75,.60]){blob=await canvas.convertToBlob({type:'image/jpeg',quality});if(blob.size<=2000000)break}
  if(blob.size>2000000)throw Error('Фото слишком большое. Снимите документ ближе, без лишнего фона.');
  const imageBytes=new Uint8Array(await blob.arrayBuffer());let raw='';for(let i=0;i<imageBytes.length;i+=8192)raw+=String.fromCharCode(...imageBytes.subarray(i,i+8192));const base64=btoa(raw);
  self.postMessage({preview:base64});
  if(documentPhoto){
   progress('Проверяем читаемость текста',.3);importScripts('/ocr/tesseract.min.js');
   const origin=self.location.origin;
   ocr=await Tesseract.createWorker('rus+eng',1,{workerPath:origin+'/ocr/worker.min.js',corePath:origin+'/ocr',langPath:origin+'/ocr',gzip:true,logger:m=>progress('Проверяем читаемость текста',.3+.65*(m.progress||0)),errorHandler:()=>{}});
   const {data}=await ocr.recognize(imageBytes);if(data.text.replace(/[^\p{L}\p{N}]/gu,'').length<20||data.confidence<45)throw Error('Текст плохо читается или фото перевёрнуто. Поверните его либо переснимите без бликов, в фокусе.');
  }
  self.postMessage({result:base64});
 }catch(e){self.postMessage({error:e instanceof Error?e.message:'Не удалось обработать фото. Выберите JPEG или сделайте новое фото.'})}
 finally{bitmap?.close();await ocr?.terminate()}
};
