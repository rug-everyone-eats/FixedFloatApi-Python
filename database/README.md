# Database Schema - Crypto Exchange Backend

## Обзор

Реляционная модель данных для перехода от in-memory хранения к SQL базе данных.

**Важно:** API ключи (`api_credentials`) принадлежат администратору/владельцу приложения 
для взаимодействия с FixedFloat API, а не конечным пользователям.

## Файлы

| Файл | Описание |
|------|----------|
| `schema.sql` | DDL скрипт для PostgreSQL |
| `models.py` | SQLAlchemy ORM модели |
| `ER_DIAGRAM.md` | ER-диаграмма и описание связей |

## Поддерживаемые СУБД

- **PostgreSQL** (рекомендуется) - полная поддержка всех функций
- **MySQL** - требуется адаптация ENUM типов
- **SQLite** - для разработки и тестирования

## Быстрый старт

### PostgreSQL

```bash
# Создание базы данных
createdb crypto_exchange

# Применение схемы
psql -d crypto_exchange -f database/schema.sql
```

### SQLAlchemy (Python)

```python
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from database.models import Base, create_all_tables

# Подключение к базе данных
DATABASE_URL = "postgresql://user:password@localhost/crypto_exchange"
engine = create_engine(DATABASE_URL)

# Создание таблиц
create_all_tables(engine)

# Создание сессии
Session = sessionmaker(bind=engine)
session = Session()
```

## Таблицы

### Основные таблицы

| Таблица | Описание | Заменяет |
|---------|----------|----------|
| `api_credentials` | Учетные данные FixedFloat API (владелец) | `auth.py: api_keys` |
| `partners` | Партнеры | `partner_system.py: partners` |
| `currencies` | Кэш валют | `currency_validator.py: _memory_cache` |
| `exchange_directions` | Направления обмена с кастомными настройками | — (новое) |
| `saved_addresses` | Сохраненные адреса для повторных обменов | — (новое) |

**Данные в Redis (без изменений):**
- Кэш курсов (`redis_cache.py`) - высокая частота обновления, TTL 60s
- Rate limiting (`rate_limiter.py`) - временные окна с автоматическим TTL

### Таблицы ордеров

| Таблица | Описание |
|---------|----------|
| `orders` | Ордера на обмен (с short_id для пользователей) |
| `order_prices` | Snapshot курсов на момент создания ордера (1:1) |
| `order_status_history` | История изменений статусов ордера |
| `order_transactions` | Транзакции ордеров |
| `emergency_actions` | Аварийные действия |
| `email_notifications` | Email уведомления |

### Служебные таблицы

| Таблица | Описание |
|---------|----------|
| `audit_log` | Аудит действий |
| `system_settings` | Системные настройки |

## Миграция данных

### Из auth.py (API credentials)

```python
from database.models import ApiCredential
from cryptography.fernet import Fernet

# Ключ шифрования (храните безопасно!)
encryption_key = Fernet.generate_key()
cipher = Fernet(encryption_key)

# Текущие данные из .env
api_key = "your_fixedfloat_api_key"
api_secret = "your_fixedfloat_api_secret"

# Миграция
credential = ApiCredential(
    name="Production",
    api_key=api_key,
    api_secret_encrypted=cipher.encrypt(api_secret.encode()),
    is_active=True,
    is_primary=True,
    environment="production"
)
session.add(credential)
session.commit()
```

### Из partner_system.py (Партнеры)

```python
from database.models import Partner

# Текущие данные
old_partners = {
    "DEMO001": {"default_commission": 1.0, "max_commission": 5.0},
    "DEMO002": {"default_commission": 2.0, "max_commission": 10.0},
}

# Миграция
for refcode, data in old_partners.items():
    partner = Partner(
        refcode=refcode,
        default_commission=data["default_commission"],
        max_commission=data["max_commission"],
        is_active=True
    )
    session.add(partner)

session.commit()
```

## Индексы

### Ключевые индексы для производительности

```sql
-- Поиск по реферальному коду
CREATE INDEX idx_partners_refcode ON partners(refcode);

-- Фильтрация ордеров по статусу
CREATE INDEX idx_orders_status ON orders(status);

-- Поиск курса по паре валют
CREATE INDEX idx_exchange_rates_pair ON exchange_rates(from_currency, to_currency);

-- Временные запросы аудита
CREATE INDEX idx_audit_created ON audit_log(created_at);

-- Основной API credential
CREATE INDEX idx_api_credentials_is_primary ON api_credentials(is_primary) WHERE is_primary = TRUE;
```

## Очистка данных

### Ручная очистка

```sql
-- Удаление старых записей аудита (старше 30 дней)
DELETE FROM audit_log WHERE created_at < NOW() - INTERVAL '30 days';

-- Удаление старых завершенных ордеров (старше 1 года)
DELETE FROM orders WHERE status = 'DONE' AND created_at < NOW() - INTERVAL '1 year';
```

**Примечание:** Rate limiting и кэш курсов в Redis очищаются автоматически по TTL.

## Резервное копирование

### PostgreSQL

```bash
# Полный бэкап
pg_dump crypto_exchange > backup.sql

# Только данные
pg_dump --data-only crypto_exchange > data_backup.sql

# Восстановление
psql crypto_exchange < backup.sql
```

## Мониторинг

### Полезные запросы

```sql
-- Активные API credentials
SELECT * FROM v_active_credentials;

-- Статистика ордеров по статусам
SELECT status, COUNT(*) FROM orders GROUP BY status;

-- Статистика ордеров по дням
SELECT * FROM v_daily_order_stats LIMIT 30;

-- Топ партнеров по количеству ордеров
SELECT * FROM v_partner_stats ORDER BY orders_count DESC LIMIT 10;

-- Ордера с ценами
SELECT o.external_id, o.status, op.exchange_rate, op.from_usd, op.to_usd
FROM orders o
JOIN order_prices op ON o.id = op.order_id
ORDER BY o.created_at DESC
LIMIT 10;
```

**Примечание:** Для мониторинга rate limiting используйте Redis CLI или инструменты мониторинга Redis.

## Безопасность

### Рекомендации

1. **API секреты** - храните только в зашифрованном виде (`api_secret_encrypted`)
2. **Ключ шифрования** - храните отдельно от базы данных (например, в переменных окружения)
3. **Аудит** - все действия логируются в `audit_log`
4. **Минимум credentials** - используйте только необходимые API ключи

### Пример безопасного хранения

```python
from cryptography.fernet import Fernet
import os

# Ключ шифрования из переменных окружения
ENCRYPTION_KEY = os.environ.get('DB_ENCRYPTION_KEY')
cipher = Fernet(ENCRYPTION_KEY)

# Шифрование секрета для хранения
api_secret_encrypted = cipher.encrypt(api_secret.encode())

# Расшифровка для использования
api_secret = cipher.decrypt(api_secret_encrypted).decode()
```

## Версионирование схемы

Рекомендуется использовать Alembic для миграций:

```bash
# Инициализация
alembic init alembic

# Создание миграции
alembic revision --autogenerate -m "Initial schema"

# Применение миграций
alembic upgrade head
```
