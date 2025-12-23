# ER-диаграмма базы данных Crypto Exchange Backend

## Обзор

Реляционная модель данных для перехода от in-memory хранения к SQL базе данных.

**Важно:** API ключи принадлежат администратору/владельцу приложения для взаимодействия 
с FixedFloat API, а не конечным пользователям.

## Диаграмма связей (Entity-Relationship)

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    CRYPTO EXCHANGE DATABASE SCHEMA                                       │
│                                                                                                          │
│  Примечание: api_credentials - учетные данные FixedFloat API (принадлежат владельцу приложения)         │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────┐                              ┌─────────────────┐
│   api_credentials   │                              │    partners     │
│  (владелец/админ)   │                              ├─────────────────┤
├─────────────────────┤                              │ PK id           │
│ PK id               │                              │    refcode      │
│    name             │                              │    name         │
│    api_key          │                              │    email        │
│    api_secret_enc   │                              │    default_comm │
│    is_active        │                              │    max_comm     │
│    is_primary       │                              │    total_orders │
│    environment      │                              │    total_volume │
│    description      │                              │    total_earned │
│    last_used_at     │                              │    is_active    │
│    created_at       │                              │    tier         │
│    updated_at       │                              │    metadata     │
└─────────────────────┘                              │    created_at   │
          │                                          │    updated_at   │
          │                                          └─────────────────┘
          │                                                   │
          │                                                   │
┌─────────────────────┐      ┌─────────────────────┐          │
│     currencies      │      │ exchange_directions │          │
├─────────────────────┤      ├─────────────────────┤          │
│ PK id               │◄─────│ FK from_currency_id │          │
│    code             │◄─────│ FK to_currency_id   │          │
│    coin             │      │    is_active        │          │
│    network          │      │    min_amount       │          │
│    name             │      │    max_amount       │          │
│    recv             │      │    extra_fee_percent│          │
│    send             │      │    extra_fee_fixed  │          │
│    decimals         │      │    priority         │          │
│    is_active        │      │    is_featured      │          │
└─────────────────────┘      └─────────────────────┘          │
          │                            │                      │
          │                            │                      │
          ▼                            │                      │
┌─────────────────────┐                │                      │
│   saved_addresses   │                │                      │
├─────────────────────┤                │                      │
│ PK id               │                │                      │
│ FK currency_id      │                │                      │
│    address          │                │                      │
│    tag              │                │                      │
│    label            │                │                      │
│    is_verified      │                │                      │
│    use_count        │                │                      │
└─────────────────────┘                │                      │
          │                            │                      │
          │    ┌───────────────────────┘                      │
          │    │    ┌─────────────────────────────────────────┘
          │    │    │
          ▼    ▼    ▼
┌─────────────────────────────────────────────────────────────┐
│                          orders                              │
├─────────────────────────────────────────────────────────────┤
│ PK id                                                       │
│    external_id (ID от FixedFloat)                           │
│    short_id (короткий ID для пользователей)                 │
│    token                                                    │
│ FK api_credential_id ───────────────────────────────────────┤
│ FK partner_id ──────────────────────────────────────────────┤
│ FK direction_id ────────────────────────────────────────────┤
│ FK saved_address_id ────────────────────────────────────────┤
│    order_type (fixed/float)                                 │
│    status (NEW/PENDING/EXCHANGE/WITHDRAW/DONE/...)          │
│    from_currency, to_currency                               │
│    from_amount, to_amount                                   │
│    from_address, to_address                                 │
│    from_tag, to_tag                                         │
│    refcode, afftax, partner_commission                      │
│    email                                                    │
│    client_ip, client_user_agent                             │
│    time_reg, time_start, time_finish, time_expiration       │
│    metadata (JSONB)                                         │
│    created_at, updated_at                                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              │
          ┌───────────────────┼───────────────────┬───────────────────┐
          │                   │                   │                   │
          ▼                   ▼                   ▼                   ▼
┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
│    order_prices     │ │order_status_history │ │ order_transactions  │ │  emergency_actions  │
│  (snapshot курсов)  │ │  (история статусов) │ ├─────────────────────┤ ├─────────────────────┤
├─────────────────────┤ ├─────────────────────┤ │ PK id               │ │ PK id               │
│ PK id               │ │ PK id               │ │ FK order_id         │ │ FK order_id         │
│ FK order_id (1:1)   │ │ FK order_id         │ │    direction        │ │    choice           │
│    from_code        │ │    old_status       │ │    tx_hash          │ │    refund_address   │
│    from_amount      │ │    new_status       │ │    amount           │ │    refund_tag       │
│    from_rate        │ │    changed_at       │ │    fee              │ │    status           │
│    from_usd         │ │    comment          │ │    fee_currency     │ │    message          │
│    to_code          │ │    metadata         │ │    time_reg         │ │    request_data     │
│    to_amount        │ └─────────────────────┘ │    time_block       │ │    response_data    │
│    to_rate          │                         │    confirmations    │ │    created_at       │
│    to_usd           │                         │    required_conf    │ └─────────────────────┘
│    exchange_rate    │                         │    max_conf         │
│    rate_type        │                         │    created_at       │ ┌─────────────────────┐
│    service_fee      │                         │    updated_at       │ │ email_notifications │
│    network_fee      │                         └─────────────────────┘ ├─────────────────────┤
│    total_fee        │                                                 │ PK id               │
│    created_at       │                                                 │ FK order_id         │
└─────────────────────┘                                                 │    email            │
                                                                        │    status           │
                                                                        │    sent_at          │
                                                                        │    created_at       │
                                                                        └─────────────────────┘


## Данные в Redis (кэш)

```
┌─────────────────────────────────────────────────────────────┐
│                         REDIS                                │
├─────────────────────────────────────────────────────────────┤
│  rates:fixed - Кэш фиксированных курсов (TTL: 60s)          │
│  rates:float - Кэш плавающих курсов (TTL: 60s)              │
│  rate_limit:{api_key}:{window} - Rate limiting (TTL: auto)  │
└─────────────────────────────────────────────────────────────┘
```


┌─────────────────┐
│   currencies    │
│    (кэш в БД)   │
├─────────────────┤
│ PK id           │
│    code         │
│    coin         │
│    decimals     │
│    network      │
│    name         │
│    recv         │
│    send         │
│    tag          │
│    logo         │
│    color        │
│    priority     │
│    min_amount   │
│    max_amount   │
│    is_active    │
│    cached_at    │
│    updated_at   │
└─────────────────┘


┌─────────────────┐                    ┌─────────────────┐
│   audit_log     │                    │ system_settings │
├─────────────────┤                    ├─────────────────┤
│ PK id           │                    │ PK id           │
│ FK api_cred_id  │                    │    key          │
│    request_id   │                    │    value        │
│    action       │                    │    value_type   │
│    endpoint     │                    │    description  │
│    method       │                    │    is_encrypted │
│    request_data │                    │    created_at   │
│    response_code│                    │    updated_at   │
│    response_data│                    └─────────────────┘
│    ip_address   │
│    user_agent   │
│    duration_ms  │
│    error_message│
│    metadata     │
│    created_at   │
└─────────────────┘
```

## Связи между таблицами

### Основные связи (Foreign Keys)

| Таблица | Поле | Ссылается на | Тип связи |
|---------|------|--------------|-----------|
| `exchange_directions` | `from_currency_id` | `currencies.id` | N:1 |
| `exchange_directions` | `to_currency_id` | `currencies.id` | N:1 |
| `saved_addresses` | `currency_id` | `currencies.id` | N:1 |
| `orders` | `api_credential_id` | `api_credentials.id` | N:1 (опционально) |
| `orders` | `partner_id` | `partners.id` | N:1 (опционально) |
| `orders` | `direction_id` | `exchange_directions.id` | N:1 (опционально) |
| `orders` | `saved_address_id` | `saved_addresses.id` | N:1 (опционально) |
| `order_prices` | `order_id` | `orders.id` | 1:1 |
| `order_status_history` | `order_id` | `orders.id` | N:1 |
| `order_transactions` | `order_id` | `orders.id` | N:1 |
| `emergency_actions` | `order_id` | `orders.id` | N:1 |
| `email_notifications` | `order_id` | `orders.id` | N:1 |
| `audit_log` | `api_credential_id` | `api_credentials.id` | N:1 (опционально) |

### Кардинальность связей

```
currencies (1) ─────────────── (N) exchange_directions (from)
currencies (1) ─────────────── (N) exchange_directions (to)
currencies (1) ─────────────── (N) saved_addresses

api_credentials (1) ────────── (N) orders
api_credentials (1) ────────── (N) audit_log

partners (1) ───────────────── (N) orders

exchange_directions (1) ────── (N) orders
saved_addresses (1) ────────── (N) orders

orders (1) ─────────────────── (1) order_prices (snapshot курсов)
orders (1) ─────────────────── (N) order_status_history
orders (1) ─────────────────── (N) order_transactions
orders (1) ─────────────────── (N) emergency_actions
orders (1) ─────────────────── (N) email_notifications
```

## Маппинг In-Memory → SQL / Redis

| In-Memory (текущее) | Хранилище | Описание |
|---------------------|-----------|----------|
| `auth.py: api_keys: Dict[str, str]` | SQL: `api_credentials` | Учетные данные FixedFloat API (владелец) |
| `rate_limiter.py: requests: Dict[str, Dict]` | **Redis** (без изменений) | Rate limiting по окнам |
| `partner_system.py: partners: Dict[str, Dict]` | SQL: `partners` | Партнеры и комиссии |
| `currency_validator.py: _memory_cache` | SQL: `currencies` | Кэш валют |
| `redis_cache.py: fixed_rates, float_rates` | **Redis** (без изменений) | Кэш курсов (TTL 60s) |
| — (новое) | SQL: `orders` | История ордеров |
| — (новое) | SQL: `order_prices` | Snapshot курсов при создании ордера |
| — (новое) | SQL: `order_transactions` | Транзакции ордеров |
| — (новое) | SQL: `emergency_actions` | Аварийные действия |
| — (новое) | SQL: `audit_log` | Аудит действий |

### Разделение ответственности

- **Redis**: 
  - Кэш курсов (высокая частота обновления, TTL 60s)
  - Rate limiting (временные окна с автоматическим TTL)
- **SQL**: Персистентные данные (ордера, партнеры, аудит, credentials)

## Индексы

### Первичные индексы (Primary Keys)
- Все таблицы имеют автоинкрементный `id` как первичный ключ

### Уникальные индексы
- `api_credentials.api_key`
- `partners.refcode`
- `currencies.code`
- `exchange_directions(from_currency_id, to_currency_id)`
- `saved_addresses(currency_id, address, tag)`
- `orders.external_id`
- `orders.short_id`
- `order_prices.order_id` (1:1 связь)
- `system_settings.key`

### Индексы для поиска
- `partners(refcode)` — поиск по реферальному коду
- `orders(status)` — фильтрация по статусу
- `orders(from_currency, to_currency)` — поиск по валютной паре
- `order_prices(from_code, to_code)` — поиск по валютной паре в ценах
- `audit_log(created_at)` — временные запросы

### Частичные индексы (PostgreSQL)
- `currencies(send) WHERE send = TRUE` — только отправляемые валюты
- `currencies(recv) WHERE recv = TRUE` — только получаемые валюты
- `orders(created_at) WHERE status IN ('NEW', 'PENDING', 'EXCHANGE')` — активные ордера
- `api_credentials(is_primary) WHERE is_primary = TRUE` — основной ключ

## Типы данных

### ENUM типы (PostgreSQL)
```sql
exchange_type: 'fixed' | 'float'
order_status: 'NEW' | 'PENDING' | 'EXCHANGE' | 'WITHDRAW' | 'DONE' | 'EXPIRED' | 'EMERGENCY' | 'FAILED'
emergency_choice: 'EXCHANGE' | 'REFUND'
transaction_direction: 'from' | 'to' | 'back'
```

### Денежные значения
- `DECIMAL(28,18)` — для криптовалютных сумм (высокая точность)
- `DECIMAL(18,2)` — для USD сумм
- `DECIMAL(5,2)` — для процентов комиссий

### JSON поля
- `api_keys.permissions` — массив разрешений
- `api_keys.ip_whitelist` — белый список IP
- `partners.metadata` — дополнительные данные партнера
- `orders.metadata` — метаданные ордера
- `audit_log.request_data` — данные запроса
- `audit_log.response_data` — данные ответа

## Views (Представления)

### v_active_api_keys
Активные API ключи с информацией о пользователе.

### v_partner_stats
Статистика партнеров с агрегированными данными по ордерам.

### v_current_rates
Текущие (не истекшие) курсы обмена.

## Триггеры

### update_updated_at_column()
Автоматическое обновление поля `updated_at` при изменении записи.

### update_partner_stats()
Обновление счетчика ордеров партнера при создании нового ордера.

## Функции очистки

### cleanup_old_rate_limits()
Удаление устаревших записей rate limiting (старше 1 часа).

### cleanup_expired_rates()
Удаление истекших курсов обмена.
