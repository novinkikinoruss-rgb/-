// UI tests use controlled RPC responses. Database rules are covered separately by accounting.integration.sql.
import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,readFile} from 'node:fs/promises';
const base=process.env.CRM_BROWSER_URL||'http://127.0.0.1:3100';
const out=process.env.CRM_BROWSER_ARTIFACTS||'/workspace/artifacts/accounting-browser';await mkdir(out,{recursive:true});
const proxyServer=base.startsWith('https://')?(process.env.HTTPS_PROXY||process.env.HTTP_PROXY):undefined;
const browser=await chromium.launch({headless:true,args:['--no-sandbox'],...(proxyServer?{proxy:{server:proxyServer}}:{})});
try{for(const mobile of [false,true]){
 const context=await browser.newContext({viewport:mobile?{width:390,height:844}:{width:1440,height:1100},isMobile:mobile,hasTouch:mobile});
 const user={id:'11111111-1111-4111-8111-111111111111',email:'qa@example.invalid',aud:'authenticated',role:'authenticated'};
 const token=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:user.id,exp:2000000000,role:'authenticated'})).toString('base64url')+'.test';
 await context.addInitScript(({token,user})=>localStorage.setItem('respectlogistic-auth-v1',JSON.stringify({access_token:token,refresh_token:'qa-refresh',expires_at:2000000000,expires_in:3600,token_type:'bearer',user})),{token,user});
 const t={id:'trip',trip_number:'17',trip_date:'2026-10-10',customer_id:'customer',site_id:'site',vehicle_id:'vehicle',driver_id:'driver',carrier_id:null,loading_address:'Карьер',unloading_address:'Площадка',volume:10,unit:'м³',unit_price:122,service_name:'Вывоз',status:'sent',modified_at:'v1',locked:false,documents_confirmed:false};
 const workspace={trips:[t],customers:[{id:'customer',name:'ООО «Очень длинное название заказчика для проверки переноса текста»'}],sites:[{id:'site',customer_id:'customer',name:'Строительство производственного комплекса — северная площадка',service_name:'Вывоз',route_km:120}],vehicles:[{id:'vehicle',plate:'А123ВС77',carrier_id:null,is_subcontractor_vehicle:false,archived_at:null}],drivers:[{id:'driver',full_name:'Тестовый водитель'}],carriers:[],company:{name:'Тестовая компания',inn:'7707083893',legalAddress:'Тестовый адрес',bank:'Тестовый банк',bik:'044525225',account:'40702810000000000000'},documents:[],links:[],credits:[],history:[]};
 let revision=1;
 await context.route('**/supabase/**',async route=>{
  const path=new URL(route.request().url()).pathname;const body=route.request().postDataJSON();let result=[];
  if(path.includes('/auth/'))result=path.endsWith('/user')?user:{access_token:token,refresh_token:'qa-refresh',user};
  else if(path.endsWith('/respectlogistic_read_workspace'))result={revision:0,customers:[],contracts:[],specifications:[],sites:[],documents:[],activity:[]};
  else if(path.endsWith('/respectlogistic_read_accounting'))result=workspace;
  else if(path.endsWith('/respectlogistic_read_profit'))result={...workspace,expenses:[],invoices:[],accruals:[],payments:[],deductions:[],settings:{vat_rate:22,prices_include_vat:true}};
  else if(path.endsWith('/crm_read_trip_workspace'))result={...workspace,accounting_documents:workspace.documents.filter(d=>!['draft','cancelled'].includes(d.status)).map(d=>({...d,trip_ids:workspace.links.filter(l=>l.document_id===d.id&&l.active).map(l=>l.trip_id)}))};
  else if(path.endsWith('/respectlogistic_create_accounting_document')){
   const r=body.p_record,items=r.kind==='advance'?[{service:r.service_name,quantity:1,unit:'усл.',price:Number(r.amount),gross:Number(r.amount),vat:Number(r.amount)*22/122,net:Number(r.amount)*100/122}]:body.p_trip_ids.map(id=>{assert.equal(id,t.id);return {trip_id:id,trip_number:t.trip_number,trip_date:t.trip_date,site_id:t.site_id,object:workspace.sites[0].name,service:t.service_name,quantity:t.volume,unit:t.unit,price:t.unit_price,gross:1220,net:1000,vat:220}});
   const total=items.reduce((s,i)=>s+i.gross,0),prefix={invoice:'СЧ',advance:'АВ',upd:'УПД',registry:'РЕЕСТР'}[r.kind];
   const d={...r,number:prefix+'-'+revision+'/2026',status:'draft',total,vat:total*22/122,paid_amount:0,snapshot:{seller:workspace.company,customer:workspace.customers[0],items,vat_rate:22},modified_at:'v'+(++revision)};
   workspace.documents.unshift(d);workspace.links.push(...body.p_trip_ids.map(trip_id=>({trip_id,document_id:d.id,kind:d.kind,active:true})));result=d.id;
  }else if(path.endsWith('/respectlogistic_accounting_action')){
   const d=workspace.documents.find(d=>d.id===body.p_id);assert.ok(d);assert.equal(body.p_expected_modified_at,d.modified_at);
   if(body.p_action==='issue'){d.status='issued';if(['upd','registry'].includes(d.kind)){assert.equal(body.p_payload.complete_trips,true);t.status='delivered';t.locked=true}}
   if(body.p_action==='payment')d.paid_amount=Number(body.p_payload.paid_amount);
   if(body.p_action==='credit')workspace.credits.push({...body.p_payload,invoice_id:d.id,amount:Number(body.p_payload.amount)});
   if(['sent','signed'].includes(body.p_action))d.status=body.p_action;
   if(body.p_action==='cancel'){d.status='cancelled';workspace.links.filter(l=>l.document_id===d.id).forEach(l=>l.active=false)}
   d.modified_at='v'+(++revision);workspace.history.push({document_id:d.id,action:body.p_action,created_at:new Date().toISOString(),detail:{}});result=null;
  }else if(path.endsWith('/respectlogistic_save_accounting_company')){workspace.company=body.p_payload;result=null}
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(result)});
 });
 const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(base,{waitUntil:'networkidle'});
 if(mobile)await page.getByRole('button',{name:'Открыть меню',exact:true}).click();
 await page.getByRole('button',{name:'Бухгалтерия',exact:true}).click();
 await page.getByRole('heading',{name:'Бухгалтерия',exact:true}).waitFor();
 await page.locator('.profit-filter').getByRole('combobox').nth(0).selectOption('customer');await page.locator('.profit-filter').getByRole('combobox').nth(1).selectOption('site');await page.locator('.profit-filter').getByRole('combobox').nth(2).selectOption('Вывоз');await page.getByRole('button',{name:'Применить',exact:true}).click();
 await page.getByRole('checkbox',{name:'Выбрать все рейсы',exact:true}).check();
 await page.getByRole('button',{name:'Счёт за услуги',exact:true}).click();await page.getByRole('button',{name:'Создать черновик',exact:true}).click();await page.getByRole('button',{name:'Сформировать',exact:true}).click();
 let dialog=page.getByRole('dialog');await dialog.getByText('Сформирован',{exact:true}).waitFor();const invoice=workspace.documents[0];
 await page.screenshot({path:out+'/'+(mobile?'mobile':'desktop')+'-invoice.png',fullPage:true});
 const popupPromise=page.waitForEvent('popup');await page.getByRole('button',{name:'Печать / PDF',exact:true}).click();const popup=await popupPromise;await popup.getByRole('heading',{name:new RegExp(invoice.number)}).waitFor();await popup.pdf({path:out+'/'+(mobile?'mobile':'desktop')+'-invoice.pdf',format:'A4'});await popup.close();
 await dialog.getByRole('button',{name:'Оплата',exact:true}).click();await page.getByLabel('Всего оплачено на сегодня, ₽ *').fill('100');await page.getByRole('button',{name:'Сохранить',exact:true}).click();
 await page.getByRole('dialog').getByRole('button',{name:'Закрыть',exact:true}).click();
 await page.getByRole('button',{name:'Счёт на аванс',exact:true}).click();await page.getByLabel('Сумма аванса с НДС, ₽ *').fill('200');await page.getByRole('button',{name:'Создать черновик',exact:true}).click();await page.getByRole('button',{name:'Сформировать',exact:true}).click();
 await page.getByRole('button',{name:'Оплата',exact:true}).click();await page.getByLabel('Всего оплачено на сегодня, ₽ *').fill('200');await page.getByRole('button',{name:'Сохранить',exact:true}).click();await page.getByRole('dialog').getByRole('button',{name:'Закрыть',exact:true}).click();
 await page.getByRole('button',{name:'Счета и документы',exact:true}).click();await page.getByRole('row').filter({hasText:invoice.number}).getByRole('button',{name:'Открыть',exact:true}).click();await page.getByRole('button',{name:'Зачесть аванс',exact:true}).click();await page.getByLabel('Зачесть в этот счёт, ₽ *').fill('200');await page.getByRole('button',{name:'Сохранить',exact:true}).click();assert.equal(workspace.credits.length,1);
 const downloadPromise=page.waitForEvent('download');await page.getByRole('button',{name:'Реестр CSV',exact:true}).click();const download=await downloadPromise;assert.ok(download.suggestedFilename().endsWith('.csv'));const downloaded=await readFile(await download.path(),'utf8');assert.ok(downloaded.includes('1220'));
 await page.getByRole('dialog').getByRole('button',{name:'Закрыть',exact:true}).click();await page.getByRole('button',{name:'Оказанные услуги',exact:true}).click();await page.getByRole('checkbox',{name:'Выбрать все рейсы',exact:true}).check();await page.getByRole('button',{name:'УПД',exact:true}).click();await page.getByRole('button',{name:'Создать черновик',exact:true}).click();
 const completeButton=page.getByRole('button',{name:'Сформировать и завершить рейсы',exact:true});assert.ok(await completeButton.isDisabled());await page.getByRole('dialog').getByRole('checkbox').check();await completeButton.click();assert.equal(t.status,'delivered');assert.equal(t.documents_confirmed,false);await page.getByRole('dialog').getByRole('button',{name:'Закрыть',exact:true}).click();
 await page.screenshot({path:out+'/'+(mobile?'mobile':'desktop')+'-accounting.png',fullPage:true});
 const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);assert.equal(overflow,false,'page overflows viewport');
 if(mobile)await page.getByRole('button',{name:'Открыть меню',exact:true}).click();await page.getByRole('button',{name:'Рейсы',exact:true}).click();await page.locator('.accounting-trip-documents').getByRole('button',{name:/УПД/}).waitFor();await page.getByText('Нет документов от водителя',{exact:true}).waitFor();
 assert.deepEqual(errors,[]);await page.screenshot({path:out+'/'+(mobile?'mobile':'desktop')+'-trip-documents.png',fullPage:true});
 console.log('PASS '+(mobile?'mobile':'desktop')+': filters, selection, invoice/advance, payments/credit, CSV, UPD explicit completion, trip attachment and separate driver-document status; no JS errors or page overflow. Controlled RPC fixtures.');await context.close();
}}finally{await browser.close()}
