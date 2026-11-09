import {test,expect} from '@playwright/test';
const uid='00000000-0000-4000-8000-000000000099';
const user={id:uid,aud:'authenticated',role:'authenticated',email:'test@example.invalid',app_metadata:{provider:'email',providers:['email']},user_metadata:{},created_at:'2026-01-01T00:00:00Z',identities:[]};
const token=()=>Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:uid,exp:Math.floor(Date.now()/1000)+3600,aud:'authenticated',role:'authenticated'})).toString('base64url')+'.'+Buffer.alloc(32).toString('base64url');
async function setup(page,{expired=false,sendFailed=false}={}){
 const calls=[];
 await page.route('https://*.supabase.co/**',route=>route.abort());
 await page.route('**/supabase/**',async route=>{
  const path=new URL(route.request().url()).pathname,body=route.request().postDataJSON();calls.push({path,method:route.request().method(),body});
  if(path.endsWith('/recover'))return route.fulfill({status:sendFailed?429:200,json:sendFailed?{code:'over_email_send_rate_limit',message:'Email rate limit exceeded'}:{}});
  if(path.endsWith('/verify')){const invalid=expired||body.token!=='123456';return route.fulfill({status:invalid?403:200,json:invalid?{code:'otp_expired',message:'Token has expired or is invalid'}:{access_token:token(),refresh_token:'test-refresh-token',expires_in:3600,token_type:'bearer',user}});}
  if(path.endsWith('/user'))return route.fulfill({json:user});
  if(path.endsWith('/logout'))return route.fulfill({status:204});
  return route.fulfill({json:{}});
 });
 await page.goto('/reset-password');return calls;
}
async function requestCode(page){await page.getByLabel('Email',{exact:true}).fill(' TEST@example.invalid ');await page.getByRole('button',{name:'Получить код',exact:true}).click();await expect(page.getByLabel('Код из письма')).toBeVisible();}
test('Email → код → новый пароль; код привязан к адресу, повторная отправка ограничена',async({page})=>{
 const calls=await setup(page);await requestCode(page);
 expect(calls.find(c=>c.path.endsWith('/recover')).body.email).toBe(user.email);
 await expect(page.getByRole('button',{name:/Отправить код повторно/})).toBeDisabled();
 await expect(page.getByLabel('Ссылка из письма')).toHaveCount(0);
 await expect(page.getByRole('button',{name:'Подтвердить код'})).toBeDisabled();
 await page.getByLabel('Код из письма').fill('000000');await page.getByRole('button',{name:'Подтвердить код'}).click();
 await expect(page.locator('main').getByRole('alert')).toContainText('Код неверный');
 await expect(page.getByLabel('Новый пароль',{exact:true})).toHaveCount(0);
 expect(calls.some(c=>c.path.endsWith('/user')&&c.method==='PUT')).toBe(false);
 await page.getByLabel('Код из письма').fill('123456');await page.getByRole('button',{name:'Подтвердить код'}).click();
 await expect(page.getByRole('heading',{name:'Новый пароль',exact:true})).toBeVisible();
 expect(calls.filter(c=>c.path.endsWith('/verify')).at(-1).body).toMatchObject({email:user.email,token:'123456',type:'recovery'});
 await page.getByLabel('Новый пароль',{exact:true}).fill('synthetic-new-password');await page.getByLabel('Повторите пароль').fill('different-password');await page.getByRole('button',{name:'Сохранить пароль'}).click();
 await expect(page.locator('main').getByRole('alert')).toHaveText('Пароли не совпадают.');
 expect(calls.some(c=>c.path.endsWith('/user')&&c.method==='PUT')).toBe(false);
 await page.getByLabel('Повторите пароль').fill('synthetic-new-password');await page.getByRole('button',{name:'Сохранить пароль'}).click();
 await expect(page.getByRole('heading',{name:'Пароль сохранён'})).toBeVisible();
 expect(calls.find(c=>c.path.endsWith('/user')&&c.method==='PUT').body.password).toBe('synthetic-new-password');
 await expect.poll(()=>calls.some(c=>c.path.endsWith('/logout'))).toBe(true);
 expect(new URL(page.url()).hash).toBe('');
});
test('Истёкший код не открывает смену пароля; изменение адреса очищает код',async({page})=>{
 const calls=await setup(page,{expired:true});await requestCode(page);
 await page.getByLabel('Код из письма').fill('123456');await page.getByRole('button',{name:'Подтвердить код'}).click();
 await expect(page.locator('main').getByRole('alert')).toContainText('истёк');await expect(page.getByLabel('Новый пароль',{exact:true})).toHaveCount(0);
 await page.getByRole('button',{name:'Изменить email'}).click();await expect(page.getByLabel('Email',{exact:true})).toBeVisible();await expect(page.getByLabel('Код из письма')).toHaveCount(0);
 expect(calls.some(c=>c.path.endsWith('/user')&&c.method==='PUT')).toBe(false);
});
test('Отказ отправки письма не выдаётся за отправленный код',async({page})=>{
 await setup(page,{sendFailed:true});await page.getByLabel('Email',{exact:true}).fill(user.email);await page.getByRole('button',{name:'Получить код',exact:true}).click();
 await expect(page.locator('main').getByRole('alert')).toContainText('часовой лимит отправки писем');await expect(page.getByLabel('Код из письма')).toHaveCount(0);
});
test('Старый прямой возврат из письма поддерживается; токены удаляются из адресной строки',async({page})=>{
 await setup(page);await page.goto('about:blank');
 await page.goto('/reset-password#access_token='+token()+'&refresh_token=test-refresh-token&expires_in=3600&token_type=bearer&type=recovery');
 await expect(page.getByRole('heading',{name:'Новый пароль',exact:true})).toBeVisible();await expect.poll(()=>new URL(page.url()).hash).toBe('');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
