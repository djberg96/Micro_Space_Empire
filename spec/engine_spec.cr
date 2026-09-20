require "./spec_helper"

describe MicroSpaceEmpire::GameEngine do
  it "sets up the core and optional expansion decks" do
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT, MicroSpaceEmpire::ScriptedRandomSource.new(Array.new(100, 0)))
    core = engine.new_game(false)
    core.near_deck.size.should eq(7)
    core.distant_deck.size.should eq(3)
    core.event_deck.size.should eq(7)
    core.event_pool.size.should eq(8)
    core.selected_system_ids.size.should eq(11)

    expanded = engine.new_game(true)
    expanded.near_deck.size.should eq(7)
    expanded.distant_deck.size.should eq(3)
    expanded.event_deck.size.should eq(7)
    expanded.event_pool.size.should eq(11)
    expanded.selected_system_ids.size.should eq(11)
  end

  it "reveals a system before requiring a deterministic attack roll" do
    state = core_state
    state.near_deck = ["tau-ceti"]
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT, MicroSpaceEmpire::ScriptedRandomSource.new([3]))
    engine.apply(state, "explore_near")
    state.subphase.should eq("attack")
    state.system_state("tau-ceti").not_nil!.status.should eq("pending")
    engine.apply(state, "roll_attack")
    state.system_state("tau-ceti").not_nil!.status.should eq("controlled")
    state.phase.should eq("collect")
    state.last_roll.should eq(4)
  end

  it "loses one military on a failed attack without going below zero" do
    state = core_state
    state.near_deck = ["epsilon-eridani"]
    state.military = 1
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT, MicroSpaceEmpire::ScriptedRandomSource.new([0]))
    engine.apply(state, "explore_near")
    engine.apply(state, "roll_attack")
    state.military.should eq(0)
    state.system_state("epsilon-eridani").not_nil!.status.should eq("unaligned")
  end

  it "requires Forward Starbases and aligned near systems for distant exploration" do
    state = core_state
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT)
    engine.can_explore_distant?(state).should be_false
    state.technologies << "forward-starbases"
    engine.can_explore_distant?(state).should be_true
    state.systems << MicroSpaceEmpire::SystemState.new("tau-ceti", "unaligned")
    engine.can_explore_distant?(state).should be_false
  end

  it "collects with storage caps and supports one Commerce trade" do
    state = core_state
    state.phase = "collect"
    state.subphase = "collect"
    state.metal = 2
    state.wealth = 2
    state.technologies << "interspecies-commerce"
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT)
    engine.apply(state, "collect_resources")
    state.metal.should eq(3)
    state.wealth.should eq(3)
    expect_raises(MicroSpaceEmpire::RuleError, "Wealth storage is full.") do
      engine.apply(state, "trade_metal_for_wealth")
    end
    state.wealth = 1
    engine.apply(state, "trade_metal_for_wealth").should be_nil
    state.metal.should eq(1)
    state.wealth.should eq(2)
    expect_raises(MicroSpaceEmpire::RuleError, "Only one commerce trade is allowed per turn.") do
      engine.apply(state, "trade_wealth_for_metal")
    end
  end

  it "halves Strike production with Robot Workers and rounds up" do
    state = core_state
    state.phase = "collect"
    state.subphase = "collect"
    state.strike_collections = 1
    state.technologies << "robot-workers"
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT)
    engine.apply(state, "collect_resources")
    state.metal.should eq(1)
    state.wealth.should eq(1)
    state.strike_collections.should eq(0)
  end

  it "builds and researches at most once with prerequisites" do
    state = core_state
    state.phase = "build"
    state.subphase = "choose"
    state.metal = 3
    state.wealth = 5
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT)
    engine.apply(state, "build_military")
    state.military.should eq(1)
    expect_raises(MicroSpaceEmpire::RuleError) { engine.apply(state, "build_military") }
    expect_raises(MicroSpaceEmpire::RuleError) { engine.apply(state, "research", "forward-starbases") }
    engine.apply(state, "research", "capital-ships")
    state.has_technology?("capital-ships").should be_true
    expect_raises(MicroSpaceEmpire::RuleError) { engine.apply(state, "research", "robot-workers") }
  end

  it "makes Diplomacy available only during the following phase one" do
    state = core_state
    state.phase = "build"
    state.subphase = "choose"
    state.wealth = 5
    state.technologies << "hyper-television"
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT)
    engine.apply(state, "research", "interstellar-diplomacy")
    state.diplomacy_available_turn.should eq(2)
  end

  it "resolves invasion defenses and revolt ties deterministically" do
    state = core_state
    state.systems << MicroSpaceEmpire::SystemState.new("tau-ceti", "controlled", 2)
    state.systems << MicroSpaceEmpire::SystemState.new("cygnus", "controlled", 3)
    state.phase = "event"
    state.subphase = "reveal"
    state.event_deck = ["small-invasion"]
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT, MicroSpaceEmpire::ScriptedRandomSource.new([5]))
    engine.apply(state, "reveal_event")
    state.pending_target.should eq("cygnus")
    engine.apply(state, "roll_event")
    state.system_state("cygnus").not_nil!.status.should eq("unaligned")
  end

  it "protects the lone Home World in Year 1 and loses it in Year 2" do
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT)
    year_one = core_state
    year_one.phase = "event"
    year_one.subphase = "reveal"
    year_one.event_deck = ["large-invasion"]
    engine.apply(year_one, "reveal_event")
    year_one.status.should eq("active")
    year_one.subphase.should eq("ack_event")

    year_two = core_state
    year_two.year = 2
    year_two.phase = "event"
    year_two.subphase = "reveal"
    year_two.event_deck = ["large-invasion"]
    engine.apply(year_two, "reveal_event")
    year_two.status.should eq("lost")
    year_two.score.should_not be_nil
  end

  it "suppresses only the Meteor target for two collections" do
    state = core_state
    target = MicroSpaceEmpire::SystemState.new("wolf-359", "controlled", 2)
    state.systems << target
    state.phase = "event"
    state.subphase = "reveal"
    state.event_deck = ["meteor-storms"]
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT)
    engine.apply(state, "reveal_event")
    target.production_disabled_collections.should eq(2)
    engine.production(state).should eq({1, 1})
  end

  it "permanently discards a Pandemic target when no cure is chosen" do
    state = core_state
    target = MicroSpaceEmpire::SystemState.new("wolf-359", "controlled", 2)
    state.systems << target
    state.phase = "event"
    state.subphase = "reveal"
    state.event_deck = ["pandemic"]
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT)
    engine.apply(state, "reveal_event")
    engine.apply(state, "resolve_pandemic", choice: "lose")
    target.status.should eq("discarded")
  end

  it "computes all bonuses at the end of Year 2" do
    state = core_state
    state.year = 2
    state.phase = "event"
    state.subphase = "ack_event"
    state.event_deck.clear
    state.near_deck.clear
    state.distant_deck.clear
    state.selected_system_ids.each do |id|
      next if id == "home-world"
      state.systems << MicroSpaceEmpire::SystemState.new(id, "controlled", state.acquire_counter += 1)
    end
    state.technologies = CONTENT.technologies.keys
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT)
    engine.apply(state, "finish_event")
    state.status.should eq("completed")
    score = state.score.not_nil!
    score.exploration_bonus.should eq(1)
    score.scientific_bonus.should eq(1)
    score.warlord_bonus.should eq(3)
  end

  it "plays a deterministic thirteen-turn game through completion" do
    state = core_state
    state.event_pool = Array.new(6, "peace-and-quiet")
    state.event_deck = Array.new(7, "peace-and-quiet")
    engine = MicroSpaceEmpire::GameEngine.new(CONTENT)
    safety = 0
    while state.active?
      safety += 1
      raise "game loop did not terminate" if safety > 100
      case state.phase
      when "phase_one"
        engine.apply(state, "bide")
      when "collect"
        state.subphase == "collect" ? engine.apply(state, "collect_resources") : engine.apply(state, "finish_collection")
      when "build"
        engine.apply(state, "finish_build")
      when "event"
        state.subphase == "reveal" ? engine.apply(state, "reveal_event") : engine.apply(state, "finish_event")
      end
    end
    state.status.should eq("completed")
    state.year.should eq(2)
    state.turn.should eq(13)
    state.score.not_nil!.total.should eq(0)
  end
end
