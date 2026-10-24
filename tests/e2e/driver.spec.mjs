import {test,expect} from '@playwright/test';
test('Driver login, private notes, historical fine and mobile layout',async({page},info)=>{
 const requests=[];const vehicle={id:'vehicle',plate:'А123АА 777',odometer_km:150000,next_service_km:150500,next_oil_km:155000,reminder_before_km:1000};
 await page.route('**/api/driver',async route=>{
  const body=route.request().postDataJSON();requests.push(body);let result=null;
  if(body.action==='login')result={token:'a'.repeat(64),must_change_password:true};
  if(body.action==='service')result={driver:{id:'driver',full_name:'Тестовый водитель'},vehicles:[vehicle],partners:[],requests:[]};
  if(body.action==='extras')result={notes:[{id:'note',title:'Доступ к рабочему приложению',has_credentials:true}],shifts:[],shift_files:[],driver_trips:[]};
  if(body.action==='road')result={duties:[],fines:[{id:'fine',vehicle_id:'vehicle',violation_at:'2026-10-23T12:00:00Z',reason:'Превышение скорости',location:'Тестовая улица, 10',amount:500,notice_number:'TEST-NOTICE',assignment:'duty',deducted:0,dispute:''}]};
  if(body.action==='note')result={id:'note',title:'Доступ',login:'test-login',password:'test-private-password',body:'Получите бланки у диспетчера'};
  await route.fulfill({json:result});
 });
 await page.goto('/driver');await page.getByLabel('Логин',{exact:true}).fill('test-driver');await page.getByLabel('Пароль',{exact:true}).fill('temporary-password');await page.getByRole('button',{name:'Войти',exact:true}).click();
 await expect(page.getByRole('heading',{name:'Создайте личный пароль'})).toBeVisible();await page.getByLabel('Новый пароль',{exact:true}).fill('personal-password-123');await page.getByLabel('Повторите пароль').fill('personal-password-123');await page.getByRole('button',{name:'Сохранить пароль'}).click();
 await expect(page.getByText('Тестовый водитель',{exact:true})).toBeVisible();
 await page.getByRole('button',{name:'Заметки',exact:true}).click();await expect(page.getByText('test-private-password',{exact:false})).toHaveCount(0);
 expect(requests.some(r=>r.action==='note')).toBe(false);
 await page.getByRole('button',{name:'Показать данные доступа'}).click();await expect(page.getByText('Пароль: test-private-password')).toBeVisible();await page.getByRole('button',{name:'Скрыть',exact:true}).click();await expect(page.getByText('Пароль: test-private-password')).toHaveCount(0);
 await page.getByRole('button',{name:'Штрафы',exact:true}).click();await expect(page.getByText('Тестовая улица, 10')).toBeVisible();await page.getByLabel('Комментарий / возражение').fill('Прошу проверить постановление');await page.getByRole('button',{name:'Ознакомлен / отправить комментарий'}).click();await expect.poll(()=>requests.find(r=>r.action==='fine_response')?.p_dispute).toBe('Прошу проверить постановление');
 await page.getByRole('button',{name:'Смена',exact:true}).click();await page.getByLabel('Состояние автомобиля').fill('Проверить тормоза');await page.getByLabel('Что требуется для работы').fill('Лента для принтера');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth)).toBe(false);
 await page.screenshot({path:`test-results/driver-${info.project.name}.png`,fullPage:true});
 await page.getByRole('button',{name:'Выйти',exact:true}).click();await expect(page.getByRole('heading',{name:'Вход',exact:true})).toBeVisible();expect(await page.evaluate(()=>localStorage.getItem('respectlogistic-driver-session-v1'))).toBeNull();
});

test('Assigned trip addresses and sequential driver progress',async({page})=>{
 let stage='';let revision=0;const calls=[];
 await page.addInitScript(()=>localStorage.setItem('respectlogistic-driver-session-v1','a'.repeat(64)));
 await page.route('**/api/driver',async route=>{
  const body=route.request().postDataJSON();calls.push(body);let result={};
  if(body.action==='service')result={driver:{id:'driver',full_name:'Водитель рейса'},vehicles:[],partners:[],requests:[]};
  if(body.action==='trip_stage'){stage=body.p_stage;revision++;result=null;}
  if(body.action==='trips')result={driver_trips:[{id:'trip',trip_number:'7',trip_date:'2026-10-24',vehicle_id:'vehicle',plate:'А123АА 777',object:'Стройка',customer:'Заказчик',service_name:'Перевозка',volume:20,unit:'м³',route_km:100,loading_address:'Улица погрузки, 1',unloading_address:'Улица выгрузки, 2',modified_at:'revision-'+revision,stage,status:stage==='completed'?'delivered':stage?'sent':'assigned',documents_confirmed:false}]};
  await route.fulfill({json:result});
 });
 await page.goto('/driver');await expect(page.getByText('Рейс №7 · 2026-10-24')).toBeVisible();await expect(page.getByText('Погрузка: Улица погрузки, 1')).toBeVisible();
 for(const name of ['Принять рейс','На погрузке','Погружен · выехал','На выгрузке','Завершить рейс'])await page.getByRole('button',{name,exact:true}).click();
 await expect(page.getByText('Отправьте накладные и талоны через отчёт смены. Комплект проверяет диспетчер.')).toBeVisible();expect(calls.filter(c=>c.action==='trip_stage').map(c=>c.p_stage)).toEqual(['accepted','loading','on_route','unloading','completed']);expect(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth)).toBe(false);
});
