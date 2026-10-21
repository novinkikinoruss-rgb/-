import {test,expect} from '@playwright/test';
test.afterEach(async({page},info)=>{if(info.status!==info.expectedStatus)console.log('CRM_FAILED_PAGE_TEXT: '+(await page.locator('body').innerText()).slice(0,9000))});
const today=new Date().toISOString().slice(0,10),start=today.slice(0,7)+'-01';
const previous=new Date(new Date(start).getTime()-86400000).toISOString().slice(0,10);
async function setup(page,{billed=false,oldInvoice=false}={}){
 page.on('pageerror',error=>console.log('CRM_BROWSER_ERROR: '+error.message));
 const tables={
  crm_customers:[{id:'customer',name:'Тестовый заказчик',inn:'1234567890',kpp:'123456789',legal_address:'Адрес заказчика'}],
  crm_sites:[{id:'site',customer_id:'customer',contract_id:'contract',specification_id:'spec',name:'Тестовый объект',loading_address:'Погрузка',unloading_address:'Разгрузка',route_km:100}],
  crm_contracts:[{id:'contract',customer_id:'customer',contract_number:'Д-1',contract_type:'transport'}],
  crm_specifications:[{id:'spec',contract_id:'contract',specification_number:'СП-1',service_name:'Перевозка',rate:1200,unit:'м³'}],
  crm_drivers:[{id:'driver',full_name:'Тестовый водитель',bonus_pct:10,tax_pct:30,pay_rate_km:70}],
  crm_vehicles:[{id:'vehicle',plate:'А001АА',brand:'КАМАЗ'}],crm_orders:[],crm_tasks:[],
  crm_trips:[{id:'trip',customer_id:'customer',order_id:null,site_id:'site',contract_id:'contract',specification_id:'spec',driver_id:'driver',vehicle_id:'vehicle',trip_number:'Р-1',trip_date:today,status:'delivered',service_name:'Перевозка',volume:2.5,unit_price:1200}],
  crm_invoices:[],crm_invoice_lines:[],crm_accounting_documents:[],crm_accounting_document_trips:[],crm_invoice_payments:[],
  crm_payroll_accruals:[{id:'accrual',driver_id:'driver',trip_id:'trip',customer_id:'customer',site_id:'site',accrual_date:today,distance_km:100,base:7000,bonus:700,tax:2310,active:true}],
  crm_payroll_payments:[{id:'salary',accrual_id:'accrual',kind:'salary',amount:3000,payment_date:today}],
  crm_payroll_deductions:[],crm_driver_fines:[{id:'fine',driver_id:'driver',order_id:null,fine_date:today,amount:500,reason:'Тестовый штраф',paid:false}]
 };
 function invoice(number,date= today){
  tables.crm_invoices=[{id:'invoice',customer_id:'customer',invoice_number:number,invoice_date:date,amount:3000,trip_id:null}];
  tables.crm_invoice_lines=[{id:'line',invoice_id:'invoice',trip_id:'trip',site_id:'site',trip_number:'Р-1',trip_date:today,service_name:'Перевозка',volume:2.5,unit_price:1200,amount:3000}];
  tables.crm_accounting_documents=[{id:'register',invoice_id:'invoice',customer_id:'customer',kind:'register',document_number:'РЕЕСТР-'+number,document_date:date,amount:3000}];
  tables.crm_accounting_document_trips=[{id:'register-link',document_id:'register',trip_id:'trip'}];
 }
 if(billed||oldInvoice)invoice('СЧ-ТЕСТ',oldInvoice?previous:today);
 if(oldInvoice)tables.crm_invoice_payments=[{id:'payment',invoice_id:'invoice',payment_date:today,amount:300}];
 const calls=[];
 await page.route('**/supabase/**',async route=>{
  const req=route.request(),url=new URL(req.url()),path=url.pathname;
  let response;
  if(path.includes('/auth/v1/token')){
   const jwt=Buffer.from(JSON.stringify({alg:'none'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:'user',aud:'authenticated',exp:Math.floor(Date.now()/1000)+3600})).toString('base64url')+'.test';
   response={access_token:jwt,refresh_token:'test-refresh-token',token_type:'bearer',expires_in:3600,user:{id:'user',email:'test@example.invalid',aud:'authenticated',role:'authenticated'}};
  }else if(path.includes('/rpc/')){
   const rpc=path.split('/').pop(),body=req.postDataJSON();calls.push({rpc,body});
   if(rpc==='crm_create_invoice_from_trips'){invoice(body.p_number,body.p_date);response='invoice'}
   else if(rpc==='crm_create_upd_from_invoice'){
    tables.crm_accounting_documents.push({id:'upd',invoice_id:'invoice',customer_id:'customer',kind:'upd',document_number:body.p_number,document_date:body.p_date,amount:3000});tables.crm_accounting_document_trips.push({id:'upd-link',document_id:'upd',trip_id:'trip'});response='upd';
   }else if(rpc==='crm_apply_driver_fines'){tables.crm_payroll_deductions.push({id:'deduction',accrual_id:'accrual',fine_id:'fine',amount:500,deduction_date:today});response=500}
   else response=null;
  }else if(path.includes('/rest/v1/')){
   const name=path.split('/').pop();response=tables[name]??[];
   if(url.searchParams.get('deleted_at')==='not.is.null')response=[];
  }else response={};
  await route.fulfill({status:200,contentType:'application/json',headers:{'content-range':'0-0/1'},body:JSON.stringify(response)});
 });
 await page.goto('/');
 await page.getByLabel('Email',{exact:true}).fill('test@example.invalid');
 await page.getByLabel('Пароль',{exact:true}).fill('test-password');
 await page.getByRole('button',{name:'Войти',exact:true}).click();
 await page.getByRole('button',{name:'Бухгалтерия',exact:true}).click();
 await page.getByLabel('Заказчик',{exact:true}).selectOption('customer');
 await page.getByLabel('Объект',{exact:true}).selectOption('site');
 return {tables,calls};
}
test('Счёт заполняется по рейсу и отображается вместе с реестром в рейсах',async({page})=>{
 const {calls}=await setup(page);
 await page.getByText('Реквизиты исполнителя',{exact:true}).click();
 await page.getByLabel('Название',{exact:true}).fill('Тестовый исполнитель');
 await page.getByLabel('ИНН',{exact:true}).fill('1234567890');
 await page.getByRole('button',{name:'+ Счёт',exact:true}).click();
 await expect(page.getByRole('cell',{name:'Перевозка',exact:true})).toBeVisible();
 await expect(page.getByRole('cell',{name:'2.5',exact:true})).toBeVisible();
 await page.getByLabel('Номер счёта',{exact:true}).fill('СЧ-НОВЫЙ');
 await page.getByRole('button',{name:'Сохранить счёт и реестр',exact:true}).click();
 await expect(page.getByRole('status').filter({hasText:'Счёт и реестр сохранены'})).toContainText('Счёт и реестр сохранены');
 expect(calls.find(c=>c.rpc==='crm_create_invoice_from_trips').body.p_trip_ids).toEqual(['trip']);
 await page.getByRole('button',{name:'Рейсы',exact:true}).click();
 await expect(page.getByText('Счёт СЧ-НОВЫЙ',{exact:true})).toBeVisible();
 await expect(page.getByText('Реестр РЕЕСТР-СЧ-НОВЫЙ',{exact:false})).toBeVisible();
});
test('УПД берёт строки выбранного счёта и появляется у его рейсов',async({page})=>{
 const {calls}=await setup(page,{billed:true});
 await page.getByRole('button',{name:'УПД',exact:true}).click();
 await page.getByLabel('Счёт',{exact:true}).selectOption('invoice');
 await expect(page.getByRole('cell',{name:'Перевозка',exact:true})).toBeVisible();
 await page.getByLabel('Номер УПД',{exact:true}).fill('УПД-ТЕСТ');
 await page.getByRole('button',{name:'Сформировать УПД по счёту',exact:true}).click();
 await expect(page.getByRole('status').filter({hasText:'УПД сохранён'})).toContainText('УПД сохранён');
 expect(calls.find(c=>c.rpc==='crm_create_upd_from_invoice').body.p_invoice_id).toBe('invoice');
 await page.getByRole('button',{name:'Рейсы',exact:true}).click();
 await expect(page.getByText('УПД УПД-ТЕСТ',{exact:false})).toBeVisible();
});
test('Акт сверки учитывает оплату старого счёта в текущем периоде',async({page})=>{
 await setup(page,{oldInvoice:true});
 await page.getByRole('button',{name:'Акт сверки',exact:true}).click();
 await expect(page.getByRole('cell',{name:'Оплата счёта № СЧ-ТЕСТ',exact:true})).toBeVisible();
 await expect(page.getByRole('button',{name:'Сформировать / PDF',exact:true})).toBeEnabled();
});
test('Штраф уменьшает оставшуюся зарплату и исчезает из доступных удержаний',async({page})=>{
 await setup(page);
 await page.getByRole('button',{name:'Зарплата',exact:true}).click();
 await page.getByLabel('Водитель',{exact:true}).selectOption('driver');
 await expect(page.getByRole('button',{name:'Учесть штрафы в зарплате',exact:true})).toBeVisible();
 await page.getByRole('button',{name:'Учесть штрафы в зарплате',exact:true}).click();
 await expect(page.getByRole('status').filter({hasText:'Удержания штрафов сохранены'})).toContainText('Удержания штрафов сохранены');
 await expect(page.getByRole('button',{name:'Учесть штрафы в зарплате',exact:true})).toHaveCount(0);
});
