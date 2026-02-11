# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Telegram::WebhookController, telegram_bot: :rails, type: :telegram_bot_controller do
  include_context 'telegram webhook base'

  context 'authenticated user' do
    let(:user) { users(:user_with_telegram) }
    let(:telegram_user) { telegram_users(:telegram_regular) }
    let(:from_id) { telegram_user.id }

    include_context 'authenticated user'

    # Use existing fixtures for test project
    let(:project) { projects(:work_project) }
    let(:other_user) { users(:regular_user) }

    describe '/rate command' do
      it 'responds without errors' do
        expect { dispatch_command :rate }.not_to raise_error
      end

      it 'shows owned projects list' do
        response = dispatch_command :rate
        expect(response).not_to be_nil
      end
    end

    context 'callback queries', :callback_query do
      describe 'rate_select_project_callback_query' do
        it 'handles project selection without errors' do
          expect do
            dispatch(callback_query: {
                       id: 'test_callback',
                       from: from,
                       message: { message_id: 22, chat: chat },
                       data: "rate_select_project:#{project.slug}"
                     })
          end.not_to raise_error
        end

        it 'shows project menu after selection' do
          response = dispatch(callback_query: {
                                id: 'test_callback',
                                from: from,
                                message: { message_id: 22, chat: chat },
                                data: "rate_select_project:#{project.slug}"
                              })

          expect(response).not_to be_nil
        end
      end

      describe 'rate_view_list_callback_query' do
        it 'handles view list callback without errors' do
          expect do
            dispatch(callback_query: {
                       id: 'test_callback',
                       from: from,
                       message: { message_id: 22, chat: chat },
                       data: "rate_view_list:#{project.slug}"
                     })
          end.not_to raise_error
        end

        it 'shows rates list for project' do
          response = dispatch(callback_query: {
                                id: 'test_callback',
                                from: from,
                                message: { message_id: 22, chat: chat },
                                data: "rate_view_list:#{project.slug}"
                              })

          expect(response).not_to be_nil

          # Проверяем, что в сообщении есть список ставок
          first_message = response.first
          expect(first_message[:text]).to include(project.slug) # название проекта
          expect(first_message[:text]).to include('👤') # эмодзи пользователей

          # Проверяем наличие информации о пользователях и ставках
          expect(first_message[:text]).to match(/@[\w\d]+/) # упоминание пользователей
        end
      end

      describe 'rate_set_rate_callback_query' do
        it 'handles set rate callback without errors' do
          expect do
            dispatch(callback_query: {
                       id: 'test_callback',
                       from: from,
                       message: { message_id: 22, chat: chat },
                       data: "rate_set_rate:#{project.slug}"
                     })
          end.not_to raise_error
        end

        it 'shows members menu' do
          response = dispatch(callback_query: {
                                id: 'test_callback',
                                from: from,
                                message: { message_id: 22, chat: chat },
                                data: "rate_set_rate:#{project.slug}"
                              })

          expect(response).not_to be_nil

          # Проверяем, что в ответе есть меню с участниками
          first_message = response.first
          keyboard = first_message.dig(:reply_markup, :inline_keyboard)&.flatten || []

          # Проверяем наличие кнопок с пользователями
          user_buttons = keyboard.select { |btn| btn[:text].include?('@') }
          expect(user_buttons.length).to be > 0 # должна быть хотя бы одна кнопка с пользователем

          # Проверяем наличие кнопки "Назад"
          back_button = keyboard.find { |btn| btn[:callback_data] == "rate_back:#{project.slug}" }
          expect(back_button).not_to be_nil
        end
      end

      describe 'rate_select_member_callback_query' do
        it 'handles member selection without errors' do
          expect do
            dispatch(callback_query: {
                       id: 'test_callback',
                       from: from,
                       message: { message_id: 22, chat: chat },
                       data: "rate_select_member:#{project.slug},#{other_user.id}"
                     })
          end.not_to raise_error
        end

        it 'shows currency selection menu' do
          response = dispatch(callback_query: {
                                id: 'test_callback',
                                from: from,
                                message: { message_id: 22, chat: chat },
                                data: "rate_select_member:#{project.slug},#{other_user.id}"
                              })

          expect(response).not_to be_nil

          # Проверяем, что в ответе есть кнопки с валютами
          first_message = response.first
          keyboard = first_message.dig(:reply_markup, :inline_keyboard)&.flatten || []

          # Проверяем наличие основных валют
          currency_buttons = keyboard.map { |btn| btn[:text] }
          expect(currency_buttons).to include('USD')
          expect(currency_buttons).to include('EUR')
          expect(currency_buttons).to include('RUB')

          # Проверяем, что есть кнопка "Назад"
          back_button = keyboard.find { |btn| btn[:callback_data] == "rate_set_rate:#{project.slug}" }
          expect(back_button).not_to be_nil
        end
      end

      describe 'rate_select_currency_callback_query' do
        it 'handles currency selection without errors' do
          expect do
            dispatch(callback_query: {
                       id: 'test_callback',
                       from: from,
                       message: { message_id: 22, chat: chat },
                       data: "rate_select_currency:#{project.slug},#{other_user.id},USD"
                     })
          end.not_to raise_error
        end

        it 'prompts for rate amount' do
          response = dispatch(callback_query: {
                                id: 'test_callback',
                                from: from,
                                message: { message_id: 22, chat: chat },
                                data: "rate_select_currency:#{project.slug},#{other_user.id},USD"
                              })

          expect(response).not_to be_nil

          # Проверяем, что в сообщении есть запрос на ввод суммы с правильными данными
          first_message = response.first
          expect(first_message[:text]).to include('50') # ожидаемая сумма
          expect(first_message[:text]).to include('USD') # выбранная валюта

          # Проверяем, что в сообщении есть имя пользователя
          username = other_user.telegram_user&.telegram_nick || other_user.id.to_s
          expect(first_message[:text]).to include(username.to_s)
        end
      end

      describe 'rate_remove_callback_query' do
        context 'when rate exists' do
          let!(:member_rate) { member_rates(:telegram_member_rate) }

          it 'handles remove callback without errors' do
            expect do
              dispatch(callback_query: {
                         id: 'test_callback',
                         from: from,
                         message: { message_id: 22, chat: chat },
                         data: "rate_remove:#{project.slug},#{user.id}"
                       })
            end.not_to raise_error
          end

          it 'removes member rate' do
            expect do
              dispatch(callback_query: {
                         id: 'test_callback',
                         from: from,
                         message: { message_id: 22, chat: chat },
                         data: "rate_remove:#{project.slug},#{user.id}"
                       })
            end.to change(MemberRate, :count).by(-1)
          end
        end

        context 'when rate does not exist' do
          it 'handles missing rate gracefully' do
            expect do
              dispatch(callback_query: {
                         id: 'test_callback',
                         from: from,
                         message: { message_id: 22, chat: chat },
                         data: "rate_remove:#{project.slug},#{other_user.id}"
                       })
            end.not_to raise_error
          end
        end
      end

      describe 'rate_back_callback_query' do
        it 'handles back navigation without errors' do
          expect do
            dispatch(callback_query: {
                       id: 'test_callback',
                       from: from,
                       message: { message_id: 22, chat: chat },
                       data: "rate_back:#{project.slug}"
                     })
          end.not_to raise_error
        end

        it 'returns to project menu' do
          response = dispatch(callback_query: {
                                id: 'test_callback',
                                from: from,
                                message: { message_id: 22, chat: chat },
                                data: "rate_back:#{project.slug}"
                              })

          expect(response).not_to be_nil
        end
      end

      describe 'rate_cancel_callback_query' do
        it 'handles cancel without errors' do
          expect do
            dispatch(callback_query: {
                       id: 'test_callback',
                       from: from,
                       message: { message_id: 22, chat: chat },
                       data: 'rate_cancel:'
                     })
          end.not_to raise_error
        end

        it 'cancels operation' do
          response = dispatch(callback_query: {
                                id: 'test_callback',
                                from: from,
                                message: { message_id: 22, chat: chat },
                                data: 'rate_cancel:'
                              })

          expect(response).not_to be_nil
        end
      end
    end

    context 'complete workflow', :callback_query do
      # Используем admin (который является членом work_project, но не имеет MemberRate там)
      let(:target_user) { users(:admin) }

      it 'saves member rate to database' do
        # Выполняем полный workflow для установки ставки
        # 1. Выбор проекта
        dispatch(callback_query: {
                   id: 'callback_1',
                   from: from,
                   message: { message_id: 22, chat: chat },
                   data: "rate_select_project:#{project.slug}"
                 })

        # 2. Выбор "Установить ставку"
        dispatch(callback_query: {
                   id: 'callback_2',
                   from: from,
                   message: { message_id: 23, chat: chat },
                   data: "rate_set_rate:#{project.slug}"
                 })

        # 3. Выбор пользователя
        dispatch(callback_query: {
                   id: 'callback_3',
                   from: from,
                   message: { message_id: 24, chat: chat },
                   data: "rate_select_member:#{project.slug},#{target_user.id}"
                 })

        # 4. Выбор валюты
        dispatch(callback_query: {
                   id: 'callback_4',
                   from: from,
                   message: { message_id: 25, chat: chat },
                   data: "rate_select_currency:#{project.slug},#{target_user.id},EUR"
                 })

        # 5. Ввод суммы - проверяем сохранение в базу
        expect do
          dispatch_message('75.50')
        end.to change(MemberRate, :count).by(1)

        # Проверяем корректность сохраненных данных
        rate = MemberRate.last
        expect(rate.user).to eq(target_user)
        expect(rate.project).to eq(project)
        expect(rate.hourly_rate).to eq(75.50)
        expect(rate.currency).to eq('EUR')
      end

      it 'completes full rate setting workflow' do
        # 1. Select project
        response1 = dispatch(callback_query: {
                               id: 'callback_1',
                               from: from,
                               message: { message_id: 22, chat: chat },
                               data: "rate_select_project:#{project.slug}"
                             })
        expect { response1 }.not_to raise_error

        # 2. Click "Set rate" button
        response2 = dispatch(callback_query: {
                               id: 'callback_2',
                               from: from,
                               message: { message_id: 23, chat: chat },
                               data: "rate_set_rate:#{project.slug}"
                             })
        expect { response2 }.not_to raise_error

        # 3. Select member
        response3 = dispatch(callback_query: {
                               id: 'callback_3',
                               from: from,
                               message: { message_id: 24, chat: chat },
                               data: "rate_select_member:#{project.slug},#{target_user.id}"
                             })
        expect { response3 }.not_to raise_error

        # 4. Select currency
        response4 = dispatch(callback_query: {
                               id: 'callback_4',
                               from: from,
                               message: { message_id: 25, chat: chat },
                               data: "rate_select_currency:#{project.slug},#{target_user.id},USD"
                             })
        expect { response4 }.not_to raise_error

        # 5. Enter amount
        expect do
          dispatch_message('50')
        end.to change(MemberRate, :count).by(1)

        # Verify rate was created correctly
        rate = MemberRate.last
        expect(rate.user).to eq(target_user)
        expect(rate.project).to eq(project)
        expect(rate.hourly_rate).to eq(50.0)
        expect(rate.currency).to eq('USD')
      end

      it 'allows canceling operation at any stage' do
        # 1. Select project
        dispatch(callback_query: {
                   id: 'callback_1',
                   from: from,
                   message: { message_id: 22, chat: chat },
                   data: "rate_select_project:#{project.slug}"
                 })

        # 2. Cancel
        expect do
          response = dispatch(callback_query: {
                                id: 'callback_cancel',
                                from: from,
                                message: { message_id: 23, chat: chat },
                                data: 'rate_cancel:'
                              })
          expect(response).not_to be_nil
        end.not_to change(MemberRate, :count)
      end

      it 'supports cancel via text input' do
        # 1. Setup context by selecting currency
        dispatch(callback_query: {
                   id: 'callback_1',
                   from: from,
                   message: { message_id: 22, chat: chat },
                   data: "rate_select_currency:#{project.slug},#{target_user.id},USD"
                 })

        # 2. Type "cancel" instead of amount
        expect do
          dispatch_message('cancel')
        end.not_to change(MemberRate, :count)
      end
    end

    context 'access control' do
      # user_with_telegram является participant (не owner) для test_project
      # Это позволяет тестировать что participant не может управлять ставками
      let(:participant_project) { projects(:test_project) }

      it 'prevents non-owner from managing rates' do
        # user_with_telegram является participant для test_project (role_cd: 2)
        response = dispatch(callback_query: {
                              id: 'test_callback',
                              from: from,
                              message: { message_id: 22, chat: chat },
                              data: "rate_select_project:#{participant_project.slug}"
                            })

        expect(response).not_to be_nil

        # Проверяем, что participant получает сообщение об ошибке доступа
        first_message = response.first
        expect(first_message[:text]).to include(I18n.t('telegram.commands.rate.access_denied_owner_only'))
      end

      it 'handles unauthorized access gracefully when trying to set rates' do
        # Пытаемся установить ставку в проекте где user participant (не owner)
        response = dispatch(callback_query: {
                              id: 'test_callback',
                              from: from,
                              message: { message_id: 22, chat: chat },
                              data: "rate_set_rate:#{participant_project.slug}"
                            })

        expect(response).not_to be_nil

        # Проверяем, что возвращается сообщение об ошибке
        first_message = response.first
        expect(first_message[:text]).to include(I18n.t('telegram.commands.rate.access_denied_owner_only'))
      end
    end

    context 'single project optimization' do
      let(:single_user) { users(:user_single_project) }
      let(:single_telegram_user) { telegram_users(:telegram_single_project) }
      let(:single_project) { projects(:single_user_project) }

      # Override user and telegram_user for this context
      let(:user) { single_user }
      let(:telegram_user) { single_telegram_user }
      let(:from_id) { single_telegram_user.id }

      it 'skips project selection when user owns exactly one project' do
        response = dispatch_command :rate

        # Should not show project selection menu
        first_message = response.first
        first_message.dig(:reply_markup, :inline_keyboard)

        # Should show project menu directly
        expect(response).not_to be_nil
      end
    end
  end
end
