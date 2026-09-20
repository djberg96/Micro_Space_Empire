require "json"

module MicroSpaceEmpire
  class SystemCard
    include JSON::Serializable

    getter id : String
    getter name : String
    getter distance : String
    getter resistance : Int32?
    getter metal : Int32
    getter wealth : Int32
    getter victory : Int32
    getter expansion : Bool

    def front_path : String
      "/assets/cards/systems/#{id}/front.webp"
    end

    def back_path : String
      "/assets/cards/systems/#{id}/back.webp"
    end
  end

  class EventCard
    include JSON::Serializable

    getter id : String
    getter name : String
    getter kind : String
    getter resource : String?
    getter year1 : Int32
    getter year2 : Int32
    getter expansion : Bool

    def value(year : Int32) : Int32
      year == 1 ? year1 : year2
    end

    def front_path : String
      "/assets/cards/events/#{id}/front.webp"
    end

    def back_path : String
      "/assets/cards/events/#{id}/back.webp"
    end
  end

  class Technology
    include JSON::Serializable

    getter id : String
    getter name : String
    getter cost : Int32
    getter prerequisite : String?
    getter description : String
  end

  private class SystemManifest
    include JSON::Serializable
    getter version : String
    getter cards : Array(SystemCard)
  end

  private class EventManifest
    include JSON::Serializable
    getter version : String
    getter cards : Array(EventCard)
  end

  private class TechnologyManifest
    include JSON::Serializable
    getter version : String
    getter technologies : Array(Technology)
  end

  class Content
    getter version : String
    getter systems : Hash(String, SystemCard)
    getter events : Hash(String, EventCard)
    getter technologies : Hash(String, Technology)

    def self.load(root : String = ENV.fetch("MSE_ROOT", Dir.current)) : Content
      system_manifest = SystemManifest.from_json(File.read(File.join(root, "data", "systems.json")))
      event_manifest = EventManifest.from_json(File.read(File.join(root, "data", "events.json")))
      tech_manifest = TechnologyManifest.from_json(File.read(File.join(root, "data", "technologies.json")))
      version = system_manifest.version
      unless event_manifest.version == version && tech_manifest.version == version
        raise "Content manifest versions do not match"
      end

      new(
        version,
        system_manifest.cards.to_h { |card| {card.id, card} },
        event_manifest.cards.to_h { |card| {card.id, card} },
        tech_manifest.technologies.to_h { |tech| {tech.id, tech} }
      )
    end

    def initialize(@version, @systems, @events, @technologies)
    end

    def validate!(root : String = ENV.fetch("MSE_ROOT", Dir.current)) : Nil
      raise "Expected 13 system definitions" unless systems.size == 13
      raise "Expected 11 event definitions" unless events.size == 11
      raise "Expected 8 technologies" unless technologies.size == 8
      raise "Original Asteroid values must be +1 Wealth in both years" unless events["asteroid"].year1 == 1 && events["asteroid"].year2 == 1 && events["asteroid"].resource == "wealth"

      systems.each_value do |card|
        {card.front_path, card.back_path}.each do |web_path|
          path = File.join(root, "public", web_path.lchop('/'))
          raise "Missing card asset: #{path}" unless File.exists?(path)
        end
      end
      events.each_value do |card|
        {card.front_path, card.back_path}.each do |web_path|
          path = File.join(root, "public", web_path.lchop('/'))
          raise "Missing card asset: #{path}" unless File.exists?(path)
        end
      end
    end
  end
end
