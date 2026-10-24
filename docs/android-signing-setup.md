# Постоянная подпись APK: завершение настройки

Ошибка 403 «Resource not accessible by integration» возникает в GitHub API для Actions Secrets. Права администратора пользователя на репозиторий не добавляют отсутствующее разрешение токену интеграции. Изменение режима подтверждений ChatGPT и `permissions:` внутри workflow также не выдаёт Secrets write.

Требуется GitHub-доступ к **одному** репозиторию `novinkikinoruss-rgb/-` с разрешением **Secrets: Read and write**. Не публикуйте токен в чате, исходниках или журнале Actions. Подключите его через секреты рабочей среды либо используйте собственный авторизованный GitHub CLI на компьютере. Подключённая интеграция этого сеанса не поддерживает изменение своих OAuth/admin-разрешений.

Для самостоятельной настройки нужны Python 3, JDK (`keytool`) и GitHub CLI (`gh`). В checkout проекта выполните:

```sh
python3 scripts/configure-android-signing.py --keystore "$HOME/.respectlogistic-signing/driver-release.p12" --create
```

Скрипт сначала проверит GitHub Secrets; при 403 не создаст ключ и не запросит пароль. При первом успешном запуске запросит пароль, создаст постоянный RSA-ключ, передаст секреты через stdin и сохранит контрольный отпечаток сертификата. Повторный запуск с существующим ключом выполняется **без `--create`**. Новый ключ поверх старого не создаётся.

Сохраните отдельную зашифрованную резервную копию `driver-release.p12` и пароля. Ключ не входит в архив исходников CRM. Потеря ключа мешает установке обновлений поверх старого приложения.

После настройки откройте GitHub → Actions → Driver Android APK → Run workflow → ветка `respectlogistic/customers`, параметр `signed=true`. Дополнительный флаг скрипта `--build` запускает ту же сборку, если токен также имеет Actions write.

Workflow проверяет подпись APK и её соответствие постоянному SHA256 сертификата. При ручном запуске с `signed=true` отсутствие секретов является ошибкой, а не успешным установщиком. Автоматические проверочные сборки без ключа помечены `unsigned-not-installable`.

Секреты: `DRIVER_ANDROID_KEYSTORE_BASE64`, `DRIVER_ANDROID_STORE_PASSWORD`, `DRIVER_ANDROID_KEY_PASSWORD`, `DRIVER_ANDROID_KEY_ALIAS`, `DRIVER_ANDROID_CERT_SHA256`.
