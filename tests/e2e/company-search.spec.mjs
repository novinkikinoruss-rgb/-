import {test,expect} from '@playwright/test';
test('Чекко selection fills requisites, preserves contacts and handles empty/error results',async({page},info)=>{
 const company={name:'ООО «Организация с очень длинным наименованием для проверки мобильного экрана»',fullName:'Полное наименование организации',inn:'7800000002',kpp:'780001001',ogrn:'1027800000000',legalAddress:'Санкт-Петербург, длинный юридический адрес, дом 1',director:'Иванов Иван'};
 let mode='success';
 await page.route('**/api/company',async route=>{const body=route.request().postDataJSON();expect(body.query).toBeTruthy();await route.fulfill(mode==='error'?{status:503,json:{error:'Чекко не подключено. Заполните вручную.'}}:{json:{suggestions:mode==='empty'?[]:[company]}})});
 await page.goto('/');const menu=page.getByRole('button',{name:'Открыть меню',exact:true});if(await menu.isVisible())await menu.click();await page.locator('.sidebar .nav-item').filter({hasText:'Заказчики'}).click();
 await page.getByRole('button',{name:'Новый заказчик',exact:true}).click();const dialog=page.getByRole('dialog');
 await dialog.getByLabel('Контактное лицо').fill('Мой контакт');const input=dialog.getByLabel('Поиск по ИНН в Чекко');await input.fill('7800000002');await input.press('Enter');
 const results=dialog.getByRole('group',{name:'Организации Чекко'});await expect(results).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth)).toBe(false);
 await results.getByRole('button').click();await expect(dialog.getByLabel('Краткое название')).toHaveValue(company.name);await expect(dialog.getByLabel('ИНН организации')).toHaveValue(company.inn);await expect(dialog.getByLabel('КПП',{exact:true})).toHaveValue(company.kpp);await expect(dialog.getByLabel('Юридический адрес')).toHaveValue(company.legalAddress);await expect(dialog.getByLabel('Руководитель')).toHaveValue(company.director);await expect(dialog.getByLabel('Контактное лицо')).toHaveValue('Мой контакт');
 mode='empty';await input.fill('7700000009');await input.press('Enter');await expect(dialog.getByText('Организации не найдены. Проверьте ИНН.')).toBeVisible();await expect(dialog.getByLabel('Краткое название')).toHaveValue(company.name);
 mode='error';await input.fill('7707083893');await input.press('Enter');await expect(dialog.getByText('Чекко не подключено. Заполните вручную.')).toBeVisible();await expect(dialog.getByLabel('Краткое название')).toBeEditable();await page.screenshot({path:'test-results/checko-'+info.project.name+'.png',fullPage:true});
});
