# frozen_string_literal: true

class ProjectsCommand < BaseCommand
  provides_context_methods(
    :awaiting_project_name,
    :awaiting_rename_title,
    :awaiting_rename_slug,
    :awaiting_rename_both,
    :awaiting_rename_both_step_two,
    :awaiting_client_name,
    :awaiting_client_delete_confirm,
    :awaiting_delete_confirm
  )

  # Context constants
  CONTEXT_AWAITING_PROJECT_NAME = :awaiting_project_name
  CONTEXT_AWAITING_RENAME_TITLE = :awaiting_rename_title
  CONTEXT_AWAITING_RENAME_SLUG = :awaiting_rename_slug
  CONTEXT_AWAITING_RENAME_BOTH = :awaiting_rename_both
  CONTEXT_AWAITING_RENAME_BOTH_STEP_TWO = :awaiting_rename_both_step_two
  CONTEXT_AWAITING_CLIENT_NAME = :awaiting_client_name
  CONTEXT_AWAITING_CLIENT_DELETE_CONFIRM = :awaiting_client_delete_confirm
  CONTEXT_AWAITING_DELETE_CONFIRM = :awaiting_delete_confirm
  CONTEXT_CURRENT_PROJECT = :current_project_slug
  CONTEXT_RENAME_ACTION = :rename_action
  CONTEXT_SUGGESTED_SLUG = :suggested_slug

  def call(*args)
    return respond_with :message, text: t('commands.projects.unauthorized') unless current_user

    if args.empty?
      show_projects_list
    else
      # Обратная совместимость со старым форматом
      handle_legacy_create_format(args)
    end
  end

  # Callback query methods - каждый тип callback имеет свой метод
  def projects_create_callback_query(_data = nil)
    start_project_creation
  end

  def projects_select_callback_query(data = nil)
    return handle_missing_callback_data(:projects_select) unless data

    show_project_menu(data)
  end

  def projects_list_callback_query(_data = nil)
    show_projects_list
  end

  def projects_rename_callback_query(data = nil)
    return handle_missing_callback_data(:projects_rename) unless data

    show_rename_menu(data)
  end

  def projects_rename_title_callback_query(data = nil)
    return handle_missing_callback_data(:projects_rename_title) unless data

    start_rename_title(data)
  end

  def projects_rename_slug_callback_query(data = nil)
    return handle_missing_callback_data(:projects_rename_slug) unless data

    start_rename_slug(data)
  end

  def projects_rename_both_callback_query(data = nil)
    return handle_missing_callback_data(:projects_rename_both) unless data

    start_rename_both(data)
  end

  def projects_rename_use_suggested_callback_query(data = nil)
    return handle_missing_callback_data(:projects_rename_use_suggested) unless data

    # Получаем suggested_slug из session, data содержит только slug
    suggested_slug = session[:suggested_slug]
    use_suggested_slug(data, suggested_slug)
  end

  def projects_client_callback_query(data = nil)
    return handle_missing_callback_data(:projects_client) unless data

    show_client_menu(data)
  end

  def projects_client_edit_callback_query(data = nil)
    return handle_missing_callback_data(:projects_client_edit) unless data

    start_client_edit(data)
  end

  def projects_client_delete_callback_query(data = nil)
    return handle_missing_callback_data(:projects_client_delete) unless data

    confirm_client_deletion(data)
  end

  def projects_client_delete_confirm_callback_query(data = nil)
    return handle_missing_callback_data(:projects_client_delete_confirm) unless data

    delete_client(data)
  end

  def projects_delete_callback_query(data = nil)
    return handle_missing_callback_data(:projects_delete) unless data

    confirm_project_deletion(data)
  end

  def projects_delete_confirm_callback_query(data = nil)
    return handle_missing_callback_data(:projects_delete_confirm) unless data

    request_deletion_confirmation(data)
  end

  # Context methods - обработка текстовых сообщений
  def awaiting_project_name(*name_parts)
    name = name_parts.join(' ').strip
    return respond_with :message, text: t('commands.projects.create.cancelled') if cancel_input?(name)
    return respond_with :message, text: t('commands.projects.create.error', reason: 'Название не может быть пустым') if name.blank?

    if name.length > 100
      return respond_with :message,
                          text: t('commands.projects.create.error', reason: 'Название слишком длинное (макс 100)')
    end

    slug = Project.generate_unique_slug(name)
    unless slug
      return respond_with :message,
                          text: t('commands.projects.create.error', reason: 'Не удалось сгенерировать уникальный идентификатор')
    end

    project = Project.new(title: name, slug: slug)
    if project.save
      Membership.create!(user: current_user, project: project, role: :owner)
      respond_with :message, text: t('commands.projects.create.success', title: project.title, slug: project.slug)
      show_projects_list
    else
      respond_with :message, text: t('commands.projects.create.error', reason: project.errors.full_messages.join(', '))
    end
  end

  def awaiting_rename_title(*title_parts)
    new_title = title_parts.join(' ').strip
    return handle_cancel_input :rename_title if cancel_input?(new_title)
    return respond_with :message, text: t('commands.projects.rename.error') if new_title.blank?

    current_slug = session[:current_project_slug]
    project = current_user.projects.find_by(slug: current_slug)
    return show_projects_list unless project

    old_title = project.title
    text = if project.update(title: new_title)
             t('commands.projects.rename.success_title', old_title: old_title, new_title: new_title)
           else
             t('commands.projects.rename.error')
           end

    session.delete(:current_project_slug)
    respond_with :message, text: text
    show_project_menu(current_slug)
  end

  def awaiting_rename_slug(*slug_parts)
    new_slug = slug_parts.join(' ').strip
    return handle_cancel_input :rename_slug if cancel_input?(new_slug)

    current_slug = session[:current_project_slug]
    project = current_user.projects.find_by(slug: current_slug)
    return show_projects_list unless project

    return respond_with :message, text: t('commands.projects.rename.slug_invalid') if invalid_slug?(new_slug)

    # Проверка уникальности
    if Project.where.not(id: project.id).exists?(slug: new_slug)
      return respond_with :message, text: t('commands.projects.rename.slug_taken', slug: new_slug)
    end

    old_slug = project.slug
    result = project.update(slug: new_slug)
    session.delete(:current_project_slug)

    if result
      text = t('commands.projects.rename.success_slug', old_slug: old_slug, new_slug: new_slug)
      respond_with :message, text: text
      show_project_menu(new_slug)
    else
      error_message = project.errors.full_messages.join(', ')
      error_message = t('commands.projects.rename.error_unknown') if error_message.blank?
      respond_with :message, text: t('commands.projects.rename.error_with_reason', reason: error_message)
      show_project_menu(old_slug)
    end
  end

  def awaiting_rename_both(*title_parts)
    new_title = title_parts.join(' ').strip
    return handle_cancel_input :rename_both if cancel_input?(new_title)
    return respond_with :message, text: t('commands.projects.rename.error') if new_title.blank?

    current_slug = session[:current_project_slug]
    project = current_user.projects.find_by(slug: current_slug)
    return show_projects_list unless project

    # Сохраняем новое название и просим slug
    session[:new_project_title] = new_title

    # Генерируем предложенный slug
    suggested_slug = Project.generate_unique_slug(new_title)
    session[:suggested_slug] = suggested_slug

    save_context(CONTEXT_AWAITING_RENAME_BOTH_STEP_TWO)

    text = t('commands.projects.rename.enter_slug',
             current_slug: current_slug)
    text += t('commands.projects.rename.suggested_slug_hint', slug: suggested_slug)

    buttons = [
      [{ text: t('commands.projects.rename.use_suggested'),
         callback_data: "projects_rename_use_suggested:#{current_slug}" }]
    ]

    respond_with :message, text: text,
                           reply_markup: { inline_keyboard: buttons }
  end

  def awaiting_rename_both_step_two(*slug_parts)
    new_slug = slug_parts.join(' ').strip
    return handle_cancel_input :rename_both if cancel_input?(new_slug)

    current_slug = session[:current_project_slug]
    new_title = session[:new_project_title]
    project = current_user.projects.find_by(slug: current_slug)
    return show_projects_list unless project && new_title

    return respond_with :message, text: t('commands.projects.rename.slug_invalid') if invalid_slug?(new_slug)

    # Проверка уникальности
    if Project.where.not(id: project.id).exists?(slug: new_slug)
      return respond_with :message, text: t('commands.projects.rename.slug_taken', slug: new_slug)
    end

    update_project_both(project, new_title, new_slug)
  end

  def awaiting_client_name(*name_parts)
    client_name = name_parts.join(' ').strip
    return handle_cancel_input :client_name if cancel_input?(client_name)

    current_slug = session[:current_project_slug]
    project = current_user.projects.find_by(slug: current_slug)
    return show_projects_list unless project

    return respond_with :message, text: t('commands.projects.client.error') if client_name.blank?
    return respond_with :message, text: t('commands.projects.client.error') if client_name.length > 255

    # Ищем или создаем клиента
    client = Client.find_or_create_by(user: current_user, name: client_name) do |c|
      c.key = client_name.parameterize
    end

    old_client = project.client&.name || t('commands.projects.menu.no_client')
    text = if project.update(client: client)
             t('commands.projects.client.success', old_client: old_client, new_client: client_name)
           else
             t('commands.projects.client.error')
           end

    session.delete(:current_project_slug)
    respond_with :message, text: text
    show_client_menu(current_slug)
  end

  def awaiting_client_delete_confirm(*parts)
    confirmation = parts.join(' ').strip
    return handle_cancel_input :client_delete if cancel_input?(confirmation)

    # Пользователь может подтвердить любым сообщением кроме "cancel"
    current_slug = session[:current_project_slug]
    project = current_user.projects.find_by(slug: current_slug)
    return show_projects_list unless project

    text = if project.update(client: nil)
             t('commands.projects.client.delete_success')
           else
             t('commands.projects.client.error')
           end

    session.delete(:current_project_slug)
    respond_with :message, text: text
    show_client_menu(current_slug)
  end

  def awaiting_delete_confirm(*parts)
    confirmation = parts.join(' ').strip
    return handle_cancel_input :delete if cancel_input?(confirmation)

    current_slug = session[:current_project_slug]
    project = current_user.projects.find_by(slug: current_slug)
    return show_projects_list unless project

    # Проверяем что пользователь ввел название проекта
    if confirmation != project.title
      respond_with :message, text: t('commands.projects.delete.title_mismatch')
      show_project_menu(current_slug)
      return
    end

    # Удаляем проект
    project_title = project.title
    project.destroy
    session.delete(:current_project_slug)
    respond_with :message, text: t('commands.projects.delete.success', title: project_title)
    show_projects_list
  end

  private

  def cancel_input?(text)
    text.downcase == 'cancel'
  end

  def handle_cancel_input(context_type)
    current_slug = session[:current_project_slug]
    clear_session_data

    case context_type
    when :rename_title, :rename_slug, :rename_both
      respond_with :message, text: t('commands.projects.rename.cancelled')
      show_project_menu(current_slug)
    when :client_name, :client_delete
      respond_with :message, text: t('commands.projects.client.cancelled')
      show_client_menu(current_slug)
    when :delete
      respond_with :message, text: t('commands.projects.delete.cancelled')
      show_project_menu(current_slug)
    end
  end

  def clear_session_data
    session.delete(:current_project_slug)
    session.delete(:new_project_title)
    session.delete(:suggested_slug)
  end

  def show_projects_list
    projects = current_user.projects.active.alphabetically.limit(30)

    buttons = []
    # Кнопка "Добавить проект" - занимает всю ширину
    buttons << [{ text: t('commands.projects.add_button'), callback_data: 'projects_create:' }]

    # Группируем проекты по 3 в ряд
    project_buttons = projects.map do |project|
      {
        text: project.slug.truncate(15, omission: '...'),
        callback_data: "projects_select:#{project.slug}"
      }
    end

    # Добавляем кнопки проектов группами по 3
    project_buttons.each_slice(3) do |row|
      buttons << row
    end

    respond_with :message, text: t('commands.projects.title'), reply_markup: {
      inline_keyboard: buttons
    }
  end

  def start_project_creation
    save_context(CONTEXT_AWAITING_PROJECT_NAME)
    respond_with :message, text: t('commands.projects.create.enter_name')
  end

  def show_project_menu(slug)
    project = current_user.projects.find_by(slug: slug)
    return show_projects_list unless project

    can_manage = project.can_be_managed_by?(current_user)

    client_text = project.client&.name || t('commands.projects.menu.no_client')
    menu_text = t('commands.projects.menu.title',
                  title: project.title,
                  slug: project.slug,
                  client: client_text)

    buttons = if can_manage
                [
                  [{ text: t('commands.projects.menu.rename_button'), callback_data: "projects_rename:#{slug}" }],
                  [{ text: t('commands.projects.menu.client_button'), callback_data: "projects_client:#{slug}" }],
                  [{ text: t('commands.projects.menu.delete_button'), callback_data: "projects_delete:#{slug}" }],
                  [{ text: t('commands.projects.menu.back_button'), callback_data: 'projects_list:' }]
                ]
              else
                [
                  [{ text: t('commands.projects.menu.owner_only') }],
                  [{ text: t('commands.projects.menu.back_button'), callback_data: 'projects_list:' }]
                ]
              end

    respond_with :message, text: menu_text,
                           reply_markup: {
                             inline_keyboard: buttons
                           }
  end

  def show_rename_menu(slug)
    project = current_user.projects.find_by(slug: slug)
    return show_projects_list unless project&.can_be_managed_by?(current_user)

    menu_text = t('commands.projects.rename.menu_title', title: project.title)
    buttons = [
      [{ text: t('commands.projects.rename.title_button'), callback_data: "projects_rename_title:#{slug}" }],
      [{ text: t('commands.projects.rename.slug_button'), callback_data: "projects_rename_slug:#{slug}" }],
      [{ text: t('commands.projects.rename.both_button'), callback_data: "projects_rename_both:#{slug}" }],
      [{ text: t('commands.projects.rename.cancel_button'), callback_data: "projects_select:#{slug}" }]
    ]

    respond_with :message, text: menu_text,
                           reply_markup: {
                             inline_keyboard: buttons
                           }
  end

  def start_rename_title(slug)
    project = current_user.projects.find_by(slug: slug)
    return show_projects_list unless project&.can_be_managed_by?(current_user)

    session[:current_project_slug] = slug
    save_context(CONTEXT_AWAITING_RENAME_TITLE)

    text = t('commands.projects.rename.enter_title',
             current_title: project.title)
    respond_with :message, text: text
  end

  def start_rename_slug(slug)
    project = current_user.projects.find_by(slug: slug)
    return show_projects_list unless project&.can_be_managed_by?(current_user)

    session[:current_project_slug] = slug
    save_context(CONTEXT_AWAITING_RENAME_SLUG)

    text = t('commands.projects.rename.enter_slug',
             current_slug: project.slug)
    respond_with :message, text: text
  end

  def start_rename_both(slug)
    project = current_user.projects.find_by(slug: slug)
    return show_projects_list unless project&.can_be_managed_by?(current_user)

    session[:current_project_slug] = slug
    save_context(CONTEXT_AWAITING_RENAME_BOTH)

    text = t('commands.projects.rename.enter_title',
             current_title: project.title)
    respond_with :message, text: text
  end

  def start_client_edit(slug)
    project = current_user.projects.find_by(slug: slug)
    return show_projects_list unless project&.can_be_managed_by?(current_user)

    session[:current_project_slug] = slug
    save_context(CONTEXT_AWAITING_CLIENT_NAME)

    current_client = project.client&.name || t('commands.projects.menu.no_client')
    text = t('commands.projects.client.enter_name',
             current_client: current_client)
    respond_with :message, text: text
  end

  def confirm_client_deletion(slug)
    project = current_user.projects.find_by(slug: slug)
    return show_projects_list unless project&.can_be_managed_by?(current_user)

    return show_client_menu(slug) unless project.client

    session[:current_project_slug] = slug
    save_context(CONTEXT_AWAITING_CLIENT_DELETE_CONFIRM)

    text = t('commands.projects.client.confirm_delete',
             client_name: project.client.name)
    buttons = [
      [{ text: t('commands.projects.client.delete_confirm_yes'), callback_data: "projects_client_delete_confirm:#{slug}" }],
      [{ text: t('commands.projects.client.delete_cancel'), callback_data: "projects_client:#{slug}" }]
    ]

    respond_with :message, text: text,
                           reply_markup: {
                             inline_keyboard: buttons
                           }
  end

  def confirm_project_deletion(slug)
    project = current_user.projects.find_by(slug: slug)
    return show_projects_list unless project&.can_be_managed_by?(current_user)

    session[:current_project_slug] = slug
    stats = project.deletion_stats

    text = t('commands.projects.delete.confirm_first',
             title: project.title,
             time_shifts: stats[:time_shifts_count],
             memberships: stats[:memberships_count],
             invites: stats[:invites_count])

    buttons = [
      [{ text: t('commands.projects.delete.confirm_yes'), callback_data: "projects_delete_confirm:#{slug}" }],
      [{ text: t('commands.projects.delete.confirm_cancel'), callback_data: "projects_select:#{slug}" }]
    ]

    respond_with :message, text: text,
                           reply_markup: {
                             inline_keyboard: buttons
                           }
  end

  def request_deletion_confirmation(slug)
    project = current_user.projects.find_by(slug: slug)
    return show_projects_list unless project&.can_be_managed_by?(current_user)

    session[:current_project_slug] = slug
    save_context(CONTEXT_AWAITING_DELETE_CONFIRM)

    text = t('commands.projects.delete.confirm_final',
             title: project.title)
    respond_with :message, text: text
  end

  def show_client_menu(slug)
    project = current_user.projects.find_by(slug: slug)
    return show_projects_list unless project&.can_be_managed_by?(current_user)

    current_client = project.client&.name || t('commands.projects.menu.no_client')
    text = t('commands.projects.client.menu_title',
             project_title: project.title,
             client_name: current_client)

    buttons = [
      [{ text: t('commands.projects.client.edit_button'), callback_data: "projects_client_edit:#{slug}" }]
    ]

    # Кнопка удаления клиента только если клиент установлен
    buttons << [{ text: t('commands.projects.client.delete_button'), callback_data: "projects_client_delete:#{slug}" }] if project.client

    buttons << [{ text: t('commands.projects.menu.back_button'), callback_data: "projects_select:#{slug}" }]

    respond_with :message, text: text,
                           reply_markup: {
                             inline_keyboard: buttons
                           }
  end

  def use_suggested_slug(slug, suggested_slug)
    project = current_user.projects.find_by(slug: slug)
    return show_projects_list unless project&.can_be_managed_by?(current_user)

    # Получаем новое название из session (должно быть сохранено перед этим)
    new_title = session[:new_project_title]
    return show_projects_list unless new_title

    update_project_both(project, new_title, suggested_slug)
  end

  def handle_legacy_create_format(args)
    # Обратная совместимость: /projects create slug или /projects create
    if args[0] == 'create'
      if args[1]
        # Явное создание: /projects create my-slug
        create_project_legacy(args[1])
      else
        # Интерактивное создание: /projects create
        start_project_creation
      end
    else
      # Неизвестное действие
      respond_with :message, text: t('commands.projects.unknown_action')
    end
  end

  def create_project_legacy(slug)
    # Проверка авторизации
    return respond_with :message, text: t('commands.projects.unauthorized') unless current_user

    # Валидация входных данных
    return respond_with :message, text: t('commands.projects.create.error', reason: 'Slug не может быть пустым') if slug.blank?
    return respond_with :message, text: t('commands.projects.rename.slug_invalid') if invalid_slug?(slug)

    # Проверка уникальности slug
    return respond_with :message, text: t('commands.projects.rename.slug_taken', slug: slug) if Project.exists?(slug: slug)

    # Для совместимости со старым форматом
    project = Project.new(title: slug, slug: slug)
    if project.save
      Membership.create!(user: current_user, project: project, role: :owner)
      respond_with :message, text: t('commands.projects.create.success',
                                     title: project.title,
                                     slug: project.slug)
    else
      respond_with :message, text: t('commands.projects.create.error',
                                     reason: project.errors.full_messages.join(', '))
    end
  end

  def update_project_both(project, new_title, new_slug)
    # Валидация нового slug
    return show_error_message(t('commands.projects.rename.slug_invalid')) if invalid_slug?(new_slug)

    # Проверка уникальности нового slug (исключая текущий проект)
    if Project.where.not(id: project.id).exists?(slug: new_slug)
      return show_error_message(t('commands.projects.rename.slug_taken', slug: new_slug))
    end

    old_title = project.title
    old_slug = project.slug

    if project.update(title: new_title, slug: new_slug)
      clear_session_data

      text = t('commands.projects.rename.success_both',
               old_title: old_title,
               new_title: new_title,
               old_slug: old_slug,
               new_slug: new_slug)
      respond_with :message, text: text
      show_project_menu(new_slug)
    else
      show_error_message(t('commands.projects.rename.error'))
    end
  end

  def delete_client(slug)
    project = current_user.projects.find_by(slug: slug)
    return show_projects_list unless project&.can_be_managed_by?(current_user)

    if project.update(client: nil)
      respond_with :message, text: t('commands.projects.client.delete_success')
      show_client_menu(slug)
    else
      show_error_message(t('commands.projects.client.delete_error'))
    end
  end

  def show_error_message(message)
    respond_with :message, text: message
  end

  def handle_missing_callback_data(callback_name)
    Bugsnag.notify(RuntimeError.new("#{callback_name}_callback_query called without data"))
    respond_with :message, text: t('commands.projects.unknown_action')
  end

  def invalid_slug?(slug)
    slug.blank? || slug.length > 15 || slug.match?(/[^a-z0-9-]/) || slug.match?(/^-|-$/)
  end
end
