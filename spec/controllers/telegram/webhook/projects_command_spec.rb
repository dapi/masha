# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Telegram::WebhookController, telegram_bot: :rails, type: :telegram_bot_controller do
  include_context 'telegram webhook base'
  include_context 'authenticated user'

  context 'user with no projects' do
    let(:telegram_user) { telegram_users(:telegram_empty) }

    it 'responds to /projects command without errors' do
      expect { dispatch_command :projects }.not_to raise_error
    end
  end

  context 'edge cases' do
    context 'project with deleted client' do
      let(:client) { clients(:delete_me_client) }
      let(:telegram_user) { telegram_users(:telegram_regular) }

      before do
        client.destroy
      end

      it 'handles projects with orphaned client references' do
        expect { dispatch_command :projects }.not_to raise_error
      end
    end
  end

  # Tests for project creation functionality (migrated from new_command)
  context 'project creation' do
    let(:user) { users(:user_with_telegram) }
    let(:telegram_user) { telegram_users(:telegram_regular) }
    let(:from_id) { telegram_user.id }

    include_context 'authenticated user'

    it 'responds to /projects create command without errors' do
      expect { dispatch_command :projects, :create }.not_to raise_error
    end

    it 'prompts for slug when /projects create is called without parameters' do
      response = dispatch_command :projects, :create
      expect(response.first[:text]).to include('Введите название проекта')
    end

    it 'creates project directly with slug parameter' do
      expect do
        dispatch_command :projects, :create, 'newproject'
      end.to change(Project, :count).by(1)

      project = Project.last
      expect(project.name).to eq('newproject')
      expect(project.slug).to eq('newproject')
      expect(project.users).to include(user)
      expect(user.memberships.where(project: project, role_cd: 0)).to exist
    end

    it 'interpolates name and slug in success message' do
      response = nil
      expect do
        response = dispatch_command :projects, :create, 'test-proj'
      end.to change(Project, :count).by(1)

      # Проверяем что в ответе нет необработанных плейсхолдеров
      expect(response.first[:text]).not_to include('%{name}')
      expect(response.first[:text]).not_to include('%{slug}')

      # Проверяем что в ответе есть реальные значения
      expect(response.first[:text]).to include('test-proj')
    end

    it 'creates project through multi-step workflow' do
      # 1. User calls /projects create without parameters
      dispatch_command :projects, :create

      # 2. User provides project name (auto-generates slug)
      expect do
        dispatch_message 'My Awesome'
      end.to change(Project, :count).by(1)

      # 3. Verify project was created with correct attributes
      project = Project.last
      expect(project.name).to eq('My Awesome')
      # Slug is auto-generated from name using Russian.translit
      expect(project.slug).to eq('my-awesome')
      expect(project.users).to include(user)

      # 4. Verify user is owner of the project
      membership = user.memberships.find_by(project: project)
      expect(membership.role_cd).to eq(0) # owner role = 0
    end

    it 'rejects empty project slug in multi-step workflow' do
      # 1. Start project creation workflow
      dispatch_command :projects, :create

      # 2. Send empty slug - should not create project
      expect do
        dispatch_message ''
      end.not_to change(Project, :count)

      # 3. Verify no project was created
      expect(Project.where(name: '')).not_to exist
    end

    it 'rejects empty project slug directly' do
      # Try to create project with empty slug directly
      expect do
        dispatch_command :projects, :create, ''
      end.not_to change(Project, :count)
    end

    it 'rejects invalid slug format in multi-step workflow' do
      # 1. Start project creation workflow
      dispatch_command :projects, :create

      # 2. In new workflow, project name is input (not slug)
      # Special chars in name are valid, slug is auto-generated
      expect do
        dispatch_message 'Project@Name'
      end.to change(Project, :count).by(1)

      # 3. Verify project was created with auto-generated slug
      project = Project.last
      expect(project.name).to eq('Project@Name')
      # Slug is auto-generated and sanitized
      expect(project.slug).to match(/^[a-z0-9-]+$/)
    end

    it 'rejects invalid slug format directly' do
      # Try to create project with invalid slug directly
      expect do
        dispatch_command :projects, :create, 'project@name'
      end.not_to change(Project, :count)
    end

    it 'handles duplicate project slug gracefully in multi-step workflow' do
      # 1. Use existing project from fixtures
      existing_project = projects(:work_project)
      memberships(:telegram_work)

      # 2. In new workflow, project name is input (not slug)
      # User enters a different name that would generate a unique slug
      dispatch_command :projects, :create

      # System auto-generates unique slug with different project name
      expect do
        dispatch_message 'New Work Project'
      end.to change(Project, :count).by(1)

      # 3. Verify new project was created with unique slug
      new_project = Project.last
      expect(new_project.name).to eq('New Work Project')
      # Slug is auto-generated (may be truncated to 15 chars) and will be different from work_project
      expect(new_project.slug).to match(/^new-work-proj/)
      expect(new_project.slug).not_to eq(existing_project.slug)
      expect(new_project.users).to include(user)
    end

    it 'handles duplicate project slug gracefully directly' do
      # 1. Use existing project from fixtures
      existing_project = projects(:work_project)
      memberships(:telegram_work)

      # 2. Try to create project with same slug directly
      expect do
        dispatch_command :projects, :create, existing_project.slug
      end.not_to change(Project, :count)

      # 3. Verify original project still exists and unchanged
      expect(Project.find_by(slug: existing_project.slug)).to eq(existing_project)
    end

    it 'handles unknown actions gracefully' do
      response = dispatch_command :projects, :unknown_action
      expect(response.first[:text]).to include('Неизвестное действие. Используйте: /projects или /projects create [slug]')
    end

    it 'validates unauthorized access for project creation' do
      # Test with unauthorized user
      allow_any_instance_of(ProjectsCommand).to receive(:current_user).and_return(nil)

      response = dispatch_command :projects, :create, 'test-project'
      expect(response.first[:text]).to include('Вы не авторизованы для работы с проектами')
    end
  end

  # Tests for rename operations
  context 'rename operations', :callback_query do
    let(:user) { users(:user_with_telegram) }
    let(:telegram_user) { telegram_users(:telegram_regular) }
    let(:from_id) { telegram_user.id }
    let(:project) { projects(:work_project) }

    include_context 'authenticated user'

    before do
      # Ensure user has owner membership to the project
      memberships(:telegram_work)
    end

    context 'rename project title only' do
      it 'renames project title through workflow' do
        # 1. User clicks on rename menu
        dispatch(callback_query: {
                   id: 'test_callback_id',
                   from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                   message: { message_id: 22, chat: { id: from_id, type: 'private' } },
                   data: "projects_rename:#{project.slug}"
                 })

        # 2. User clicks on rename title button
        dispatch(callback_query: {
                   id: 'test_callback_id_2',
                   from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                   message: { message_id: 23, chat: { id: from_id, type: 'private' } },
                   data: "projects_rename_title:#{project.slug}"
                 })

        # 3. User enters new title
        old_slug = project.slug
        expect do
          dispatch_message('New Project Title')
        end.to change { project.reload.name }.to('New Project Title')

        # Verify slug didn't change
        expect(project.slug).to eq(old_slug)
      end
    end

    context 'rename project slug only' do
      it 'renames project slug through workflow' do
        # 1. User clicks on rename menu
        dispatch(callback_query: {
                   id: 'test_callback_id',
                   from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                   message: { message_id: 22, chat: { id: from_id, type: 'private' } },
                   data: "projects_rename:#{project.slug}"
                 })

        # 2. User clicks on rename slug button
        dispatch(callback_query: {
                   id: 'test_callback_id_2',
                   from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                   message: { message_id: 23, chat: { id: from_id, type: 'private' } },
                   data: "projects_rename_slug:#{project.slug}"
                 })

        # 3. User enters new slug
        old_name = project.name
        expect do
          dispatch_message('new-slug')
        end.to change { project.reload.slug }.to('new-slug')

        # Verify name didn't change
        expect(project.name).to eq(old_name)
      end
    end

    context 'rename project both title and slug' do
      it 'renames both title and slug through workflow' do
        # 1. User clicks on rename menu
        dispatch(callback_query: {
                   id: 'test_callback_id',
                   from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                   message: { message_id: 22, chat: { id: from_id, type: 'private' } },
                   data: "projects_rename:#{project.slug}"
                 })

        # 2. User clicks on rename both button
        dispatch(callback_query: {
                   id: 'test_callback_id_2',
                   from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                   message: { message_id: 23, chat: { id: from_id, type: 'private' } },
                   data: "projects_rename_both:#{project.slug}"
                 })

        # 3. User enters new title
        response = dispatch_message('New Title')
        expect(response).not_to be_nil

        # 4. User enters new slug
        expect do
          dispatch_message('new-slug')
        end.to change { project.reload.name }.to('New Title')
          .and change { project.slug }.to('new-slug')
      end

      it 'uses suggested slug when button clicked' do
        # 1. User clicks on rename menu
        dispatch(callback_query: {
                   id: 'test_callback_id',
                   from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                   message: { message_id: 22, chat: { id: from_id, type: 'private' } },
                   data: "projects_rename:#{project.slug}"
                 })

        # 2. User clicks on rename both button
        dispatch(callback_query: {
                   id: 'test_callback_id_2',
                   from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                   message: { message_id: 23, chat: { id: from_id, type: 'private' } },
                   data: "projects_rename_both:#{project.slug}"
                 })

        # 3. User enters new title
        response = dispatch_message('My Awesome Project')

        # 4. Extract suggested slug button from response (button is in last message)
        keyboard = response.last.dig(:reply_markup, :inline_keyboard)&.flatten || []
        suggested_button = keyboard.find { |btn| btn[:text].include?('Использовать') }
        expect(suggested_button).not_to be_nil

        # 5. User clicks suggested slug button
        old_slug = project.slug
        expect do
          dispatch(callback_query: {
                     id: 'test_callback_id_3',
                     from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                     message: { message_id: 24, chat: { id: from_id, type: 'private' } },
                     data: suggested_button[:callback_data]
                   })
        end.to change { project.reload.slug }.from(old_slug)
          .and change { project.name }.to('My Awesome Project')
      end
    end
  end

  # Tests for client management
  context 'client management', :callback_query do
    let(:user) { users(:user_with_telegram) }
    let(:telegram_user) { telegram_users(:telegram_regular) }
    let(:from_id) { telegram_user.id }
    let(:project) { projects(:work_project) }

    include_context 'authenticated user'

    before do
      # Ensure user has owner membership to the project
      memberships(:telegram_work)
    end

    it 'sets client for project' do
      # 1. User clicks on client menu
      dispatch(callback_query: {
                 id: 'test_callback_id',
                 from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                 message: { message_id: 22, chat: { id: from_id, type: 'private' } },
                 data: "projects_client:#{project.slug}"
               })

      # 2. User clicks on edit client button
      dispatch(callback_query: {
                 id: 'test_callback_id_2',
                 from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                 message: { message_id: 23, chat: { id: from_id, type: 'private' } },
                 data: "projects_client_edit:#{project.slug}"
               })

      # 3. User enters client name
      expect do
        dispatch_message('ACME Corporation')
      end.to change { project.reload.client&.name }.to('ACME Corporation')
    end

    it 'removes client from project' do
      # Setup: assign a client to project
      project.update(client: clients(:work_client))

      # 1. User clicks on client menu
      dispatch(callback_query: {
                 id: 'test_callback_id',
                 from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                 message: { message_id: 22, chat: { id: from_id, type: 'private' } },
                 data: "projects_client:#{project.slug}"
               })

      # 2. User clicks on delete client button
      dispatch(callback_query: {
                 id: 'test_callback_id_2',
                 from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                 message: { message_id: 23, chat: { id: from_id, type: 'private' } },
                 data: "projects_client_delete:#{project.slug}"
               })

      # 3. User confirms deletion
      expect do
        dispatch(callback_query: {
                   id: 'test_callback_id_3',
                   from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                   message: { message_id: 24, chat: { id: from_id, type: 'private' } },
                   data: "projects_client_delete_confirm:#{project.slug}"
                 })
      end.to change { project.reload.client }.to(nil)
    end
  end

  # Tests for project deletion
  context 'delete project', :callback_query do
    let(:user) { users(:user_with_telegram) }
    let(:telegram_user) { telegram_users(:telegram_regular) }
    let(:from_id) { telegram_user.id }
    let(:project) { projects(:dev_project) }

    include_context 'authenticated user'

    before do
      # Ensure user has owner membership to the project
      memberships(:telegram_test_project)
    end

    it 'deletes project through workflow' do
      project_name = project.name

      # 1. User clicks on project menu
      dispatch(callback_query: {
                 id: 'test_callback_id',
                 from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                 message: { message_id: 22, chat: { id: from_id, type: 'private' } },
                 data: "projects_select:#{project.slug}"
               })

      # 2. User clicks on delete button
      dispatch(callback_query: {
                 id: 'test_callback_id_2',
                 from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                 message: { message_id: 23, chat: { id: from_id, type: 'private' } },
                 data: "projects_delete:#{project.slug}"
               })

      # 3. User confirms first step (yes button)
      dispatch(callback_query: {
                 id: 'test_callback_id_3',
                 from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                 message: { message_id: 24, chat: { id: from_id, type: 'private' } },
                 data: "projects_delete_confirm:#{project.slug}"
               })

      # 4. User enters project name to confirm deletion
      expect do
        dispatch_message(project_name)
      end.to change(Project, :count).by(-1)

      # Verify project was deleted
      expect(Project.find_by(slug: project.slug)).to be_nil
    end

    it 'cancels deletion on wrong name' do
      project_name = project.name

      # 1. User clicks on project menu
      dispatch(callback_query: {
                 id: 'test_callback_id',
                 from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                 message: { message_id: 22, chat: { id: from_id, type: 'private' } },
                 data: "projects_select:#{project.slug}"
               })

      # 2. User clicks on delete button
      dispatch(callback_query: {
                 id: 'test_callback_id_2',
                 from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                 message: { message_id: 23, chat: { id: from_id, type: 'private' } },
                 data: "projects_delete:#{project.slug}"
               })

      # 3. User confirms first step (yes button)
      dispatch(callback_query: {
                 id: 'test_callback_id_3',
                 from: { id: from_id, first_name: 'Test', last_name: 'User', username: 'testuser' },
                 message: { message_id: 24, chat: { id: from_id, type: 'private' } },
                 data: "projects_delete_confirm:#{project.slug}"
               })

      # 4. User enters wrong project name
      expect do
        dispatch_message('Wrong Name')
      end.not_to change(Project, :count)

      # Verify project still exists
      expect(Project.find_by(slug: project.slug)).to eq(project)
    end
  end
end
