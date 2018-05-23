require 'base62-rb'

class Integer
  def to_base62
    Base62.encode(self )
  end
end
