require "ecr"
require "html"

module MicroSpaceEmpire
  class Renderer
    def initialize(@content : Content, @engine : GameEngine)
    end

    def menu(saves : Array(SaveSummary), error : String? = nil) : String
      page("Micro Space Empire", ECR.render("src/views/menu.ecr"))
    end

    def game(record : SaveRecord, error : String? = nil) : String
      page(record.name, game_shell(record, error))
    end

    def game_shell(record : SaveRecord, error : String? = nil) : String
      state = record.state
      ECR.render("src/views/game_shell.ecr")
    end

    def rules : String
      page("Rules", ECR.render("src/views/rules.ecr"))
    end

    def h(value) : String
      HTML.escape(value.to_s)
    end

    def system_card(id : String) : SystemCard
      @content.systems[id]
    end

    def event_card(id : String) : EventCard
      @content.events[id]
    end

    def technologies : Array(Technology)
      @content.technologies.values
    end

    def research_hint(state : GameState, tech : Technology) : String
      return tech.description if @engine.can_research?(state, tech)
      return "Only one technology may be researched each turn." if state.researched_technology
      if prerequisite = tech.prerequisite
        return "Requires #{@content.technologies[prerequisite].name}." unless state.has_technology?(prerequisite)
      end
      return "Requires #{tech.cost} Wealth." if state.wealth < tech.cost
      tech.description
    end

    def military_hint(state : GameState) : String
      return "Military may only be built once each turn." if state.built_military
      return "Requires 1 Metal and 1 Wealth." if state.metal < 1 || state.wealth < 1
      return "Current Military limit reached." if state.military >= @engine.military_cap(state)
      "Spend 1 Metal and 1 Wealth to gain 1 Military."
    end

    def phase_title(state : GameState) : String
      return state.status == "lost" ? "Empire Lost" : "Final Score" unless state.active?
      case state.phase
      when "phase_one" then "1 · Explore or Conquer"
      when "collect"   then "2 · Collect Resources"
      when "build"     then "3 · Build and Research"
      when "event"     then "4 · Event"
      else                  "Unknown phase"
      end
    end

    def phase_help(state : GameState) : String
      return "This game is complete and remains available as a read-only record." unless state.active?
      case state.phase
      when "phase_one"
        state.subphase == "attack" ? "Resolve the mandatory attack before continuing." : "Explore a system, reconquer an unaligned world, or safely bide your time."
      when "collect"
        state.subphase == "collect" ? "Collect production up to your storage limit." : "Make one optional Commerce trade, then continue."
      when "build"
        "Build Military and research Technology in either order, at most once each."
      when "event"
        "Reveal and completely resolve the next event."
      else
        ""
      end
    end

    def page(title : String, body : String) : String
      <<-HTML
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <meta name="color-scheme" content="dark">
            <title>#{h(title)} · Micro Space Empire</title>
            <link rel="stylesheet" href="/assets/app.css">
            <script src="/assets/app.js" defer></script>
          </head>
          <body>#{body}</body>
        </html>
      HTML
    end
  end
end
