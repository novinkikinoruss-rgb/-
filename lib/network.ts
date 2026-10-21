export const REQUEST_TIMEOUT_MS=15000;
export async function boundedFetch(input:RequestInfo|URL,init?:RequestInit):Promise<Response>{
  const controller=new AbortController();
  const source=init?.signal||(typeof Request!=='undefined'&&input instanceof Request?input.signal:null);
  const cancel=()=>controller.abort(source?.reason);
  if(source?.aborted)cancel();else source?.addEventListener('abort',cancel,{once:true});
  const timer=setTimeout(()=>controller.abort(new DOMException('Сервис не ответил вовремя','TimeoutError')),REQUEST_TIMEOUT_MS);
  try{return await fetch(input,{...init,signal:controller.signal});}
  catch(error){if(controller.signal.aborted&&!source?.aborted)throw new Error('Сервис входа не ответил вовремя. Повторите попытку.');throw error;}
  finally{clearTimeout(timer);source?.removeEventListener('abort',cancel);}
}
export async function deadline<T>(operation:PromiseLike<T>,milliseconds:number,message='Сервис входа не ответил вовремя. Повторите попытку.'):Promise<T>{
  let timer:ReturnType<typeof setTimeout>|undefined;
  try{return await Promise.race([operation,new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(new Error(message)),milliseconds);})]);}
  finally{clearTimeout(timer);}
}
export function authMessage(error:unknown){
  const detail=error as {message?:string;code?:string;status?:number};
  if(detail?.code==='invalid_credentials'||/invalid login credentials/i.test(detail?.message||''))return 'Неверный email или пароль.';
  if(detail?.code==='email_not_confirmed')return 'Подтвердите email по ссылке из письма перед входом.';
  if(detail?.status===429)return 'Слишком много попыток входа. Подождите немного и повторите.';
  if(/timeout|timed out|lock|не ответил вовремя/i.test(detail?.message||''))return 'Сервис входа не ответил вовремя. Повторите попытку.';
  if([502,503,504].includes(detail?.status||0)||/fetch|network|load failed|подключ|связаться/i.test(detail?.message||''))return 'Не удалось связаться с сервисом входа. Проверьте соединение и повторите попытку.';
  return 'Не удалось выполнить вход. Повторите попытку; если ошибка сохраняется, обратитесь к администратору.';
}
