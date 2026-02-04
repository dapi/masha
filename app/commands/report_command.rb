# frozen_string_literal: true

# Unified report command supporting flexible period, filters, and format options.
# Replaces /day, /summary, /hours commands with single comprehensive interface.
#
# Usage:
#   /report                                    # Today, summary format
#   /report week                               # Current week, summary
#   /report month project:work-project         # Month filtered by project
#   /report yesterday detailed                 # Yesterday with descriptions
#   /report 2025-01-01:2025-01-31 detailed     # Date range, detailed
class ReportCommand < BaseCommand
  def call(*args)
    # Check for help request
    return show_help if args.first == 'help'

    # Parse command parameters
    params = parse_params(args)

    # Build report data
    builder = ReportBuilder.new(
      user: current_user,
      period: params[:period],
      filters: params[:filters]
    )
    report_data = builder.build

    # Format output
    formatter = ReportFormatter.new(report_data, format: params[:format])
    text = formatter.format_report

    # Send response
    respond_with :message, text: code(text), parse_mode: :Markdown
  rescue InvalidPeriodError => e
    show_error_with_help(e)
  end

  private

  def parse_params(args)
    params = {
      period: :today,
      filters: {},
      format: :summary
    }

    return params if args.empty?

    # Join args to handle split text
    text = args.join(' ')

    # Extract format option (detailed)
    if text.match?(/\bdetailed\b/i)
      params[:format] = :detailed
      text = text.gsub(/\bdetailed\b/i, '').strip
    end

    # Extract project filter
    if (match = text.match(/project:([a-z0-9_-]+)/i))
      params[:filters][:project] = match[1]
      text = text.gsub(/project:[a-z0-9_-]+/i, '').strip
    end

    # Extract projects filter (multiple)
    if (match = text.match(/projects:([\w\s,_-]+)/i))
      params[:filters][:projects] = match[1].strip
      text = text.gsub(/projects:[\w\s,_-]+/i, '').strip
    end

    # Parse period from remaining text
    period_text = text.strip.downcase

    params[:period] = parse_period(period_text) unless period_text.empty?

    params
  end

  def parse_period(text)
    case text
    when 'today'
      :today
    when 'yesterday'
      :yesterday
    when 'week'
      :week
    when 'month'
      :month
    when 'quarter'
      :quarter
    when /^\d{4}-\d{2}-\d{2}$/
      # Single date format YYYY-MM-DD - validate date
      validate_date!(text)
      text
    when /^\d{4}-\d{2}-\d{2}:\d{4}-\d{2}-\d{2}$/
      # Date range format YYYY-MM-DD:YYYY-MM-DD - validate dates
      validate_date_range!(text)
      text
    else
      raise InvalidPeriodError.new(
        I18n.t('telegram.commands.report.errors.unrecognized_period', period: text),
        period_string: text
      )
    end
  end

  def validate_date!(date_string)
    Date.parse(date_string)
  rescue Date::Error
    raise InvalidPeriodError.new(
      I18n.t('telegram.commands.report.errors.invalid_date', date: date_string),
      period_string: date_string
    )
  end

  def validate_date_range!(range_string)
    start_date_str, end_date_str = range_string.split(':')
    begin
      start_date = Date.parse(start_date_str)
    rescue Date::Error
      raise InvalidPeriodError.new(
        I18n.t('telegram.commands.report.errors.invalid_date', date: start_date_str),
        period_string: range_string
      )
    end
    begin
      end_date = Date.parse(end_date_str)
    rescue Date::Error
      raise InvalidPeriodError.new(
        I18n.t('telegram.commands.report.errors.invalid_date', date: end_date_str),
        period_string: range_string
      )
    end
    return unless start_date > end_date

    raise InvalidPeriodError.new(
      I18n.t('telegram.commands.report.errors.start_after_end'),
      period_string: range_string
    )
  end

  def show_help
    help_formatter = ReportHelpFormatter.new
    text = help_formatter.main_help
    keyboard = help_formatter.main_keyboard

    respond_with :message,
                 text: text,
                 reply_markup: keyboard
  end

  def show_error_with_help(error)
    help_formatter = ReportHelpFormatter.new
    error_text = "#{I18n.t('telegram.commands.report.errors.title')}\n#{error.message}\n\n#{help_formatter.main_help}"
    keyboard = help_formatter.main_keyboard

    respond_with :message,
                 text: error_text,
                 reply_markup: keyboard
  end

  # Callback query methods - один метод для каждого раздела справки
  def report_periods_callback_query
    help_formatter = ReportHelpFormatter.new
    text = help_formatter.periods_help
    keyboard = help_formatter.navigation_keyboard('periods')

    edit_message :text, text: text, reply_markup: keyboard
    safe_answer_callback_query
  end

  def report_filters_callback_query
    help_formatter = ReportHelpFormatter.new
    text = help_formatter.filters_help
    keyboard = help_formatter.navigation_keyboard('filters')

    edit_message :text, text: text, reply_markup: keyboard
    safe_answer_callback_query
  end

  def report_options_callback_query
    help_formatter = ReportHelpFormatter.new
    text = help_formatter.options_help
    keyboard = help_formatter.navigation_keyboard('options')

    edit_message :text, text: text, reply_markup: keyboard
    safe_answer_callback_query
  end

  def report_examples_callback_query
    help_formatter = ReportHelpFormatter.new
    text = help_formatter.examples_help
    keyboard = help_formatter.navigation_keyboard('examples')

    edit_message :text, text: text, reply_markup: keyboard
    safe_answer_callback_query
  end

  def report_main_callback_query
    help_formatter = ReportHelpFormatter.new
    text = help_formatter.main_help
    keyboard = help_formatter.main_keyboard

    edit_message :text, text: text, reply_markup: keyboard
    safe_answer_callback_query
  end
end
