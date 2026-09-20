require "db"
require "sqlite3"

module MicroSpaceEmpire
  class StoreError < Exception
  end

  class StaleSaveError < StoreError
  end

  class Store
    getter db : DB::Database

    def self.open(root : String = ENV.fetch("MSE_ROOT", Dir.current)) : Store
      default_path = File.join(root, "var", "micro_space_empire.db")
      path = ENV.fetch("MSE_DATABASE_PATH", default_path)
      Dir.mkdir_p(File.dirname(path))
      new(DB.open("sqlite3://#{path}"))
    end

    def initialize(@db)
      migrate!
      db.exec "DELETE FROM games WHERE saved = 0"
    end

    def close : Nil
      db.close
    end

    def migrate! : Nil
      db.exec "PRAGMA foreign_keys = ON"
      db.exec "PRAGMA journal_mode = WAL"
      db.exec "PRAGMA busy_timeout = 5000"
      db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS schema_migrations (
          version INTEGER PRIMARY KEY,
          applied_at TEXT NOT NULL
        )
      SQL
      unless db.query_one?("SELECT version FROM schema_migrations WHERE version = 1", as: Int32)
        db.transaction do |tx|
          tx.connection.exec <<-SQL
            CREATE TABLE games (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL COLLATE NOCASE UNIQUE,
              ruleset TEXT NOT NULL,
              status TEXT NOT NULL,
              state_json TEXT NOT NULL,
              lock_version INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          SQL
          tx.connection.exec(
            "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            1,
            timestamp
          )
        end
      end

      unless db.query_one?("SELECT version FROM schema_migrations WHERE version = 2", as: Int32)
        db.transaction do |tx|
          tx.connection.exec "ALTER TABLE games ADD COLUMN saved INTEGER NOT NULL DEFAULT 1"
          tx.connection.exec(
            "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            2,
            timestamp
          )
        end
      end
    end

    def create(name : String, state : GameState) : SaveRecord
      clean_name = validate_name(name)
      if db.query_one?("SELECT 1 FROM games WHERE name = ? COLLATE NOCASE", clean_name, as: Int32)
        raise StoreError.new("A save with that name already exists.")
      end
      now = timestamp
      result = db.exec(
        "INSERT INTO games(name, ruleset, status, state_json, lock_version, created_at, updated_at) VALUES (?, ?, ?, ?, 0, ?, ?)",
        clean_name,
        state.content_version,
        state.status,
        state.to_json,
        now,
        now
      )
      get(result.last_insert_id)
    end

    def create_unsaved(state : GameState) : SaveRecord
      now = timestamp
      internal_name = "__unsaved__#{Time.utc.to_unix_ms}_#{Random.rand(100_000)}"
      id = 0_i64
      db.transaction do |tx|
        tx.connection.exec "DELETE FROM games WHERE saved = 0"
        result = tx.connection.exec(
          "INSERT INTO games(name, ruleset, status, state_json, lock_version, created_at, updated_at, saved) VALUES (?, ?, ?, ?, 0, ?, ?, 0)",
          internal_name,
          state.content_version,
          state.status,
          state.to_json,
          now,
          now
        )
        id = result.last_insert_id
      end
      get(id)
    end

    def start_new(current_id : Int64, state : GameState, save_current_as : String? = nil) : SaveRecord
      clean_name = save_current_as.try { |name| validate_name(name) }
      if clean_name && db.query_one?("SELECT 1 FROM games WHERE name = ? COLLATE NOCASE AND id != ?", clean_name, current_id, as: Int32)
        raise StoreError.new("A save with that name already exists.")
      end

      now = timestamp
      internal_name = "__unsaved__#{Time.utc.to_unix_ms}_#{Random.rand(100_000)}"
      new_id = 0_i64
      db.transaction do |tx|
        if clean_name
          result = tx.connection.exec("UPDATE games SET name = ?, saved = 1, updated_at = ? WHERE id = ? AND saved = 0", clean_name, now, current_id)
          raise StoreError.new("The current game could not be saved.") unless result.rows_affected == 1
        else
          tx.connection.exec "DELETE FROM games WHERE id = ? AND saved = 0", current_id
        end
        tx.connection.exec "DELETE FROM games WHERE saved = 0"
        result = tx.connection.exec(
          "INSERT INTO games(name, ruleset, status, state_json, lock_version, created_at, updated_at, saved) VALUES (?, ?, ?, ?, 0, ?, ?, 0)",
          internal_name,
          state.content_version,
          state.status,
          state.to_json,
          now,
          now
        )
        new_id = result.last_insert_id
      end
      get(new_id)
    end

    def get(id : Int64) : SaveRecord
      record = db.query_one?(
        "SELECT name, saved, state_json, lock_version, created_at, updated_at FROM games WHERE id = ?",
        id,
        as: {String, Int32, String, Int32, String, String}
      )
      raise StoreError.new("Save not found.") unless record
      name, saved, json, version, created_at, updated_at = record
      SaveRecord.new(id, name, saved == 1, GameState.from_json(json), version, created_at, updated_at)
    end

    def list : Array(SaveSummary)
      saves = [] of SaveSummary
      db.query("SELECT id, name, state_json, updated_at FROM games WHERE saved = 1 ORDER BY updated_at DESC, id DESC") do |rows|
        rows.each do
          id = rows.read(Int64)
          name = rows.read(String)
          state = GameState.from_json(rows.read(String))
          updated_at = rows.read(String)
          saves << SaveSummary.new(
            id,
            name,
            state.status,
            state.year,
            state.turn,
            state.expansion,
            state.score.try(&.total),
            updated_at
          )
        end
      end
      saves
    end

    def update(id : Int64, expected_version : Int32, state : GameState) : SaveRecord
      result = db.exec(
        "UPDATE games SET status = ?, state_json = ?, lock_version = lock_version + 1, updated_at = ? WHERE id = ? AND lock_version = ?",
        state.status,
        state.to_json,
        timestamp,
        id,
        expected_version
      )
      raise StaleSaveError.new("This save changed in another tab. Reload before continuing.") unless result.rows_affected == 1
      get(id)
    end

    def rename(id : Int64, name : String) : Nil
      result = db.exec("UPDATE games SET name = ?, updated_at = ? WHERE id = ?", validate_name(name), timestamp, id)
      raise StoreError.new("Save not found.") unless result.rows_affected == 1
    end

    def save(id : Int64, name : String) : SaveRecord
      clean_name = validate_name(name)
      if db.query_one?("SELECT 1 FROM games WHERE name = ? COLLATE NOCASE AND id != ?", clean_name, id, as: Int32)
        raise StoreError.new("A save with that name already exists.")
      end
      result = db.exec("UPDATE games SET name = ?, saved = 1, updated_at = ? WHERE id = ?", clean_name, timestamp, id)
      raise StoreError.new("Game not found.") unless result.rows_affected == 1
      get(id)
    end

    def delete(id : Int64) : Nil
      result = db.exec("DELETE FROM games WHERE id = ?", id)
      raise StoreError.new("Save not found.") unless result.rows_affected == 1
    end

    private def validate_name(name : String) : String
      clean = name.strip
      raise StoreError.new("Save name is required.") if clean.empty?
      raise StoreError.new("Save name must be 50 characters or fewer.") if clean.size > 50
      clean
    end

    private def timestamp : String
      Time.utc.to_rfc3339(fraction_digits: 3)
    end
  end
end
