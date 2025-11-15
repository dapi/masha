# frozen_string_literal: true

# Проект для отслеживания времени с friendly_id slug. Может быть активным или архивным.
# Имеет участников с разными ролями и временные записи.
class Project < ApplicationRecord
  include Authority::Abilities
  extend FriendlyId

  friendly_id :slug, use: :slugged

  # belongs_to :owner, class_name: 'User'
  belongs_to :client, optional: true

  has_many :time_shifts, dependent: :destroy
  has_many :timed_projects, through: :time_shift, class_name: 'Project'

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invites, dependent: :destroy
  has_many :member_rates, dependent: :destroy
  has_many :rated_users, through: :member_rates, source: :user

  scope :ordered, -> { order(:slug) }
  scope :active, -> { where(active: true) }
  scope :alive, -> { where(active: true) }
  scope :archive, -> { where(active: false) }
  scope :alphabetically, -> { order(slug: :asc) }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9._+-]+\Z/, message: :invalid_slug_format }
  validate :slug_not_reserved
  validate :slug_not_integer

  # active_admin в упор не видит friendly_id-шный slug
  def to_param
    id.to_s
  end

  def to_s
    slug
  end

  def roles_of_user(user)
    applied_roles.select { |r| r.user == user }
  end

  def activate
    update_attribute(:active, true)
  end

  def archivate
    update_attribute(:active, false)
  end

  def can_be_managed_by?(user)
    memberships.owners.exists?(user: user)
  end

  def client_name_for_display
    client&.name || I18n.t('commands.projects.menu.no_client')
  end

  def deletion_stats
    {
      time_shifts_count: time_shifts.count,
      memberships_count: memberships.count,
      invites_count: invites.count
    }
  end

  def self.generate_unique_slug(base_name)
    # Генерируем базовый slug из названия
    base_slug = Russian.translit(base_name.to_s)
                       .downcase
                       .strip
                       .gsub(/[^\w\s-]/, '')  # Удаляем спецсимволы
                       .gsub(/\s+/, '-')      # Пробелы в дефисы
                       .gsub(/-+/, '-')       # Множественные дефисы в один
                       .gsub(/^-|-$/, '')     # Дефисы в начале и конце
                       .slice(0, 15)          # Ограничение до 15 символов

    # Проверяем уникальность
    return base_slug unless Project.exists?(slug: base_slug)

    # Добавляем суффикс если slug занят
    (1..100).each do |i|
      candidate_slug = "#{base_slug.slice(0, 13)}-#{i}"[0..14]
      return candidate_slug unless Project.exists?(slug: candidate_slug)
    end

    # Если не получилось найти уникальный (очень маловероятно)
    nil
  end

  private

  def slug_not_reserved
    return if slug.blank?

    return unless ApplicationConfig.reserved_project_slugs.include?(slug.downcase)

    errors.add(:slug, "не может быть зарезервированным словом: #{slug}")
  end

  def slug_not_integer
    return if slug.blank?

    # Проверяем что slug не является целым числом
    return unless slug.match?(/\A\d+\z/)

    errors.add(:slug, "не может быть целым числом: #{slug}")
  end
end
