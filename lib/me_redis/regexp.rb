class Regexp
  def match?(string)
    string =~ self
  end
end unless Regexp.method_defined?(:match?)