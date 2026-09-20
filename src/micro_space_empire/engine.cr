module MicroSpaceEmpire
  class RuleError < Exception
  end

  class GameEngine
    getter content : Content

    def initialize(@content : Content, @random : RandomSource = SecureRandomSource.new)
    end

    def new_game(expansion : Bool) : GameState
      state = GameState.new(content.version, expansion)
      state.systems << SystemState.new("home-world", "controlled", 1)

      near = content.systems.values.select { |card| card.distance == "near" && (expansion || !card.expansion) }.map(&.id)
      distant = content.systems.values.select { |card| card.distance == "distant" && !card.expansion }.map(&.id)
      selected_near = expansion ? shuffled(near).first(7) : shuffled(near)
      selected_distant = shuffled(distant)
      state.selected_system_ids = ["home-world"] + selected_near + selected_distant
      state.near_deck = shuffled(selected_near)
      state.distant_deck = shuffled(selected_distant)

      events = content.events.values.select { |card| expansion || !card.expansion }.map(&.id)
      state.event_pool = events
      state.event_deck = shuffled(events).first(7)
      state
    end

    def apply(state : GameState, action : String, target : String? = nil, choice : String? = nil) : Nil
      raise RuleError.new("This game is finished.") unless state.active?
      state.last_roll = nil

      case state.phase
      when "phase_one"
        apply_phase_one(state, action, target)
      when "collect"
        apply_collect(state, action)
      when "build"
        apply_build(state, action, target)
      when "event"
        apply_event(state, action, choice)
      else
        raise RuleError.new("Unknown game phase.")
      end
    end

    def storage_cap(state : GameState) : Int32
      state.has_technology?("interstellar-banking") ? 5 : 3
    end

    def military_cap(state : GameState) : Int32
      state.has_technology?("capital-ships") ? 5 : 3
    end

    def production(state : GameState) : Tuple(Int32, Int32)
      metal = 0
      wealth = 0
      state.controlled_systems.each do |system|
        next if system.production_disabled_collections > 0
        card = content.systems[system.id]
        metal += card.metal
        wealth += card.wealth
      end
      {metal, wealth}
    end

    def can_explore_near?(state : GameState) : Bool
      state.phase == "phase_one" && state.subphase == "choose" && !state.near_deck.empty?
    end

    def can_explore_distant?(state : GameState) : Bool
      state.phase == "phase_one" && state.subphase == "choose" &&
        !state.distant_deck.empty? && state.has_technology?("forward-starbases") &&
        state.unaligned_systems.none? { |system| content.systems[system.id].distance == "near" }
    end

    def can_research?(state : GameState, tech : Technology) : Bool
      return false unless state.phase == "build" && !state.researched_technology
      return false if state.has_technology?(tech.id) || state.wealth < tech.cost
      prerequisite = tech.prerequisite
      prerequisite.nil? || state.has_technology?(prerequisite)
    end

    private def apply_phase_one(state : GameState, action : String, target : String?) : Nil
      if state.subphase == "choose"
        case action
        when "explore_near"
          raise RuleError.new("No near systems remain to explore.") unless can_explore_near?(state)
          begin_exploration(state, state.near_deck.shift)
        when "explore_distant"
          unless can_explore_distant?(state)
            raise RuleError.new("Distant exploration requires Forward Starbases and no unaligned near systems.")
          end
          begin_exploration(state, state.distant_deck.shift)
        when "conquer"
          id = target || raise RuleError.new("Choose an unaligned system.")
          system = state.system_state(id)
          raise RuleError.new("That system is not available to conquer.") unless system && system.status == "unaligned"
          state.current_system = id
          state.pending_target = id
          state.subphase = "attack"
          transition(state, "Preparing to reconquer #{content.systems[id].name}.")
        when "bide"
          finish_phase_one(state)
          transition(state, "The empire bides its time.")
        else
          raise RuleError.new("Choose Explore, Conquer, or Bide Time.")
        end
      elsif state.subphase == "attack"
        id = state.pending_target || raise RuleError.new("No system is awaiting an attack.")
        card = content.systems[id]
        case action
        when "roll_attack"
          roll = roll_die
          state.last_roll = roll
          military_before_battle = state.military
          total = roll + military_before_battle
          system = state.system_state(id) || raise RuleError.new("The target system is missing.")
          if total >= card.resistance.not_nil!
            control_system(state, system)
            transition(state, "Rolled #{roll} + #{military_before_battle} military: #{card.name} joins the empire.")
          else
            state.military = Math.max(0, state.military - 1)
            system.status = "unaligned"
            transition(state, "Rolled #{roll} + #{military_before_battle} military against resistance #{card.resistance}; the attack failed and military fell to #{state.military}.")
          end
          finish_phase_one(state)
        when "use_diplomacy"
          unless state.diplomacy_available_turn == state.turn
            raise RuleError.new("Interstellar Diplomacy is not available this turn.")
          end
          system = state.system_state(id) || raise RuleError.new("The target system is missing.")
          control_system(state, system)
          transition(state, "Interstellar Diplomacy brings #{card.name} into the empire without a roll.")
          finish_phase_one(state)
        else
          raise RuleError.new("This attack must be resolved.")
        end
      else
        raise RuleError.new("The current phase-one step is invalid.")
      end
    end

    private def begin_exploration(state : GameState, id : String) : Nil
      state.systems << SystemState.new(id, "pending")
      state.current_system = id
      state.pending_target = id
      state.subphase = "attack"
      transition(state, "#{content.systems[id].name} is revealed. An attack is mandatory.")
    end

    private def control_system(state : GameState, system : SystemState) : Nil
      state.acquire_counter += 1
      system.status = "controlled"
      system.acquired_order = state.acquire_counter
    end

    private def finish_phase_one(state : GameState) : Nil
      if available = state.diplomacy_available_turn
        state.diplomacy_available_turn = nil if available <= state.turn
      end
      state.current_system = nil
      state.pending_target = nil
      state.phase = "collect"
      state.subphase = "collect"
      state.collection_trade_used = false
    end

    private def apply_collect(state : GameState, action : String) : Nil
      if state.subphase == "collect"
        raise RuleError.new("Collect resources before continuing.") unless action == "collect_resources"
        metal_gain, wealth_gain = production(state)
        if state.strike_collections > 0
          if state.has_technology?("robot-workers")
            metal_gain = (metal_gain + 1) // 2
            wealth_gain = (wealth_gain + 1) // 2
          else
            metal_gain = 0
            wealth_gain = 0
          end
          state.strike_collections -= 1
        end
        cap = storage_cap(state)
        old_metal = state.metal
        old_wealth = state.wealth
        state.metal = Math.min(cap, state.metal + metal_gain)
        state.wealth = Math.min(cap, state.wealth + wealth_gain)
        state.systems.each do |system|
          if system.production_disabled_collections > 0
            system.production_disabled_collections -= 1
          end
        end
        state.subphase = "trade"
        transition(state, "Collected #{state.metal - old_metal} Metal and #{state.wealth - old_wealth} Wealth.")
        return
      end

      raise RuleError.new("Resource collection is not ready.") unless state.subphase == "trade"
      case action
      when "trade_metal_for_wealth"
        trade(state, "metal")
      when "trade_wealth_for_metal"
        trade(state, "wealth")
      when "finish_collection"
        state.phase = "build"
        state.subphase = "choose"
        state.built_military = false
        state.researched_technology = false
        transition(state, "Collection is complete. Build military and technology.")
      else
        raise RuleError.new("Choose a commerce trade or continue.")
      end
    end

    private def trade(state : GameState, spend : String) : Nil
      raise RuleError.new("Interspecies Commerce has not been researched.") unless state.has_technology?("interspecies-commerce")
      raise RuleError.new("Only one commerce trade is allowed per turn.") if state.collection_trade_used
      cap = storage_cap(state)
      if spend == "metal"
        raise RuleError.new("Two Metal are required.") if state.metal < 2
        raise RuleError.new("Wealth storage is full.") if state.wealth >= cap
        state.metal -= 2
        state.wealth += 1
        transition(state, "Traded 2 Metal for 1 Wealth.")
      else
        raise RuleError.new("Two Wealth are required.") if state.wealth < 2
        raise RuleError.new("Metal storage is full.") if state.metal >= cap
        state.wealth -= 2
        state.metal += 1
        transition(state, "Traded 2 Wealth for 1 Metal.")
      end
      state.collection_trade_used = true
    end

    private def apply_build(state : GameState, action : String, target : String?) : Nil
      raise RuleError.new("The build phase is not ready.") unless state.subphase == "choose"
      case action
      when "build_military"
        raise RuleError.new("Military may only be built once per turn.") if state.built_military
        raise RuleError.new("One Metal and one Wealth are required.") if state.metal < 1 || state.wealth < 1
        raise RuleError.new("Military strength is already at its current limit.") if state.military >= military_cap(state)
        state.metal -= 1
        state.wealth -= 1
        state.military += 1
        state.built_military = true
        transition(state, "Military strength increased to #{state.military}.")
      when "research"
        id = target || raise RuleError.new("Choose a technology.")
        tech = content.technologies[id]? || raise RuleError.new("Unknown technology.")
        raise RuleError.new("That technology cannot be researched now.") unless can_research?(state, tech)
        state.wealth -= tech.cost
        state.technologies << tech.id
        state.researched_technology = true
        state.diplomacy_available_turn = state.turn + 1 if tech.id == "interstellar-diplomacy"
        transition(state, "Researched #{tech.name}.")
      when "finish_build"
        state.phase = "event"
        state.subphase = "reveal"
        transition(state, "Construction is complete. Reveal an event.")
      else
        raise RuleError.new("Choose a build action or continue.")
      end
    end

    private def apply_event(state : GameState, action : String, choice : String?) : Nil
      case state.subphase
      when "reveal"
        raise RuleError.new("Reveal the next event.") unless action == "reveal_event"
        reveal_event(state)
      when "roll_event"
        raise RuleError.new("Roll to resolve the event.") unless action == "roll_event"
        resolve_attack_event(state)
      when "pandemic_choice"
        raise RuleError.new("Resolve the Pandemic.") unless action == "resolve_pandemic"
        resolve_pandemic(state, choice || "")
      when "ack_event"
        raise RuleError.new("Finish resolving the event.") unless action == "finish_event"
        finish_event(state)
      else
        raise RuleError.new("The event step is invalid.")
      end
    end

    private def reveal_event(state : GameState) : Nil
      id = state.event_deck.shift? || raise RuleError.new("The event deck is empty.")
      state.current_event = id
      card = content.events[id]
      transition(state, "Event revealed: #{card.name}.")

      case card.kind
      when "resource"
        cap = storage_cap(state)
        amount = card.value(state.year)
        if card.resource == "metal"
          old = state.metal
          state.metal = Math.min(cap, state.metal + amount)
          transition(state, "#{card.name}: gained #{state.metal - old} Metal.")
        else
          old = state.wealth
          state.wealth = Math.min(cap, state.wealth + amount)
          transition(state, "#{card.name}: gained #{state.wealth - old} Wealth.")
        end
        state.subphase = "ack_event"
      when "strike"
        state.strike_collections = Math.max(state.strike_collections, 1)
        transition(state, "Strike: the next collection is disrupted.")
        state.subphase = "ack_event"
      when "none"
        transition(state, "Peace and quiet. Nothing happens.")
        state.subphase = "ack_event"
      when "alien"
        old = state.military
        state.military = Math.min(military_cap(state), state.military + 1)
        transition(state, "The alliance increases Military by #{state.military - old}.")
        state.subphase = "ack_event"
      when "revolt", "invasion", "meteor", "pandemic"
        if only_home_world?(state)
          handle_home_world_event(state, card)
        elsif card.kind == "meteor"
          target = most_recent_system(state)
          state.pending_target = target.id
          definition = content.systems[target.id]
          if definition.metal > 0 || definition.wealth > 0
            target.production_disabled_collections = 2
            transition(state, "Meteor Storms disable #{definition.name}'s production for two collections.")
          else
            transition(state, "Meteor Storms hit #{definition.name}, which produces no resources.")
          end
          state.subphase = "ack_event"
        elsif card.kind == "pandemic"
          target = most_recent_system(state)
          state.pending_target = target.id
          transition(state, "Pandemic threatens #{content.systems[target.id].name}.")
          state.subphase = "pandemic_choice"
        else
          target = card.kind == "revolt" ? lowest_resistance_system(state) : most_recent_system(state)
          state.pending_target = target.id
          transition(state, "#{card.name} targets #{content.systems[target.id].name}. Roll to resolve it.")
          state.subphase = "roll_event"
        end
      else
        raise RuleError.new("Unknown event type #{card.kind}.")
      end
    end

    private def handle_home_world_event(state : GameState, card : EventCard) : Nil
      if state.year == 1
        transition(state, "#{card.name} has no effect while only the Home World remains in Year 1.")
        state.subphase = "ack_event"
      else
        state.status = "lost"
        state.score = calculate_score(state)
        transition(state, "#{card.name} overwhelms the Home World. The empire is lost.")
      end
    end

    private def resolve_attack_event(state : GameState) : Nil
      event = content.events[state.current_event.not_nil!]
      target = state.system_state(state.pending_target.not_nil!) || raise RuleError.new("Event target is missing.")
      definition = content.systems[target.id]
      defense = definition.resistance.not_nil!
      defense += 1 if event.kind == "revolt" && state.has_technology?("hyper-television")
      defense += 1 if event.kind == "invasion" && state.has_technology?("planetary-defenses")
      roll = roll_die
      state.last_roll = roll
      force = event.value(state.year)
      if roll + force >= defense
        target.status = "unaligned"
        transition(state, "Rolled #{roll} + #{force} force against #{defense}: #{definition.name} becomes unaligned.")
      else
        transition(state, "Rolled #{roll} + #{force} force against #{defense}: #{definition.name} remains loyal.")
      end
      state.subphase = "ack_event"
    end

    private def resolve_pandemic(state : GameState, choice : String) : Nil
      target = state.system_state(state.pending_target.not_nil!) || raise RuleError.new("Pandemic target is missing.")
      name = content.systems[target.id].name
      case choice
      when "wealth"
        raise RuleError.new("One Wealth is required.") if state.wealth < 1
        state.wealth -= 1
        transition(state, "Spent 1 Wealth to cure the Pandemic on #{name}.")
      when "metal"
        raise RuleError.new("Two Metal are required.") if state.metal < 2
        state.metal -= 2
        transition(state, "Spent 2 Metal to cure the Pandemic on #{name}.")
      when "lose"
        target.status = "discarded"
        transition(state, "#{name} is permanently lost to the Pandemic.")
      else
        raise RuleError.new("Choose a valid Pandemic response.")
      end
      state.subphase = "ack_event"
    end

    private def finish_event(state : GameState) : Nil
      state.event_draws_this_year += 1
      state.current_event = nil
      state.pending_target = nil
      if state.event_deck.empty?
        if state.year == 1
          state.year = 2
          state.event_draws_this_year = 0
          state.event_deck = shuffled(state.event_pool).first(6)
          state.turn += 1
          begin_turn(state)
          transition(state, "Year 2 begins. Six events remain.")
        else
          state.status = "completed"
          state.score = calculate_score(state)
          transition(state, "Year 2 is complete. Final score: #{state.score.not_nil!.total}.")
        end
      else
        state.turn += 1
        begin_turn(state)
        transition(state, "Turn #{state.turn} begins.")
      end
    end

    private def begin_turn(state : GameState) : Nil
      state.phase = "phase_one"
      state.subphase = "choose"
      state.collection_trade_used = false
      state.built_military = false
      state.researched_technology = false
      state.last_roll = nil
    end

    private def only_home_world?(state : GameState) : Bool
      state.controlled_systems.none? { |system| system.id != "home-world" }
    end

    private def most_recent_system(state : GameState) : SystemState
      state.controlled_systems.reject { |system| system.id == "home-world" }.max_by(&.acquired_order)
    end

    private def lowest_resistance_system(state : GameState) : SystemState
      candidates = state.controlled_systems.reject { |system| system.id == "home-world" }
      lowest = candidates.min_of { |system| content.systems[system.id].resistance.not_nil! }
      tied = candidates.select { |system| content.systems[system.id].resistance == lowest }
      tied[@random.next_int(tied.size)]
    end

    private def calculate_score(state : GameState) : Score
      system_points = state.controlled_systems.sum { |system| content.systems[system.id].victory }
      all_explored = state.near_deck.empty? && state.distant_deck.empty?
      all_technologies = state.technologies.size == content.technologies.size
      all_controlled = state.selected_system_ids.all? do |id|
        system = state.system_state(id)
        system && system.status == "controlled"
      end
      Score.new(
        systems: system_points,
        technologies: state.technologies.size,
        exploration_bonus: all_explored ? 1 : 0,
        scientific_bonus: all_technologies ? 1 : 0,
        warlord_bonus: all_controlled ? 3 : 0
      )
    end

    private def roll_die : Int32
      @random.next_int(6) + 1
    end

    private def shuffled(values : Array(String)) : Array(String)
      result = values.dup
      i = result.size - 1
      while i > 0
        j = @random.next_int(i + 1)
        result[i], result[j] = result[j], result[i]
        i -= 1
      end
      result
    end

    private def transition(state : GameState, message : String) : Nil
      state.last_transition = message
      state.log << message
      state.log.shift if state.log.size > 60
    end
  end
end
