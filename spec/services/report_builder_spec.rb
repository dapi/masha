# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReportBuilder do
  let(:user) { users(:user_with_telegram) }

  describe '#initialize' do
    it 'accepts required parameters' do
      builder = ReportBuilder.new(user: user)
      expect(builder).to be_a(ReportBuilder)
    end

    it 'sets default values' do
      builder = ReportBuilder.new(user: user)
      expect(builder.period).to eq(:today)
      expect(builder.filters).to eq({})
      expect(builder.options).to eq({})
    end

    it 'accepts period parameter' do
      builder = ReportBuilder.new(user: user, period: :week)
      expect(builder.period).to eq(:week)
    end

    it 'accepts filters parameter' do
      filters = { project: 'work-project' }
      builder = ReportBuilder.new(user: user, filters: filters)
      expect(builder.filters).to eq(filters)
    end

    it 'accepts options parameter' do
      options = { detailed: true }
      builder = ReportBuilder.new(user: user, options: options)
      expect(builder.options).to eq(options)
    end
  end

  describe 'period parsing' do
    around do |example|
      # Фиксируем текущую дату для предсказуемости тестов
      travel_to Date.new(2025, 1, 15) do
        example.run
      end
    end

    describe ':today period' do
      it 'parses :today symbol' do
        builder = ReportBuilder.new(user: user, period: :today)
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 1, 15))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 15))
      end

      it 'parses "today" string' do
        builder = ReportBuilder.new(user: user, period: 'today')
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 1, 15))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 15))
      end
    end

    describe ':yesterday period' do
      it 'parses :yesterday symbol' do
        builder = ReportBuilder.new(user: user, period: :yesterday)
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 1, 14))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 14))
      end

      it 'parses "yesterday" string' do
        builder = ReportBuilder.new(user: user, period: 'yesterday')
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 1, 14))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 14))
      end
    end

    describe ':week period' do
      it 'parses :week symbol' do
        builder = ReportBuilder.new(user: user, period: :week)
        result = builder.build

        # 2025-01-15 это среда, неделя начинается с понедельника 2025-01-13
        expect(result[:period][:from]).to eq(Date.new(2025, 1, 13))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 19))
      end

      it 'parses "week" string' do
        builder = ReportBuilder.new(user: user, period: 'week')
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 1, 13))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 19))
      end
    end

    describe ':month period' do
      it 'parses :month symbol' do
        builder = ReportBuilder.new(user: user, period: :month)
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 1, 1))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 31))
      end

      it 'parses "month" string' do
        builder = ReportBuilder.new(user: user, period: 'month')
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 1, 1))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 31))
      end
    end

    describe ':quarter period' do
      it 'parses :quarter symbol' do
        builder = ReportBuilder.new(user: user, period: :quarter)
        result = builder.build

        # Quarter = 3 месяца назад от текущей даты
        expect(result[:period][:from]).to eq(Date.new(2024, 10, 15))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 15))
      end

      it 'parses "quarter" string' do
        builder = ReportBuilder.new(user: user, period: 'quarter')
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2024, 10, 15))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 15))
      end
    end

    describe 'single date format' do
      it 'parses YYYY-MM-DD format' do
        builder = ReportBuilder.new(user: user, period: '2025-01-10')
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 1, 10))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 10))
      end

      it 'handles different months' do
        builder = ReportBuilder.new(user: user, period: '2024-12-25')
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2024, 12, 25))
        expect(result[:period][:to]).to eq(Date.new(2024, 12, 25))
      end
    end

    describe 'date range format' do
      it 'parses YYYY-MM-DD:YYYY-MM-DD format' do
        builder = ReportBuilder.new(user: user, period: '2025-01-01:2025-01-15')
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 1, 1))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 15))
      end

      it 'handles ranges across months' do
        builder = ReportBuilder.new(user: user, period: '2024-12-15:2025-01-15')
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2024, 12, 15))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 15))
      end

      it 'handles ranges across years' do
        builder = ReportBuilder.new(user: user, period: '2024-01-01:2025-01-01')
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2024, 1, 1))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 1))
      end
    end

    describe 'edge cases and error handling' do
      it 'raises InvalidPeriodError for invalid date string' do
        builder = ReportBuilder.new(user: user, period: 'invalid-date')

        expect { builder.build }.to raise_error(InvalidPeriodError)
      end

      it 'raises InvalidPeriodError for malformed date range' do
        builder = ReportBuilder.new(user: user, period: '2025-01-01:invalid')

        expect { builder.build }.to raise_error(InvalidPeriodError)
      end

      it 'falls back to today for unknown period type (symbol)' do
        builder = ReportBuilder.new(user: user, period: :unknown_period)
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 1, 15))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 15))
      end

      it 'raises InvalidPeriodError for invalid date in YYYY-MM-DD format' do
        builder = ReportBuilder.new(user: user, period: '2025-13-45')

        expect { builder.build }.to raise_error(InvalidPeriodError)
      end

      it 'handles nil period' do
        builder = ReportBuilder.new(user: user, period: nil)
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 1, 15))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 15))
      end

      it 'raises InvalidPeriodError for November 31st (non-existent date)' do
        builder = ReportBuilder.new(user: user, period: '2025-11-31')

        expect { builder.build }.to raise_error(InvalidPeriodError)
      end

      it 'raises InvalidPeriodError for date range with non-existent end date' do
        builder = ReportBuilder.new(user: user, period: '2025-11-01:2025-11-31')

        expect { builder.build }.to raise_error(InvalidPeriodError)
      end
    end
  end

  describe 'project filtering' do
    let(:work_project) { projects(:work_project) }
    let(:test_project) { projects(:test_project) }
    let(:personal_project) { projects(:personal_project) }

    describe 'single project filter' do
      it 'filters by single project slug' do
        builder = ReportBuilder.new(
          user: user,
          period: :today,
          filters: { project: work_project.slug }
        )
        result = builder.build

        # Проверяем что все записи относятся к указанному проекту
        result[:entries].each do |entry|
          expect(entry[:project].slug).to eq(work_project.slug)
        end
      end

      it 'returns empty results for non-existent project' do
        builder = ReportBuilder.new(
          user: user,
          period: :today,
          filters: { project: 'non-existent-project' }
        )
        result = builder.build

        expect(result[:entries]).to be_empty
        expect(result[:total_hours]).to eq(0)
      end
    end

    describe 'multiple projects filter' do
      it 'filters by multiple project slugs' do
        builder = ReportBuilder.new(
          user: user,
          period: :today,
          filters: { projects: "#{work_project.slug},#{test_project.slug}" }
        )
        result = builder.build

        # Проверяем что все записи относятся к указанным проектам
        project_slugs = result[:entries].map { |e| e[:project].slug }.uniq
        expect(project_slugs).to all(be_in([work_project.slug, test_project.slug]))
      end

      it 'handles projects with spaces around commas' do
        builder = ReportBuilder.new(
          user: user,
          period: :today,
          filters: { projects: "#{work_project.slug} , #{test_project.slug}" }
        )
        result = builder.build

        project_slugs = result[:entries].map { |e| e[:project].slug }.uniq
        expect(project_slugs).to all(be_in([work_project.slug, test_project.slug]))
      end

      it 'filters out non-existent projects from list' do
        builder = ReportBuilder.new(
          user: user,
          period: :today,
          filters: { projects: "#{work_project.slug},non-existent,#{test_project.slug}" }
        )
        result = builder.build

        # Должны вернуться только записи для существующих проектов
        project_slugs = result[:entries].map { |e| e[:project].slug }.uniq
        expect(project_slugs).to all(be_in([work_project.slug, test_project.slug]))
      end

      it 'returns empty results for all non-existent projects' do
        builder = ReportBuilder.new(
          user: user,
          period: :today,
          filters: { projects: 'non-existent-1,non-existent-2' }
        )
        result = builder.build

        expect(result[:entries]).to be_empty
        expect(result[:total_hours]).to eq(0)
      end
    end

    describe 'filter priority' do
      it 'uses single project filter when both filters present' do
        builder = ReportBuilder.new(
          user: user,
          period: :today,
          filters: {
            project: work_project.slug,
            projects: test_project.slug
          }
        )
        result = builder.build

        # Должен использоваться фильтр :project
        result[:entries].each do |entry|
          expect(entry[:project].slug).to eq(work_project.slug)
        end
      end
    end

    describe 'no filters' do
      it 'returns all user projects when no filter specified' do
        builder = ReportBuilder.new(user: user, period: :today)
        result = builder.build

        # Должны вернуться записи из всех доступных пользователю проектов
        project_slugs = result[:entries].map { |e| e[:project].slug }.uniq
        expect(project_slugs.length).to be > 1
      end
    end
  end

  describe 'data grouping' do
    describe 'group_by_project' do
      it 'groups entries by project slug' do
        builder = ReportBuilder.new(user: user, period: :today)
        result = builder.build

        grouped = result[:grouped_by_project]

        expect(grouped).to be_a(Hash)
        # Проверяем что ключи - это slug проектов
        expect(grouped.keys).to all(be_a(String))
      end

      it 'calculates total hours per project' do
        builder = ReportBuilder.new(user: user, period: :today)
        result = builder.build

        grouped = result[:grouped_by_project]

        # Каждый проект должен иметь hours и count
        grouped.each do |_slug, data|
          expect(data).to have_key(:hours)
          expect(data).to have_key(:count)
          expect(data[:hours]).to be_a(Numeric)
          expect(data[:count]).to be_a(Integer)
          expect(data[:hours]).to be >= 0
          expect(data[:count]).to be_positive
        end
      end

      it 'returns correct count of entries per project' do
        work_project = projects(:work_project)

        builder = ReportBuilder.new(
          user: user,
          period: :today,
          filters: { project: work_project.slug }
        )
        result = builder.build

        grouped = result[:grouped_by_project]

        # Должна быть одна группа для work_project
        expect(grouped.keys).to eq([work_project.slug])

        # Количество записей должно совпадать с общим количеством
        expect(grouped[work_project.slug][:count]).to eq(result[:entries].count)
      end

      it 'sums hours correctly per project' do
        work_project = projects(:work_project)

        builder = ReportBuilder.new(
          user: user,
          period: :today,
          filters: { project: work_project.slug }
        )
        result = builder.build

        grouped = result[:grouped_by_project]

        # Сумма часов в группировке должна совпадать с total_hours
        project_hours = grouped[work_project.slug][:hours]
        expect(project_hours).to eq(result[:total_hours])
      end

      it 'returns empty hash when no entries' do
        builder = ReportBuilder.new(
          user: user,
          period: :today,
          filters: { project: 'non-existent' }
        )
        result = builder.build

        grouped = result[:grouped_by_project]

        expect(grouped).to eq({})
      end

      it 'handles multiple projects correctly' do
        builder = ReportBuilder.new(user: user, period: :today)
        result = builder.build

        grouped = result[:grouped_by_project]

        # Должно быть несколько проектов
        expect(grouped.keys.length).to be > 1

        # Сумма часов всех проектов должна равняться total_hours
        total = grouped.values.sum { |data| data[:hours] }
        expect(total).to eq(result[:total_hours])
      end
    end

    describe 'group_by_day' do
      it 'groups entries by date' do
        builder = ReportBuilder.new(user: user, period: :week)
        result = builder.build

        grouped = result[:grouped_by_day]

        expect(grouped).to be_a(Hash)
        # Проверяем что ключи - это Date объекты
        expect(grouped.keys).to all(be_a(Date))
      end

      it 'calculates total hours per day' do
        builder = ReportBuilder.new(user: user, period: :week)
        result = builder.build

        grouped = result[:grouped_by_day]

        # Каждый день должен иметь hours и count
        grouped.each do |_date, data|
          expect(data).to have_key(:hours)
          expect(data).to have_key(:count)
          expect(data[:hours]).to be_a(Numeric)
          expect(data[:count]).to be_a(Integer)
          expect(data[:hours]).to be >= 0
          expect(data[:count]).to be_positive
        end
      end

      it 'returns correct count of entries per day' do
        builder = ReportBuilder.new(user: user, period: :today)
        result = builder.build

        grouped = result[:grouped_by_day]

        # Для today должна быть только одна дата
        expect(grouped.keys.length).to eq(1)
        expect(grouped.keys.first).to eq(Date.current)

        # Количество записей должно совпадать с общим количеством
        expect(grouped[Date.current][:count]).to eq(result[:entries].count)
      end

      it 'sums hours correctly per day' do
        builder = ReportBuilder.new(user: user, period: :today)
        result = builder.build

        grouped = result[:grouped_by_day]

        # Сумма часов для сегодня должна равняться total_hours
        today_hours = grouped[Date.current][:hours]
        expect(today_hours).to eq(result[:total_hours])
      end

      it 'returns empty hash when no entries' do
        builder = ReportBuilder.new(
          user: user,
          period: :today,
          filters: { project: 'non-existent' }
        )
        result = builder.build

        grouped = result[:grouped_by_day]

        expect(grouped).to eq({})
      end

      it 'handles multiple days correctly' do
        builder = ReportBuilder.new(user: user, period: :week)
        result = builder.build

        grouped = result[:grouped_by_day]

        # Сумма часов всех дней должна равняться total_hours
        total = grouped.values.sum { |data| data[:hours] }
        expect(total).to eq(result[:total_hours])
      end

      it 'sorts entries by date correctly' do
        builder = ReportBuilder.new(user: user, period: :week)
        result = builder.build

        # Записи должны быть отсортированы по дате по убыванию
        dates = result[:entries].map { |e| e[:date] }
        expect(dates).to eq(dates.sort.reverse)
      end
    end
  end

  describe 'month boundaries' do
    it 'handles end of month correctly' do
      travel_to Date.new(2025, 1, 31) do
        builder = ReportBuilder.new(user: user, period: :month)
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 1, 1))
        expect(result[:period][:to]).to eq(Date.new(2025, 1, 31))
      end
    end

    it 'handles February in leap year' do
      travel_to Date.new(2024, 2, 15) do
        builder = ReportBuilder.new(user: user, period: :month)
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2024, 2, 1))
        expect(result[:period][:to]).to eq(Date.new(2024, 2, 29))
      end
    end

    it 'handles February in non-leap year' do
      travel_to Date.new(2025, 2, 15) do
        builder = ReportBuilder.new(user: user, period: :month)
        result = builder.build

        expect(result[:period][:from]).to eq(Date.new(2025, 2, 1))
        expect(result[:period][:to]).to eq(Date.new(2025, 2, 28))
      end
    end
  end

  describe '#build' do
    let(:builder) { ReportBuilder.new(user: user, period: :today) }

    it 'returns report structure' do
      result = builder.build

      expect(result).to be_a(Hash)
      expect(result).to have_key(:period)
      expect(result).to have_key(:total_hours)
      expect(result).to have_key(:entries)
      expect(result).to have_key(:grouped_by_project)
      expect(result).to have_key(:grouped_by_day)
    end

    it 'includes period dates' do
      result = builder.build

      expect(result[:period]).to have_key(:from)
      expect(result[:period]).to have_key(:to)
      expect(result[:period][:from]).to be_a(Date)
      expect(result[:period][:to]).to be_a(Date)
    end

    it 'includes total hours as float' do
      result = builder.build

      expect(result[:total_hours]).to be_a(Numeric)
    end

    it 'includes entries array' do
      result = builder.build

      expect(result[:entries]).to be_an(Array)
    end

    context 'with entries' do
      before do
        # Используем существующие fixtures
        # user_with_telegram имеет записи: telegram_time_today, today_meeting, today_afternoon, today_morning
      end

      it 'includes entry details' do
        result = builder.build

        expect(result[:entries]).not_to be_empty
        entry = result[:entries].first

        expect(entry).to have_key(:date)
        expect(entry).to have_key(:project)
        expect(entry).to have_key(:hours)
        expect(entry).to have_key(:description)
        expect(entry[:date]).to be_a(Date)
        expect(entry[:project]).to be_a(Project)
        expect(entry[:hours]).to be_a(Numeric)
      end
    end

    it 'includes grouped_by_project hash' do
      result = builder.build

      expect(result[:grouped_by_project]).to be_a(Hash)
    end

    it 'includes grouped_by_day hash' do
      result = builder.build

      expect(result[:grouped_by_day]).to be_a(Hash)
    end
  end
end
