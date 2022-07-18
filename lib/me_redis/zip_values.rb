module MeRedis
  # todo warn in development when gzipped size iz bigger than strict
  # use prepend for classes
  module ZipValues
    module FutureUnzip
      def set_transformation(&block)
        return if @transformation_set
        @transformation_set = true

        @old_transformation = @transformation
        @transformation = -> (vl) {
          if @old_transformation
            @old_transformation.call(block.call(vl, self))
          else
            block.call(vl, self)
          end
        }
        self
      end

      # patch futures we need only when we are returning values, usual setters returns OK
      COMMANDS = %i[incr incrby hincrby get hget getset mget hgetall].map{ |cmd| [cmd, true]}.to_h
    end

    module ZlibCompressor
      def self.compress(value); Zlib.deflate(value.to_s ) end

      def self.decompress(value)
        value ? Zlib.inflate(value) : value
      rescue Zlib::DataError, Zlib::BufError
        return value
      end
    end

    module EmptyCompressor
      def self.compress(value); value end
      def self.decompress(value); value end
    end

    def self.prepended(base)
      base::Future.prepend(FutureUnzip)

      base.extend(MeRedis::ClassMethods)

      base.me_config.default_compressor = ::MeRedis::ZipValues::ZlibCompressor
    end

    def pipelined(&block)
      super do |redis|
        block.call(redis)
        _patch_futures(@client)
      end
    end

    def multi(&block)
      super do |redis|
        block.call(redis)
        _patch_futures(@client)
      end
    end

    def _patch_futures(client)
      client.futures.each do |ftr|

        ftr.set_transformation do |vl|
          if vl && FutureUnzip::COMMANDS[ftr._command[0]]
            # we only dealing here with GET methods, so it could be hash getters or get/mget
            keys = ftr._command[0][0] == 'h' ? ftr._command[1, 1] : ftr._command[1..-1]
            if ftr._command[0] == :mget
              vl.each_with_index.map{ |v, i| zip?(keys[i]) ? self.class.get_compressor_for_key(keys[i]).decompress( v ) : v }
            elsif zip?(keys[0])
              compressor = self.class.get_compressor_for_key(keys[0])
              # on hash commands it could be an array
              vl.is_a?(Array) ? vl.map!{ |v| compressor.decompress(v) } : compressor.decompress(vl)
            else
              vl
            end
          else
            vl
          end
        end

      end
    end


    def zip_value(value, key )
      zip?(key) ? self.class.get_compressor_for_key(key).compress( value ) : value
    end

    def unzip_value(value, key)
      return value if value.is_a?( FutureUnzip )

      value.is_a?(String) && zip?(key) ? self.class.get_compressor_for_key(key).decompress( value ) : value
    end

    def zip?(key); self.class.zip?(key) end

    # Redis prepended methods
    def get( key ); unzip_value( super( key ), key) end
    def set( key, value, **options); super( key, zip_value(value, key), **options ) end

    def mget(*args); unzip_arr_or_future(super(*args), args ) end
    def mset(*args); super( *map_msets_arr(args) ) end

    def getset( key, value ); unzip_value( super( key, zip_value(value, key) ), key ) end

    def hget( key, h_key ); unzip_value( super( key, h_key ), key ) end
    def hset( key, h_key, value );  super( key, h_key, zip_value(value, key) ) end
    def hsetnx( key, h_key, value ); super( key, h_key, zip_value(value, key) ) end

    def hmset( key, *args ); super( key, map_hmsets_arr(key, *args) ) end

    def hmget( key, *args ); unzip_arr_or_future( super(key, *args), key ) end

    private

    def unzip_arr_or_future( arr, keys )
      return arr if arr.is_a?(FutureUnzip)

      arr.tap { arr.each_with_index { |val, i| arr[i] = unzip_value(val,keys.is_a?(Array) ? keys[i] : keys)} }
    end

    def map_hmsets_arr( key, *args )
      return args unless zip?(key)
      counter = 0
      args.map!{ |kv| (counter +=1).odd? ? kv : zip_value(kv, key ) }
    end

    def map_msets_arr( args )
      args.tap { (args.length/2).times{ |i| args[2*i+1] = zip_value(args[2*i+1], args[2*i] ) } }
    end
  end

end