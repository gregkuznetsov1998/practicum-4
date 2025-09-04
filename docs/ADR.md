### **Название задачи:**  
Проектирование архитектуры базы данных для онлайн-магазина «Мобильный мир»  

### **Автор:**  
Архитектурная команда «Мобильный мир»  

### **Дата:**  
2025-09-02  

### **Функциональные требования**  

| № | Действующие лица/системы | Use Case                          | Описание                                                                 |
|---|--------------------------|-----------------------------------|-------------------------------------------------------------------------|
| 1 | Пользователь             | Создание заказа                  | Добавление товаров в корзину → Оформление → Списание остатков           |
| 2 | Пользователь             | Просмотр истории заказов         | Фильтрация по идентификатору пользователя → Отображение статуса         |
| 3 | Система                  | Обновление остатков товаров      | Корректировка количества товаров при покупках                          |
| 4 | Пользователь             | Управление корзиной              | Добавление/удаление товаров → Слияние корзин при авторизации           |
| 5 | Администратор            | Поиск товаров                    | Фильтрация по категориям и ценам                                       |

### **Нефункциональные требования**  

| № | Требование                                                                 |
|---|----------------------------------------------------------------------------|
| 1 | Обработка 50 000 запросов/сек в пиковые нагрузки                           |
| 2 | Задержка обновления остатков товаров ≤ 100 мс                              |
| 3 | Автоматическое масштабирование шардов                                      |
| 4 | Обеспечение консистентности данных при высокой нагрузке                   |
| 5 | Поддержка кросс-региональных операций (геозоны)                           |
| 6 | Время отклика для операций с корзиной ≤ 50 мс                              |

### **Архитектурно значимые требования (ASR)**  

| ASR | Требование                                      | Категория | Обоснование                                                      |
|-----|-------------------------------------------------|-----------|------------------------------------------------------------------|
| 1   | Шардирование коллекций orders и products        | P, S      | Распределение нагрузки и данных                                 |
| 2   | Кэширование корзин в Redis                      | P         | Ускорение операций с корзинами                                  |
| 3   | Read Replica для запросов истории заказов       | P         | Разделение чтения и записи                                      |
| 4   | Hash-Based Sharding для коллекции carts         | P         | Равномерное распределение                                       |
| 5   | Range-Based Sharding для orders и products      | P         | Оптимизация геозапросов и диапазонных выборок                  |
| 6   | Circuit Breaker для внешних интеграций          | R         | Защита от сбоев внешних сервисов                                |

### **Структуры данных и ключи шардирования**  

#### **MongoDB: схемы коллекций и шард-ключи**  
**Коллекция `orders`:**  
- Поля:  
  _id: ObjectId  
  user_id: ObjectId  
  order_date: ISODate  
  items: Array[{ product_id: ObjectId, price: Decimal128 }]  
  status: String  
  total: Decimal128  
  geo_zone: String  
- Шард-ключ: geo_zone (Range-Based Sharding)  
- Преимущества: Локальность данных для геозапросов  
- Риски: Возможный дисбаланс при неравномерном распределении заказов по регионам  

**Коллекция `products`:**  
- Поля:  
  _id: ObjectId  
  name: String  
  category: String  
  price: Decimal128  
  stock: Object[{ geo_zone: String, quantity: Int }]  
  attributes: Object  
- Шард-ключ: category (Range-Based Sharding)  
- Преимущества: Оптимизация запросов по категориям  
- Риски: Горячие шарды для популярных категорий  

**Коллекция `carts`:**  
- Поля:  
  _id: ObjectId  
  user_id: ObjectId  
  session_id: String  
  items: Array[{ product_id: ObjectId, quantity: Int }]  
  status: String  
  created_at: ISODate  
  updated_at: ISODate  
  expires_at: ISODate  
- Шард-ключ: user_id (Hashed Sharding)  
- Преимущества: Равномерное распределение нагрузки  
- Риски: Нет географической локализации  

#### **Использование реплик в MongoDB**  

**Коллекция `orders`:**
- Операции чтения на secondary: 
  * Просмотр истории заказов
  * Аналитика и отчетность
  * Статистические запросы
- Операции только на primary:
  * Создание новых заказов
  * Обновление статуса заказа
  * Проверка актуального статуса для выполнения операций
- Допустимая задержка репликации: до 5 минут (для аналитических запросов)

**Коллекция `products`:**
- Операции чтения на secondary:
  * Просмотр каталога товаров
  * Поиск и фильтрация товаров
  * Чтение описаний товаров
- Операции только на primary:
  * Обновление остатков товаров
  * Изменение цен
  * Модификация атрибутов товаров
- Допустимая задержка репликации: до 1 секунды (для обеспечения актуальности данных о наличии)

**Коллекция `carts`:**
- Операции чтения на secondary: нет
- Операции только на primary:
  * Все операции чтения и записи
  * Добавление товаров в корзину
  * Обновление количества товаров
  * Слияние корзин
- Допустимая задержка репликации: 0 (требуется строгая консистентность)

#### **Команды шардирования MongoDB**  
```js
use ecommerce_db  
sh.enableSharding("ecommerce_db")  
sh.shardCollection("ecommerce_db.orders", { geo_zone: 1 })  
sh.shardCollection("ecommerce_db.products", { category: 1 })  
sh.shardCollection("ecommerce_db.carts", { user_id: "hashed" })  

// пример настройки шарда с репликацией
rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard1_primary:27018", priority: 3 },
        { _id : 1, host : "shard1_secondary1:27018", priority: 2 },
        { _id : 2, host : "shard1_secondary2:27018", priority: 1 }
      ]
    }
);

// пример настройки config server
rs.initiate(
  {
    _id : "config_server",
    configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);

// пример настройки роутера с шардами, репликацией и config 
sh.addShard("shard1/shard1_primary:27018,shard1_secondary1:27018,shard1_secondary2:27018");
sh.addShard("shard2/shard2_primary:27019,shard2_secondary1:27019,shard2_secondary2:27019");
sh.enableSharding("ecommerce_db");

db = db.getSiblingDB("ecommerce_db");
db.createCollection("orders");

sh.shardCollection("ecommerce_db.helloDoc", { _id: "hashed" });
```

#### **Cassandra: таблицы и partition keys**  
**Таблица `carts`:**  
- Поля:  
  user_id UUID  
  created_at TIMESTAMP  
  items MAP<UUID, INT>  
  status TEXT  
  session_id TEXT  
  expires_at TIMESTAMP  
- Partition key: user_id  
- Clustering key: created_at  
- Преимущества: Равномерное распределение и сортировка по времени  
- Риски: Возможные горячие партиции для активных пользователей  

**Таблица `products`:**  
- Поля:  
  category TEXT  
  price DECIMAL  
  product_id UUID  
  name TEXT  
  stock MAP<TEXT, INT>  
  attributes MAP<TEXT, TEXT>  
- Partition key: category  
- Clustering key: price  
- Преимущества: Эффективные запросы по категориям и ценам  
- Риски: Дисбаланс для категорий с большим количеством товаров  

**Таблица `orders`:**  
- Поля:  
  geo_zone TEXT  
  order_date TIMESTAMP  
  order_id UUID  
  user_id UUID  
  items LIST<UUID>  
  total DECIMAL  
  status TEXT  
- Partition key: geo_zone  
- Clustering key: order_date  
- Преимущества: Оптимизация для региональных отчетов  
- Риски: Неравномерное распределение для плотных регионов  

#### **Команды создания таблиц Cassandra**  
```sql
CREATE TABLE carts (
    user_id UUID,
    created_at TIMESTAMP,
    items MAP<UUID, INT>,
    status TEXT,
    session_id TEXT,
    expires_at TIMESTAMP,
    PRIMARY KEY (user_id, created_at)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

```sql
CREATE TABLE products (
    category TEXT,
    price DECIMAL,
    product_id UUID,
    name TEXT,
    stock MAP<TEXT, INT>,
    attributes MAP<TEXT, TEXT>,
    PRIMARY KEY (category, price)
);
```

```sql
CREATE TABLE orders (
    geo_zone TEXT,
    order_date TIMESTAMP,
    order_id UUID,
    user_id UUID,
    items LIST<UUID>,
    total DECIMAL,
    status TEXT,
    PRIMARY KEY (geo_zone, order_date)
) WITH CLUSTERING ORDER BY (order_date DESC);
```

#### **CQL запросы для управления шардированием**  
```sql
-- Настройка репликации для разных датацентров
ALTER KEYSPACE ecommerce WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'datacenter1': 3,
  'datacenter2': 2
};

-- Добавление нового датацентра
ALTER KEYSPACE ecommerce WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'datacenter1': 3,
  'datacenter2': 2,
  'datacenter3': 2
};

-- Изменение уровня согласованности для конкретных операций
CONSISTENCY QUORUM;
INSERT INTO orders (geo_zone, order_date, order_id, user_id, items, total, status) 
VALUES ('Moscow', toTimestamp(now()), uuid(), uuid(), [uuid(), uuid()], 199.99, 'completed');

CONSISTENCY ONE;
SELECT * FROM carts WHERE user_id = uuid();
```

### **Метрики мониторинга и действия**  

| Метрика | Пороговое значение | Действие |
|---------|---------------------|----------|
| Задержка репликации | >500 мс | Проверить сеть и нагрузку на узлы |
| Размер шарда | >50 ГБ | Инициировать балансировку |
| Количество операций/сек | >10 000 | Добавить шард или реплику |
| Потребление CPU | >80% | Оптимизировать запросы или масштабировать |
| Расхождение данных | >1% | Запустить repair-процедуры |

### **Альтернативные решения**  

#### **Для MongoDB**  
1. **Единый replica set без шардирования**  
   - Преимущества: Простота реализации  
   - Недостатки: Не удовлетворяет требованиям масштабируемости  

2. **Зональное шардирование**  
   - Преимущества: Лучшая географическая локализация  
   - Недостатки: Сложность управления и риски дисбаланса  

3. **Гибридное шардирование**  
   - Преимущества: Комбинация разных стратегий  
   - Недостатки: Повышенная сложность реализации  

#### **Для Cassandra**  
1. **Использование другого partition key**  
   - Преимущества: Возможность оптимизации под конкретные сценарии  
   - Недостатки: Риск создания горячих партиций  

2. **Денормализация данных**  
   - Преимущества: Улучшение производительности чтения  
   - Недостатки: Увеличение объема данных и сложность обновлений  

### **Стратегии обеспечения целостности в Cassandra**  
- **Hinted Handoff**: Для корзин и сессий (приоритет доступности)  
- **Read Repair**: Для заказов (баланс latency и консистентности)  
- **Anti-Entropy Repair**: Для товаров (гарантия согласованности остатков)  

### **Процедуры при проблемах**  
1. **Дисбаланс шардов**: Запуск балансировщика MongoDB или nodetool repair в Cassandra  
2. **Высокая задержка**: Добавление реплик для чтения или кэширование  
3. **Расхождение данных**: Ручной запуск repair-процессов с учетом нагрузки  
4. **Перегрузка узлов**: Перераспределение данных или горизонтальное масштабирование  

### **Сравнение стратегий шардирования**  

| Критерий | Range-Based | Hash-Based |
|----------|-------------|------------|
| Распределение | Неравномерное | Равномерное |
| Локальность данных | Высокая | Низкая |
| Поддержка диапазонных запросов | Да | Нет |
| Риск горячих шардов | Высокий | Низкий |

### **Ограничения решения**  
- Сложность JOIN-операций: Требуется денормализация данных  
- Настройка согласованности: Компромисс между latency и консистентностью  
- Миграция данных: Требуется тщательное планирование для минимизации downtime  