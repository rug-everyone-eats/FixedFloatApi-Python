"""
SQLAlchemy ORM модели для Crypto Exchange Backend

Реляционная модель данных для перехода от in-memory хранения к SQL базе данных.
Поддерживает PostgreSQL (рекомендуется), MySQL, SQLite.

Примечание: API ключи принадлежат администратору/владельцу приложения,
а не конечным пользователям.
"""

from datetime import datetime
from typing import Optional, List, Dict, Any
from enum import Enum as PyEnum

from sqlalchemy import (
    Column, Integer, BigInteger, String, Text, Boolean, 
    DateTime, Numeric, ForeignKey, Index, UniqueConstraint,
    Enum, JSON, LargeBinary, CheckConstraint
)
from sqlalchemy.dialects.postgresql import INET, JSONB
from sqlalchemy.orm import relationship, declarative_base
from sqlalchemy.sql import func

Base = declarative_base()


# ============================================================================
# ENUM TYPES
# ============================================================================

class ExchangeType(str, PyEnum):
    """Тип обмена"""
    FIXED = "fixed"
    FLOAT = "float"


class OrderStatus(str, PyEnum):
    """Статус ордера"""
    NEW = "NEW"
    PENDING = "PENDING"
    EXCHANGE = "EXCHANGE"
    WITHDRAW = "WITHDRAW"
    DONE = "DONE"
    EXPIRED = "EXPIRED"
    EMERGENCY = "EMERGENCY"
    FAILED = "FAILED"


class EmergencyChoice(str, PyEnum):
    """Выбор аварийного действия"""
    EXCHANGE = "EXCHANGE"
    REFUND = "REFUND"


class TransactionDirection(str, PyEnum):
    """Направление транзакции"""
    FROM = "from"
    TO = "to"
    BACK = "back"


# ============================================================================
# MODELS
# ============================================================================

class ApiCredential(Base):
    """
    Учетные данные FixedFloat API (принадлежат администратору/владельцу).
    Заменяет: auth.py -> self.api_keys: Dict[str, str]
    """
    __tablename__ = "api_credentials"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(255), nullable=False)  # "Production", "Test", etc.
    api_key = Column(String(64), unique=True, nullable=False)
    api_secret_encrypted = Column(LargeBinary, nullable=False)  # Зашифрованный секрет
    is_active = Column(Boolean, default=True, index=True)
    is_primary = Column(Boolean, default=False)  # Основной ключ для использования
    environment = Column(String(20), default="production")  # production, sandbox, test
    description = Column(Text)
    last_used_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # Relationships
    orders = relationship("Order", back_populates="api_credential")
    audit_logs = relationship("AuditLog", back_populates="api_credential")
    
    def __repr__(self):
        return f"<ApiCredential(id={self.id}, name='{self.name}', api_key='{self.api_key[:8]}...')>"
    
    @property
    def is_valid(self) -> bool:
        """Проверка валидности ключа"""
        return self.is_active


class Partner(Base):
    """
    Партнерская программа.
    Заменяет: partner_system.py -> self.partners: Dict[str, Dict[str, Any]]
    """
    __tablename__ = "partners"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    refcode = Column(String(50), unique=True, nullable=False, index=True)
    name = Column(String(255))
    email = Column(String(255))
    default_commission = Column(Numeric(5, 2), nullable=False, default=0)
    max_commission = Column(Numeric(5, 2), nullable=False, default=100)
    total_orders = Column(Integer, default=0)
    total_volume_usd = Column(Numeric(18, 2), default=0)
    total_earned_usd = Column(Numeric(18, 2), default=0)
    is_active = Column(Boolean, default=True, index=True)
    tier = Column(String(50), default="standard")
    metadata = Column(JSON, default=dict)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # Relationships
    orders = relationship("Order", back_populates="partner")
    
    def __repr__(self):
        return f"<Partner(id={self.id}, refcode='{self.refcode}')>"


# Rate limiting хранится в Redis (rate_limiter.py)
# Ключи: rate_limit:{api_key}:{window_start}
# TTL: автоматическое истечение по окончании окна


class Currency(Base):
    """
    Кэш поддерживаемых валют.
    Заменяет: currency_validator.py -> self._memory_cache
    """
    __tablename__ = "currencies"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    code = Column(String(20), unique=True, nullable=False, index=True)
    coin = Column(String(20), nullable=False)
    network = Column(String(50), nullable=False)
    name = Column(String(100), nullable=False)
    recv = Column(Boolean, default=False)  # Доступна для получения
    send = Column(Boolean, default=False)  # Доступна для отправки
    tag = Column(String(50))  # Название тега (Memo, etc.)
    logo = Column(String(500))
    color = Column(String(7))  # #RRGGBB
    priority = Column(Integer, default=0)
    decimals = Column(Integer, default=8)  # Точность валюты
    min_amount = Column(Numeric(28, 18))
    max_amount = Column(Numeric(28, 18))
    is_active = Column(Boolean, default=True, index=True)
    cached_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # Relationships
    directions_from = relationship("ExchangeDirection", foreign_keys="ExchangeDirection.from_currency_id", back_populates="from_currency")
    directions_to = relationship("ExchangeDirection", foreign_keys="ExchangeDirection.to_currency_id", back_populates="to_currency")
    saved_addresses = relationship("SavedAddress", back_populates="currency")
    
    def __repr__(self):
        return f"<Currency(code='{self.code}', name='{self.name}')>"
    
    def to_dict(self) -> Dict[str, Any]:
        """Конвертация в словарь"""
        return {
            "code": self.code,
            "coin": self.coin,
            "network": self.network,
            "name": self.name,
            "recv": self.recv,
            "send": self.send,
            "tag": self.tag,
            "logo": self.logo,
            "color": self.color,
            "priority": self.priority,
            "decimals": self.decimals,
        }


class ExchangeDirection(Base):
    """
    Направления обмена с кастомными настройками.
    Позволяет переопределять лимиты и комиссии для конкретных пар.
    """
    __tablename__ = "exchange_directions"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    from_currency_id = Column(Integer, ForeignKey("currencies.id", ondelete="CASCADE"), nullable=False)
    to_currency_id = Column(Integer, ForeignKey("currencies.id", ondelete="CASCADE"), nullable=False)
    is_active = Column(Boolean, default=True, index=True)
    
    # Лимиты
    min_amount = Column(Numeric(28, 18))
    max_amount = Column(Numeric(28, 18))
    
    # Кастомные комиссии
    extra_fee_percent = Column(Numeric(5, 4), default=0)
    extra_fee_fixed = Column(Numeric(28, 18), default=0)
    
    # Приоритет и отображение
    priority = Column(Integer, default=0)
    is_featured = Column(Boolean, default=False)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # Relationships
    from_currency = relationship("Currency", foreign_keys=[from_currency_id], back_populates="directions_from")
    to_currency = relationship("Currency", foreign_keys=[to_currency_id], back_populates="directions_to")
    orders = relationship("Order", back_populates="direction")
    
    # Constraints
    __table_args__ = (
        UniqueConstraint("from_currency_id", "to_currency_id", name="unique_direction"),
    )
    
    def __repr__(self):
        return f"<ExchangeDirection(id={self.id}, from={self.from_currency_id}, to={self.to_currency_id})>"


class SavedAddress(Base):
    """
    Сохраненные адреса для повторных обменов.
    """
    __tablename__ = "saved_addresses"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    currency_id = Column(Integer, ForeignKey("currencies.id", ondelete="CASCADE"), nullable=False, index=True)
    address = Column(String(255), nullable=False, index=True)
    tag = Column(String(100))
    label = Column(String(100))
    is_verified = Column(Boolean, default=False)
    use_count = Column(Integer, default=0)
    last_used_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    currency = relationship("Currency", back_populates="saved_addresses")
    orders = relationship("Order", back_populates="saved_address")
    
    # Constraints
    __table_args__ = (
        UniqueConstraint("currency_id", "address", "tag", name="unique_address_per_currency"),
    )
    
    def __repr__(self):
        return f"<SavedAddress(id={self.id}, address='{self.address[:10]}...', label='{self.label}')>"


class Order(Base):
    """
    Ордера на обмен криптовалют.
    """
    __tablename__ = "orders"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    external_id = Column(String(50), unique=True, nullable=False, index=True)
    short_id = Column(String(12), unique=True, nullable=False, index=True)  # Короткий ID для пользователей
    token = Column(String(100), nullable=False)
    api_credential_id = Column(Integer, ForeignKey("api_credentials.id", ondelete="SET NULL"), nullable=True, index=True)
    partner_id = Column(Integer, ForeignKey("partners.id", ondelete="SET NULL"), nullable=True, index=True)
    direction_id = Column(Integer, ForeignKey("exchange_directions.id", ondelete="SET NULL"), nullable=True, index=True)
    
    # Тип и статус
    order_type = Column(Enum(ExchangeType), nullable=False)
    status = Column(Enum(OrderStatus), nullable=False, default=OrderStatus.NEW, index=True)
    
    # Валюты и суммы
    from_currency = Column(String(20), nullable=False)
    to_currency = Column(String(20), nullable=False)
    from_amount = Column(Numeric(28, 18), nullable=False)
    to_amount = Column(Numeric(28, 18), nullable=False)
    
    # Адреса
    from_address = Column(String(255), nullable=False)
    to_address = Column(String(255), nullable=False)
    from_tag = Column(String(100))
    to_tag = Column(String(100))
    saved_address_id = Column(Integer, ForeignKey("saved_addresses.id", ondelete="SET NULL"), nullable=True)
    
    # Партнерская информация
    refcode = Column(String(50), index=True)
    afftax = Column(Numeric(5, 2))
    partner_commission = Column(Numeric(28, 18))
    
    # Контактная информация
    email = Column(String(255))
    
    # Клиентская информация (для аналитики)
    client_ip = Column(String(45))  # IPv6 compatible
    client_user_agent = Column(Text)
    
    # Временные метки
    time_reg = Column(DateTime(timezone=True))
    time_start = Column(DateTime(timezone=True))
    time_finish = Column(DateTime(timezone=True))
    time_expiration = Column(DateTime(timezone=True))
    
    # Метаданные
    metadata = Column(JSON, default=dict)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # Relationships
    api_credential = relationship("ApiCredential", back_populates="orders")
    partner = relationship("Partner", back_populates="orders")
    direction = relationship("ExchangeDirection", back_populates="orders")
    saved_address = relationship("SavedAddress", back_populates="orders")
    price = relationship("OrderPrice", back_populates="order", uselist=False, cascade="all, delete-orphan")
    transactions = relationship("OrderTransaction", back_populates="order", cascade="all, delete-orphan")
    emergency_actions = relationship("EmergencyAction", back_populates="order", cascade="all, delete-orphan")
    email_notifications = relationship("EmailNotification", back_populates="order", cascade="all, delete-orphan")
    status_history = relationship("OrderStatusHistory", back_populates="order", cascade="all, delete-orphan")
    
    # Indexes
    __table_args__ = (
        Index("idx_orders_currencies", "from_currency", "to_currency"),
        Index("idx_orders_status_created", "status", "created_at"),
        Index("idx_orders_credential_status", "api_credential_id", "status"),
    )
    
    def __repr__(self):
        return f"<Order(id={self.id}, short_id='{self.short_id}', status={self.status.value})>"


class OrderPrice(Base):
    """
    Snapshot курсов на момент создания ордера.
    Сохраняет актуальные цены при создании обмена.
    """
    __tablename__ = "order_prices"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, unique=True)
    
    # Исходная валюта (from)
    from_code = Column(String(20), nullable=False)
    from_coin = Column(String(20))
    from_network = Column(String(50))
    from_amount = Column(Numeric(28, 18), nullable=False)
    from_rate = Column(Numeric(28, 18), nullable=False)
    from_precision = Column(Integer)
    from_min = Column(Numeric(28, 18))
    from_max = Column(Numeric(28, 18))
    from_usd = Column(Numeric(28, 18))
    
    # Целевая валюта (to)
    to_code = Column(String(20), nullable=False)
    to_coin = Column(String(20))
    to_network = Column(String(50))
    to_amount = Column(Numeric(28, 18), nullable=False)
    to_rate = Column(Numeric(28, 18), nullable=False)
    to_precision = Column(Integer)
    to_min = Column(Numeric(28, 18))
    to_max = Column(Numeric(28, 18))
    to_usd = Column(Numeric(28, 18))
    
    # Общая информация о курсе
    exchange_rate = Column(Numeric(28, 18), nullable=False)
    rate_type = Column(Enum(ExchangeType), nullable=False)
    
    # Комиссии
    service_fee = Column(Numeric(28, 18))
    network_fee = Column(Numeric(28, 18))
    total_fee = Column(Numeric(28, 18))
    fee_currency = Column(String(20))
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    order = relationship("Order", back_populates="price")
    
    # Indexes
    __table_args__ = (
        Index("idx_order_prices_currencies", "from_code", "to_code"),
    )
    
    def __repr__(self):
        return f"<OrderPrice(order_id={self.order_id}, rate={self.exchange_rate})>"


class OrderStatusHistory(Base):
    """
    История изменений статусов ордера.
    """
    __tablename__ = "order_status_history"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True)
    old_status = Column(Enum(OrderStatus), nullable=True)  # NULL для первой записи
    new_status = Column(Enum(OrderStatus), nullable=False)
    changed_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    comment = Column(Text)
    metadata = Column(JSON, default=dict)
    
    # Relationships
    order = relationship("Order", back_populates="status_history")
    
    def __repr__(self):
        old = self.old_status.value if self.old_status else "NULL"
        return f"<OrderStatusHistory(order_id={self.order_id}, {old} -> {self.new_status.value})>"


class OrderTransaction(Base):
    """
    Транзакции ордеров (входящие, исходящие, возвраты).
    """
    __tablename__ = "order_transactions"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True)
    direction = Column(Enum(TransactionDirection), nullable=False)
    
    # Данные транзакции
    tx_hash = Column(String(255), index=True)
    amount = Column(Numeric(28, 18))
    fee = Column(Numeric(28, 18))
    fee_currency = Column(String(20))
    
    # Временные метки
    time_reg = Column(DateTime(timezone=True))
    time_block = Column(DateTime(timezone=True))
    
    # Подтверждения
    confirmations = Column(Integer, default=0)
    required_confirmations = Column(Integer)
    max_confirmations = Column(Integer)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # Relationships
    order = relationship("Order", back_populates="transactions")
    
    def __repr__(self):
        return f"<OrderTransaction(order_id={self.order_id}, direction={self.direction.value})>"


class EmergencyAction(Base):
    """
    История аварийных действий по ордерам.
    """
    __tablename__ = "emergency_actions"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True)
    choice = Column(Enum(EmergencyChoice), nullable=False)
    
    # Данные для возврата
    refund_address = Column(String(255))
    refund_tag = Column(String(100))
    
    # Результат
    status = Column(String(50), nullable=False)
    message = Column(Text)
    
    # Метаданные
    request_data = Column(JSON)
    response_data = Column(JSON)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    order = relationship("Order", back_populates="emergency_actions")
    
    def __repr__(self):
        return f"<EmergencyAction(order_id={self.order_id}, choice={self.choice.value})>"


class EmailNotification(Base):
    """
    Подписки на email уведомления по ордерам.
    """
    __tablename__ = "email_notifications"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True)
    email = Column(String(255), nullable=False)
    status = Column(String(50), default="pending", index=True)  # pending, sent, failed
    sent_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    order = relationship("Order", back_populates="email_notifications")
    
    def __repr__(self):
        return f"<EmailNotification(order_id={self.order_id}, email='{self.email}')>"


class AuditLog(Base):
    """
    Аудит всех действий в системе.
    """
    __tablename__ = "audit_log"
    
    id = Column(BigInteger, primary_key=True, autoincrement=True)
    api_credential_id = Column(Integer, ForeignKey("api_credentials.id", ondelete="SET NULL"), nullable=True, index=True)
    
    # Информация о запросе
    request_id = Column(String(36), index=True)
    action = Column(String(100), nullable=False, index=True)
    endpoint = Column(String(255))
    method = Column(String(10))
    
    # Данные запроса/ответа
    request_data = Column(JSON)
    response_code = Column(Integer)
    response_data = Column(JSON)
    
    # Клиентская информация
    ip_address = Column(String(45))  # IPv6 compatible
    user_agent = Column(Text)
    
    # Дополнительные данные
    duration_ms = Column(Integer)
    error_message = Column(Text)
    metadata = Column(JSON, default=dict)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    
    # Relationships
    api_credential = relationship("ApiCredential", back_populates="audit_logs")
    
    # Indexes
    __table_args__ = (
        Index("idx_audit_credential_action_created", "api_credential_id", "action", "created_at"),
    )
    
    def __repr__(self):
        return f"<AuditLog(id={self.id}, action='{self.action}')>"


class SystemSetting(Base):
    """
    Системные настройки (key-value).
    """
    __tablename__ = "system_settings"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    key = Column(String(100), unique=True, nullable=False, index=True)
    value = Column(Text)
    value_type = Column(String(20), default="string")  # string, integer, boolean, json
    description = Column(Text)
    is_encrypted = Column(Boolean, default=False)
    updated_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    def __repr__(self):
        return f"<SystemSetting(key='{self.key}')>"
    
    def get_typed_value(self) -> Any:
        """Получение значения с правильным типом"""
        if self.value is None:
            return None
        
        if self.value_type == "integer":
            return int(self.value)
        elif self.value_type == "boolean":
            return self.value.lower() in ("true", "1", "yes")
        elif self.value_type == "json":
            import json
            return json.loads(self.value)
        else:
            return self.value


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def create_all_tables(engine):
    """Создание всех таблиц"""
    Base.metadata.create_all(engine)


def drop_all_tables(engine):
    """Удаление всех таблиц"""
    Base.metadata.drop_all(engine)
