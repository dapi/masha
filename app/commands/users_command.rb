# frozen_string_literal: true

class UsersCommand < BaseCommand
  provides_context_methods :users_add_project, :users_add_username_input

  def call(action = nil, *)
    case action
    when nil, 'help'
      show_users_help
    when 'projects', 'list'
      show_project_users
    when 'all'
      show_all_users
    when 'add'
      users_add(*)
    when 'remove'
      users_remove(*)
    else
      respond_with :message, text: 'Неизвестная подкоманда. Используйте /users для подсказки'
    end
  end

  def show_project_users
    if current_user.nil?
      respond_with :message, text: t('errors.auth_required')
      return
    end

    projects = current_user.available_projects.alive

    if projects.empty?
      respond_with :message, text: 'У вас нет доступных проектов'
      return
    end

    if projects.one?
      show_users_for_project(projects.first)
    else
      respond_with :message,
                   text: 'Выберите проект для просмотра пользователей:',
                   reply_markup: {
                     inline_keyboard: projects.map { |p| [{ text: p.slug, callback_data: "users_list_project:#{p.slug}" }] }
                   }
    end
  end

  def show_all_users
    return respond_with :message, text: 'Эта команда доступна только разработчику системы' unless developer?

    # Для разработчика current_user может быть nil, это нормально
    # Загружаем все проекты для каждого пользователя, чтобы отфильтровать active в памяти
    users = User.includes(:telegram_user, :projects).all
    users_text = users.map { |user| format_user_info(user) }.join("\n\n")

    respond_with :message, text: users_text.presence || 'Пользователи не найдены', parse_mode: :Markdown
  end

  def users_add(project_slug = nil, username = nil, role = 'member', *)
    if current_user.nil?
      respond_with :message, text: t('errors.auth_required')
      return
    end

    return show_manageable_projects_for_add if project_slug.blank?

    return respond_with :message, text: 'Укажите никнейм пользователя (например: @username или username)' if username.blank?

    TelegramProjectManager.new(current_user, controller: controller)
                          .add_user_to_project(project_slug, username, role)
  end

  def users_remove(_project_slug = nil, _username = nil, *)
    respond_with :message, text: 'Функция удаления пользователей пока не реализована'
  end

  def show_users_help
    help_text = <<~HELP
      *Управление пользователями:*
      /users - Эта подсказка
      /users projects - Показать пользователей проекта
      /users all - Показать всех пользователей (только для разработчика)
      /users add {project} {username} [role] - Добавить пользователя в проект
      /users remove {project} {username} - Удалить пользователя из проекта

      *Роли пользователей:*
      owner - владелец проекта
      viewer - наблюдатель
      member - участник
    HELP

    respond_with :message, text: help_text, parse_mode: :Markdown
  end

  def show_users_for_project(project)
    memberships = project.memberships.includes(user: :telegram_user).order(:role_cd, :created_at)

    if memberships.empty?
      respond_with :message, text: "В проекте '#{project.slug}' нет пользователей"
      return
    end

    users_text = memberships.map do |membership|
      user = membership.user
      telegram_user = user.telegram_user
      status = telegram_user ? "(@#{telegram_user.username})" : '(нет Telegram)'
      "#{user.name || user.email} #{status} - #{membership.role}"
    end.join("\n")

    respond_with :message, text: "Пользователи проекта '#{project.slug}':\n\n#{users_text}"
  end

  def show_manageable_projects_for_add
    manageable_projects = current_user.available_projects.alive
                                      .joins(:memberships)
                                      .merge(Membership.owners.where(user: current_user))

    return respond_with :message, text: 'У вас нет проектов, в которые можно добавить пользователей' if manageable_projects.empty?

    respond_with :message,
                 text: 'Выберите проект, в который хотите добавить пользователя:',
                 reply_markup: {
                   inline_keyboard: manageable_projects.map { |p| [{ text: p.slug, callback_data: "users_add_project:#{p.slug}" }] }
                 }
  end

  # Public methods needed by BaseCommand
  def multiline(*args)
    args.flatten.map(&:to_s).join("\n")
  end

  def format_user_info(user)
    telegram_info = user.telegram_user ? "(@#{user.telegram_user.username})" : ''
    # Фильтруем активные проекты в памяти, чтобы не делать дополнительные SQL-запросы
    alive_projects = user.projects.select(&:active?)
    projects_info = alive_projects.any? ? "Проекты: #{alive_projects.map(&:slug).join(', ')}" : ''
    "*#{user.name || user.email}*#{telegram_info}\n#{projects_info}"
  end

  # Context methods for interactive add user workflow (must be public)
  def users_add_project(project_slug)
    users_add(project_slug)
  end

  def users_add_username_input(username, *)
    username = username.delete_prefix('@') if username.start_with?('@')
    tg_session = telegram_session
    tg_session[:username] = username
    self.telegram_session = tg_session

    respond_with :message,
                 text: "Пользователь: @#{username}\nВыберите роль для пользователя:",
                 reply_markup: {
                   inline_keyboard: [
                     [{ text: 'Владелец (owner)', callback_data: 'users_add_role:owner' }],
                     [{ text: 'Наблюдатель (viewer)', callback_data: 'users_add_role:viewer' }],
                     [{ text: 'Участник (member)', callback_data: 'users_add_role:member' }]
                   ]
                 }
  end

  def users_add_project_callback_query(project_slug)
    if current_user.nil?
      edit_message :text, text: t('errors.auth_required')
      return safe_answer_callback_query('❌ Требуется авторизация', show_alert: true)
    end

    project = find_project(project_slug)
    unless project
      edit_message :text, text: 'Проект не найден'
      safe_answer_callback_query('❌ Ошибка: проект не найден', show_alert: true)
      return
    end

    # Check permissions - only owners can add users
    membership = current_user.membership_of(project)
    unless membership&.owner?
      edit_message :text, text: 'У вас нет прав для добавления пользователей в этот проект, только владелец (owner) может это сделать.'
      safe_answer_callback_query('❌ Ошибка доступа', show_alert: true)
      return
    end

    self.telegram_session = TelegramSession.users_add_user(project_slug: project_slug)
    save_context :users_add_username_input
    edit_message :text, text: "Проект: #{project.slug}\nТеперь введите никнейм пользователя (например: @username или username):"
    safe_answer_callback_query('✅ Проект выбран')
  end

  def users_add_role_callback_query(role)
    if current_user.nil?
      edit_message :text, text: t('errors.auth_required')
      return safe_answer_callback_query('❌ Требуется авторизация', show_alert: true)
    end

    safe_answer_callback_query('✅ Роль выбрана')

    data = telegram_session_data
    project_slug = data['project_slug']
    username = data['username']

    # Clean up session
    clear_telegram_session

    edit_message :text, text: "Добавляем пользователя @#{username} в проект #{project_slug} с ролью #{role}..."

    add_user_to_project(project_slug, username, role)
  end

  def users_list_project_callback_query(project_slug)
    if current_user.nil?
      edit_message :text, text: t('errors.auth_required')
      return safe_answer_callback_query('❌ Требуется авторизация', show_alert: true)
    end

    project = find_project(project_slug)
    if project
      show_users_for_project(project)
      safe_answer_callback_query('✅ Проект выбран')
    else
      edit_message :text, text: 'Проект не найден'
      safe_answer_callback_query('❌ Ошибка: проект не найден', show_alert: true)
    end
  end

  # Public methods needed for delegation
  def add_user_to_project(project_slug, username, role)
    TelegramProjectManager.new(current_user, controller: controller)
                          .add_user_to_project(project_slug, username, role)
  end
end
