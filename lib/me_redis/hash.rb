# ruby 2.3 support
class Hash
  # Returns a new hash with all keys converted using the +block+ operation.
  #
  #  hash = { name: 'Rob', age: '28' }
  #
  #  hash.transform_keys { |key| key.to_s.upcase } # => {"NAME"=>"Rob", "AGE"=>"28"}
  #
  # If you do not provide a +block+, it will return an Enumerator
  # for chaining with other methods:
  #
  #  hash.transform_keys.with_index { |k, i| [k, i].join } # => {"name0"=>"Rob", "age1"=>"28"}
  def transform_keys
    return enum_for(:transform_keys) { size } unless block_given?
    result = {}
    each_key do |key|
      result[yield(key)] = self[key]
    end
    result
  end
  # Destructively converts all keys using the +block+ operations.
  # Same as +transform_keys+ but modifies +self+.
  def transform_keys!
    return enum_for(:transform_keys!) { size } unless block_given?
    keys.each do |key|
      self[yield(key)] = delete(key)
    end
    self
  end
  # Returns a new hash with the results of running +block+ once for every value.
  # The keys are unchanged.
  #
  #   { a: 1, b: 2, c: 3 }.transform_values { |x| x * 2 } # => { a: 2, b: 4, c: 6 }
  #
  # If you do not provide a +block+, it will return an Enumerator
  # for chaining with other methods:
  #
  #   { a: 1, b: 2 }.transform_values.with_index { |v, i| [v, i].join.to_i } # => { a: 10, b: 21 }
  def transform_values
    return enum_for(:transform_values) { size } unless block_given?
    return {} if empty?
    result = self.class.new
    each do |key, value|
      result[key] = yield(value)
    end
    result
  end

  # Destructively converts all values using the +block+ operations.
  # Same as +transform_values+ but modifies +self+.
  def transform_values!
    return enum_for(:transform_values!) { size } unless block_given?
    each do |key, value|
      self[key] = yield(value)
    end
  end

end unless Hash.method_defined?(:transform_keys)