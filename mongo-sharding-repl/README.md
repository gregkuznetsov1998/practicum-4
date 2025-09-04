# pymongo-api

## Как запустить

### Запускаем mongodb и приложение

Если в логах ошибка featureCompatibilityVersion, нужно очистить старые volume, которые остались от mongo старых версий
```shell
docker volume rm mongo-sharding-repl_config-data mongo-sharding-repl_shard1-primary-data mongo-sharding-repl_shard1-secondary1-data mongo-sharding-repl_shard1-secondary2-data mongo-sharding-repl_shard2-primary-data mongo-sharding-repl_shard2-secondary1-data mongo-sharding-repl_shard2-secondary2-data
```
Запуск приложения
```shell
docker compose up -d
```

### Инициализация шардирования, заполняем mongodb данными
```shell
chmod +x mongo-init.sh
```
```shell
./scripts/mongo-init.sh
```

## Как проверить

### Если вы запускаете проект на локальной машине

Откройте в браузере http://localhost:8080

### Если вы запускаете проект на предоставленной виртуальной машине

Узнать белый ip виртуальной машины

```shell
curl --silent http://ifconfig.me
```

Откройте в браузере http://<ip виртуальной машины>:8080

## Доступные эндпоинты

Список доступных эндпоинтов, swagger http://<ip виртуальной машины>:8080/docs

