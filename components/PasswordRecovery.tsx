'use client';
import {useEffect,useRef,useState,type FormEvent} from 'react';
import {db} from '../lib/supabase';

// Capture before Auth initialization can consume and remove the fragment.
const recoveryReturn=typeof window!=='undefined'&&new URLSearchParams(window.location.hash.slice(1)).get('type')==='recovery';

const expired='Ссылка истекла или уже использована. Запросите новое письмо.';
function recoveryHash(value:string):string{
  let url:URL;
  try{url=new URL(value.trim());}catch{throw new Error('Скопируйте ссылку восстановления из письма целиком.');}
  // Gmail may wrap the original email link. Never navigate to or fetch a pasted URL.
  if(url.origin==='https://www.google.com'&&url.pathname==='/url'){
    try{url=new URL(url.searchParams.get('q')||url.searchParams.get('url')||'');}catch{throw new Error('Не удалось прочитать ссылку из письма.');}
  }
  const origin=process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/,'');
  const token=url.searchParams.get('token')||url.searchParams.get('token_hash');
  if(url.origin!==origin||url.pathname!=='/auth/v1/verify'||url.searchParams.get('type')!=='recovery'||!token||!(/^[a-f0-9]{40,128}$/i.test(token)))throw new Error('Нужна ссылка восстановления именно этой CRM из последнего письма.');
  return token;
}

export function PasswordRecovery(){
  const [email,setEmail]=useState(''),[link,setLink]=useState(''),[password,setPassword]=useState(''),[confirm,setConfirm]=useState('');
  const [verified,setVerified]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[error,setError]=useState(''),[done,setDone]=useState(false);
  const started=useRef(false);
  useEffect(()=>{
    if(!db)return;
    let active=true;
    const {data:{subscription}}=db.auth.onAuthStateChange(event=>{if(event==='PASSWORD_RECOVERY'){setVerified(true);setError('');window.history.replaceState(null,'','/reset-password');}});
    // A fast Auth response may emit PASSWORD_RECOVERY before React subscribes.
    // getSession waits for SDK initialization and validates that a session exists.
    if(recoveryReturn)void db.auth.getSession().then(({data,error})=>{
      if(!active)return;
      window.history.replaceState(null,'','/reset-password');
      if(!error&&data.session){setVerified(true);setError('');}else setError(expired);
    });
    if(!started.current){
      started.current=true;
      const hash=new URLSearchParams(window.location.hash.slice(1));
      if(hash.has('error')){setError(expired);window.history.replaceState(null,'','/reset-password');}
    }
    return()=>{active=false;subscription.unsubscribe();};
  },[]);
  async function send(event:FormEvent){
    event.preventDefault();if(!db||busy)return;setBusy(true);setError('');setMessage('');
    try{
      const {error}=await db.auth.resetPasswordForEmail(email.trim(),{redirectTo:window.location.origin+'/reset-password'});
      if(error)throw error;
      setMessage('Если адрес зарегистрирован, письмо отправлено. Если ссылка не открывается, скопируйте её из письма в поле ниже.');
    }catch{setError('Не удалось отправить письмо. Попробуйте позже; проверьте, не пришло ли предыдущее письмо.');}finally{setBusy(false);}
  }
  async function verify(event:FormEvent){
    event.preventDefault();if(!db||busy)return;setError('');
    let token:string;try{token=recoveryHash(link);}catch(e){setError((e as Error).message);return;}
    setBusy(true);setLink('');
    try{const {data,error}=await db.auth.verifyOtp({token_hash:token,type:'recovery'});if(error||!data.session)throw new Error();setVerified(true);setMessage('');}catch{setError(expired);}finally{setBusy(false);}
  }
  async function save(event:FormEvent){
    event.preventDefault();if(!db||busy)return;setError('');
    if(password.length<12){setError('Пароль должен содержать не менее 12 символов.');return;}
    if(password!==confirm){setError('Пароли не совпадают.');return;}
    setBusy(true);
    try{
      const {error}=await db.auth.updateUser({password});
      if(error){setError(error.code==='same_password'?'Укажите новый пароль, который отличается от прежнего.':'Не удалось сохранить пароль. Проверьте соединение или запросите новое письмо.');return;}
      setPassword('');setConfirm('');setDone(true);setVerified(false);
      // Revoke refresh sessions after recovery. Do not disguise a sign-out failure as a password failure.
      const {error:logoutError}=await db.auth.signOut();
      if(logoutError)setMessage('Пароль сохранён. При следующем входе используйте новый пароль.');
    }catch{setError('Не удалось сохранить пароль. Проверьте соединение и повторите попытку.');}finally{setBusy(false);}
  }
  return <main style={{maxWidth:560,margin:'8vh auto',padding:18}}><section className="panel" style={{overflowWrap:'anywhere'}}><h1>{done?'Пароль сохранён':verified?'Новый пароль':'Восстановление доступа'}</h1>
    {!db?<p role="alert">Сервис входа не настроен.</p>:done?<p role="status">Теперь войдите в CRM с новым паролем.</p>:verified?<form onSubmit={save}>
      <label className="field">Новый пароль<input type="password" autoComplete="new-password" minLength={12} required value={password} onChange={e=>setPassword(e.target.value)}/></label>
      <label className="field">Повторите пароль<input type="password" autoComplete="new-password" minLength={12} required value={confirm} onChange={e=>setConfirm(e.target.value)}/></label>
      <button className="button" disabled={busy}>{busy?'Сохраняем…':'Сохранить пароль'}</button>
    </form>:<>
      <p>Запросите письмо на email учётной записи. Используйте последнее письмо.</p>
      <form onSubmit={send}><label className="field">Email<input type="email" autoComplete="username" required value={email} onChange={e=>setEmail(e.target.value)}/></label><button className="button" disabled={busy}>Отправить письмо</button></form>
      <hr style={{margin:'24px 0',border:0,borderTop:'1px solid #dce2dc'}}/>
      <h2>Письмо уже пришло?</h2><p>Если ссылка не открывается, скопируйте её из письма и вставьте здесь. Не отправляйте её в чат.</p>
      <form onSubmit={verify}><label className="field">Ссылка из письма<input type="text" autoComplete="off" spellCheck={false} required value={link} onChange={e=>setLink(e.target.value)}/></label><button className="button" disabled={busy}>Проверить ссылку</button></form>
    </>}
    {error&&<p role="alert" className="form-error">{error}</p>}{message&&<p role="status">{message}</p>}
    <p><a href="/">Вернуться ко входу в CRM</a></p>
  </section></main>;
}
