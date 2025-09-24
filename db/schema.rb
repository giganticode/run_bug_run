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

ActiveRecord::Schema[7.1].define(version: 2025_04_22_134004) do
  create_table "bugs", force: :cascade do |t|
    t.text "buggy_code", null: false
    t.text "fixed_code", null: false
    t.string "problem_id", null: false
    t.string "user_id", null: false
    t.string "buggy_submission_id", null: false
    t.string "fixed_submission_id", null: false
    t.integer "language", null: false
    t.json "label_ids"
    t.json "runtime_errors"
    t.integer "change_count"
    t.integer "split"
    t.string "buggy_main_class"
    t.string "fixed_main_class"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "token_count"
    t.boolean "active", default: true, null: false
    t.integer "hunk_count"
    t.integer "buggy_locs"
    t.integer "fixed_locs"
    t.index ["language", "split"], name: "index_bugs_on_language_and_split", where: "active"
    t.index ["problem_id", "user_id", "buggy_submission_id", "fixed_submission_id"], name: "index_bugs_uniq", unique: true
  end

  create_table "evaluations", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_evaluations_on_name", unique: true
  end

  create_table "problems", force: :cascade do |t|
    t.string "problem_id"
    t.text "text"
    t.json "similar_problems"
    t.index ["problem_id"], name: "index_problems_on_problem_id", unique: true
  end

  create_table "runs", force: :cascade do |t|
    t.integer "evaluation_id", null: false
    t.integer "status", null: false
    t.integer "bug_id", null: false
    t.integer "bug_version", null: false
    t.integer "bug_variant", null: false
    t.integer "candidate_index"
    t.integer "test_id", null: false
    t.text "error_output"
    t.text "output"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "wall_time"
    t.index ["bug_id", "evaluation_id", "bug_version", "test_id", "bug_variant", "candidate_index"], name: "index_runs1", unique: true
    t.index ["evaluation_id"], name: "index_runs_on_evaluation_id"
    t.index ["test_id"], name: "index_runs_on_test_id"
  end

  create_table "tests", force: :cascade do |t|
    t.string "problem_id", null: false
    t.integer "test_id", null: false
    t.text "input"
    t.text "output"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "origin", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.index ["active"], name: "index_tests_on_active", where: "active"
    t.index ["problem_id", "test_id"], name: "index_tests_on_problem_id_and_test_id", unique: true
  end

  add_foreign_key "runs", "bugs"
  add_foreign_key "runs", "evaluations"
  add_foreign_key "runs", "tests"
end
