export function driverErrorMessage(error:unknown){
 const detail=error as {name?:string;message?:string};const message=detail?.message||String(error||'');
 if(/TimeoutError|AbortError/.test(detail?.name||'')||/timed?\s*out|timeout|signal.*abort/i.test(message))return 'Сервер не ответил вовремя. Проверьте соединение и повторите действие. Введённые данные остаются на экране.';
 if(/failed to fetch|fetch failed|networkerror|load failed/i.test(message))return 'Не удалось связаться с сервером. Проверьте интернет и повторите действие.';
 return message||'Не удалось выполнить действие. Повторите попытку.';
}
