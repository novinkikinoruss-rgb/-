import {test,expect} from '@playwright/test';
test('Trip attachments appear after upload, download original bytes and link to the saved Drive folder',async({page},info)=>{
 const uid='00000000-0000-4000-8000-000000000099',tripId='00000000-0000-4000-8000-000000000010';
 const user={id:uid,aud:'authenticated',role:'authenticated',email:'test@example.invalid',app_metadata:{},user_metadata:{},created_at:'2026-01-01T00:00:00Z'};
 const token=Buffer.from('{"alg":"HS256"}').toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:uid,exp:Math.floor(Date.now()/1000)+3600})).toString('base64url')+'.test';
 const filename='ТТН — Накладная с длинным названием по перевозке материалов на строительный объект.pdf';
 const content='%PDF-1.4 original trip attachment';
 let files=[],downloadRequests=0,failDownload=false;
 const folder='https://drive.google.com/drive/folders/test-trip-folder';
 const trip={id:tripId,trip_number:'42',trip_date:'2026-10-24',customer_id:null,site_id:null,vehicle_id:null,driver_id:null,carrier_id:null,loading_address:'Погрузка',unloading_address:'Выгрузка',volume:10,unit:'м³',unit_price:100,service_name:'Перевозка',status:'assigned',modified_at:'2026-10-24T00:00:00Z',locked:false,documents_confirmed:false};
 await page.route('**/api/trip-drive',route=>route.fulfill({json:{configured:false}}));
 await page.route('**/api/trip-files',async route=>{
  expect(route.request().method()).toBe('POST');
  files=[{id:'file-1',trip_id:tripId,file_name:filename,doc_type:'ttn',storage_path:uid+'/'+tripId+'/ttn.pdf',mime_type:'application/pdf',file_size:content.length}];
  await route.fulfill({json:{saved:true,id:'file-1'}});
 });
 await page.route('**/supabase/**',async route=>{
  const path=new URL(route.request().url()).pathname;let result={};
  if(path.endsWith('/token'))result={access_token:token,refresh_token:'test-refresh',expires_in:3600,token_type:'bearer',user};
  if(path.endsWith('/user'))result=user;
  if(path.endsWith('/respectlogistic_read_workspace'))result={revision:0,customers:[],contracts:[],specifications:[],sites:[],documents:[],activity:[]};
  if(path.endsWith('/crm_read_trip_workspace'))result={trips:[trip],customers:[],sites:[],vehicles:[],drivers:[],carriers:[],accounting_documents:[]};
  if(path.endsWith('/crm_trip_files'))result=files;
  if(path.endsWith('/crm_drive_exports'))result=[{trip_id:tripId,state:'awaiting_connection',folder_url:folder,error:null}];
  if(path.endsWith('/respectlogistic_driver_extras'))result={notes:[],shifts:[],shift_files:[]};
  if(path.endsWith('/respectlogistic_read_trip_progress'))result=[];
  if(path.includes('/storage/v1/object/sign/')&&route.request().method()==='POST'){
   downloadRequests++;
   if(failDownload){await route.fulfill({status:500,json:{message:'Хранилище временно недоступно'}});return}
   result={signedURL:'/object/sign/respectlogistic-trip-documents/ttn.pdf?token=test-signed'};
  }
  if(path.includes('/object/sign/')&&route.request().method()==='GET'){
   expect(new URL(route.request().url()).searchParams.get('download')).toBe(filename);
   await route.fulfill({body:content,contentType:'application/pdf',headers:{'Content-Disposition':"attachment; filename*=UTF-8''"+encodeURIComponent(filename)}});return;
  }
  await route.fulfill({json:result});
 });
 await page.goto('/');await page.getByLabel('Email',{exact:true}).fill('test@example.invalid');await page.getByLabel('Пароль',{exact:true}).fill('test-password');await page.getByRole('button',{name:'Войти',exact:true}).click();
 const menu=page.getByRole('button',{name:'Открыть меню',exact:true});if(await menu.isVisible())await menu.click();
 await page.locator('.sidebar .nav-item').filter({hasText:'Рейсы'}).click();
 const documents=page.locator('.trip-documents-row');
 await expect(documents.getByRole('link',{name:'Папка на Google Диске'})).toHaveAttribute('href',folder);
 await expect(documents.getByRole('link',{name:'Папка на Google Диске'})).toHaveAttribute('target','_blank');
 await documents.getByLabel('Загрузить документ любого формата до 10 МБ').setInputFiles({name:filename,mimeType:'application/pdf',buffer:Buffer.from(content)});
 const downloadButton=documents.getByRole('button',{name:'Скачать ТТН / накладная: '+filename,exact:true});
 await expect(downloadButton).toBeVisible();await expect(downloadButton.locator('svg')).toHaveCount(2);
 await expect(downloadButton.getByText('Скачать',{exact:true})).toBeVisible();
 const attachment=await downloadButton.boundingBox();expect(attachment.width).toBeLessThanOrEqual(page.viewportSize().width);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth)).toBe(false);
 const download=page.waitForEvent('download');await downloadButton.click();expect((await download).suggestedFilename()).toBe(filename);
 expect(downloadRequests).toBeGreaterThan(0);
 failDownload=true;await downloadButton.click();await expect(documents.getByRole('alert')).toContainText('Хранилище временно недоступно');
 await expect(downloadButton).toBeEnabled();
 await page.screenshot({path:'test-results/trip-documents-'+info.project.name+'.png',fullPage:true});
});
