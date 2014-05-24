module JunitMerge
  VERSION = [0, 1, 2]

  class << VERSION
    include Comparable

    def to_s
      join('.')
    end
  end
end
