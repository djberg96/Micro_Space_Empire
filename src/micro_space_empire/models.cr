require "json"

module MicroSpaceEmpire
  class SystemState
    include JSON::Serializable

    property id : String
    property status : String
    property acquired_order : Int32
    property production_disabled_collections : Int32

    def initialize(@id, @status = "unaligned", @acquired_order = 0, @production_disabled_collections = 0)
    end
  end

  class Score
    include JSON::Serializable

    property systems : Int32
    property technologies : Int32
    property exploration_bonus : Int32
    property scientific_bonus : Int32
    property warlord_bonus : Int32

    def initialize(@systems = 0, @technologies = 0, @exploration_bonus = 0, @scientific_bonus = 0, @warlord_bonus = 0)
    end

    def total : Int32
      systems + technologies + exploration_bonus + scientific_bonus + warlord_bonus
    end
  end

  class GameState
    include JSON::Serializable

    property content_version : String
    property expansion : Bool
    property status : String
    property year : Int32
    property turn : Int32
    property phase : String
    property subphase : String
    property metal : Int32
    property wealth : Int32
    property military : Int32
    property technologies : Array(String)
    property systems : Array(SystemState)
    property selected_system_ids : Array(String)
    property near_deck : Array(String)
    property distant_deck : Array(String)
    property event_pool : Array(String)
    property event_deck : Array(String)
    property current_system : String?
    property current_event : String?
    property pending_target : String?
    property event_draws_this_year : Int32
    property strike_collections : Int32
    property collection_trade_used : Bool
    property built_military : Bool
    property researched_technology : Bool
    property diplomacy_available_turn : Int32?
    property acquire_counter : Int32
    property last_roll : Int32?
    property last_transition : String
    property log : Array(String)
    property score : Score?

    def initialize(@content_version, @expansion)
      @status = "active"
      @year = 1
      @turn = 1
      @phase = "phase_one"
      @subphase = "choose"
      @metal = 0
      @wealth = 0
      @military = 0
      @technologies = [] of String
      @systems = [] of SystemState
      @selected_system_ids = [] of String
      @near_deck = [] of String
      @distant_deck = [] of String
      @event_pool = [] of String
      @event_deck = [] of String
      @current_system = nil
      @current_event = nil
      @pending_target = nil
      @event_draws_this_year = 0
      @strike_collections = 0
      @collection_trade_used = false
      @built_military = false
      @researched_technology = false
      @diplomacy_available_turn = nil
      @acquire_counter = 1
      @last_roll = nil
      @last_transition = "A new empire begins."
      @log = ["Year 1 begins at the Home World."]
      @score = nil
    end

    def active? : Bool
      status == "active"
    end

    def has_technology?(id : String) : Bool
      technologies.includes?(id)
    end

    def system_state(id : String) : SystemState?
      systems.find { |system| system.id == id }
    end

    def controlled_systems : Array(SystemState)
      systems.select { |system| system.status == "controlled" }
    end

    def unaligned_systems : Array(SystemState)
      systems.select { |system| system.status == "unaligned" }
    end
  end

  class SaveRecord
    getter id : Int64
    getter name : String
    getter state : GameState
    getter version : Int32
    getter created_at : String
    getter updated_at : String

    def initialize(@id, @name, @state, @version, @created_at, @updated_at)
    end
  end

  class SaveSummary
    getter id : Int64
    getter name : String
    getter status : String
    getter year : Int32
    getter turn : Int32
    getter expansion : Bool
    getter score : Int32?
    getter updated_at : String

    def initialize(@id, @name, @status, @year, @turn, @expansion, @score, @updated_at)
    end
  end
end
