# frozen_string_literal: true

# Строит структурированные данные для отчетов на основе временных записей пользователя.
# Поддерживает фильтрацию по периодам и проектам, а также группировку данных.
class ReportBuilder
  attr_reader :user, :period, :filters, :options

  def initialize(user:, period: :today, filters: {}, options: {})
    @user = user
    @period = period
    @filters = filters
    @options = options
  end

  def build
    {
      period: parse_period,
      total_hours: calculate_total_hours,
      entries: fetch_entries,
      grouped_by_project: group_by_project,
      grouped_by_day: group_by_day
    }
  end

  private

  def parse_period
    case period
    when :today, 'today'
      { from: Date.current, to: Date.current }
    when :yesterday, 'yesterday'
      { from: Date.yesterday, to: Date.yesterday }
    when :week, 'week'
      { from: Date.current.beginning_of_week, to: Date.current.end_of_week }
    when :month, 'month'
      { from: Date.current.beginning_of_month, to: Date.current.end_of_month }
    when :quarter, 'quarter'
      { from: 3.months.ago.to_date, to: Date.current }
    else
      # Для строк с датами используем существующий PeriodParser
      if period.is_a?(String)
        parse_period_string(period)
      else
        { from: Date.current, to: Date.current }
      end
    end
  end

  def parse_period_string(period_string)
    # Парсинг дат в формате YYYY-MM-DD или YYYY-MM-DD:YYYY-MM-DD
    if period_string.match?(/^\d{4}-\d{2}-\d{2}$/)
      # Одна дата
      date = Date.parse(period_string)
      { from: date, to: date }
    elsif period_string.match?(/^\d{4}-\d{2}-\d{2}:\d{4}-\d{2}-\d{2}$/)
      # Диапазон дат
      start_date, end_date = period_string.split(':').map { |d| Date.parse(d) }
      { from: start_date, to: end_date }
    else
      raise InvalidPeriodError.new(
        I18n.t('telegram.commands.report.errors.unrecognized_period', period: period_string),
        period_string: period_string
      )
    end
  rescue Date::Error
    raise InvalidPeriodError.new(
      I18n.t('telegram.commands.report.errors.invalid_date', date: period_string),
      period_string: period_string
    )
  end

  def base_scope
    period_range = parse_period
    user.time_shifts
        .includes(:project)
        .where(date: period_range[:from]..period_range[:to])
        .order(date: :desc, created_at: :desc)
  end

  def fetch_entries
    scope = base_scope

    # Фильтрация по проекту
    if filters[:project].present?
      project = find_project(filters[:project])
      # Если проект не найден, вернуть пустой scope
      scope = project ? scope.where(project: project) : scope.none
    elsif filters[:projects].present?
      # Фильтрация по нескольким проектам
      project_slugs = filters[:projects].split(',').map(&:strip)
      projects = find_projects(project_slugs)
      # Если ни один проект не найден, вернуть пустой scope
      scope = projects.any? ? scope.where(project: projects) : scope.none
    end

    scope.map do |time_shift|
      {
        date: time_shift.date,
        project: time_shift.project,
        hours: time_shift.hours,
        description: time_shift.description
      }
    end
  end

  def calculate_total_hours
    fetch_entries.sum { |entry| entry[:hours] }
  end

  def group_by_project
    entries = fetch_entries
    grouped = entries.group_by { |entry| entry[:project].slug }

    grouped.transform_values do |project_entries|
      {
        hours: project_entries.sum { |e| e[:hours] },
        count: project_entries.count
      }
    end
  end

  def group_by_day
    entries = fetch_entries
    grouped = entries.group_by { |entry| entry[:date] }

    grouped.transform_values do |day_entries|
      {
        hours: day_entries.sum { |e| e[:hours] },
        count: day_entries.count
      }
    end
  end

  def find_project(project_slug)
    user.available_projects.alive.find_by(slug: project_slug)
  end

  def find_projects(project_slugs)
    user.available_projects.alive.where(slug: project_slugs)
  end
end
