import {test,expect} from '@playwright/test';
const first='00000000-0000-4000-8000-000000000099',second='00000000-0000-4000-8000-000000000098';
function identity(id){return {id,aud:'authenticated',role:'authenticated',email:(id===first?'first':'second')+'@example.invalid',app_metadata:{},user_metadata:{},created_at:'2026-01-01T00:00:00Z'};}
function jwt(user){return Buffer.from('{"alg":"HS256"}').toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:user.id,exp:Math.floor(Date.now()/1000)+3600})).toString('base64url')+'.synthetic';}
async function install(page,store,id=first){
 const user=identity(id),day=new Date().toLocaleDateString('en-CA',{timeZone:'Europe/Moscow'});
 const customer={id:'c',name:'ООО «Строительные материалы и транспортные перевозки»'},site={id:'s',customerId:'c',name:'Строительство логистического комплекса'};
 const trips=Array.from({length:300},(_,i)=>({id:'t'+i,trip_number:String(i+1),trip_date:day,customer_id:'c',site_id:'s',vehicle_id:'v',driver_id:'d',carrier_id:null,volume:12.5,unit:'м³',unit_price:1200,service_name:'Перевозка строительных материалов',status:'sent',modified_at:'v1',locked:false,documents_confirmed:false,loading_address:'Московская область, городской округ Домодедово, промышленная зона Северная, участок погрузки 14',unloading_address:'Москва, строительная площадка логистического комплекса, разгрузочная зона 7'}));
 const workspace={revision:0,customers:[customer],contracts:[],specifications:[],sites:[site],documents:[],activity:[]};
 const data={trips,customers:[customer],sites:[{id:'s',customer_id:'c',name:site.name}],vehicles:[{id:'v',plate:'А123ВС77',carrier_id:null,is_subcontractor_vehicle:false}],drivers:[{id:'d',full_name:'Александр Александрович Александров',carrier_id:null}],carriers:[],accounting_documents:[],request_links:[]};
 await page.route('**/api/google-sync',route=>route.fulfill({json:{configured:false,hasClient:false}}));
 await page.route('**/supabase/**',async route=>{
  const request=route.request(),path=new URL(request.url()).pathname,body=request.postDataJSON();let result={};
  if(path.endsWith('/token'))result={access_token:jwt(user),refresh_token:'synthetic-refresh',expires_in:3600,token_type:'bearer',user};
  if(path.endsWith('/user'))result=user;
  if(path.endsWith('/respectlogistic_read_ui_settings')){if(store.failRead)return route.fulfill({status:503,json:{message:'Fixture offline'}});result=store.values[id]||{};}
  if(path.endsWith('/respectlogistic_save_ui_setting')){
   store.calls.push(body);if(store.failSave)return route.fulfill({status:503,json:{message:'Fixture offline'}});
   expect(body.p_owner).toBe(id);store.values[id]={...(store.values[id]||{}),[body.p_key]:body.p_value};result=null;
  }
  if(path.endsWith('/respectlogistic_read_workspace'))result=workspace;
  if(path.endsWith('/crm_read_trip_workspace'))result=data;
  if(path.endsWith('/crm_trip_files')||path.endsWith('/crm_drive_exports')||path.endsWith('/respectlogistic_read_trip_progress'))result=[];
  if(path.endsWith('/respectlogistic_driver_extras'))result={notes:[],shifts:[],shift_files:[]};
  await route.fulfill({json:result});
 });
 await page.goto('/?workspace=trips');await page.getByLabel('Email',{exact:true}).fill(user.email);await page.getByLabel('Пароль',{exact:true}).fill('synthetic-password');await page.getByRole('button',{name:'Войти',exact:true}).click();
 const pageSize=store.values[id]?.trips?.pageSize||25;await expect(page.getByLabel('Рейсов на странице')).toHaveValue(String(pageSize));await expect(page.locator('.compact-trip-grid tbody>tr:not([hidden])')).toHaveCount(pageSize);
}
const state=()=>({values:{},calls:[],failSave:false,failRead:false});
async function customers(page){const menu=page.getByRole('button',{name:'Открыть меню',exact:true});if(await menu.isVisible())await menu.click();await page.locator('.sidebar .nav-item').filter({hasText:'Заказчики'}).click();await expect(page.getByRole('heading',{name:/^Заказчики/,level:1})).toBeVisible();}
test('300 рейсов: верхний фильтр, читаемые строки, пагинация, закреплённые номера и заголовки',async({page},info)=>{
 const store=state();await install(page,store);await expect(page.getByLabel('Плотность строк')).toBeEnabled();
 if(!info.project.use.isMobile){await page.getByRole('button',{name:'Прокрутить меню вправо'}).click();await expect.poll(()=>page.locator('.sidebar nav').evaluate(el=>el.scrollLeft)).toBeGreaterThan(0);await page.getByRole('button',{name:'Прокрутить меню влево'}).click();await expect.poll(()=>page.locator('.sidebar nav').evaluate(el=>el.scrollLeft)).toBe(0);}
 await page.getByLabel('Рейсов на странице').selectOption('100');await expect(page.locator('.compact-trip-grid tbody>tr:not([hidden])')).toHaveCount(100);
 await page.getByLabel('Перенос текста',{exact:true}).uncheck();
 const row=page.locator('.compact-trip-grid tbody>tr:not([hidden])').first();const compact=(await row.boundingBox()).height;
 await page.getByLabel('Плотность строк').selectOption('comfortable');await expect.poll(async()=>(await row.boundingBox()).height).toBeGreaterThan(compact+8);
 await page.getByLabel('Плотность строк').selectOption('compact');
 const filter=await page.locator('.record-filter').boundingBox(),main=await page.locator('.record-main').boundingBox();
 expect(filter.y+filter.height).toBeLessThanOrEqual(main.y+1);expect(Math.abs(filter.x-main.x)).toBeLessThan(2);expect(Math.abs(filter.width-main.width)).toBeLessThan(2);
 const sheet=page.locator('.trip-sheet');await sheet.scrollIntoViewIfNeeded();const number=page.locator('thead .trip-sticky-number');const before=await number.boundingBox();
 await sheet.evaluate(el=>{el.scrollLeft=500;el.scrollTop=500;});await expect.poll(()=>sheet.evaluate(el=>el.scrollTop)).toBeGreaterThan(0);
 const after=await number.boundingBox();expect(Math.abs(before.x-after.x)).toBeLessThan(2);expect(Math.abs(before.y-after.y)).toBeLessThan(2);
 await sheet.evaluate(el=>{el.scrollLeft=0;el.scrollTop=0;});await page.getByRole('button',{name:'Далее',exact:true}).click();await expect(page.getByRole('checkbox',{name:'Выбрать рейс 101',exact:true})).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.evaluate(()=>window.scrollTo(0,0));await expect.poll(()=>page.evaluate(()=>scrollY)).toBe(0);
 await page.screenshot({path:'test-results/operations-300-trips-'+info.project.name+'.png',fullPage:true});
});
test('Настройки БД доступны в чистом браузере того же пользователя и изолированы от другого',async({page,browser})=>{
 const store=state();await install(page,store);await expect(page.getByLabel('Плотность строк')).toBeEnabled();
 await page.getByLabel('Плотность строк').selectOption('comfortable');await page.getByLabel('Перенос текста',{exact:true}).uncheck();await page.getByLabel('Рейсов на странице').selectOption('100');
 const separator=page.getByRole('separator',{name:'Ширина столбца «Дата»'}),initial=Number(await separator.getAttribute('aria-valuenow'));await separator.focus();await separator.press('ArrowRight');await separator.press('ArrowRight');
 await page.locator('.trip-columns-control summary').click();await page.getByRole('button',{name:'Правее: Дата',exact:true}).click();await page.locator('.trip-columns-control summary').click();
 await expect.poll(()=>store.values[first]?.trips?.widths?.date).toBe(initial+20);await expect.poll(()=>store.values[first]?.tables?.density).toBe('comfortable');
 await customers(page);await page.getByRole('button',{name:'Список',exact:true}).click();await expect.poll(()=>store.values[first]?.tables?.customerMode).toBe('list');
 const context=await browser.newContext({viewport:page.viewportSize()});const fresh=await context.newPage();await install(fresh,store);
 await expect(fresh.getByLabel('Плотность строк')).toHaveValue('comfortable');await expect(fresh.getByLabel('Перенос текста',{exact:true})).not.toBeChecked();await expect(fresh.getByLabel('Рейсов на странице')).toHaveValue('100');
 await expect(fresh.getByRole('separator',{name:'Ширина столбца «Дата»'})).toHaveAttribute('aria-valuenow',String(initial+20));
 const columns=await fresh.locator('thead th[data-column]').evaluateAll(nodes=>nodes.map(n=>n.dataset.column));expect(columns.indexOf('date')).toBeGreaterThan(columns.indexOf('loading'));
 await customers(fresh);await expect(fresh.locator('.view-switch button.selected')).toHaveText('Список');
 expect(await fresh.evaluate(()=>Object.keys(localStorage).filter(k=>/columns|table-view|ui-settings/.test(k)))).toEqual([]);
 const otherContext=await browser.newContext({viewport:page.viewportSize()});const other=await otherContext.newPage();await install(other,store,second);
 await expect(other.getByLabel('Плотность строк')).toHaveValue('compact');await expect(other.getByLabel('Рейсов на странице')).toHaveValue('25');
 await otherContext.close();await context.close();
});
test('Ошибка сохранения настроек видна; повтор записывает в БД без браузерного кеша',async({page})=>{
 const store=state();await install(page,store);await expect(page.getByLabel('Плотность строк')).toBeEnabled();store.failSave=true;
 await page.getByLabel('Плотность строк').selectOption('comfortable');await expect(page.locator('.crm-settings-state.error')).toContainText('не сохранены в базе');expect(store.values[first]).toBeUndefined();
 store.failSave=false;await page.locator('.crm-settings-state').getByRole('button',{name:'Повторить',exact:true}).click();await expect.poll(()=>store.values[first]?.tables?.density).toBe('comfortable');await expect(page.locator('.crm-settings-state')).toHaveText('Настройки в БД');
});
test('Недоступная БД не подменяется настройками браузера и не перезаписывается значениями по умолчанию',async({page})=>{
 const store=state();store.values[first]={tables:{density:'comfortable',wrap:false}};store.failRead=true;
 await page.addInitScript(()=>localStorage.setItem('respectlogistic-trip-columns-v1',JSON.stringify({order:['number','date'],widths:{date:600}})));
 await install(page,store);await expect(page.locator('.crm-settings-state.error')).toContainText('Не удалось загрузить');await expect(page.getByLabel('Плотность строк')).toBeDisabled();expect(store.calls).toHaveLength(0);
 store.failRead=false;await page.locator('.crm-settings-state').getByRole('button',{name:'Повторить',exact:true}).click();await expect(page.getByLabel('Плотность строк')).toHaveValue('comfortable');await expect(page.getByLabel('Плотность строк')).toBeEnabled();
 expect(store.calls).toHaveLength(0);expect(store.values[first].tables).toEqual({density:'comfortable',wrap:false});
});
