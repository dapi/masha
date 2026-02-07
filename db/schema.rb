# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_02_07_070824) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_admin_comments", force: :cascade do |t|
    t.string "resource_id", null: false
    t.string "resource_type", null: false
    t.integer "author_id"
    t.string "author_type"
    t.text "body"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "namespace"
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author_type_and_author_id"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource_type_and_resource_id"
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "authentications", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.jsonb "auth_hash"
    t.index ["provider", "uid"], name: "index_authentications_on_provider_and_uid", unique: true
    t.index ["user_id", "provider"], name: "index_authentications_on_user_id_and_provider", unique: true
  end

  create_table "clients", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_clients_on_key"
    t.index ["user_id", "key"], name: "index_clients_on_user_id_and_key", unique: true
    t.index ["user_id"], name: "index_clients_on_user_id"
  end

  create_table "invites", force: :cascade do |t|
    t.integer "user_id"
    t.string "email", null: false
    t.string "role", null: false
    t.integer "project_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "telegram_username"
    t.index ["email", "project_id"], name: "index_invites_on_email_and_project_id", unique: true
    t.index ["project_id"], name: "index_invites_on_project_id"
    t.index ["telegram_username", "project_id"], name: "index_invites_on_telegram_username_and_project_id", unique: true
    t.index ["user_id"], name: "index_invites_on_user_id"
  end

  create_table "member_rates", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "user_id", null: false
    t.decimal "hourly_rate", precision: 10, scale: 2
    t.string "currency", limit: 3, default: "RUB"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "user_id"], name: "index_member_rates_on_project_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_member_rates_on_user_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.integer "user_id"
    t.integer "project_id"
    t.integer "role_cd", default: 2, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["project_id"], name: "index_memberships_on_project_id"
    t.index ["user_id", "project_id"], name: "index_memberships_on_user_id_and_project_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "notified_versions", force: :cascade do |t|
    t.string "version", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["version"], name: "index_notified_versions_on_version", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "slug", null: false
    t.text "description"
    t.boolean "active", default: true, null: false
    t.integer "telegram_chat_id"
    t.bigint "client_id"
    t.string "title", null: false
    t.index ["client_id"], name: "index_projects_on_client_id"
    t.index ["slug"], name: "index_projects_on_slug", unique: true
  end

  create_table "telegram_users", id: :bigint, default: nil, force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "username"
    t.string "photo_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "time_shifts", force: :cascade do |t|
    t.integer "project_id", null: false
    t.integer "user_id", null: false
    t.decimal "hours", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.date "date", null: false
    t.text "description"
    t.index ["date"], name: "index_time_shifts_on_date", order: :desc
    t.index ["project_id"], name: "index_time_shifts_on_project_id"
    t.index ["user_id"], name: "index_time_shifts_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.boolean "is_root", default: false, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "pivotal_person_id"
    t.string "email"
    t.string "nickname"
    t.string "crypted_password"
    t.string "salt"
    t.string "remember_me_token"
    t.datetime "remember_me_token_expires_at", precision: nil
    t.boolean "subscribed", default: true
    t.string "reset_password_token"
    t.datetime "reset_password_token_expires_at", precision: nil
    t.datetime "reset_password_email_sent_at", precision: nil
    t.string "locale", default: "ru"
    t.bigint "telegram_user_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["nickname"], name: "index_users_on_nickname", unique: true
    t.index ["pivotal_person_id"], name: "index_users_on_pivotal_person_id", unique: true
    t.index ["remember_me_token"], name: "index_users_on_remember_me_token"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token"
  end

  add_foreign_key "authentications", "users", on_delete: :restrict
  add_foreign_key "clients", "users"
  add_foreign_key "invites", "projects", on_delete: :restrict
  add_foreign_key "invites", "users", on_delete: :restrict
  add_foreign_key "member_rates", "projects"
  add_foreign_key "member_rates", "users"
  add_foreign_key "memberships", "projects", on_delete: :restrict
  add_foreign_key "memberships", "users", on_delete: :restrict
  add_foreign_key "projects", "clients"
  add_foreign_key "time_shifts", "projects", on_delete: :restrict
  add_foreign_key "time_shifts", "users", on_delete: :restrict
  add_foreign_key "users", "telegram_users"
end
