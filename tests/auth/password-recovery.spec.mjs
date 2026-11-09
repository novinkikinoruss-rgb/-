import {test,expect} from '@playwright/test';
const uid='00000000-0000-4000-8000-000000000099';
const user={id:uid,aud:'authenticated',role:'authenticated',email:'test@example.invalid',app_metadata:{provider:'email',providers:['email']},user_metadata:{},created_at:'2026-01-01T00:00:00Z',identities:[]};
const token=()=>Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:uid,exp:Math.floor(Date.now()/1000)+3600,aud:'authenticated',role:'authenticated'})).toString('base64url')+'.'+Buffer.alloc(32).toString('base64url');
async function setup(page,expired=false){
 const calls=[];
 await page.route('https://*.supabase.co/**',route=>route.abort());
 await page.route('**/supabase/**',async route=>{
  const path=new URL(route.request().url()).pathname,body=route.request().postDataJSON();calls.push({path,method:route.request().method(),body});
  if(path.endsWith('/recover'))return route.fulfill({json:{}});
  if(path.endsWith('/verify'))return route.fulfill({status:expired?403:200,json:expired?{code:'otp_expired',message:'Token has expired or is invalid'}:{access_token:token(),refresh_token:'test-refresh-token',expires_in:3600,token_type:'bearer',user}});
  if(path.endsWith('/user'))return route.fulfill({json:user});
  if(path.endsWith('/logout'))return route.fulfill({status:204});
  return route.fulfill({json:{}});
 });
 await page.goto('/reset-password');return calls;
}
const emailLink='https://yoqejkedmksmvbqagqru.supabase.co/auth/v1/verify?token='+('a'.repeat(56))+'&type=recovery&redirect_to=http://localhost:3000';
test('Восстановление из письма работает без перехода на localhost; пароль меняется только после проверки',async({page})=>{
 const calls=await setup(page);
 await page.getByLabel('Email',{exact:true}).fill(user.email);await page.getByRole('button',{name:'Отправить письмо',exact:true}).click();
 await expect(page.getByRole('status')).toContainText('письмо отправлено');
 expect(calls.some(c=>c.path.endsWith('/user')&&c.method==='PUT')).toBe(false);
 await page.getByLabel('Ссылка из письма').fill('https://www.google.com/url?q='+encodeURIComponent(emailLink));await page.getByRole('button',{name:'Проверить ссылку'}).click();
 await expect(page.getByRole('heading',{name:'Новый пароль',exact:true})).toBeVisible();
 expect(calls.find(c=>c.path.endsWith('/verify')).body).toMatchObject({token_hash:'a'.repeat(56),type:'recovery'});
 await page.getByLabel('Новый пароль',{exact:true}).fill('synthetic-new-password');await page.getByLabel('Повторите пароль').fill('different-password');await page.getByRole('button',{name:'Сохранить пароль'}).click();
 await expect(page.locator('main').getByRole('alert')).toHaveText('Пароли не совпадают.');
 expect(calls.some(c=>c.path.endsWith('/user')&&c.method==='PUT')).toBe(false);
 await page.getByLabel('Повторите пароль').fill('synthetic-new-password');await page.getByRole('button',{name:'Сохранить пароль'}).click();
 await expect(page.getByRole('heading',{name:'Пароль сохранён'})).toBeVisible();
 expect(calls.find(c=>c.path.endsWith('/user')&&c.method==='PUT').body.password).toBe('synthetic-new-password');
 await expect.poll(()=>calls.some(c=>c.path.endsWith('/logout'))).toBe(true);
 expect(new URL(page.url()).pathname).toBe('/reset-password');
});
test('Чужая ссылка не отправляется на сервер; истёкшая ссылка не открывает смену пароля',async({page})=>{
 const calls=await setup(page,true);
 await page.getByLabel('Ссылка из письма').fill(emailLink.replace('yoqejkedmksmvbqagqru.supabase.co','other.supabase.co'));await page.getByRole('button',{name:'Проверить ссылку'}).click();
 await expect(page.locator('main').getByRole('alert')).toContainText('именно этой CRM');expect(calls.some(c=>c.path.endsWith('/verify'))).toBe(false);
 await page.getByLabel('Ссылка из письма').fill(emailLink);await page.getByRole('button',{name:'Проверить ссылку'}).click();
 await expect(page.locator('main').getByRole('alert')).toContainText('истекла');await expect(page.getByLabel('Новый пароль',{exact:true})).toHaveCount(0);
});
test('Прямой возврат из письма показывает форму и удаляет токены из адресной строки',async({page})=>{
 await setup(page);
 await page.goto('about:blank');
 await page.goto('/reset-password#access_token='+token()+'&refresh_token=test-refresh-token&expires_in=3600&token_type=bearer&type=recovery');
 await expect(page.getByRole('heading',{name:'Новый пароль',exact:true})).toBeVisible();
 await expect.poll(()=>new URL(page.url()).hash).toBe('');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
