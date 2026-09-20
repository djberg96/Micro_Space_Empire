require "random/secure"

module MicroSpaceEmpire
  abstract class RandomSource
    abstract def next_int(max : Int32) : Int32
  end

  class SecureRandomSource < RandomSource
    def next_int(max : Int32) : Int32
      Random::Secure.rand(max)
    end
  end

  class ScriptedRandomSource < RandomSource
    def initialize(@values : Array(Int32))
      @index = 0
    end

    def next_int(max : Int32) : Int32
      value = @values[@index]? || 0
      @index += 1
      value % max
    end
  end
end
