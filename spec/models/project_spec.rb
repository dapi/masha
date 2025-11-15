# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Project, type: :model do
  subject { projects(:base_project) }

  it { should be_valid }

  describe 'validations' do
    it { should validate_presence_of(:name) }

    context 'slug validation' do
      it { should validate_uniqueness_of(:slug) }
    end

    context 'reserved words' do
      it 'does not allow reserved words as slug' do
        # Проверяем несколько примеров реальных зарезервированных слов
        reserved_words = %w[list start stop day week projects settings]

        reserved_words.each do |reserved_word|
          project = Project.new(slug: reserved_word)
          project.valid?
          expect(project.errors[:slug]).to include("не может быть зарезервированным словом: #{reserved_word}")
        end
      end

      it 'allows normal slugs' do
        project = Project.new(slug: 'my-awesome-project')
        project.valid?
        expect(project.errors[:slug]).to be_empty
      end

      context 'integer slugs' do
        it 'does not allow integer slugs' do
          integer_slugs = %w[1 2 123 999 0]

          integer_slugs.each do |integer_slug|
            project = Project.new(slug: integer_slug)
            project.valid?
            expect(project.errors[:slug]).to include("не может быть целым числом: #{integer_slug}")
          end
        end

        it 'allows slugs with numbers mixed with letters' do
          mixed_slugs = %w[newproject1 2newproject test123abc abc123test]

          mixed_slugs.each do |mixed_slug|
            project = Project.new(slug: mixed_slug)
            project.valid?
            expect(project.errors[:slug]).to be_empty
          end
        end

        it 'allows decimal numbers in slug' do
          decimal_slugs = %w[1.5 2.0 123.45]

          decimal_slugs.each do |decimal_slug|
            project = Project.new(slug: decimal_slug)
            project.valid?
            expect(project.errors[:slug]).to be_empty
          end
        end
      end
    end
  end

  describe 'scopes' do
    let!(:active_project) { projects(:work_project) }
    let!(:archived_project) { projects(:inactive_project) }

    it '.active returns only active projects' do
      expect(Project.active).to include(active_project)
      expect(Project.active).not_to include(archived_project)
    end

    it '.archive returns only archived projects' do
      expect(Project.archive).to include(archived_project)
      expect(Project.archive).not_to include(active_project)
    end
  end

  describe '#can_be_managed_by?' do
    let(:project) { projects(:test_project) }
    let(:owner) { users(:project_owner) }
    let(:member) { users(:project_member) }
    let(:watcher) { users(:project_watcher) }
    let(:non_member) { users(:regular_user) }

    it 'returns true for project owner' do
      expect(project.can_be_managed_by?(owner)).to be true
    end

    it 'returns false for project member' do
      expect(project.can_be_managed_by?(member)).to be false
    end

    it 'returns false for project watcher' do
      expect(project.can_be_managed_by?(watcher)).to be false
    end

    it 'returns false for non-member' do
      expect(project.can_be_managed_by?(non_member)).to be false
    end
  end

  describe 'dependent: :destroy associations' do
    let(:project) { projects(:test_project) }

    it 'destroys invites when project is destroyed' do
      # invites уже созданы в fixtures для test_project, просто проверяем их удаление
      invite_count = project.invites.count

      # Для других проектов создаем тестовые записи
      if invite_count.zero?
        Invite.create!(project: project, user: users(:admin), email: 'test1@example.com', role: 'member')
        Invite.create!(project: project, user: users(:admin), email: 'test2@example.com', role: 'viewer')
        invite_count = 2
      end

      expect { project.destroy }.to change(Invite, :count).by(-invite_count)
    end

    it 'destroys time_shifts when project is destroyed' do
      # time_shifts уже созданы в fixtures для test_project, просто проверяем их удаление
      time_shift_count = project.time_shifts.count

      # Для других проектов создаем тестовые записи
      if time_shift_count.zero?
        TimeShift.create!(project: project, user: users(:admin), hours: 1.5, date: Date.current, description: 'Test work')
        TimeShift.create!(project: project, user: users(:regular_user), hours: 2.0, date: Date.yesterday, description: 'More work')
        time_shift_count = 2
      end

      expect { project.destroy }.to change(TimeShift, :count).by(-time_shift_count)
    end

    it 'destroys member_rates when project is destroyed' do
      # member_rates уже созданы в fixtures для test_project: high_member_rate и low_member_rate
      member_rate_count = project.member_rates.count

      # Для других проектов создаем тестовые записи
      if member_rate_count.zero?
        MemberRate.create!(project: project, user: users(:regular_user), hourly_rate: 50, currency: 'USD')
        MemberRate.create!(project: project, user: users(:admin), hourly_rate: 100, currency: 'USD')
        member_rate_count = 2
      end

      expect { project.destroy }.to change(MemberRate, :count).by(-member_rate_count)
    end
  end
end
