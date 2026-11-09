# Вход в CRM через Google

В приложении подготовлена кнопка «Войти через Google». Она проверяет /supabase/auth/v1/settings и при включённом провайдере использует Supabase signInWithOAuth. Обычный клиент Auth идёт через API-прокси CRM; OAuth-навигация направляется прямо на фиксированный HTTPS origin проекта Supabase, чтобы браузер выполнил редиректы Google. Возврат идёт на корень CRM, существующий Auth client восстанавливает сессию; ошибки очищаются из URL и отображаются в форме. Парольный вход сохранён до проверки Google владельцем. Анонимный доступ к данным не добавлялся, RPC, ownership и RLS не менялись.

## Один раз настроить в панелях

1. Открыть Google Cloud → Google Auth Platform → Clients: https://console.cloud.google.com/auth/clients . Создать OAuth Client типа Web application для входа CRM. Authorized JavaScript origins: https://respectlogistic.onrender.com . Authorized redirect URIs: https://yoqejkedmksmvbqagqru.supabase.co/auth/v1/callback . У проекта должны быть настроены Branding/Audience; при External/Testing добавить собственный Google email в Test users. Не менять рабочий OAuth клиент синхронизации Drive без необходимости.
2. Открыть Supabase Google provider: https://supabase.com/dashboard/project/yoqejkedmksmvbqagqru/auth/providers?provider=Google . Включить Google, вставить Client ID и Client Secret из Google Cloud и сохранить. Client Secret вводить только в Supabase, не в чат, исходники или браузерное хранилище. Skip nonce check не включать.
3. Открыть https://supabase.com/dashboard/project/yoqejkedmksmvbqagqru/auth/url-configuration . Site URL: https://respectlogistic.onrender.com . В Redirect URLs добавить точный URL https://respectlogistic.onrender.com/ и, для восстановления, https://respectlogistic.onrender.com/reset-password . Сохранить. Не использовать localhost как production Site URL.
4. Открыть CRM и нажать «Войти через Google». Выбрать Google-аккаунт с тем же email, что у существующего пользователя CRM. Supabase автоматически связывает подтверждённые identities с одинаковым email; вход другим аккаунтом не даёт права на данные владельца. После возврата проверить свои заказчики и рейсы. До этого не отключать парольный вход. В этой задаче пользователь и его пароль не менялись.

## Граница доступности инструментов

На момент диагностики публичные Auth settings проекта возвращали external.google=false. Подключённые Supabase инструменты не предоставляют изменение Auth provider / URL configuration, а Management API credential в среде отсутствует. Google Cloud OAuth client и согласие владельца также требуют его панели. Изменение кода не считается включением провайдера или успешным входом реального Google-аккаунта. Для окончания настройки нужны шаги 1–3 и реальная проверка шага 4. В дальнейшем скрытие формы пароля — отдельное действие после подтверждения работающего Google.

## Проверки и восстановление

Browser fixtures desktop/mobile проверяют отключённого провайдера, сохранение парольного входа, HTTPS authorize правильного проекта, provider=google, prompt=select_account, redirect_to текущей CRM, успешный callback и отмену без токенов в URL. Это контролируемые ответы Auth, не проверка реального согласия Google. Сборка/TypeScript и существующие login-сценарии проверяются отдельно. SQL-миграции не нужны. Исходный архив не содержит .env, секреты, токены, node_modules или базу клиента. Восстановление: точный commit, npm ci, существующие настройки Render отдельно, npm test, npm run build, ветка respectlogistic/customers. Откат кода не отменяет настройки провайдера в Supabase.

Документация: https://supabase.com/docs/guides/auth/social-login/auth-google , https://supabase.com/docs/guides/auth/auth-identity-linking .
