#We need only to fallback getters, when you are setting
# new value it will go in a new place already
# me_mget doesn't compartible with pipeline, it will raise exception when placed inside one.
module MeRedisHotMigrator
  ZK_FALLBACK_METHODS = %i[mget hget hgetall get exists type getset]

  def self.included(base)
    base::Future.prepend(FutureMigrator)

    base.class_eval do
      ZK_FALLBACK_METHODS.each do |method|
        alias_method "_#{method}", method
      end

      include(MeRedis)

      def me_get( key )
        prev_future = _get( key ) unless @client.is_a?(self.class::Client)
        newvl = super(key)

        newvl.prev_future = prev_future if newvl.is_a?(self.class::Future)
        newvl || _get( key )
      end

      def me_mget(*keys)
        #cannot run in pipeline because of fallbacks
        raise 'Cannot run in pipeline!!!' unless @client.is_a?(self.class::Client)
        me_mget_p(*keys).map(&:value)
      end

    end

    base.prepend( MeRedisHotMigrator::PrependMethods )
  end

  module PrependMethods
    ZK_FALLBACK_METHODS.each do |method|
      define_method(method) do |*args|
        prev_future = send("_#{method}", *args) unless @client.is_a?(self.class::Client)
        newvl = super(*args)

        newvl.prev_future = prev_future if newvl.is_a?(self.class::Future)

        if method != :mget
          newvl || send("_#{method}", *args)
        else
          newvl.is_a?(Array) ? newvl.zip( send("_#{method}", *args) ).map!{|nvl, oldv| nvl || oldv } : newvl
        end

      end
    end
  end


  #-------------------------------ME method migration------------------------------
  #check if migration possible, if not raises exception with a reason
  def hash_migration_possible?( keys )
    result = keys.map{ |key| [split_key(key).each_with_index.map{|v,i| i == 0 ? zip_key(v) : v }, key] }.to_h

    raise ArgumentError.new( "Hash zipping is not one to one! #{result.keys} != #{keys}" ) if result.length != keys.length

    result.each do |sp_key, key|
      key_start = key.to_s.scan(/\A(.*?)(\d+)\z/).flatten[0]
      if sp_key[0].start_with?( key_start )
        raise ArgumentError.new( "#{sp_key[0]} contains original key main part: #{key_start} Hash migration must be done with key zipping!")
      end
    end

    true
  end

  # keys will exists after migrate, you need to call del(keys) directly
  # uses hsetnx, meaning you will not overwrtite new values
  def migrate_to_hash_representation( keys )
    raise StandardError.new('Cannot migrate inside pipeline.') unless @client.is_a?( self.class::Client )
    raise ArgumentError.new('Migration is unavailable!') unless hash_migration_possible?( keys )

    values = mget( keys )
    pipelined do
      keys.each_with_index do |key, i|
        me_setnx( key, values[i] )
      end
    end
  end

  def reverse_from_hash_representation!( keys )
    raise "Cannot migrate inside pipeline" unless @client.is_a?(self.class::Client )
    values = me_mget( keys )

    pipelined do
      keys.each_with_index{|key, i| set( key, values[i] ) }
    end
  end
  #-------------------------------ME method migration ENDED------------------------

  # -------------------------------KZ migration------------------------------------
  def migrate_to_key_zipping(keys)
    pipelined do
      zk_map_keys(keys).each{|new_key, key| renamenx( key, new_key )}
    end
  end

  # reverse migration done with same set of keys, i.e,
  # if you migrated [ user:1, user:2 ] with migrate_to_key_zipping and want to reverse migration
  # then use same argument [ user:1, user:2 ]
  def reverse_from_key_zipping!( keys )
    pipelined do
      zk_map_keys(keys).each{|new_key, key| rename( new_key, key ) }
    end
  end

  # use only uniq keys! or zk_map_keys will fire an error!
  # if transition is not one to one zk_map_keys would also fire an error
  def zk_map_keys(keys)
    keys.map{ |key| [zip_key(key), key] }.to_h
        .tap{ |result| raise ArgumentError.new( "Key zipping is not one to one! #{result.keys} != #{keys}" ) if result.length != keys.length }
  end

  def key_zipping_migration_reversible?( keys )
    !!zk_map_keys(keys)
  end
  # -------------------------------KZ migration ENDED ------------------------------------

  module FutureMigrator
    def prev_future=(new_prev_future); @prev_future = new_prev_future end
    def value;
      vl = super
      if !vl
        @prev_future&.value
      elsif vl.is_a?(Array) && @prev_future
        vl.zip( @prev_future&.value ).map{|nvl, old| nvl || old }
      else
        vl
      end
    end
  end

end