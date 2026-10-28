import {CRM_ORIGIN,GOOGLE_COOKIE,CALLBACK_PATH,googleCookie,ownerRpc} from '../../../../lib/google-sync-server.ts';
export const dynamic='force-dynamic';export const runtime='nodejs';
export async function GET(request:Request){const url=new URL(request.url);const redirect=(status:string)=>new Response(null,{status:303,headers:{Location:CRM_ORIGIN+'/?workspace=trips&google='+status,'Set-Cookie':googleCookie('',0),'Cache-Control':'no-store'}});
 try{const raw=request.headers.get('cookie')?.split(';').map(s=>s.trim()).find(s=>s.startsWith(GOOGLE_COOKIE+'='))?.slice(GOOGLE_COOKIE.length+1);if(!raw||url.searchParams.has('error'))return redirect('denied');const session=JSON.parse(Buffer.from(raw,'base64url').toString());if(session.expires<Date.now()||session.state!==url.searchParams.get('state')||!url.searchParams.get('code'))return redirect('invalid_state');
 const cfg=await ownerRpc(session.authorization,'respectlogistic_google_settings',{p_action:'credentials'});
 const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({client_id:cfg.clientId,client_secret:cfg.clientSecret,code:url.searchParams.get('code')!,code_verifier:session.verifier,grant_type:'authorization_code',redirect_uri:CRM_ORIGIN+CALLBACK_PATH}),signal:AbortSignal.timeout(25000),cache:'no-store'});const token=await response.json();if(!response.ok||!token.refresh_token)return redirect('token_error');
 await ownerRpc(session.authorization,'respectlogistic_google_settings',{p_action:'token',p_record:{refreshToken:token.refresh_token}});return redirect('connected');
 }catch{return redirect('connection_error')}
}
