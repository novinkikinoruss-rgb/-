# Подключение Google к CRM

Папка: https://drive.google.com/drive/folders/16EV7FQC6-89aIsFXJE9DPWH5O1LKD5W8
Реестр: https://docs.google.com/spreadsheets/d/11k_GIdfhfW9EmUztr-EjHqDhl1PteepuloRrA0Pfdho/edit

Подключение Google Диска в чате не выдаёт серверу CRM постоянного доступа. Для этого нужен OAuth-клиент вашего проекта Google Cloud и ваше согласие. Создание клиента само по себе не требует платного тарифа Render.

1. В обычном браузере войдите в https://console.cloud.google.com/ под владельцем папки. Создайте проект «CRM».
2. «APIs & Services → Library»: включите **Google Drive API** и **Google Sheets API**.
3. «Google Auth Platform → Branding»: название CRM, ваш email поддержки и контактный email. «Audience»: External; при Testing добавьте свой Google email в Test users. Если используете Google Workspace и доступ нужен только внутри организации, можно выбрать Internal.
4. «Clients → Create client → Web application». Название: CRM Render.
   - Authorized JavaScript origins: `https://respectlogistic.onrender.com`
   - Authorized redirect URIs: `https://respectlogistic.onrender.com/api/google-sync/callback`
5. Откройте https://respectlogistic.onrender.com/?workspace=trips&googleSettings=open . Войдите как администратор. Нажмите значок Google Диска вверху раздела «Рейсы». В открывшемся окне раскройте инструкцию подключения.
6. Вставьте **Client ID** и **Client Secret** в поля CRM. Не отправляйте секрет в чат, по почте или в скриншоте. Нажмите «Подключить Google». Выберите аккаунт владельца папки и подтвердите доступ.
7. После возврата нажмите «Синхронизировать сейчас». Появится время успешной синхронизации; проверьте вкладки «Рейсы», «Закрывающие», «Файлы» и документы в папке.

В External / Testing Google обычно отзывает разрешение с этими scopes через 7 дней. Для постоянной работы переведите приложение в Production в Audience. Google может потребовать проверку приложения, в зависимости от аудитории и использования Drive. Статус Production сам по себе не заменяет необходимые требования Google.

Ошибки:
- `redirect_uri_mismatch`: проверьте полный адрес возврата, HTTPS и отсутствие лишнего завершающего `/`.
- `access_denied`: проверьте Test users и выбранный аккаунт.
- API disabled: включите обе API в том же проекте, где создан Client ID.
- Доступ к папке/реестру: подключайте аккаунт, которому они принадлежат, либо предоставьте ему доступ.
- Разрешение отозвано: «Подключить повторно» и подтвердите Google.

Синхронизация запускается раз в минуту, пока открыт раздел «Рейсы», либо кнопкой. При закрытой CRM периодического задания пока нет. Исходные вложения и сохранённые HTML-формы выгружаются в Drive по заказчику, объекту, услуге, дате и машине. Базовая форма УПД остаётся формой для проверки: XML/ЭДО и собственный шаблон компании не подключены. Реестр является зеркалом CRM; изменять данные нужно в CRM. Обычные фото, реквизиты и финансовые данные не включаются в архив исходного кода.
