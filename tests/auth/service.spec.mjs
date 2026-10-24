import {test,expect} from '@playwright/test';
test('CRM service forms, driver access, private notes and fine attribution',async({page},info)=>{
 const uid='00000000-0000-4000-8000-000000000099';
 const user={id:uid,aud:'authenticated',role:'authenticated',email:'test@example.invalid',app_metadata:{},user_metadata:{},created_at:'2026-01-01T00:00:00Z'};
 const token=Buffer.from('{"alg":"HS256"}').toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:uid,exp:Math.floor(Date.now()/1000)+3600})).toString('base64url')+'.test';
 const workspace={revision:0,customers:[],contracts:[],specifications:[],sites:[],documents:[],activity:[]};
 const service={drivers:[{id:'00000000-0000-4000-8000-000000000001',full_name:'Водитель с длинным полным именем'}],vehicles:[{id:'00000000-0000-4000-8000-000000000002',plate:'А123АА 777'}],partners:[],requests:[],accounts:[]};const mutations=[];
 await page.route('**/supabase/**',async route=>{
  const path=new URL(route.request().url()).pathname;let result={};
  if(path.endsWith('/token'))result={access_token:token,refresh_token:'test-refresh',expires_in:3600,token_type:'bearer',user};
  if(path.endsWith('/user'))result=user;
  if(path.endsWith('/respectlogistic_read_workspace'))result=workspace;
  if(path.endsWith('/respectlogistic_read_service'))result=service;
  if(path.endsWith('/respectlogistic_driver_extras'))result={notes:[],shifts:[],shift_files:[]};
  if(path.endsWith('/respectlogistic_driver_road_data'))result={duties:[],fines:[]};
  if(/save_service_partner|driver_access|save_driver_note|save_road_fine/.test(path)){const body=route.request().postDataJSON();mutations.push({path,body});if(path.endsWith('/respectlogistic_save_service_partner'))service.partners.push({...body.p_record,modified_at:'2026-10-24T00:00:00Z'});result=null;}
  await route.fulfill({json:result});
 });
 await page.goto('/');await page.getByLabel('Email',{exact:true}).fill('test@example.invalid');await page.getByLabel('Пароль',{exact:true}).fill('test-password');await page.getByRole('button',{name:'Войти',exact:true}).click();
 const menu=page.getByRole('button',{name:'Открыть меню',exact:true});if(await menu.isVisible())await menu.click();await page.locator('.sidebar .nav-item').filter({hasText:'Сервис и водители'}).click();
 await expect(page.getByRole('heading',{name:'Сервис и кабинет водителя'})).toBeVisible();await page.getByRole('button',{name:'Договорные сервисы',exact:true}).click();await page.getByRole('button',{name:'Добавить сервис',exact:true}).click();const dialog=page.getByRole('dialog');
 await dialog.getByLabel('Название',{exact:true}).fill('Сервис с длинным названием для проверки переноса строк');await dialog.getByLabel('Адрес',{exact:true}).fill('Москва, улица Тестовая, дом 1');await dialog.getByLabel('Телефон',{exact:true}).fill('+79990000000');await dialog.getByLabel('График работы',{exact:true}).fill('Пн–Сб 09:00–18:00');await dialog.getByLabel('Номер договора',{exact:true}).fill('С-01');await dialog.getByRole('button',{name:'Сохранить',exact:true}).click();await expect(dialog).not.toBeVisible();
 expect(mutations[0].body.p_record.work_kinds).toEqual(['service','oil','repair','tyres']);await expect(page.getByText('Сервис с длинным названием для проверки переноса строк',{exact:true})).toBeVisible();
 await page.getByRole('button',{name:'Доступ водителей',exact:true}).click();await page.getByRole('button',{name:'Создать / сбросить доступ',exact:true}).click();await dialog.getByLabel('Водитель',{exact:true}).selectOption(service.drivers[0].id);await dialog.getByLabel('Логин (латиница, цифры, от 3 символов)').fill('driver-test');await dialog.getByLabel('Временный пароль (от 12 символов)').fill('temporary-password');await dialog.getByRole('button',{name:'Сохранить',exact:true}).click();await expect(dialog).not.toBeVisible();expect(mutations.at(-1).body.p_action).toBe('password');
 await page.getByRole('button',{name:'Заметки',exact:true}).click();await page.getByRole('button',{name:'Добавить личную заметку'}).click();await dialog.getByLabel('Водитель',{exact:true}).selectOption(service.drivers[0].id);await dialog.getByLabel('Название приложения / заметки').fill('Платон');await dialog.getByLabel('Текст заметки').fill('Забрать бланки');await dialog.getByLabel('Пароль',{exact:true}).fill('private-test');await dialog.getByRole('button',{name:'Сохранить',exact:true}).click();await expect(dialog).not.toBeVisible();expect(mutations.at(-1).body.p_record.password).toBe('private-test');
 await page.getByRole('button',{name:'Штрафы',exact:true}).click();await page.getByRole('button',{name:'Внести постановление'}).click();await dialog.getByLabel('Машина',{exact:true}).selectOption(service.vehicles[0].id);await dialog.getByLabel('Номер постановления').fill('TEST-NOTICE');await dialog.getByLabel('Дата и время нарушения (часовой пояс устройства)').fill('2026-10-23T12:30');await dialog.getByLabel('Место нарушения').fill('Тестовая улица');await dialog.getByLabel('Причина',{exact:true}).fill('Превышение скорости');await dialog.getByLabel('Сумма штрафа, ₽').fill('500');await dialog.getByRole('button',{name:'Сохранить',exact:true}).click();await expect(dialog).not.toBeVisible();expect(mutations.at(-1).body.p_record.driver_id).toBeUndefined();expect(mutations.at(-1).body.p_record.violation_at).toMatch(/T.*Z$/);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth)).toBe(false);await page.getByRole('button',{name:'Договорные сервисы',exact:true}).click();await page.screenshot({path:`test-results/service-${info.project.name}.png`,fullPage:true});
});
