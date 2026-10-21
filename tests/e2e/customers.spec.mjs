import {test,expect} from '@playwright/test';
async function ready(page){await page.goto('/');await expect(page.getByRole('heading',{name:'ООО «Стройресурс»',exact:true}).first()).toBeVisible();}
async function save(page){await page.getByRole('dialog').getByRole('button',{name:'Сохранить',exact:true}).click();await expect(page.getByRole('dialog')).toHaveCount(0);}
test('Карточка по макету, папки и честный статус подключений',async({page},testInfo)=>{
 await ready(page);await page.getByRole('button',{name:'Сайт работает · деморежим'}).click();await expect(page.getByLabel('Состояние подключений').getByText('Не настроено',{exact:true})).toHaveCount(2);
 await page.getByRole('button',{name:'Сайт работает · деморежим'}).click();
 await page.screenshot({path:`test-results/customer-${testInfo.project.name}.png`,fullPage:true,animations:'disabled'});
 await page.getByRole('tab',{name:'Документы',exact:true}).click();
 const download=page.waitForEvent('download');await page.getByRole('button',{name:'Договор ТР-2026-0001'}).click();expect((await download).suggestedFilename()).toContain('Договор');
});
test('Вся цепочка: заказчик → договор → услуги → объект → документы и сохранение',async({page})=>{
 await ready(page);await page.getByRole('button',{name:'Новый заказчик',exact:true}).click();
 await page.getByRole('dialog').getByLabel('ИНН организации').fill('7800000002');
 await page.getByLabel('Краткое название').fill('ООО «Тестовая компания»');await save(page);
 await expect(page.getByRole('status').filter({hasText:'Создана карточка заказчика'})).toBeVisible();
 await page.getByRole('button',{name:'Создать договор',exact:true}).click();await save(page);
 await page.getByRole('button',{name:'Создать спецификацию',exact:true}).click();
 await page.getByRole('textbox',{name:'Услуга 1',exact:true}).fill('Перевозка щебня');await page.getByRole('textbox',{name:'Цена 1',exact:true}).fill('725,50');await save(page);
 await expect(page.getByText('725,50',{exact:false}).first()).toBeVisible();
 await page.getByRole('button',{name:'Создать объект',exact:true}).click();
 await page.getByLabel('Название объекта').fill('ЖК «Новый»');await page.getByLabel('Адрес объекта').fill('Москва, тестовый адрес');await page.getByLabel('Ответственный прораб').fill('Петров Иван');await page.getByLabel('Расстояние в одну сторону').fill('52,5');await save(page);
 await expect(page.getByText('ЖК «Новый»',{exact:true}).first()).toBeVisible();await expect(page.getByText('Петров Иван',{exact:true})).toBeVisible();
 await page.reload();await expect(page.getByRole('button',{name:/ООО «Тестовая компания»/})).toBeVisible();await page.getByRole('button',{name:/ООО «Тестовая компания»/}).click();await page.getByRole('tab',{name:'Документы',exact:true}).click();
 await expect(page.getByRole('button',{name:/Карточка объекта «ЖК «Новый»»/})).toBeVisible();
 await page.getByRole('tab',{name:'История',exact:true}).click();await expect(page.getByText('Создан объект «ЖК «Новый»»',{exact:true})).toBeVisible();
});
test('Дубликат ИНН блокируется, форма остаётся открытой',async({page})=>{
 await ready(page);await page.getByRole('button',{name:'Новый заказчик',exact:true}).click();await page.getByRole('dialog').getByLabel('ИНН организации').fill('7700000009');await page.getByLabel('Краткое название').fill('Дубликат');await page.getByRole('dialog').getByRole('button',{name:'Сохранить',exact:true}).click();await expect(page.getByRole('dialog').getByRole('alert')).toContainText('уже существует');
});
test('ИНН без провайдера показывает ошибку и позволяет ручное заполнение',async({page})=>{
 await ready(page);await page.getByRole('button',{name:'Новый заказчик',exact:true}).click();await page.getByRole('dialog').getByLabel('ИНН организации').fill('7800000002');await page.getByRole('button',{name:'Заполнить по ИНН'}).click();await expect(page.getByRole('dialog').getByRole('alert')).toContainText('не подключено');await expect(page.getByLabel('Краткое название')).toBeEditable();
});
test('Канбан отражает реальные связи, карточка открывается из колонки',async({page})=>{
 await ready(page);await page.getByRole('button',{name:'Канбан',exact:true}).click();await expect(page.getByRole('heading',{name:'Объект готов',exact:true})).toBeVisible();await page.locator('.kanban-card').click();await expect(page.getByRole('tab',{name:'Обзор',exact:true})).toBeVisible();const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth);expect(overflow).toBe(false);
});
test('Дополнительный договор предлагает свою спецификацию даже у готовой компании',async({page})=>{
 await ready(page);await page.getByRole('button',{name:'Договор',exact:true}).click();await save(page);
 await expect(page.getByRole('button',{name:'Создать спецификацию',exact:true})).toBeVisible();await page.getByRole('button',{name:'Создать спецификацию',exact:true}).click();
 await expect(page.getByRole('dialog').getByLabel('Договор')).toHaveValue(/.+/);
 const chosen=await page.getByRole('dialog').getByLabel('Договор').locator('option:checked').textContent();expect(chosen).toContain('0002');
 await page.getByRole('textbox',{name:'Услуга 1',exact:true}).fill('Новая услуга');await page.getByRole('textbox',{name:'Цена 1',exact:true}).fill('1000');await save(page);
 await expect(page.getByRole('button',{name:'Создать объект',exact:true})).toBeVisible();
});
