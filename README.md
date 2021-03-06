# MeRedis

Me - Memory Efficient

This gem is delivering memory optimizations for Redis with slightest code changes.

To understand optimizations and how to use them 
I suggest you to read my paper: https://medium.com/@leshchuk/zipem-all-61076c7da4c

Compatibility: ruby >= 2.4, redis gem >= 3.0.4

## Features:
 
* seamless integration with code already in use. **It's all in MeRedis configuration, not your current code.** 

* hash key/value optimization with seamless code changes, just replace set('object:id', value) with me_set( 'object:id', value) and free upto 90 bytes for each ['object:id', value] pair. 

* zips user-friendly key crumbs according to configuration, i.e. converts for example user:id to u:id

* zip integer parts of keys with base62 encoding. Since all keys in redis are always strings, than we don't care for integer parts base, and by using base62 encoding we can shorten them upto 1.8 times shorter  

* respects pipelined and multi, properly works with Futures. 

* allow different compressors for a different key namespaces, 
   you can deflate separately objects, short strings, large strings, primitives. 

* hot migration module with fallbacks to previous keys.

* rails-less, it's rails independent, you can use it apart from rails

* seamless refactoring of old crumbs, i.e. you may rename crumbs keeping 
  existing cache intact 

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'me-redis'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install me-redis

## Usage

**Main consideration:**
1) less memory on redis side is better than less performance on ruby side
2) more result with less code changes,
   i.e. overriding native redis methods with proper configuration basis is 
   preferred over mixin new methods. 
   
I wanted magic to happend: mix all kind of optimizations without making 3 call of different methods.   

MeRedis based on three general optimization ideas:
* shorten keys
* compress values 
* 'zip to hash', a Redis specific optimization from [Redis official memory optimization guide](https://medium.com/r/?url=https%3A%2F%2Fredis.io%2Ftopics%2Fmemory-optimization)


Thats why MeRedis contains three modules : MeRedis::ZipKeys, MeRedis::ZipValues, MeRedis::ZipToHash.

They can be used separately in any combination, but the simplest 
way to deal with them all is call include upon MeRedis:

```ruby 
   Redis.include(MeRedis)
   redis = Redis.new
``` 

If you want to keep a clear Redis class, you can do it this way:

```ruby
   me_redis = Class.new(Redis).include(MeRedis).configure({...}).new
```

So now me_redis is a instance of unnamed class derived from Redis, 
and patched with all MeRedis modules. 

If you want to include them separately look at MeRedis.included method:

```ruby
  def self.included(base)
    base.prepend( MeRedis::ZipValues )
    base.prepend( MeRedis::ZipKeys )
    base.include( MeRedis::ZipToHash )
  end
```

This is the right chain of prepending/including, so just remove unnecessary module.

### AWS ElasticCache usage

AWS blocks config call with exception. To prevent this behaviour prepend MeRedis successor 
with AwsConfigBlocker module:

```ruby

# !!! it should be prepended before including main module.
Class.new(Redis)
     .prepend(MeRedis::AwsConfigBlocker)
     .include(MeRedis)
     .configure({
       # some config
     }).new
```


### Base use

```ruby
  redis = Redis.new
  me_redis = Class.new(Redis).include(MeRedis).configure({
    hash_max_ziplist_entries: 64,
    zip_crumbs: :user,
    integers_to_base62: true,
    compress_namespaces: :user
  }).new

  # keep using code as you already do, like this:
  me_redis.set( 'user:100', @user.to_json )
  me_redis.get( 'user:100' )
    
  # is equal under a hood to: 
  redis.set( 'u:1C', Zlib.deflate( @user.to_json ) )
  Zlib.inflate( redis.get( 'u:1C' ) )
  
  #OR replace all get/set/incr e.t.c with me_ prefixed version like this:
  me_redis.me_set( 'user:100', @user.to_json )
  me_redis.me_get( 'user:100' )
  
  # under the hood equals to:
  redis.hset( 'u:1', 'A', Zlib.deflate( @user.to_json ) )
  Zlib.inflate( redis.hget( 'u:1', 'A' ) )
      
  # future works same
  ftr, me_ftr = nil, nil
  me_redis.pipelined{ me_redis.set('user:100', '111'); me_ftr = me_redis.get(:user) } 
  #is equal to:
  redis.pipelined{ redis.set( 'u:1C', Zlib.defalte( '111' ) ); ftr = redis.get('u:1C') }
  # and
  me_ftr.value == ftr.value 
  
```

As you can see you can get a result with smallest or even none code changes!

The idea is to move complexity to config.
   
### Config
```ruby

  Redis.include(MeRedis).configure( hash_max_ziplist_entries: 512 ) 

  #Options are: 
  
    # if set - configures Redis hash_max_ziplist_entries value,
    # otherwise it will be filled from Redis hash-max-ziplist-entries
    :hash_max_ziplist_entries
    
    # if set - configures Redis hash-max-ziplist-value value,
    # otherwise it will be filled from Redis hash-max-ziplist-value
    :hash_max_ziplist_value
     
    # array or hash or string/sym of keys crumbs to zip, 
    # when a hash is given it used as is,
    # otherwise MeRedis tries to construct hash by using first char from each key given 
    # + integer in base62 starting from 1 for subsequent appearence of a crumbs starting with same char
    :zip_crumbs
    
    # set to true if you want to zip ALL integers in keys to base62 form
    :integers_to_base62
    
    # regexp composed from zip_crumbs keys and general integer regexp (\d+) if integers_to_base62 is set
    # better not to set directly
    :key_zip_regxp
    
    # keys prefixes/namespaces for values need to be zipped,
    # acceptable formats:
    # 1. single string/symbol/regexp - will map it to default compressor
    # 2. array of string/symbols/regexp will map them all to default compressor
    # 3. hash maps different kinds of 1 and 2 to custom compressors
    
    # compress_namespaces will convert to two regexp: 
    #  1. one for strings and symbols 
    #  2. second for regexps 
    #  they both will start with \A meaning this is a namespace/prefix 
    #  be aware of it and omit \A in your regexps 
    :compress_namespaces
    
    # if set directly than default_compressor applied to any key matched this regexp 
    # compress_namespaces is ignored  
    :compress_ns_regexp
    
    # any kind of object which responds to compress/decompress methods
    :default_compressor
```
  ### Config examples
  
```ruby

redis = Redis.include( MeRedis ).new

# zip key crumbs 'user', 'card', 'card_preview', to u, c, c1
# zips integer crumbs to base62, 
# for keys starting with gz prefix compress values with Zlib 
# for keys starting with json values with ActiveRecordJSONCompressor
Redis.configure( 
  hash_max_ziplist_entries: 256,
  zip_crumbs: %i[user card card_preview json], # -> { user: :u, card: :c, card_preview: :c1 }
  integers_to_base62: true,
  compress_namespaces: {
      gz: MeRedis::ZipValues::ZlibCompressor,
      json: ActiveRecordJSONCompressor 
  }
)

 redis.set( 'gz/card_preview:62', @card_preview )

#is equal under hood to:
 redis.set( 'gz/c0:Z', Zlib.deflate( @card_preview) )

# and using me_ method:
 redis.me_set( 'gz/card_preview:62', @card_preview )
 
#under the hood converts to:
  redis.hset( 'gz/c0:1', '0', Zlib.deflate( @card_preview ) )

    
# It's possible to intersect zip_crumbs with compress_namespaces
Redis.configure( 
  hash_max_ziplist_entries: 256,
  zip_crumbs: %i[user card card_preview json], # -> { user: :u, card: :c, card_preview: :c1 }
  integers_to_base62: true,
  compress_namespaces: {
      gz: MeRedis::ZipValues::ZlibCompressor,
      [:user, :card] => ActiveRecordJSONCompressor 
  } 
)

redis.set( 'user:62', @user )
#under hood now converted to
redis.set( 'u:Z', ActiveRecordJSONCompressor.compress( @user ) )

#It's possible for compress_namespaces to use regexp:
Redis.configure( 
  zip_crumbs: %i[user card card_preview json], # -> { user: :u, card: :c, card_preview: :c1 }
  compress_namespaces: {
      /organization:[\d]+:card_preview/ => MeRedis::ZipValues::ZlibCompressor,
      [:user, :card].map{|crumb| /organization:[\d]+:#{crumb}/ } => ActiveRecordJSONCompressor 
  }
)

redis.set( 'organization:1:user:62', @user )
#under hood now converted to
redis.set( 'organization:1:u:Z', ActiveRecordJSONCompressor.compress( @user ) )

# If you want intersect key zipping with regexp 
# **you must intersect them using substituted crumbs!!!**

Redis.configure( 
  integers_to_base62: true,
  zip_crumbs: %i[user card card_preview organization], # -> { user: :u, card: :c, card_preview: :c1, organization: :o }
  compress_namespaces: {
      /o:[a-zA-Z\d]+:c1/ => MeRedis::ZipValues::ZlibCompressor,
      [:u, :c].map{|crumb| /o:[a-zA-Z\d]+:#{crumb}/ } => ActiveRecordJSONCompressor 
  }
)

redis.set( 'organization:1:user:62', @user )
#under hood now converted to
redis.set( 'o:1:u:Z', ActiveRecordJSONCompressor.compress( @user ) )

# You may set key zipping rules directly with a hash:
Redis.configure( 
  hash_max_ziplist_entries: 256,
  zip_crumbs: { user: :u, card: :c, card_preview: :cp],
  integers_to_base62: true,
)

# This config means: don't zip keys only zip values. 
# For keys started with :user, :card, :card_preview 
# compress all values with default compressor 
# default compressor is ZlibCompressor if you prepend ZipValues module or include whole MeRedis module,
# otherwise it is EmptyCompressor which doesn't compress anything 
Redis.configure( 
  hash_max_ziplist_entries: 256,
  compress_namespaces: %i[user card card_preview]
)
```
### Config best practices
Now I may suggest some best practices for MeRedis configure:

* explicit crumbs schema is preferable over implicit
* if you are going lazy, and use implicit schemas, than avoid keys reshuffling, 
  cause it messes with your cache
* better to configure hash-max-ziplist-* in MeRedis.configure than 
  elsewhere. And don't forget - this will reset them globally 
  for this Redis server!
* use MeRedis in persistent Redis-based system with extreme caution!

  
 
# Custom Compressors

MeRedis allow you to compress values through different compressor. 
Here is an example of custom compressor for ActiveRecord objects, 
I use it to test compression ratio against plain compression of to_json. It takes ~40% less memory than Zlib.deflate(object.to_json). 

```ruby

module ActiveRecordJSONCompressor
  # this is the example, automated for simplicity, if DB schema changes, than cache may broke!!
  # in reallife scenario either invalidate cache, or use explicit schemas
  # like User: { first_name: 1, last_name: 2 ... }, 
  # than your cache will be safer on schema changes.
  COMPRESSOR_SCHEMAS = [User, HTag].map{|mdl|
    [mdl.to_s, mdl.column_names.each_with_index.map{ |el, i| [el, i.to_base62] }.to_h]
  }.to_h.with_indifferent_access

  REVERSE_COMPRESSOR_SCHEMA = COMPRESSOR_SCHEMAS.dup.transform_values(&:invert)

  def self.compress( object )
    use_schema = COMPRESSOR_SCHEMAS[object.class.to_s]
    # _s - shorten for schema, s cannot be used since its a number in Base62 system
    Zlib.deflate(
        object.serializable_hash
            .slice( *use_schema.keys )
            .transform_keys{ |k| use_schema[k] }
            .reject{ |_,v| v.blank? }
            .merge!( _s: object.class.to_s ).to_json
    )
  end

  def self.decompress(value)
    compressed_hash = JSON.load( Zlib.inflate(value) )
    model = compressed_hash.delete('_s')
    schema = REVERSE_COMPRESSOR_SCHEMA[model]
    model.constantize.new( compressed_hash.transform_keys{ |k| schema[k] } )
  end
end

```

# Hot migration 
MeRedis deliver additional module MeRedisHotMigrator for hot migration to KeyZipping and ZipToHash. 

We don't need one in generally for base implementation of ZipValues module cause 
its getter methods fallbacks to values. 

### Features
* mget hget hgetall get exists type getset - fallbacks to original methods for key_zipping
* me_get me_mget - fallbacks to original methods for hash zipping
* partially respects pipelining and multi 
* protecting you from accidentally do many to less many migration 
  and from ZipToHash migration without key zipping ( 
    though it's impossible to hot migrate from 'user:100' to 'user:1', 'B', 
    because of same namespace 'user' for flat key/value pair and hashes, 
    you'll definetely get an error from Redis ) 
* reverse migration methods

```ruby
  redis = Redis.include( MeRedisHotMigrator ).configure( 
    zip_crumbs: :user 
  )
  
  usr_1_cache = redis.me_get('user:1')
  
  all_user_keys = redis.keys('user*') 
  # it doesn't delete all_user_keys!!! they still all in the Redis
  redis.migrate_to_hash_representation( all_user_keys )
  usr_1_cache == redis.me_get('user:1') # true
  
  redis.del( *all_user_keys )
  # now you a ready to measure memory bonus you've got
  ap redis.info(:memory)
  
  usr_1_cache == redis.me_get('user:1') # true
    
  redis.reverse_from_hash_representation!( all_user_keys )
  
  usr_1_cache == redis.me_get('user:1') # true
```

For persistent store use with extreme caution!! 
Backup, test, test, user test and after you are completely sure than you may migrate. 

Try not to stuck with MeRedisHotMigrator because it doing double amount of actions: 
 
 1. do BG deploy of code with MeRedisHotMigrator, 
 2. run migration in parallel, 
 3. replace MeRedisHotMigrator with MeRedis
 4. do BG deploy 
 
 and you are done. 
 
# Debug and broken expectations

1. Check if modules you using override appropriate method ( if not make issue :) )
2. Check the order of prepending / including modules ( look into MeRedis.included to see how things must be done ) 
3. Call ap Redis.me_config and check it over your expectation, 
   mistakes are usually in config. Don't forget - namespaces inside regexp must be in zipped form ( integers became base62 integers strings and crumbs are zipped )!
4. Check hash-max-size-value, if your average data size is greater 
   than hash-max-size-value than hash optimization will not bring resource savings.
5. Check hash-max-size-entries if it small than hash effect is less than expected
5. Trace through code and inspect zip_key and zip? output.  

# Limitations

### Me_* methods limitation

Some of me_methods like me_mget/me_mset/me_getset 
are imitations for corresponded Redis base methods behaviour through 
pipeline and transactions. So inside pipelined call it may not 
deliver a completely equal behaviour. 

me_mget has a method double me_mget_p in case you need to use it with futures. 

### ZipKeys and ZipValues
As I already mention if you want to use custom prefix regex 
for zipping values than it must be constructed with a crumbs substitutions, 
not the original crumb, see config example. 
                 
## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Testing

```bash
docker-compose build
docker-compose run test
```

### MockRedis

If you are using in mock_redis gem for testing purpose and see some test 
breakage me-redis has a MockRedis extended class.
Its imitate single DB for all instances of MockRedis class 
and add some methods MeRedis rely upon. Its not a complete replacement 
for Redis class, but you can try it out.
 

### RedisSafety
 MeRedis tests itself against RedisSafety class which is a Redis descendant class. 
 All instances of RedisSafety ensure that Redis DB is empty otherwise they will raise an error. 
 This is a precaution measure to prevent you from accidentally run MeRedis test again production DB.
 
```
  rake test REDIS_TEST_DB=5
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/alekseyl/me-redis.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

## ToDo List

* Place config for keys zipping in text form into predefined key, so it would be observable with just redis-cli 
* add warning option for hash-max-ziplist-value overthrowing
* add keys method 
* refactor readme
* 
