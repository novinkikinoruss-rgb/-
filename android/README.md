# Кабинет водителя Android

Модуль 0.2: назначенные рейсы с этапами работы, сервис, личные заметки, периоды управления, отчёты с фотографиями и штрафы. Приложение открывает защищённый кабинет `/driver`, работает при подключении к интернету. Чат, OCR чеков, push при закрытом приложении и автономная работа в этот выпуск не входят. Установку на реальное устройство проверять отдельно от сборки.

Сборка: GitHub Actions → Driver Android APK → artifact. Java 17, Gradle 8.11.1, Android SDK 35. Идентификатор `com.respectlogistic.driver` должен оставаться постоянным.

Для устанавливаемого APK требуются пять GitHub Actions secrets:

- `DRIVER_ANDROID_KEYSTORE_BASE64` — base64 постоянного JKS;
- `DRIVER_ANDROID_STORE_PASSWORD`;
- `DRIVER_ANDROID_KEY_PASSWORD`;
- `DRIVER_ANDROID_KEY_ALIAS`.
- `DRIVER_ANDROID_CERT_SHA256` — постоянный контрольный отпечаток сертификата.

Проверка доступа, создание ключа и настройка секретов: [инструкция](../docs/android-signing-setup.md), скрипт `scripts/configure-android-signing.py`. Ошибка 403 требует отдельного GitHub-доступа с Secrets write и не исправляется изменением кода приложения. При ручном запуске сборки подпись обязательна по умолчанию.

Создайте ключ один раз командой `keytool -genkeypair -v -keystore driver-release.jks -alias driver-release -keyalg RSA -keysize 3072 -validity 10000` и сохраните независимую защищённую резервную копию JKS и паролей. Не добавляйте их в git или общий архив разработки. При отсутствии secrets workflow создаёт явно неподписанный APK для проверки сборки. Такой файл не является готовым установщиком. Не заменяйте постоянный ключ от версии к версии.
