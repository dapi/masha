# Спецификация: Команда /invite для Telegram бота

## Обзор

Команда `/invite` генерирует одноразовую ссылку-приглашение в проект. Любой пользователь, перешедший по ссылке, автоматически присоединяется к проекту.

## Контекст

### Текущее состояние
- Модель `Invite` хранит приглашения по email/telegram_username
- Команда `/users add @username` добавляет конкретного известного пользователя
- Нет механизма создания invite-ссылок через Telegram

### Проблема
Нельзя пригласить человека, если не знаешь его telegram username. Нужен механизм:
1. Создать ссылку `t.me/MashTimeBot?start=invite_TOKEN`
2. Отправить ссылку человеку (в чате, мессенджере, email)
3. Человек переходит → автоматически в проекте

## Функциональные требования

### FR-1: Создание приглашения

**Команда:** `/invite {project_slug} [role]`

**Параметры:**
- `project_slug` — обязательный, slug проекта
- `role` — опциональный, по умолчанию `member`. Доступные: `owner`, `viewer`, `member`

**Поведение:**
1. Если пользователь не авторизован → ошибка
2. Если проект не найден или пользователь не owner → ошибка доступа
3. Генерируется уникальный токен (16 символов, URL-safe)
4. Создается запись InviteLink со сроком действия 7 дней
5. Возвращается сообщение со ссылкой

**Пример:**
```
/invite my-project

✅ Приглашение создано!

🔗 Ссылка: t.me/MashTimeBot?start=invite_Abc123XyZ789
📁 Проект: my-project
👤 Роль: member
⏰ Действует до: 13 февраля 2026

⚠️ Ссылка одноразовая — после использования станет недействительной.
```

**Интерактивный режим:**
Если вызвать `/invite` без параметров:
1. Показать inline keyboard со списком проектов (где пользователь owner)
2. После выбора проекта — показать выбор роли
3. После выбора роли — сгенерировать ссылку

### FR-2: Просмотр активных приглашений

**Команда:** `/invite list`

**Поведение:**
1. Показать все активные (неиспользованные, не истёкшие) invite-ссылки пользователя
2. Группировка по проектам

**Формат вывода:**
```
📨 Активные приглашения:

📁 my-project:
  • member — истекает через 3 дня
    t.me/MashTimeBot?start=invite_Abc123

📁 another-project:
  • owner — истекает через 6 дней
    t.me/MashTimeBot?start=invite_Xyz789

💡 Отозвать: /invite cancel {token}
```

### FR-3: Отзыв приглашения

**Команда:** `/invite cancel {token}`

**Поведение:**
1. Найти приглашение по токену (только свои)
2. Удалить запись
3. Подтверждение

**Пример:**
```
/invite cancel Abc123XyZ789

✅ Приглашение отозвано.
```

### FR-4: Обработка перехода по ссылке

**Deep link:** `t.me/MashTimeBot?start=invite_TOKEN`

**Поведение в StartCommand:**
1. Распарсить параметр `invite_TOKEN`
2. Найти InviteLink по токену
3. Проверки:
   - Токен существует
   - Не истёк срок (7 дней)
   - Не использован
4. Если проверки прошли:
   - Создать/найти User для telegram_user
   - Добавить в проект с указанной ролью
   - Пометить invite как использованный
   - Сообщение: "Вы добавлены в проект X!"
5. Если ошибка:
   - "Приглашение недействительно или истекло"

### FR-5: Справка

**Команда:** `/invite help`

```
📨 *Приглашения в проект:*

/invite {project} [role] — Создать ссылку-приглашение
/invite list — Показать активные приглашения
/invite cancel {token} — Отозвать приглашение
/invite help — Эта справка

*Роли:* owner, viewer, member (по умолчанию)

*Особенности:*
• Ссылка одноразовая
• Действует 7 дней
```

## Технический дизайн

### Новая модель: InviteLink

```ruby
# db/migrate/xxx_create_invite_links.rb
create_table :invite_links do |t|
  t.references :user, null: false        # кто создал
  t.references :project, null: false     # в какой проект
  t.string :token, null: false           # уникальный токен
  t.string :role, null: false            # роль для приглашаемого
  t.datetime :expires_at, null: false    # срок действия
  t.datetime :used_at                    # когда использовано (null = не использовано)
  t.references :invited_user             # кто воспользовался
  t.timestamps

  t.index :token, unique: true
end
```

### Модель InviteLink

```ruby
class InviteLink < ApplicationRecord
  belongs_to :user                    # создатель
  belongs_to :project
  belongs_to :invited_user, class_name: 'User', optional: true

  validates :token, presence: true, uniqueness: true
  validates :role, presence: true, inclusion: { in: Membership.roles.keys }
  validates :expires_at, presence: true

  scope :active, -> { where(used_at: nil).where('expires_at > ?', Time.current) }
  scope :by_user, ->(user) { where(user: user) }

  before_validation :generate_token, on: :create
  before_validation :set_expires_at, on: :create

  def active?
    used_at.nil? && expires_at > Time.current
  end

  def use!(invited_user)
    update!(used_at: Time.current, invited_user: invited_user)
  end

  def telegram_link
    "t.me/#{ApplicationConfig.telegram_bot_username}?start=invite_#{token}"
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(12)
  end

  def set_expires_at
    self.expires_at ||= 7.days.from_now
  end
end
```

### Новые файлы
- `app/models/invite_link.rb`
- `db/migrate/xxx_create_invite_links.rb`
- `app/commands/invite_command.rb`
- `spec/models/invite_link_spec.rb`
- `spec/controllers/telegram/webhook/invite_command_spec.rb`

### Изменения в существующих файлах
- `app/commands/start_command.rb` — обработка `invite_TOKEN` в deep link
- `config/locales/ru.yml` — ключи `commands.invite.*`

### Структура InviteCommand

```ruby
class InviteCommand < BaseCommand
  provides_context_methods :invite_select_role

  def call(action = nil, *args)
    case action
    when nil
      create_invite_interactive
    when 'list'
      list_invites
    when 'cancel'
      cancel_invite(args.first)
    when 'help'
      show_help
    else
      # action = project_slug
      create_invite(action, args.first)
    end
  end

  # Callback handlers
  def invite_project_callback_query(project_slug)
  def invite_role_callback_query(role)
end
```

## Acceptance Criteria

### AC-1: Создание приглашения
- [ ] `/invite project-slug` создает ссылку с ролью member
- [ ] `/invite project-slug owner` создает ссылку с ролью owner
- [ ] Только owner проекта может создавать приглашения
- [ ] Токен уникальный, 16 символов
- [ ] Срок действия 7 дней

### AC-2: Интерактивное создание
- [ ] `/invite` показывает список проектов
- [ ] После выбора проекта — выбор роли
- [ ] После выбора роли — генерация ссылки

### AC-3: Просмотр приглашений
- [ ] `/invite list` показывает активные приглашения
- [ ] Истёкшие и использованные не показываются

### AC-4: Отзыв приглашения
- [ ] `/invite cancel TOKEN` удаляет приглашение
- [ ] Нельзя отозвать чужое приглашение

### AC-5: Использование ссылки
- [ ] Переход по ссылке добавляет в проект
- [ ] Ссылка становится недействительной после использования
- [ ] Истёкшая ссылка не работает
- [ ] Повторное использование невозможно

## Миграция данных

Существующая модель `Invite` (по email/telegram_username) остается без изменений. Новая модель `InviteLink` работает параллельно.

## Оценка

- **Сложность:** Средняя
- **Новая модель + миграция:** InviteLink
- **Изменения:** StartCommand, локали
