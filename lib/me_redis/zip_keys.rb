module MeRedis
  # how to use:
  # Redis.prepend( MeRedis::KeyMinimizer )
  module ZipKeys

    def self.prepended(base)
      base.extend( MeRedis::ClassMethods )
    end

    def zip_key( key )
      key.to_s.split( self.class.key_zip_regxp ).map do |zip_me|
        if zip_me.to_i != 0
          zip_me.to_i.to_base62
        else
          self.class.zip_crumbs&.send(:[], zip_me ) || zip_me
        end
      end.join
    end

    #---- h_methods ---------------------------
    def hdel( key, hkey ); super( zip_key(key), hkey ) end
    def hset( key, hkey, value );  super( zip_key(key), hkey, value ) end
    def hsetnx( key, hkey, value );  super( zip_key(key), hkey, value ) end
    def hexists( key, hkey ); super( zip_key(key), hkey ) end
    def hget( key, hkey );  super( zip_key(key), hkey ) end
    def hincrby( key, hkey, value ); super( zip_key(key), hkey, value ) end
    def hmset( key, *args ); super( zip_key(key), *args ) end
    def hmget( key, *args ); super( zip_key(key), *args ) end
    #---- Hash methods END --------------------

    def incr( key ); super( zip_key(key) ) end
    def get( key ); super( zip_key(key) ) end

    def exists(key); super( zip_key(key) ) end
    def type(key); super(zip_key(key)) end
    def decr(key); super(zip_key(key)) end
    def persist(key); super(zip_key(key)) end

    def decrby( key, decrement ); super(zip_key(key), decrement) end
    def set( key, value, options = {} );  super( zip_key(key), value, options ) end
    def mset( *key_values ); super( *key_values.each_slice(2).map{ |k,v| [zip_key(k),v] }.flatten ) end
    def mget( *keys ); super( *keys.map!{ |k| zip_key(k) } ) end

    def getset( key, value );  super( zip_key(key), value ) end
    def move(key, db); super( zip_key(key), db ) end

    def del(*keys); super( *keys.map{ |key| zip_key(key) } ) end

    def rename(old_name, new_name); super( zip_key(old_name), zip_key(new_name) ) end
    def renamenx(old_name, new_name); super( zip_key(old_name), zip_key(new_name) ) end
  end
end