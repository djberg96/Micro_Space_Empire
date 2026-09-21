module MicroSpaceEmpire
  module EmbeddedFiles
    FILES = begin
      files = {} of String => String
      {{ run("#{__DIR__}/../../scripts/list_embedded_files.cr").id }}
      files
    end

    def self.fetch(path : String) : String
      FILES.fetch(path) { raise KeyError.new("Embedded file not found: #{path}") }
    end

    def self.has_key?(path : String) : Bool
      FILES.has_key?(path)
    end
  end
end
