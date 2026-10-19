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

ActiveRecord::Schema[8.1].define(version: 2026_10_19_223501) do
  create_table "friendships", force: :cascade do |t|
    t.integer "requester_id", null: false
    t.integer "addressee_id", null: false
    t.string "state", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "min(requester_id, addressee_id), max(requester_id, addressee_id)", name: "index_friendships_on_user_pair", unique: true
    t.index ["addressee_id"], name: "index_friendships_on_addressee_id"
    t.index ["requester_id"], name: "index_friendships_on_requester_id"
    t.check_constraint "requester_id <> addressee_id", name: "friendships_not_self"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "username", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "approval_state", default: "pending", null: false
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_seen_at"
    t.index "lower(username)", name: "index_users_on_lower_username", unique: true
    t.index ["approval_state"], name: "index_users_on_approval_state"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "friendships", "users", column: "addressee_id"
  add_foreign_key "friendships", "users", column: "requester_id"
  add_foreign_key "sessions", "users"
end
