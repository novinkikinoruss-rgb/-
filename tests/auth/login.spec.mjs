import {test,expect} from '@playwright/test';
const uid='00000000-0000-4000-8000-000000000099';
const user={id:uid,aud:'authenticated',role:'authenticated',email:'test@example.invalid',app_metadata:{provider:'email',providers:['email']},user_metadata:{},created_at:'2026-01-01T00:00:00Z',identities:[]};
const token=()=>Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:uid,exp:Math.floor(Date.now()/1000)+3600,aud:'authenticated',role:'authenticated'})).toString('base64url')+'.'+Buffer.alloc(32).toString('base64url');
const workspace={revision:0,customers:[],contracts:[],specifications:[],sites:[],documents:[],activity:[]};
async function setup(page,invalid=false){
 const external=[];
 await page.route('https://*.supabase.co/**',route=>{external.push(route.request().url());return route.abort();});
 await page.route('**/supabase/**',async route=>{
  const path=new URL(route.request().url()).pathname;
  if(path.endsWith('/token'))return route.fulfill({status:invalid?400:200,json:invalid?{error:'invalid_grant',code:'invalid_credentials',error_description:'Invalid login credentials'}:{access_token:token(),refresh_token:'test-refresh-token',expires_in:3600,token_type:'bearer',user}});
  if(path.endsWith('/user'))return route.fulfill({json:user});
  if(path.endsWith('/respectlogistic_read_workspace'))return route.fulfill({json:workspace});
  if(path.endsWith('/logout'))return route.fulfill({status:204});
  return route.fulfill({json:{}});
 });
 await page.goto('/');await expect(page.getByRole('heading',{name:'Вход в рабочее пространство'})).toBeVisible();
 return external;
}
async function openCustomers(page){await expect(page.getByRole('heading',{name:'Обзор',level:1,exact:true})).toBeVisible();const menu=page.getByRole('button',{name:'Открыть меню',exact:true});if(await menu.isVisible())await menu.click();await page.locator('.sidebar .nav-item').filter({hasText:'Заказчики'}).click();}
async function fill(page){await page.getByLabel('Email',{exact:true}).fill('test@example.invalid');await page.getByLabel('Пароль',{exact:true}).fill('test-only-password');}
test('Вход завершается открытием CRM, запросы идут через свой сайт',async({page})=>{
 const external=await setup(page);await fill(page);await page.getByRole('button',{name:'Войти',exact:true}).click();
 await openCustomers(page);await expect(page.getByRole('heading',{name:/^Заказчики/,level:1})).toBeVisible();await expect(page.getByText('Добавьте первого заказчика',{exact:true})).toBeVisible();expect(external).toEqual([]);
 await page.reload();await openCustomers(page);await expect(page.getByRole('heading',{name:/^Заказчики/,level:1})).toBeVisible();
});
test('Неверный пароль показывает ошибку и возвращает кнопку входа',async({page})=>{
 await setup(page,true);await fill(page);await page.getByRole('button',{name:'Войти',exact:true}).click();
 await expect(page.locator('.auth-card').getByRole('alert')).toHaveText('Неверный email или пароль.');await expect(page.getByRole('button',{name:'Войти',exact:true})).toBeEnabled();
});
test('Зависший запрос прерывается и можно сразу войти повторно',async({page})=>{
 await page.addInitScript(()=>{
  window.__hangLogin=true;const original=window.fetch.bind(window);
  window.fetch=(input,init)=>{
   if(window.__hangLogin&&String(input).includes('/auth/v1/token'))return new Promise((_,reject)=>{if(init?.signal?.aborted)reject(new DOMException('Aborted','AbortError'));else init?.signal?.addEventListener('abort',()=>reject(new DOMException('Aborted','AbortError')),{once:true});});
   return original(input,init);
  };
 });
 await setup(page);await fill(page);await page.getByRole('button',{name:'Войти',exact:true}).click();
 await expect(page.locator('.auth-card').getByRole('alert')).toContainText('не ответил вовремя',{timeout:28000});await expect(page.getByRole('button',{name:'Войти',exact:true})).toBeEnabled();
 await page.evaluate(()=>window.__hangLogin=false);await page.getByRole('button',{name:'Войти',exact:true}).click();await openCustomers(page);await expect(page.getByRole('heading',{name:/^Заказчики/,level:1})).toBeVisible();
});
test('Зависшая загрузка карточек показывает ошибку и допускает повтор',async({page})=>{
 await page.addInitScript(()=>{
  window.__hangCards=true;const original=window.fetch.bind(window);
  window.fetch=(input,init)=>{
   if(window.__hangCards&&String(input).includes('/respectlogistic_read_workspace'))return new Promise((_,reject)=>{if(init?.signal?.aborted)reject(new DOMException('Aborted','AbortError'));else init?.signal?.addEventListener('abort',()=>reject(new DOMException('Aborted','AbortError')),{once:true});});
   return original(input,init);
  };
 });
 await setup(page);await fill(page);await page.getByRole('button',{name:'Войти',exact:true}).click();
 await openCustomers(page);await expect(page.getByRole('heading',{name:'Данные не загружены',exact:true})).toBeVisible({timeout:28000});
 await page.evaluate(()=>window.__hangCards=false);await page.getByRole('button',{name:'Повторить загрузку',exact:true}).click();await expect(page.getByText('Добавьте первого заказчика',{exact:true})).toBeVisible();
});
