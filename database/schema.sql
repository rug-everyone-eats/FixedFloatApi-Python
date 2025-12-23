-- ============================================================================
-- Crypto Exchange Backend - SQL Database Schema
-- Реляционная модель для перехода от in-memory хранения к SQL базе данных
-- ============================================================================

-- Поддерживаемые СУБД: PostgreSQL (рекомендуется), MySQL, SQLite

-- ============================================================================
-- ENUM TYPES (PostgreSQL)
-- ============================================================================

-- Для PostgreSQL создаем ENUM типы
-- Для MySQL/SQLite используйте VARCHAR с CHECK constraints

CREATE TYPE exchange_type AS ENUM ('fixed', 'float');
CREATE TYPE order_status AS ENUM ('NEW', 'PENDING', 'EXCHANGE', 'WITHDRAW', 'DONE', 'EXPIRED', 'EMERGENCY', 'FAILED');
CREATE TYPE emergency_choice AS ENUM ('EXCHANGE', 'REFUND');
CREATE TYPE transaction_direction AS ENUM ('from', 'to', 'back');

-- ============================================================================
-- TABLE: api_credentials
-- Учетные данные FixedFloat API (принадлежат администратору/владельцу)
-- Заменяет: auth.py -> self.api_keys: Dict[str, str]
-- ============================================================================

CREATE TABLE api_credentials (
    id                      SERIAL PRIMARY KEY,
    name                    VARCHAR(255) NOT NULL,           -- Название (например, "Production", "Test")
    api_key                 VARCHAR(64) NOT NULL UNIQUE,     -- API ключ FixedFloat
    api_secret_encrypted    BYTEA NOT NULL,                  -- Зашифрованный секрет
    is_active               BOOLEAN DEFAULT TRUE,
    is_primary              BOOLEAN DEFAULT FALSE,           -- Основной ключ для использования
    environment             VARCHAR(20) DEFAULT 'production', -- production, sandbox, test
    description             TEXT,
    last_used_at            TIMESTAMP WITH TIME ZONE,
    created_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_api_credentials_is_active ON api_credentials(is_active);
CREATE INDEX idx_api_credentials_is_primary ON api_credentials(is_primary) WHERE is_primary = TRUE;

COMMENT ON TABLE api_credentials IS 'Учетные данные FixedFloat API (администратор/владелец)';
COMMENT ON COLUMN api_credentials.api_key IS 'API ключ FixedFloat';
COMMENT ON COLUMN api_credentials.api_secret_encrypted IS 'Зашифрованный секрет для подписи запросов';
COMMENT ON COLUMN api_credentials.is_primary IS 'Основной ключ для использования по умолчанию';

-- ============================================================================
-- TABLE: partners
-- Партнерская программа
-- Заменяет: partner_system.py -> self.partners: Dict[str, Dict[str, Any]]
-- ============================================================================

CREATE TABLE partners (
    id                  SERIAL PRIMARY KEY,
    refcode             VARCHAR(50) NOT NULL UNIQUE,  -- Реферальный код
    name                VARCHAR(255),
    email               VARCHAR(255),
    default_commission  DECIMAL(5,2) NOT NULL DEFAULT 0,  -- Комиссия по умолчанию (%)
    max_commission      DECIMAL(5,2) NOT NULL DEFAULT 100, -- Максимальная комиссия (%)
    total_orders        INTEGER DEFAULT 0,            -- Счетчик ордеров
    total_volume_usd    DECIMAL(18,2) DEFAULT 0,      -- Общий объем в USD
    total_earned_usd    DECIMAL(18,2) DEFAULT 0,      -- Общий заработок в USD
    is_active           BOOLEAN DEFAULT TRUE,
    tier                VARCHAR(50) DEFAULT 'standard', -- Уровень партнера
    metadata            JSONB DEFAULT '{}',           -- Дополнительные данные
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_partners_refcode ON partners(refcode);
CREATE INDEX idx_partners_is_active ON partners(is_active);

COMMENT ON TABLE partners IS 'Партнеры и их комиссии (замена in-memory partner_system.partners)';
COMMENT ON COLUMN partners.refcode IS 'Уникальный реферальный код партнера';
COMMENT ON COLUMN partners.default_commission IS 'Комиссия партнера по умолчанию (%)';

-- Rate limiting хранится в Redis (rate_limiter.py)
-- Ключи: rate_limit:{api_key}:{window_start}
-- TTL: автоматическое истечение по окончании окна

-- ============================================================================
-- TABLE: currencies
-- Кэш поддерживаемых валют
-- Заменяет: currency_validator.py -> self._memory_cache
-- ============================================================================

CREATE TABLE currencies (
    id              SERIAL PRIMARY KEY,
    code            VARCHAR(20) NOT NULL UNIQUE,      -- Код валюты (BTC, ETH, etc.)
    coin            VARCHAR(20) NOT NULL,             -- Символ монеты
    network         VARCHAR(50) NOT NULL,             -- Сеть (Bitcoin, Ethereum, etc.)
    name            VARCHAR(100) NOT NULL,            -- Полное название
    recv            BOOLEAN DEFAULT FALSE,            -- Доступна для получения
    send            BOOLEAN DEFAULT FALSE,            -- Доступна для отправки
    tag             VARCHAR(50),                      -- Название тега (Memo, etc.)
    logo            VARCHAR(500),                     -- URL логотипа
    color           VARCHAR(7),                       -- Цвет бренда (#RRGGBB)
    priority        INTEGER DEFAULT 0,                -- Приоритет отображения
    decimals        INTEGER DEFAULT 8,                -- Точность валюты (кол-во знаков после запятой)
    min_amount      DECIMAL(28,18),                   -- Минимальная сумма
    max_amount      DECIMAL(28,18),                   -- Максимальная сумма
    is_active       BOOLEAN DEFAULT TRUE,
    cached_at       TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_currencies_code ON currencies(code);
CREATE INDEX idx_currencies_send ON currencies(send) WHERE send = TRUE;
CREATE INDEX idx_currencies_recv ON currencies(recv) WHERE recv = TRUE;
CREATE INDEX idx_currencies_is_active ON currencies(is_active);

COMMENT ON TABLE currencies IS 'Кэш поддерживаемых валют (замена in-memory currency_validator._memory_cache)';
COMMENT ON COLUMN currencies.recv IS 'Валюта доступна для получения (toCcy)';
COMMENT ON COLUMN currencies.send IS 'Валюта доступна для отправки (fromCcy)';
COMMENT ON COLUMN currencies.decimals IS 'Точность валюты (количество знаков после запятой)';

-- ============================================================================
-- TABLE: exchange_directions
-- Направления обмена с кастомными настройками
-- Позволяет переопределять лимиты и комиссии для конкретных пар
-- ============================================================================

CREATE TABLE exchange_directions (
    id                  SERIAL PRIMARY KEY,
    from_currency_id    INTEGER NOT NULL REFERENCES currencies(id) ON DELETE CASCADE,
    to_currency_id      INTEGER NOT NULL REFERENCES currencies(id) ON DELETE CASCADE,
    is_active           BOOLEAN DEFAULT TRUE,
    
    -- Лимиты (переопределяют значения из FixedFloat)
    min_amount          DECIMAL(28,18),               -- Минимальная сумма обмена
    max_amount          DECIMAL(28,18),               -- Максимальная сумма обмена
    
    -- Кастомные комиссии (добавляются к комиссии FixedFloat)
    extra_fee_percent   DECIMAL(5,4) DEFAULT 0,       -- Дополнительная комиссия (%)
    extra_fee_fixed     DECIMAL(28,18) DEFAULT 0,     -- Фиксированная доп. комиссия
    
    -- Приоритет и отображение
    priority            INTEGER DEFAULT 0,            -- Приоритет в списке
    is_featured         BOOLEAN DEFAULT FALSE,        -- Популярное направление
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT unique_direction UNIQUE (from_currency_id, to_currency_id),
    CONSTRAINT different_currencies CHECK (from_currency_id != to_currency_id)
);

CREATE INDEX idx_directions_from ON exchange_directions(from_currency_id);
CREATE INDEX idx_directions_to ON exchange_directions(to_currency_id);
CREATE INDEX idx_directions_active ON exchange_directions(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_directions_featured ON exchange_directions(is_featured) WHERE is_featured = TRUE;

COMMENT ON TABLE exchange_directions IS 'Направления обмена с кастомными настройками';
COMMENT ON COLUMN exchange_directions.extra_fee_percent IS 'Дополнительная комиссия в процентах';
COMMENT ON COLUMN exchange_directions.is_featured IS 'Популярное/рекомендуемое направление';

-- ============================================================================
-- TABLE: saved_addresses
-- Сохраненные адреса для повторных обменов
-- ============================================================================

CREATE TABLE saved_addresses (
    id              SERIAL PRIMARY KEY,
    currency_id     INTEGER NOT NULL REFERENCES currencies(id) ON DELETE CASCADE,
    address         VARCHAR(255) NOT NULL,
    tag             VARCHAR(100),                     -- Memo/Tag если требуется
    label           VARCHAR(100),                     -- Название адреса (например, "Мой Binance")
    is_verified     BOOLEAN DEFAULT FALSE,            -- Адрес проверен
    use_count       INTEGER DEFAULT 0,                -- Счетчик использований
    last_used_at    TIMESTAMP WITH TIME ZONE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT unique_address_per_currency UNIQUE (currency_id, address, tag)
);

CREATE INDEX idx_saved_addresses_currency ON saved_addresses(currency_id);
CREATE INDEX idx_saved_addresses_address ON saved_addresses(address);

COMMENT ON TABLE saved_addresses IS 'Сохраненные адреса для повторных обменов';
COMMENT ON COLUMN saved_addresses.label IS 'Пользовательское название адреса';



-- ============================================================================
-- TABLE: orders
-- Ордера на обмен
-- Хранение истории и статусов ордеров
-- ============================================================================

CREATE TABLE orders (
    id                  SERIAL PRIMARY KEY,
    external_id         VARCHAR(50) NOT NULL UNIQUE,  -- ID от FixedFloat
    short_id            VARCHAR(12) NOT NULL UNIQUE,  -- Короткий ID для пользователей (например, "ABC123")
    token               VARCHAR(100) NOT NULL,        -- Токен безопасности
    api_credential_id   INTEGER REFERENCES api_credentials(id) ON DELETE SET NULL,
    partner_id          INTEGER REFERENCES partners(id) ON DELETE SET NULL,
    direction_id        INTEGER REFERENCES exchange_directions(id) ON DELETE SET NULL,
    
    -- Тип и статус
    order_type          exchange_type NOT NULL,
    status              order_status NOT NULL DEFAULT 'NEW',
    
    -- Валюты и суммы
    from_currency       VARCHAR(20) NOT NULL,
    to_currency         VARCHAR(20) NOT NULL,
    from_amount         DECIMAL(28,18) NOT NULL,
    to_amount           DECIMAL(28,18) NOT NULL,
    
    -- Адреса
    from_address        VARCHAR(255) NOT NULL,        -- Адрес для отправки (генерируется)
    to_address          VARCHAR(255) NOT NULL,        -- Адрес получателя
    from_tag            VARCHAR(100),                 -- Memo/Tag для отправки
    to_tag              VARCHAR(100),                 -- Memo/Tag для получения
    saved_address_id    INTEGER REFERENCES saved_addresses(id) ON DELETE SET NULL,
    
    -- Партнерская информация
    refcode             VARCHAR(50),
    afftax              DECIMAL(5,2),
    partner_commission  DECIMAL(28,18),
    
    -- Контактная информация
    email               VARCHAR(255),
    
    -- Клиентская информация (для аналитики)
    client_ip           VARCHAR(45),                  -- IP клиента
    client_user_agent   TEXT,                         -- User-Agent клиента
    
    -- Временные метки
    time_reg            TIMESTAMP WITH TIME ZONE,     -- Время создания ордера
    time_start          TIMESTAMP WITH TIME ZONE,     -- Время получения транзакции
    time_finish         TIMESTAMP WITH TIME ZONE,     -- Время завершения
    time_expiration     TIMESTAMP WITH TIME ZONE,     -- Время истечения
    
    -- Метаданные
    metadata            JSONB DEFAULT '{}',
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TABLE: order_prices
-- Актуальные цены на момент создания ордера
-- Сохраняет snapshot курсов при создании обмена
-- ============================================================================

CREATE TABLE order_prices (
    id                  SERIAL PRIMARY KEY,
    order_id            INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    
    -- Исходная валюта (from)
    from_code           VARCHAR(20) NOT NULL,
    from_coin           VARCHAR(20),
    from_network        VARCHAR(50),
    from_amount         DECIMAL(28,18) NOT NULL,
    from_rate           DECIMAL(28,18) NOT NULL,      -- Курс на момент создания
    from_precision      INTEGER,
    from_min            DECIMAL(28,18),
    from_max            DECIMAL(28,18),
    from_usd            DECIMAL(28,18),               -- Эквивалент в USD
    
    -- Целевая валюта (to)
    to_code             VARCHAR(20) NOT NULL,
    to_coin             VARCHAR(20),
    to_network          VARCHAR(50),
    to_amount           DECIMAL(28,18) NOT NULL,
    to_rate             DECIMAL(28,18) NOT NULL,      -- Курс на момент создания
    to_precision        INTEGER,
    to_min              DECIMAL(28,18),
    to_max              DECIMAL(28,18),
    to_usd              DECIMAL(28,18),               -- Эквивалент в USD
    
    -- Общая информация о курсе
    exchange_rate       DECIMAL(28,18) NOT NULL,      -- Итоговый курс обмена (from -> to)
    rate_type           exchange_type NOT NULL,       -- fixed или float
    
    -- Комиссии
    service_fee         DECIMAL(28,18),               -- Комиссия сервиса
    network_fee         DECIMAL(28,18),               -- Сетевая комиссия
    total_fee           DECIMAL(28,18),               -- Общая комиссия
    fee_currency        VARCHAR(20),                  -- Валюта комиссии
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT unique_order_price UNIQUE (order_id)
);

CREATE INDEX idx_order_prices_order ON order_prices(order_id);
CREATE INDEX idx_order_prices_currencies ON order_prices(from_code, to_code);
CREATE INDEX idx_order_prices_created ON order_prices(created_at);

COMMENT ON TABLE order_prices IS 'Snapshot курсов на момент создания ордера';
COMMENT ON COLUMN order_prices.exchange_rate IS 'Зафиксированный курс обмена';
COMMENT ON COLUMN order_prices.from_usd IS 'Эквивалент исходной суммы в USD';

CREATE INDEX idx_orders_external_id ON orders(external_id);
CREATE INDEX idx_orders_short_id ON orders(short_id);
CREATE INDEX idx_orders_credential ON orders(api_credential_id);
CREATE INDEX idx_orders_partner ON orders(partner_id);
CREATE INDEX idx_orders_direction ON orders(direction_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_currencies ON orders(from_currency, to_currency);
CREATE INDEX idx_orders_created ON orders(created_at);
CREATE INDEX idx_orders_refcode ON orders(refcode) WHERE refcode IS NOT NULL;

COMMENT ON TABLE orders IS 'Ордера на обмен криптовалют';
COMMENT ON COLUMN orders.external_id IS 'ID ордера от FixedFloat API';
COMMENT ON COLUMN orders.short_id IS 'Короткий ID для отображения пользователям';
COMMENT ON COLUMN orders.token IS 'Токен безопасности для доступа к ордеру';

-- ============================================================================
-- TABLE: order_status_history
-- История изменений статусов ордера
-- ============================================================================

CREATE TABLE order_status_history (
    id              SERIAL PRIMARY KEY,
    order_id        INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    old_status      order_status,                     -- Предыдущий статус (NULL для первой записи)
    new_status      order_status NOT NULL,            -- Новый статус
    changed_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    comment         TEXT,                             -- Комментарий к изменению
    metadata        JSONB DEFAULT '{}'                -- Дополнительные данные
);

CREATE INDEX idx_order_status_history_order ON order_status_history(order_id);
CREATE INDEX idx_order_status_history_changed ON order_status_history(changed_at);
CREATE INDEX idx_order_status_history_status ON order_status_history(new_status);

COMMENT ON TABLE order_status_history IS 'История изменений статусов ордера';
COMMENT ON COLUMN order_status_history.old_status IS 'Предыдущий статус (NULL для создания)';

-- ============================================================================
-- TABLE: order_transactions
-- Транзакции ордеров (входящие, исходящие, возвраты)
-- ============================================================================

CREATE TABLE order_transactions (
    id                  SERIAL PRIMARY KEY,
    order_id            INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    direction           transaction_direction NOT NULL,  -- from, to, back
    
    -- Данные транзакции
    tx_hash             VARCHAR(255),                 -- Хэш транзакции
    amount              DECIMAL(28,18),
    fee                 DECIMAL(28,18),
    fee_currency        VARCHAR(20),
    
    -- Временные метки
    time_reg            TIMESTAMP WITH TIME ZONE,     -- Время регистрации
    time_block          TIMESTAMP WITH TIME ZONE,     -- Время включения в блок
    
    -- Подтверждения
    confirmations       INTEGER DEFAULT 0,
    required_confirmations INTEGER,
    max_confirmations   INTEGER,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_order_tx_order ON order_transactions(order_id);
CREATE INDEX idx_order_tx_hash ON order_transactions(tx_hash) WHERE tx_hash IS NOT NULL;
CREATE INDEX idx_order_tx_direction ON order_transactions(direction);

COMMENT ON TABLE order_transactions IS 'Транзакции ордеров';
COMMENT ON COLUMN order_transactions.direction IS 'Направление: from (входящая), to (исходящая), back (возврат)';

-- ============================================================================
-- TABLE: emergency_actions
-- История аварийных действий
-- ============================================================================

CREATE TABLE emergency_actions (
    id              SERIAL PRIMARY KEY,
    order_id        INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    choice          emergency_choice NOT NULL,        -- EXCHANGE или REFUND
    
    -- Данные для возврата
    refund_address  VARCHAR(255),
    refund_tag      VARCHAR(100),
    
    -- Результат
    status          VARCHAR(50) NOT NULL,
    message         TEXT,
    
    -- Метаданные
    request_data    JSONB,
    response_data   JSONB,
    
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_emergency_order ON emergency_actions(order_id);
CREATE INDEX idx_emergency_choice ON emergency_actions(choice);

COMMENT ON TABLE emergency_actions IS 'История аварийных действий по ордерам';

-- ============================================================================
-- TABLE: email_notifications
-- Подписки на email уведомления
-- ============================================================================

CREATE TABLE email_notifications (
    id              SERIAL PRIMARY KEY,
    order_id        INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    email           VARCHAR(255) NOT NULL,
    status          VARCHAR(50) DEFAULT 'pending',    -- pending, sent, failed
    sent_at         TIMESTAMP WITH TIME ZONE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_email_order ON email_notifications(order_id);
CREATE INDEX idx_email_status ON email_notifications(status);

COMMENT ON TABLE email_notifications IS 'Подписки на email уведомления по ордерам';

-- ============================================================================
-- TABLE: audit_log
-- Аудит всех действий в системе
-- ============================================================================

CREATE TABLE audit_log (
    id                  BIGSERIAL PRIMARY KEY,
    api_credential_id   INTEGER REFERENCES api_credentials(id) ON DELETE SET NULL,
    
    -- Информация о запросе
    request_id      VARCHAR(36),                      -- UUID запроса
    action          VARCHAR(100) NOT NULL,            -- Тип действия
    endpoint        VARCHAR(255),                     -- API endpoint
    method          VARCHAR(10),                      -- HTTP метод
    
    -- Данные запроса/ответа
    request_data    JSONB,
    response_code   INTEGER,
    response_data   JSONB,
    
    -- Клиентская информация
    ip_address      INET,
    user_agent      TEXT,
    
    -- Дополнительные данные
    duration_ms     INTEGER,                          -- Время выполнения
    error_message   TEXT,
    metadata        JSONB DEFAULT '{}',
    
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Партиционирование по дате для больших объемов (PostgreSQL 10+)
-- CREATE TABLE audit_log (...) PARTITION BY RANGE (created_at);

CREATE INDEX idx_audit_credential ON audit_log(api_credential_id);
CREATE INDEX idx_audit_action ON audit_log(action);
CREATE INDEX idx_audit_request_id ON audit_log(request_id);
CREATE INDEX idx_audit_created ON audit_log(created_at);
CREATE INDEX idx_audit_ip ON audit_log(ip_address);

COMMENT ON TABLE audit_log IS 'Аудит всех действий в системе';

-- ============================================================================
-- TABLE: system_settings
-- Системные настройки (key-value)
-- ============================================================================

CREATE TABLE system_settings (
    id              SERIAL PRIMARY KEY,
    key             VARCHAR(100) NOT NULL UNIQUE,
    value           TEXT,
    value_type      VARCHAR(20) DEFAULT 'string',     -- string, integer, boolean, json
    description     TEXT,
    is_encrypted    BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_settings_key ON system_settings(key);

COMMENT ON TABLE system_settings IS 'Системные настройки';

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Активные API credentials
CREATE VIEW v_active_credentials AS
SELECT 
    id,
    name,
    api_key,
    is_active,
    is_primary,
    environment,
    last_used_at,
    created_at
FROM api_credentials
WHERE is_active = TRUE;

-- Статистика партнеров
CREATE VIEW v_partner_stats AS
SELECT 
    p.id,
    p.refcode,
    p.name,
    p.default_commission,
    p.total_orders,
    p.total_volume_usd,
    p.total_earned_usd,
    COUNT(o.id) as orders_count,
    SUM(CASE WHEN o.status = 'DONE' THEN 1 ELSE 0 END) as completed_orders,
    SUM(o.from_amount) as total_from_amount
FROM partners p
LEFT JOIN orders o ON p.id = o.partner_id
GROUP BY p.id;

-- Статистика ордеров по дням
CREATE VIEW v_daily_order_stats AS
SELECT 
    DATE(created_at) as order_date,
    COUNT(*) as total_orders,
    SUM(CASE WHEN status = 'DONE' THEN 1 ELSE 0 END) as completed_orders,
    SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) as failed_orders,
    SUM(CASE WHEN status = 'EXPIRED' THEN 1 ELSE 0 END) as expired_orders
FROM orders
GROUP BY DATE(created_at)
ORDER BY order_date DESC;

-- ============================================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================================

-- Функция обновления updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Триггеры для автоматического обновления updated_at
CREATE TRIGGER update_api_credentials_updated_at BEFORE UPDATE ON api_credentials
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_partners_updated_at BEFORE UPDATE ON partners
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_currencies_updated_at BEFORE UPDATE ON currencies
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_order_transactions_updated_at BEFORE UPDATE ON order_transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_exchange_directions_updated_at BEFORE UPDATE ON exchange_directions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Функция генерации короткого ID для ордера
CREATE OR REPLACE FUNCTION generate_short_id()
RETURNS VARCHAR(12) AS $$
DECLARE
    chars VARCHAR(36) := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  -- Без 0,O,1,I для читаемости
    result VARCHAR(12) := '';
    i INTEGER;
BEGIN
    FOR i IN 1..8 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Триггер для автоматической генерации short_id
CREATE OR REPLACE FUNCTION set_order_short_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.short_id IS NULL OR NEW.short_id = '' THEN
        LOOP
            NEW.short_id := generate_short_id();
            EXIT WHEN NOT EXISTS (SELECT 1 FROM orders WHERE short_id = NEW.short_id);
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_order_short_id
    BEFORE INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION set_order_short_id();

-- Триггер для записи истории статусов ордера
CREATE OR REPLACE FUNCTION log_order_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO order_status_history (order_id, old_status, new_status, comment)
        VALUES (NEW.id, NULL, NEW.status, 'Order created');
    ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO order_status_history (order_id, old_status, new_status)
        VALUES (NEW.id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_log_order_status
    AFTER INSERT OR UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION log_order_status_change();

-- Триггер для обновления счетчика использований saved_addresses
CREATE OR REPLACE FUNCTION update_saved_address_usage()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.saved_address_id IS NOT NULL THEN
        UPDATE saved_addresses 
        SET use_count = use_count + 1, last_used_at = CURRENT_TIMESTAMP
        WHERE id = NEW.saved_address_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_saved_address_usage
    AFTER INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION update_saved_address_usage();





-- Функция обновления статистики партнера при создании ордера
CREATE OR REPLACE FUNCTION update_partner_stats()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.partner_id IS NOT NULL THEN
        UPDATE partners
        SET 
            total_orders = total_orders + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.partner_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_partner_stats
    AFTER INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION update_partner_stats();

-- ============================================================================
-- INITIAL DATA
-- ============================================================================

-- Демо партнеры (как в partner_system.py)
INSERT INTO partners (refcode, name, default_commission, max_commission) VALUES
    ('DEMO001', 'Demo Partner 1', 1.0, 5.0),
    ('DEMO002', 'Demo Partner 2', 2.0, 10.0),
    ('PREMIUM', 'Premium Partner', 5.0, 15.0);

-- Системные настройки по умолчанию
INSERT INTO system_settings (key, value, value_type, description) VALUES
    ('rate_limit_requests_per_minute', '250', 'integer', 'Максимальный вес запросов в минуту'),
    ('rate_limit_create_order_weight', '50', 'integer', 'Вес запроса создания ордера'),
    ('rate_limit_default_weight', '1', 'integer', 'Вес обычного запроса'),
    ('rates_cache_ttl', '60', 'integer', 'TTL кэша курсов в секундах'),
    ('currencies_cache_ttl', '3600', 'integer', 'TTL кэша валют в секундах');

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Составные индексы для частых запросов
CREATE INDEX idx_orders_status_created ON orders(status, created_at DESC);
CREATE INDEX idx_orders_credential_status ON orders(api_credential_id, status);
CREATE INDEX idx_audit_credential_action_created ON audit_log(api_credential_id, action, created_at DESC);

-- Частичные индексы
CREATE INDEX idx_orders_pending ON orders(created_at) WHERE status IN ('NEW', 'PENDING', 'EXCHANGE');
