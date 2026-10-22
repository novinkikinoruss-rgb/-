// Fixed destination proxy. User JWT is forwarded unchanged, so Supabase RLS and
// authentication remain authoritative. Passwords, bodies and tokens are not logged.
export const dynamic='force-dynamic';
export const runtime='nodejs';
type Context={params:Promise<{path:string[]}>};
async function forward(request:Request,context:Context){
  const {path}=await context.params;
  const auth=path[0]==='auth'&&path[1]==='v1';
  const rpc=path[0]==='rest'&&path[1]==='v1'&&path[2]==='rpc'&&['respectlogistic_read_workspace','respectlogistic_customer_action'].includes(path[3])&&path.length===4;
  const tables=['crm_carriers','crm_vehicles','crm_drivers','crm_trips','crm_sites','crm_documents','crm_counterparty_invoices','crm_counterparty_contracts','crm_counterparty_specifications'];
  const table=path[0]==='rest'&&path[1]==='v1'&&path.length===3&&tables.includes(path[2])&&['GET','HEAD','POST','PATCH'].includes(request.method);
  if((!auth&&!rpc&&!table)||path.some(part=>!/^[a-zA-Z0-9_-]+$/.test(part)))return Response.json({message:'Endpoint not available'},{status:404});
  const base=process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if(!base||!key||!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(base))return Response.json({message:'Сервис входа не настроен',code:'service_unavailable'},{status:503});
  const destination=new URL(path.join('/'),base.replace(/\/?$/,'/'));
  destination.search=new URL(request.url).search;
  const headers=new Headers({apikey:key});
  for(const name of ['authorization','content-type','accept','x-client-info','x-supabase-api-version','prefer','range']){
    const value=request.headers.get(name);if(value)headers.set(name,value);
  }
  const controller=new AbortController();
  const cancel=()=>controller.abort();request.signal.addEventListener('abort',cancel,{once:true});
  const timer=setTimeout(()=>controller.abort(),12000);
  try{
    const body=['GET','HEAD'].includes(request.method)?undefined:await request.arrayBuffer();
    if(body&&body.byteLength>1048576)return Response.json({message:'Слишком большой запрос'},{status:413});
    const upstream=await fetch(destination,{method:request.method,headers,body,signal:controller.signal,cache:'no-store',redirect:'error'});
    const result=await upstream.arrayBuffer();
    const responseHeaders=new Headers({'Cache-Control':'no-store, private'});
    for(const name of ['content-type','content-range','preference-applied','retry-after']){const value=upstream.headers.get(name);if(value)responseHeaders.set(name,value);}
    return new Response([204,205,304].includes(upstream.status)?null:result,{status:upstream.status,headers:responseHeaders});
  }catch{
    return Response.json({message:controller.signal.aborted?'Сервис входа не ответил вовремя':'Не удалось связаться с сервисом входа',code:controller.signal.aborted?'upstream_timeout':'service_unavailable'},{status:controller.signal.aborted?504:502,headers:{'Cache-Control':'no-store'}});
  }finally{clearTimeout(timer);request.signal.removeEventListener('abort',cancel);}
}
export {forward as GET,forward as POST,forward as PUT,forward as PATCH,forward as DELETE};
