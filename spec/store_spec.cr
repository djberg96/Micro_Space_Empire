require "./spec_helper"

describe MicroSpaceEmpire::Store do
  it "creates, reloads, renames, locks, lists, and deletes saves" do
    path = File.join(Dir.tempdir, "mse-store-spec-#{Random.rand(1_000_000)}.db")
    store = MicroSpaceEmpire::Store.new(DB.open("sqlite3://#{path}"))
    begin
      record = store.create("Test Empire", core_state)
      record.version.should eq(0)
      record.saved.should be_true
      store.list.first.name.should eq("Test Empire")
      store.rename(record.id, "Renamed Empire")
      store.get(record.id).name.should eq("Renamed Empire")

      state = record.state
      state.metal = 2
      updated = store.update(record.id, 0, state)
      updated.version.should eq(1)
      updated.state.metal.should eq(2)
      expect_raises(MicroSpaceEmpire::StaleSaveError) { store.update(record.id, 0, state) }

      store.delete(record.id)
      store.list.should be_empty
    ensure
      store.close
      File.delete(path) if File.exists?(path)
      File.delete("#{path}-wal") if File.exists?("#{path}-wal")
      File.delete("#{path}-shm") if File.exists?("#{path}-shm")
    end
  end

  it "keeps unnamed games out of the save library until the player saves" do
    path = File.join(Dir.tempdir, "mse-unsaved-spec-#{Random.rand(1_000_000)}.db")
    store = MicroSpaceEmpire::Store.new(DB.open("sqlite3://#{path}"))
    begin
      draft = store.create_unsaved(core_state)
      draft.saved.should be_false
      store.list.should be_empty

      saved = store.save(draft.id, "First Contact")
      saved.saved.should be_true
      saved.name.should eq("First Contact")
      store.list.map(&.name).should eq(["First Contact"])
    ensure
      store.close
      File.delete(path) if File.exists?(path)
      File.delete("#{path}-wal") if File.exists?("#{path}-wal")
      File.delete("#{path}-shm") if File.exists?("#{path}-shm")
    end
  end

  it "atomically saves or discards the current draft when starting a new game" do
    path = File.join(Dir.tempdir, "mse-start-new-spec-#{Random.rand(1_000_000)}.db")
    store = MicroSpaceEmpire::Store.new(DB.open("sqlite3://#{path}"))
    begin
      first = store.create_unsaved(core_state)
      second = store.start_new(first.id, core_state, "First Contact")
      store.get(first.id).saved.should be_true
      store.get(first.id).name.should eq("First Contact")
      second.saved.should be_false
      store.list.map(&.name).should eq(["First Contact"])

      third = store.start_new(second.id, core_state)
      expect_raises(MicroSpaceEmpire::StoreError, "Save not found.") { store.get(second.id) }
      third.saved.should be_false
      store.list.map(&.name).should eq(["First Contact"])
    ensure
      store.close
      File.delete(path) if File.exists?(path)
      File.delete("#{path}-wal") if File.exists?("#{path}-wal")
      File.delete("#{path}-shm") if File.exists?("#{path}-shm")
    end
  end

  it "validates names and enforces case-insensitive uniqueness" do
    path = File.join(Dir.tempdir, "mse-name-spec-#{Random.rand(1_000_000)}.db")
    store = MicroSpaceEmpire::Store.new(DB.open("sqlite3://#{path}"))
    begin
      expect_raises(MicroSpaceEmpire::StoreError) { store.create("   ", core_state) }
      store.create("Orion", core_state)
      expect_raises(MicroSpaceEmpire::StoreError, "A save with that name already exists.") { store.create("orion", core_state) }
    ensure
      store.close
      File.delete(path) if File.exists?(path)
      File.delete("#{path}-wal") if File.exists?("#{path}-wal")
      File.delete("#{path}-shm") if File.exists?("#{path}-shm")
    end
  end
end
