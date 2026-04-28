# Тесты ONVIF

Дамнный каталог содержит некоторый набор тестов для проверки работы теж либо иных сервисов **onvifd**. Тесты разделены на базовые типы JSON/SOAP и отсортированы по сервисам ONVIF.

## Пример использования

Тесты запускаются из командной строки:

```
./<TestScript> <arguments...> <IP> <name=value...>
```

Поддерживаются следующие параметры запуска:

| Имя                            | Описание                                                                                                                                                                                  |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| -h, --help, help               | Вывод справки.                                                                                                                                                                            |
| -t, --timeout, timeout SECONDS | Задает таймаут для JSON/SOAP операции в секундах. Таймаут по умолчанию - 2 секунды.                                                                                                       |
| -u, --user USER                | Имя пользователя на IP-камере. По умолчанию - "admin".                                                                                                                                    |
| -p, --pass PASSWORD            | Пароль выбранного пользователя. По умолчанию - "admin".                                                                                                                                   |
| IP                             | Опциональный IP адрес IP-камеры. По умолчанию тестовые скрипты берут IP адрес из текущей конфигурации VS Code, тест запускается на камере на которой производится отладка onvifd.         |
| name=value                     | Набор параметров для подстановки в JSON/SOAP запросы. Имя параметра должно соответствовать и присутствовать в данных запроса. Позволяет менять работу теста без изменения исходного кода. |

Порядок следования параметров запуска не имеет значения.

Примеры использования:

```
❯ ./ForceNTPSync
10.113.12.164: device.ForceNTPSync()
IN:
{
  "Timeout": "PT5.155S"
}
OUT in 01.463s:
{
  "jsonrpc": "2.0",
  "result": {
    "CanNTP": true,
    "NTP": true,
    "NTPSynchronized": true
  },
  "id": "b0631939-fe25-4408-b748-85d80188d104"
}
```

Запуск с указанием IP и временем ожидания ответа:

```
❯ ./GetNTPStatus 192.168.1.0 timeout 30
```

Запуск с заменой данных JSON запроса:

```
./GetImagingSettings VideoSourceToken="xyz"
```

Тесты могут запускаться из любого подкаталога:

```
Imaging> $ ./GetImagingSettings
  tests> $ ./JSON/Imaging/GetImagingSettings
```

## Список тестов

На данный момент поддержтиваются следующие тесты:

| Тип      | Сервис             | Тест                                | Описание                                   |
| -------- | ------------------ | ----------------------------------- | ------------------------------------------ |
| **JSON** | **Analytics**      | CreateAnalyticsModules_Test12       |                                            |
|          |                    | CreateAnalyticsModules_Test34       |                                            |
|          |                    | DeleteAnalyticsModules_Test12       |                                            |
|          |                    | GetAnalyticsModules                 |                                            |
|          |                    | ModifyAnalyticsModules_Test12       |                                            |
|          | **AppMgmt**        | AppInstall1                         | Установка приложения "somefacedetector".   |
|          |                    | AppInstall2                         | Установка приложения "somemotiondetector". |
|          |                    | AppUninstall1                       | Удалуние приложения "somefacedetector".    |
|          |                    | AppUninstall2                       | Удаление приложения "somemotiondetector".  |
|          |                    | GetInstalledApps                    |                                            |
|          |                    | GetServiceCapabilities              |                                            |
|          | **Audio**          | GetAudioEncoderConfiguration        |                                            |
|          |                    | GetAudioEncoderConfigurationOptions |                                            |
|          |                    | GetAudioEncoderConfigurations       |                                            |
|          |                    | GetAudioSourceConfiguration         |                                            |
|          |                    | GetAudioSourceConfigurationOptions  |                                            |
|          |                    | GetAudioSourceConfigurations        |                                            |
|          |                    | GetAudioSources                     |                                            |
|          |                    | GetProfiles                         |                                            |
|          |                    | SetAudioEncoderConfiguration        |                                            |
|          |                    | SetAudioSourceConfiguration         |                                            |
|          | **Device**         | FaceDBInstall                       |                                            |
|          |                    | ForceNTPSync                        |                                            |
|          |                    | GetDot1XConfigurations              |                                            |
|          |                    | GetNetworkInterfaces                |                                            |
|          |                    | GetNTPStatus                        |                                            |
|          |                    | GetServices                         |                                            |
|          |                    | GetSystemUris                       |                                            |
|          |                    | LampAuto                            |                                            |
|          |                    | LampCurrentMode                     |                                            |
|          |                    | LampInvalid                         |                                            |
|          |                    | LampOff                             |                                            |
|          |                    | LampOn                              |                                            |
|          |                    | LampState                           |                                            |
|          |                    | StartUploadFaceDB                   |                                            |
|          | **Imaging**        | FilterAuto                          |                                            |
|          |                    | FilterBad                           |                                            |
|          |                    | FilterOff                           |                                            |
|          |                    | FilterOn                            |                                            |
|          |                    | GetImagingSettings                  |                                            |
|          |                    | GetMoveOptions                      |                                            |
|          |                    | GetOptions                          |                                            |
|          |                    | ReinitializeLens                    |                                            |
|          |                    | ReinitializeLensStatus              |                                            |
|          |                    | SetImagingSettings                  |                                            |
|          |                    | SetImagingSettings2                 |                                            |
|          | **Media**          | GetMetadataConfiguration            |                                            |
|          |                    | GetMetadataConfigurations           |                                            |
|          |                    | GetVideoAnalyticsConfigurations     |                                            |
|          |                    | PlayUploadedAudio_Play              |                                            |
|          |                    | PlayUploadedAudio_Repeat            |                                            |
|          |                    | PlayUploadedAudio_Status            |                                            |
|          |                    | PlayUploadedAudio_Stop              |                                            |
|          |                    | SetMetadataConfiguration            |                                            |
|          |                    | SetVideoEncoderConfiguration        |                                            |
|          |                    | StartUploadAudio                    |                                            |
|          |                    | StartUploadAudio_Remove             |                                            |
|          | **Media2**         | CreateOSD                           |                                            |
|          |                    | GetOSDs                             |                                            |
|          |                    | GetServiceCapabilities              |                                            |
|          | **PTZ**            | AbsoluteMove                        |                                            |
|          |                    | ContinuousMove                      |                                            |
|          |                    | GetConfigurationOptions             |                                            |
|          |                    | RelativeMove                        |                                            |
|          |                    | Stop                                |                                            |
|          | **StorageControl** | FormatStorage                       |                                            |
|          |                    | GetStorageStates                    |                                            |
|          |                    | ListStorage                         |                                            |
| **SOAP** | **Analytics**      | GetAnalyticsModules                 | В разработке.                              |
