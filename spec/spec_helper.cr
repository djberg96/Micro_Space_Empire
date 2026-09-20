require "spec"
require "../src/micro_space_empire/content"
require "../src/micro_space_empire/models"
require "../src/micro_space_empire/rng"
require "../src/micro_space_empire/engine"
require "../src/micro_space_empire/store"

ROOT    = File.expand_path("..", __DIR__)
CONTENT = MicroSpaceEmpire::Content.load(ROOT)

def core_state : MicroSpaceEmpire::GameState
  MicroSpaceEmpire::GameEngine.new(CONTENT, MicroSpaceEmpire::ScriptedRandomSource.new(Array.new(80, 0))).new_game(false)
end
