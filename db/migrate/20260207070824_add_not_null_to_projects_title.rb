# frozen_string_literal: true

class AddNotNullToProjectsTitle < ActiveRecord::Migration[8.0]
  def change
    change_column_null :projects, :title, false
  end
end
