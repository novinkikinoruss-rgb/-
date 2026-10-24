import {validInn} from './domain.ts';
export type CompanyDetails={name:string;fullName:string;inn:string;kpp:string;ogrn:string;legalAddress:string;director:string};
type Config={token?:string;base?:string;key?:string};
const headers={'Cache-Control':'no-store'};
export async function handleCompanyLookup(request:Request,config:Config,transport:typeof fetch=fetch){
 const fail=(error:string,status:number)=>Response.json({error},{status,headers});
 const authorization=request.headers.get('Authorization')||'';
 if(!config.base||!config.key)return fail('Автозаполнение DaData ещё не подключено. Можно заполнить карточку вручную.',503);
 if(!authorization.startsWith('Bearer '))return fail('Для поиска реквизитов войдите в CRM',401);
 try{
  const auth=await transport(config.base+'/auth/v1/user',{headers:{apikey:config.key,Authorization:authorization},cache:'no-store',signal:AbortSignal.timeout(10000)});
  if(!auth.ok||!(await auth.json())?.id)return fail('Сессия истекла. Войдите снова',401);
 }catch{return fail('Не удалось проверить вход. Повторите поиск.',502)}
 if(!config.token)return fail('Автозаполнение DaData ещё не подключено. Можно заполнить реквизиты вручную.',503);
 let query:string,exact:boolean;
 try{
  const body=await request.text();if(body.length>1000)throw Error();
  const input=JSON.parse(body);exact=input.inn!==undefined;
  const value=exact?input.inn:input.query;if(typeof value!=='string')throw Error();query=value.trim();
  if(exact?!validInn(query):query.length<3||query.length>200)throw Error();
 }catch{return fail('Введите ИНН организации из 10 цифр или название от 3 символов',400)}
 try{
  const response=await transport('https://suggestions.dadata.ru/suggestions/api/4_1/rs/'+(exact?'findById':'suggest')+'/party',{method:'POST',headers:{'Content-Type':'application/json',Accept:'application/json',Authorization:`Token ${config.token}`},body:JSON.stringify({query,type:'LEGAL',branch_type:'MAIN',count:exact?1:5}),signal:AbortSignal.timeout(10000),cache:'no-store'});
  if(response.status===429)return fail('Лимит запросов DaData исчерпан. Повторите позже или заполните вручную.',429);
  if(!response.ok)throw Error();
  const result=await response.json();if(!Array.isArray(result.suggestions))throw Error();
  const suggestions:CompanyDetails[]=result.suggestions.map((s:{data:Record<string,any>})=>s.data).filter((p:Record<string,any>)=>p&&validInn(p.inn)&&(!exact||p.inn===query)).slice(0,5).map((p:Record<string,any>)=>({name:p.name?.short_with_opf||'',fullName:p.name?.full_with_opf||'',inn:p.inn,kpp:p.kpp||'',ogrn:p.ogrn||'',legalAddress:p.address?.unrestricted_value||p.address?.value||'',director:p.management?.name||''}));
  if(exact&&!suggestions.length)return fail('Организация не найдена. Проверьте ИНН или заполните данные вручную.',404);
  return Response.json(exact?{company:suggestions[0]}:{suggestions},{headers});
 }catch{return fail('Сервис DaData временно недоступен. Попробуйте позже или заполните вручную.',502)}
}
