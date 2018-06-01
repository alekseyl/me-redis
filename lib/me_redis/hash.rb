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

end unless Hash.method_defined?(:transform_keys)