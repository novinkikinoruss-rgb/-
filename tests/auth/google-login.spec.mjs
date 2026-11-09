import {test,expect} from '@playwright/test';
const uid='00000000-0000-4000-8000-000000000099';
const user={id:uid,aud:'authenticated',role:'authenticated',email:'test@example.invalid',app_metadata:{provider:'google',providers:['email','google']},user_metadata:{},created_at:'2026-01-01T00:00:00Z',identities:[]};
const token=()=>Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:uid,exp:Math.floor(Date.now()/1000)+3600,aud:'authenticated',role:'authenticated'})).toString('base64url')+'.'+Buffer.alloc(32).toString('base64url');
async function setup(page,enabled=false){
 await page.route('**/supabase/**',async route=>{
  const path=new URL(route.request().url()).pathname;
  if(path.endsWith('/settings'))return route.fulfill({json:{external:{google:enabled}}});
  if(path.endsWith('/user'))return route.fulfill({json:user});
  if(path.endsWith('/respectlogistic_read_workspace'))return route.fulfill({json:{revision:0,customers:[],contracts:[],specifications:[],sites:[],documents:[],activity:[]}});
  return route.fulfill({json:{}});
 });
 await page.goto('/');
}
test('Отключённый Google объясняет настройку, не открывает CRM и сохраняет вход по паролю',async({page})=>{
 await setup(page);await page.getByRole('button',{name:'Войти через Google',exact:true}).click();
 await expect(page.locator('.auth-card').getByRole('alert')).toContainText('ещё не подключён');
 await expect(page.getByRole('heading',{name:'Вход в рабочее пространство'})).toBeVisible();
 await expect(page.getByLabel('Пароль',{exact:true})).toBeVisible();
 expect(new URL(page.url()).pathname).toBe('/');
});
test('Google переходит к фиксированному Supabase authorize с возвратом на CRM, без API-прокси',async({page,baseURL})=>{
 let destination;
 await page.route('https://*.supabase.co/auth/v1/authorize?**',route=>{destination=new URL(route.request().url());return route.fulfill({contentType:'text/html',body:'<h1>Google sign-in fixture</h1>'});});
 await setup(page,true);await page.getByRole('button',{name:'Войти через Google',exact:true}).click();
 await expect(page.getByRole('heading',{name:'Google sign-in fixture'})).toBeVisible();
 expect(destination.origin).toBe('https://yoqejkedmksmvbqagqru.supabase.co');expect(destination.pathname).toBe('/auth/v1/authorize');
 expect(destination.searchParams.get('provider')).toBe('google');expect(destination.searchParams.get('prompt')).toBe('select_account');
 expect(destination.searchParams.get('redirect_to')).toBe(new URL('/',baseURL).href);
});
test('Возврат Google открывает существующую учётную запись; отказ показывает ошибку без токенов в URL',async({page})=>{
 await setup(page);await page.goto('about:blank');
 await page.goto('/#access_token='+token()+'&refresh_token=synthetic-google-refresh&expires_in=3600&token_type=bearer');
 await expect(page.getByRole('heading',{name:'Обзор',level:1,exact:true})).toBeVisible();
 await expect.poll(()=>new URL(page.url()).hash).toBe('');
 await page.evaluate(()=>localStorage.clear());await page.goto('about:blank');await page.goto('/#error=access_denied&error_description=synthetic');
 await expect(page.locator('.auth-card').getByRole('alert')).toContainText('Не удалось завершить вход');
 await expect.poll(()=>new URL(page.url()).hash).toBe('');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
