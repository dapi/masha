# frozen_string_literal: true

class RenameNameToTitleInProjects < ActiveRecord::Migration[8.0]
  def change
    rename_column :projects, :name, :title
  end
end
