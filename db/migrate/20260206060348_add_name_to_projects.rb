# frozen_string_literal: true

class AddNameToProjects < ActiveRecord::Migration[8.0]
  def up
    add_column :projects, :name, :string

    # Копируем slug в name для существующих проектов
    execute <<-SQL.squish
      UPDATE projects SET name = slug WHERE name IS NULL
    SQL
  end

  def down
    remove_column :projects, :name
  end
end
