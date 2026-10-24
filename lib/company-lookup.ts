import {validInn} from './domain.ts';
export type CompanyDetails={name:string;fullName:string;inn:string;kpp:string;ogrn:string;legalAddress:string;director:string};
type Config={token?:string;base?:string;key?:string};
const headers={'Cache-Control':'no-store'};
export async function handleCompanyLookup(request:Request,config:Config,transport:typeof fetch=fetch){
 const fail=(error:string,status:number)=>Response.json({error},{status,headers});
 const authorization=request.headers.get('Authorization')||'';
 if(!config.base||!config.key)return fail('Автозаполнение Чекко ещё не подключено. Можно заполнить карточку вручную.',503);
 if(!authorization.startsWith('Bearer '))return fail('Для поиска реквизитов войдите в CRM',401);
 try{
  const auth=await transport(config.base+'/auth/v1/user',{headers:{apikey:config.key,Authorization:authorization},cache:'no-store',signal:AbortSignal.timeout(10000)});
  if(!auth.ok||!(await auth.json())?.id)return fail('Сессия истекла. Войдите снова',401);
 }catch{return fail('Не удалось проверить вход. Повторите поиск.',502)}
 if(!config.token)return fail('Автозаполнение Чекко ещё не подключено. Можно заполнить реквизиты вручную.',503);
 let inn:string,exact:boolean;
 try{
  const body=await request.text();if(body.length>1000)throw Error();
  const input=JSON.parse(body);exact=input.inn!==undefined;
  const value=exact?input.inn:input.query;if(typeof value!=='string')throw Error();inn=value.trim();
  if(!validInn(inn))throw Error();
 }catch{return fail('Введите корректный ИНН организации из 10 цифр',400)}
 try{
  // The provider requires its key in the query. Never log this URL or forward provider errors.
  const url=new URL('https://api.checko.ru/v2/company');url.search=new URLSearchParams({key:config.token,inn}).toString();
  const response=await transport(url.toString(),{headers:{Accept:'application/json'},signal:AbortSignal.timeout(10000),cache:'no-store',redirect:'error'});
  if(response.status===429||response.status===402)return fail('Лимит запросов Чекко исчерпан. Повторите позже или заполните вручную.',429);
  if(response.status===401||response.status===403)return fail('Чекко отклонил запрос: проверьте ключ и доступный лимит сервиса. Можно заполнить вручную.',503);
  if(response.status===404)return fail('Организация не найдена. Проверьте ИНН или заполните данные вручную.',404);
  if(!response.ok)throw Error();
  const result=await response.json();
  if(result.meta?.status!=='ok')return fail('Чекко не выполнил поиск. Проверьте доступный лимит или заполните вручную.',502);
  const p=result.data;
  if(!p||!p['ИНН'])return fail('Организация не найдена. Проверьте ИНН или заполните данные вручную.',404);
  if(p['ИНН']!==inn||!validInn(p['ИНН']))throw Error();
  const text=(v:unknown)=>typeof v==='string'?v.slice(0,4000):'';
  const company:CompanyDetails={name:text(p['НаимСокр'])||text(p['НаимПолн']),fullName:text(p['НаимПолн']),inn,kpp:text(p['КПП']),ogrn:text(p['ОГРН']),legalAddress:text(p['ЮрАдрес']?.['АдресРФ']),director:Array.isArray(p['Руковод'])?p['Руковод'].map((r:Record<string,unknown>)=>text(r['ФИО'])).filter(Boolean).join('; ').slice(0,4000):''};
  if(!company.name)throw Error();
  return Response.json(exact?{company}:{suggestions:[company]},{headers});
 }catch{return fail('Сервис Чекко временно недоступен. Попробуйте позже или заполните вручную.',502)}
}
