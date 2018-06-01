class String
  def match?(regexp)
    self =~ regexp
  end
end unless String.method_defined?(:match?)