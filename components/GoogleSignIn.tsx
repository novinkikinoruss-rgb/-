'use client';
import {useState} from 'react';
import {db} from '../lib/supabase';
import {boundedFetch,deadline} from '../lib/network';

export function GoogleSignIn({disabled=false}:{disabled?:boolean}){
  const [busy,setBusy]=useState(false),[error,setError]=useState('');
  async function signIn(){
    if(!db||busy||disabled)return;setBusy(true);setError('');
    try{
      const response=await boundedFetch('/supabase/auth/v1/settings',{cache:'no-store'});
      if(!response.ok)throw new Error();
      const settings=await response.json();
      if(settings?.external?.google!==true){setError('Вход через Google ещё не подключён. Администратору нужно включить Google в настройках входа.');return;}
      const {data,error}=await deadline(db.auth.signInWithOAuth({provider:'google',options:{skipBrowserRedirect:true,redirectTo:window.location.origin+'/',queryParams:{prompt:'select_account'}}}),15000);
      if(error||!data.url)throw new Error();
      const base=process.env.NEXT_PUBLIC_SUPABASE_URL;
      if(!base||!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(base))throw new Error();
      // The ordinary Auth client uses our same-origin API proxy. OAuth must
      // navigate directly to Supabase so its browser redirects reach Google.
      const generated=new URL(data.url);
      const target=new URL('/auth/v1/authorize',base);
      target.search=generated.search;
      if(target.searchParams.get('provider')!=='google')throw new Error();
      window.location.assign(target.href);
    }catch{setError('Не удалось начать вход через Google. Проверьте соединение и повторите попытку.');}
    finally{setBusy(false);}
  }
  return <div style={{marginBottom:24}}><button type="button" className="button secondary" style={{width:'100%',justifyContent:'center'}} disabled={busy||disabled} onClick={()=>void signIn()}>
    <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><path fill="#4285f4" d="M21.6 12.23c0-.71-.06-1.39-.18-2.05H12v3.88h5.38a4.61 4.61 0 0 1-2 3.03v2.52h3.24c1.9-1.75 2.98-4.33 2.98-7.38Z"/><path fill="#34a853" d="M12 22c2.7 0 4.96-.9 6.62-2.42l-3.24-2.52c-.9.6-2.04.97-3.38.97-2.6 0-4.8-1.76-5.59-4.12H3.07v2.6A10 10 0 0 0 12 22Z"/><path fill="#fbbc05" d="M6.41 13.91a6 6 0 0 1 0-3.82v-2.6H3.07a10 10 0 0 0 0 9.02l3.34-2.6Z"/><path fill="#ea4335" d="M12 5.97c1.47 0 2.79.5 3.83 1.5l2.88-2.87A9.6 9.6 0 0 0 12 2a10 10 0 0 0-8.93 5.49l3.34 2.6C7.2 7.73 9.4 5.97 12 5.97Z"/></svg>
    {busy?'Переходим к Google…':'Войти через Google'}
  </button>{error&&<p role="alert" className="form-error">{error}</p>}<p style={{fontSize:12}}>Выберите Google-аккаунт с email вашей CRM.</p></div>;
}
