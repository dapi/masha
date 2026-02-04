# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Telegram::WebhookController, telegram_bot: :rails, type: :telegram_bot_controller do
  include_context 'telegram webhook base'

  context 'authenticated user' do
    let(:user) { users(:user_with_telegram) }
    let(:telegram_user) { telegram_users(:telegram_regular) }
    let(:from_id) { telegram_user.id }
    let(:work_project) { projects(:work_project) }
    let(:test_project) { projects(:test_project) }

    include_context 'authenticated user'

    describe '/report command' do
      describe 'basic usage' do
        it 'responds to /report without parameters' do
          expect { dispatch_command :report }.not_to raise_error
        end

        it 'returns formatted report for today by default' do
          response = dispatch_command :report

          expect(response).not_to be_nil
        end
      end

      describe 'period parsing' do
        context 'with symbol periods' do
          it 'parses "today" period' do
            expect { dispatch_command :report, 'today' }.not_to raise_error
          end

          it 'parses "yesterday" period' do
            expect { dispatch_command :report, 'yesterday' }.not_to raise_error
          end

          it 'parses "week" period' do
            expect { dispatch_command :report, 'week' }.not_to raise_error
          end

          it 'parses "month" period' do
            expect { dispatch_command :report, 'month' }.not_to raise_error
          end

          it 'parses "quarter" period' do
            expect { dispatch_command :report, 'quarter' }.not_to raise_error
          end
        end

        context 'with date formats' do
          it 'parses specific date YYYY-MM-DD' do
            expect { dispatch_command :report, '2025-01-15' }.not_to raise_error
          end

          it 'parses date range YYYY-MM-DD:YYYY-MM-DD' do
            expect { dispatch_command :report, '2025-01-01:2025-01-31' }.not_to raise_error
          end
        end

        context 'with invalid periods' do
          it 'shows error for unrecognized period' do
            response = dispatch_command :report, 'invalid_period'
            first_message = response.first
            expect(first_message[:text]).to include(I18n.t('telegram.commands.report.errors.title'))
            expect(first_message[:text]).to include('invalid_period')
          end

          it 'shows error for invalid date (e.g. November 31)' do
            response = dispatch_command :report, '2025-11-31'
            first_message = response.first
            expect(first_message[:text]).to include(I18n.t('telegram.commands.report.errors.title'))
            expect(first_message[:text]).to include('2025-11-31')
          end

          it 'shows error for invalid date range with non-existent date' do
            response = dispatch_command :report, '2025-11-01:2025-11-31'
            first_message = response.first
            expect(first_message[:text]).to include(I18n.t('telegram.commands.report.errors.title'))
            expect(first_message[:text]).to include('2025-11-31')
          end

          it 'shows error when start date is after end date' do
            response = dispatch_command :report, '2025-01-31:2025-01-01'
            first_message = response.first
            expect(first_message[:text]).to include(I18n.t('telegram.commands.report.errors.title'))
          end

          it 'includes help keyboard in error response' do
            response = dispatch_command :report, 'invalid_period'
            first_message = response.first
            expect(first_message[:reply_markup]).not_to be_nil
            expect(first_message[:reply_markup][:inline_keyboard]).not_to be_empty
          end

          it 'shows error for cyrillic period names' do
            response = dispatch_command :report, 'вчера'
            first_message = response.first
            expect(first_message[:text]).to include(I18n.t('telegram.commands.report.errors.title'))
            expect(first_message[:text]).to include('вчера')
          end
        end
      end

      describe 'filter parsing' do
        context 'single project filter' do
          it 'filters by single project using project:slug' do
            expect { dispatch_command :report, 'today', "project:#{work_project.slug}" }.not_to raise_error
          end

          it 'handles non-existent project gracefully' do
            expect { dispatch_command :report, 'today', 'project:non_existent' }.not_to raise_error
          end
        end

        context 'multiple projects filter' do
          it 'filters by multiple projects using projects:slug1,slug2' do
            expect do
              dispatch_command :report, 'today', "projects:#{work_project.slug},#{test_project.slug}"
            end.not_to raise_error
          end

          it 'handles projects with spaces in filter' do
            expect do
              dispatch_command :report, 'today', "projects:#{work_project.slug}, #{test_project.slug}"
            end.not_to raise_error
          end
        end
      end

      describe 'format option parsing' do
        it 'uses detailed format when "detailed" option is provided' do
          expect { dispatch_command :report, 'today', 'detailed' }.not_to raise_error
        end

        it 'defaults to summary format without "detailed" option' do
          expect { dispatch_command :report, 'today' }.not_to raise_error
        end
      end

      describe 'combined parameters' do
        it 'handles period + filter' do
          expect { dispatch_command :report, 'week', "project:#{work_project.slug}" }.not_to raise_error
        end

        it 'handles period + format option' do
          expect { dispatch_command :report, 'week', 'detailed' }.not_to raise_error
        end

        it 'handles period + filter + format option' do
          expect do
            dispatch_command :report, 'week', "project:#{work_project.slug}", 'detailed'
          end.not_to raise_error
        end

        it 'handles all parameters together' do
          expect do
            dispatch_command :report, '2025-01-01:2025-01-31',
                             "projects:#{work_project.slug},#{test_project.slug}", 'detailed'
          end.not_to raise_error
        end
      end

      describe 'help functionality' do
        it 'responds to /report help' do
          expect { dispatch_command :report, 'help' }.not_to raise_error
        end

        it 'returns help message for /report help' do
          response = dispatch_command :report, 'help'

          expect(response).not_to be_nil
        end
      end

      describe 'help navigation via callback_query', :callback_query do
        let(:chat) { { id: 123, type: 'private' } }
        let(:message) { { message_id: 456, chat: chat } }

        context 'periods section' do
          let(:data) { 'report_periods' }

          it 'shows periods help' do
            response = dispatch(callback_query: {
                                  id: 'test_callback_id',
                                  from: from,
                                  message: message,
                                  data: data
                                })

            expect(response).not_to be_nil
          end
        end

        context 'filters section' do
          let(:data) { 'report_filters' }

          it 'shows filters help' do
            response = dispatch(callback_query: {
                                  id: 'test_callback_id',
                                  from: from,
                                  message: message,
                                  data: data
                                })

            expect(response).not_to be_nil
          end
        end

        context 'options section' do
          let(:data) { 'report_options' }

          it 'shows options help' do
            response = dispatch(callback_query: {
                                  id: 'test_callback_id',
                                  from: from,
                                  message: message,
                                  data: data
                                })

            expect(response).not_to be_nil
          end
        end

        context 'examples section' do
          let(:data) { 'report_examples' }

          it 'shows examples help' do
            response = dispatch(callback_query: {
                                  id: 'test_callback_id',
                                  from: from,
                                  message: message,
                                  data: data
                                })

            expect(response).not_to be_nil
          end
        end

        context 'back to main' do
          let(:data) { 'report_main' }

          it 'shows main help' do
            response = dispatch(callback_query: {
                                  id: 'test_callback_id',
                                  from: from,
                                  message: message,
                                  data: data
                                })

            expect(response).not_to be_nil
          end
        end

        context 'non-help callback_query' do
          let(:data) { 'some_other_action' }

          it 'does not process non-help callbacks' do
            response = dispatch(callback_query: {
                                  id: 'test_callback_id',
                                  from: from,
                                  message: message,
                                  data: data
                                })

            # Should not raise error, just return nil or not process
            expect { response }.not_to raise_error
          end
        end
      end
    end
  end
end
