module MeRedis
  # include
  module ZipToHash

    module PrependMethods
      def initialize(*args, **kwargs, &block)
        super(*args,**kwargs, &block)

        # hash-max-ziplist-entries must be cashed, we can't ask Redis every time we need to zip keys,
        # cause it's less performant and impossible during pipelining.
        _config = config(:get, 'hash-max-ziplist-*' )
        @hash_max_ziplist_entries = _config['hash-max-ziplist-entries'].to_i
        if self.class.me_config.hash_max_ziplist_entries && @hash_max_ziplist_entries != self.class.me_config.hash_max_ziplist_entries
          #if me_config configures hash-max-ziplist-entries than we assume it global
          config(:set, 'hash-max-ziplist-entries', self.class.me_config.hash_max_ziplist_entries )
        end

        if self.class.me_config.hash_max_ziplist_value &&
            self.class.me_config.hash_max_ziplist_value != _config['hash-max-ziplist-value'].to_i

          config(:set, 'hash-max-ziplist-value', self.class.me_config.hash_max_ziplist_value)
        end
      end

      def config(action, *args)
        @hash_max_ziplist_entries = args[1].to_i if action.to_s == 'set' && args[0] == 'hash-max-ziplist-entries'
        super( action, *args )
      end

    end

    def self.included(base)
      base.extend(MeRedis::ClassMethods)
      base.prepend(PrependMethods)
    end

    def me_del( *keys )
      keys.length == 1 ? hdel( *split_key(*keys) ) : pipelined{ keys.each{ |key| hdel( *split_key(key) ) } }
    end

    def me_set( key, value ); hset( *split_key(key), value ) end
    def me_setnx( key, value ); hsetnx( *split_key(key), value ) end
    def me_get( key ); hget(*split_key(key)) end

    def me_getset(key, value)
      # multi returns array of results, also we can use raw results in case of commpression take place
      # but inside pipeline, multi returns nil
      ftr = []
      ( multi{ ftr << me_get( key ); me_set( key, value ) } || ftr )[0]
    end

    def me_exists?(key); hexists(*split_key(key)) end

    def me_incr(key); hincrby( *split_key(key), 1 ) end

    def me_incrby(key, value); hincrby(*split_key(key), value) end

    # must be noticed it's not a equal replacement for a mset,
    # because me_mset can be partially executed, since redis doesn't rollbacks partially failed transactions
    def me_mset( *args )
      #it must be multi since it keeps an order of commands
      multi{ args.each_slice(2) { |key, value| me_set( key, value ) } }
    end

    # be aware: you cant save result of me_mget inside pipeline or multi cause pipeline returns nil
    def me_mget( *keys )
      pipelined { keys.each{ |key| me_get( key ) } }
    end

    # version to be called inside pipeline, to get values, call map(&:value)
    def me_mget_p( *keys )
      ftr = []
      pipelined { keys.each{ |key| ftr << me_get( key ) } }
      ftr
    end

    private

    def split_key(key)
      split = key.to_s.scan(/\A(.*?)(\d+)\z/).flatten
      raise ArgumentError.new("Cannot split key: #{key}, key doesn't end with the numbers after zipping(#{key})!" ) if split.length == 0

      split[0] = split[0] + (split[1].to_i / @hash_max_ziplist_entries).to_s
      split[1] = ( split[1].to_i % @hash_max_ziplist_entries)
      split[1] = split[1].to_base62 if self.class.me_config.integers_to_base62

      split
    end

  end

end