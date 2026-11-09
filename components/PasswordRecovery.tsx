'use client';
import {useEffect,useRef,useState,type FormEvent} from 'react';
import {db} from '../lib/supabase';

// Capture before Auth initialization can consume and remove the fragment.
const recoveryReturn=typeof window!=='undefined'&&new URLSearchParams(window.location.hash.slice(1)).get('type')==='recovery';

const expired='Код неверный, истёк или уже использован. Проверьте последнее письмо или запросите новый код.';

export function PasswordRecovery(){
  const [email,setEmail]=useState(''),[requestedEmail,setRequestedEmail]=useState(''),[code,setCode]=useState(''),[password,setPassword]=useState(''),[confirm,setConfirm]=useState('');
  const [verified,setVerified]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[error,setError]=useState(''),[done,setDone]=useState(false);
  const [nextSendAt,setNextSendAt]=useState(0),[now,setNow]=useState(0);
  const remaining=Math.max(0,Math.ceil((nextSendAt-now)/1000));
  const started=useRef(false);
  useEffect(()=>{if(!nextSendAt)return;const timer=setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(timer);},[nextSendAt]);
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
    event.preventDefault();if(!db||busy||Date.now()<nextSendAt)return;setBusy(true);setError('');setMessage('');
    try{
      const destination=(requestedEmail||email).trim().toLowerCase();
      const {error}=await db.auth.resetPasswordForEmail(destination,{redirectTo:window.location.origin+'/reset-password'});
      if(error)throw error;
      setRequestedEmail(destination);setCode('');setNow(Date.now());setNextSendAt(Date.now()+60000);
      setMessage('Если адрес зарегистрирован, код отправлен. Проверьте «Входящие» и «Спам».');
    }catch(error){
      const detail=error as {status?:number;code?:string;message?:string};
      if(detail.code==='over_email_send_rate_limit'||/email rate limit exceeded/i.test(detail.message||''))setError('Достигнут часовой лимит отправки писем. Попробуйте позже.');
      else if(detail.status===429)setError('Слишком много запросов на отправку кода. Подождите немного и повторите.');
      else setError('Не удалось отправить код. Проверьте соединение и повторите попытку.');
    }finally{setBusy(false);}
  }
  async function verify(event:FormEvent){
    event.preventDefault();if(!db||busy||!requestedEmail)return;setError('');
    if(!/^\d{6}$/.test(code)){setError('Введите 6 цифр из письма.');return;}
    setBusy(true);
    try{
      const {data,error}=await db.auth.verifyOtp({email:requestedEmail,token:code,type:'recovery'});
      if(error){setError((error.code==='otp_expired'||error.status===403)?expired:error.status===429?'Слишком много попыток. Подождите немного и повторите.':'Не удалось проверить код. Проверьте соединение и повторите попытку.');return;}
      if(!data.session)throw new Error();setCode('');setVerified(true);setMessage('');
    }catch{setError('Не удалось проверить код. Проверьте соединение и повторите попытку.');}finally{setBusy(false);}
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
    </form>:requestedEmail?<>
      <p>Введите код из последнего письма для <strong>{requestedEmail}</strong>.</p>
      <form onSubmit={verify}><label className="field">Код из письма<input type="text" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required value={code} onChange={e=>setCode(e.target.value.replace(/\D/g,'').slice(0,6))}/></label><button className="button" disabled={busy||code.length!==6}>{busy?'Проверяем…':'Подтвердить код'}</button></form>
      <form onSubmit={send} style={{marginTop:16}}><button className="button secondary" disabled={busy||remaining>0}>{remaining>0?'Отправить код повторно через '+remaining+' с':'Отправить код повторно'}</button></form>
      <p><button type="button" className="button secondary" disabled={busy} onClick={()=>{setRequestedEmail('');setCode('');setError('');setMessage('');}}>Изменить email</button></p>
    </>:<>
      <p>Укажите email учётной записи. На него придёт одноразовый код для создания нового пароля.</p>
      <form onSubmit={send}><label className="field">Email<input type="email" autoComplete="username" required value={email} onChange={e=>setEmail(e.target.value)}/></label><button className="button" disabled={busy||remaining>0}>{remaining>0?'Повторная отправка через '+remaining+' с':busy?'Отправляем…':'Получить код'}</button></form>
    </>}
    {error&&<p role="alert" className="form-error">{error}</p>}{message&&<p role="status">{message}</p>}
    <p><a href="/">Вернуться ко входу в CRM</a></p>
  </section></main>;
}
