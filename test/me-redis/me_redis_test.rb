require 'test_helper'
require 'redis'
require 'me_redis'

# safety for Redis class, prevents to run test if base is not empty
class RedisSafety < Redis
  def initialize(options = {})
    options[:db] = ENV['TEST_REDIS_DB'] || 5
    super(options).tap {
      # preventing accidental connect to existing DB!
      raise "Redis DB contains keys! Check if the config is appropriate and flushdb before running test" if self.keys('*').length > 0
    }
  end
end

class MeRedisTest < Minitest::Test

  extend ActiveSupport::Testing::Declarative

  def redis; @clear_redis ||= RedisSafety.new
  end

  def setup; redis end

  def teardown; redis.flushdb end

  def check_me_methods(me_redis, redis, key, split)
    me_redis.me_incr(key)
    assert(me_redis.me_get(key) == '1')
    assert (redis.hget(*split) == '1')
    assert(redis.hget(*split) == me_redis.me_get(key))

    me_redis.me_set(key, 'it works')
    assert(me_redis.me_get(key) == 'it works')
    assert(redis.hget(*split) == me_redis.me_get(key))

    assert(me_redis.me_getset(key, 'Cool!') == 'it works')
    assert(me_redis.me_get(key) == 'Cool!')
    assert(redis.hget(*split) == me_redis.me_get(key))

    assert(redis.hexists(*split))
    assert(me_redis.me_exists?(key))

    me_redis.me_del(key)
    assert(!me_redis.me_exists?(key))
    assert(!redis.hexists(*split))

    me_redis.me_setnx(key, 'start')
    assert(me_redis.me_get(key) == 'start')

    me_redis.me_setnx(key, 'finish')
    assert(me_redis.me_get(key) == 'start')
  end

  def check_me_multi_methods(me_redis, keys, splits)
    me_redis.me_mset(keys[0], 'one', keys[1], 'two',)
    assert(me_redis.me_get(keys[1]) == 'two')
    assert(me_redis.hget(*splits[1]) == me_redis.me_get(keys[1]))

    assert(me_redis.me_mget(*keys) == [me_redis.hget(*splits[0]), me_redis.hget(*splits[1])])
    assert(me_redis.me_mget(*keys) == %w[one two])
  end

  def check_key_zipping(kz_redis)
    kz_redis.class.configure do |c|
      c.zip_crumbs = 'some/long/key/construct'.split('/')
    end

    key = 'some/long/construct/1'
    kz_key = 's/l/c/1'

    kz_redis.incr(key)
    assert(kz_redis.get(key) == redis.get(kz_key))
    assert(kz_redis.exists(key) == redis.exists(kz_key))
    assert(kz_redis.type(key) == redis.type(kz_key))
    kz_redis.decr(key)
    assert(kz_redis.get(key) == '0')

    kz_redis.decrby(key, 2)
    assert(kz_redis.get(key) == '-2')

    kz_redis.set(key, 'string')
    assert(kz_redis.get(key) == redis.get(kz_key))

    kz_redis.getset(key, {hash: true})
    assert(kz_redis.get(key) == redis.get(kz_key))

    kz_redis.del('some/long/construct/1')
    assert(!kz_redis.exists('some/long/construct/1'))

    kz_redis.incr('some/long/construct/1')
    kz_redis.incr('some/long/construct/2')

    kz_redis.rename('some/long/construct/1', 'some/long/construct/3')
    assert(redis.exists('s/l/c/3'))
    assert(!redis.exists('s/l/c/1'))

    kz_redis.renamenx('some/long/construct/2', 'some/long/construct/3')
    assert(redis.exists('s/l/c/2'))
  end

  def check_future(redis, must_be)
    ftr = nil
    redis.pipelined {ftr = yield}
    assert(ftr.value == must_be)
  end

  test 'MeRedis configure' do
    MeConfigureTest = Class.new(RedisSafety)
    MeConfigureTest.include(MeRedis)

    MeConfigureTest.configure {|c|
      c.compress_namespaces = [:key, :hkey]
      c.zip_crumbs = 'test|test_me'.split('|')
    }

    assert(MeConfigureTest.me_config.default_compressor == MeRedis::ZipValues::ZlibCompressor)
    assert(MeConfigureTest.zip_ns_finder == {
        string_ns: /\A(hkey|key)/,
        rgxps_ns: nil,
        rgxps_arr: []
    })
    assert(MeConfigureTest.key_zip_regxp == /(test_me|test)/)
    assert(MeConfigureTest.me_config.zip_crumbs == {'test_me' => 't1', 'test' => 't'})

    MeConfigureTest.configure {|c|
      c.compress_namespaces = :key
      c.zip_crumbs = 'test'
    }

    assert(MeConfigureTest.zip_ns_finder == {
        string_ns: /\A(key)/,
        rgxps_ns: nil,
        rgxps_arr: []
    })
    assert(MeConfigureTest.key_zip_regxp == /(test)/)
    assert(MeConfigureTest.me_config.zip_crumbs == {'test' => 't'})

    MeConfigureTest.configure(
        compress_namespaces: :key,
        zip_crumbs: {test: :ts}
    )

    assert(MeConfigureTest.me_config.compress_namespaces == {'key' => MeConfigureTest.me_config.default_compressor})
    assert(MeConfigureTest.key_zip_regxp == /(test)/)
    assert(MeConfigureTest.me_config.zip_crumbs == {'test' => 'ts'})

    key_rgxp = /key:[\d]+:/
    MeConfigureTest.configure(
        compress_namespaces: {
            key_rgxp => MeRedis::ZipValues::EmptyCompressor,
            hkey: MeRedis::ZipValues::EmptyCompressor
        },
        zip_crumbs: {hkey: :ts}
    )

    assert( MeConfigureTest.zip_ns_finder == {
        string_ns: /\A(ts)/,
        rgxps_ns: /\A(#{key_rgxp})/,
        rgxps_arr: [key_rgxp]
    })

    assert(MeConfigureTest.me_config.compress_namespaces == {
        key_rgxp => MeRedis::ZipValues::EmptyCompressor,
        'ts' => MeRedis::ZipValues::EmptyCompressor
    })

    MeConfigureTest.configure(compress_namespaces: key_rgxp)

    assert_raises(ArgumentError) do
      MeConfigureTest.configure(compress_namespaces: MeRedis::ZipValues::EmptyCompressor)
    end

    assert_raises(ArgumentError) do
      MeConfigureTest.configure(zip_crumbs: MeRedis::ZipValues::EmptyCompressor)
    end

    assert_raises(ArgumentError) do
      MeConfigureTest.configure(zip_crumbs: {user: :u, user_preview: :u})
    end

  end

  test "Test MeRedis base me_methods" do
    me_redis = Class.new(RedisSafety)
                   .include(MeRedis::ZipToHash)
                   .configure(
                       hash_max_ziplist_entries: 64,
                       integers_to_base62: true
                   ).new

    key, key2 = 'user:100', 'user:101'
    # 100 / 64 == 1, ( 100 % 64 ).to_base62 == 'A'
    split, split2 = ['user:1', 'A'], ['user:1', 'B']

    check_me_methods(me_redis, redis, key, split)
    check_me_multi_methods(me_redis, [key, key2], [split, split2])
  end

  test "Test MeRedis base me_methods + Key zipping" do
    me_redis = Class.new(RedisSafety)
                   .include(MeRedis::ZipToHash)
                   .prepend(MeRedis::ZipKeys)
                   .configure(
                       zip_crumbs: :user,
                       hash_max_ziplist_entries: 64,
                       integers_to_base62: true
                   ).new

    key, key2 = 'user:100', 'user:101'
    # 100 / ( hash_max_ziplist_entries = 64 ) == 1, ( 100 % 64 ).to_base62 == 'A'
    split, split2 = ['u:1', 'A'], ['u:1', 'B']

    check_me_methods(me_redis, redis, key, split)
    check_me_multi_methods(me_redis, [key, key2], [split, split2])
  end

  test "Test MeRedis " do
    me_redis = Class.new(RedisSafety)
                   .include(MeRedis::ZipToHash)
                   .prepend(MeRedis::ZipKeys)
                   .configure(
                       zip_crumbs: [:user, :user_inside],
                       hash_max_ziplist_entries: 64,
                       integers_to_base62: true
                   ).new

    # test that sub crumb doesn't overthrow longer crumb
    key = 'user_inside:100'
    # 100 / 64 == 1, ( 100 % 64 ).to_base62 == 'A'
    split = ['u1:1', 'A']

    me_redis.me_incr(key)
    assert(me_redis.me_get(key) == '1')
    assert(redis.hget(*split) == me_redis.me_get(key))

    # but in case of only shorter crumb present all goes also well
    key, key2 = 'user:100', 'user:101'
    # 100 / 64 == 1, ( 100 % 64 ).to_base62 == 'A'
    split, split2 = ['u:1', 'A'], ['u:1', 'B']

    redis.flushdb
    check_me_methods(me_redis, redis, key, split)
    check_me_multi_methods(me_redis, [key, key2], [split, split2])
  end

  test 'Key zipping' do
    check_key_zipping(Class.new(RedisSafety).prepend(MeRedis::ZipKeys).new)
  end

  test 'Value zipping compressor matchig' do
    gz_redis = Class.new(RedisSafety)
                   .prepend(MeRedis::ZipValues)
                   .configure(compress_namespaces: {
                       key: 1,
                       /org:[\d]+:hkey/ => 2
                   } ).new

    gz_redis.class.get_compressor_for_key('org:123:hkey')

    assert(gz_redis.class.get_compressor_for_key('org:123:hkey') == 2)
    assert(gz_redis.class.get_compressor_for_key('org::hkey').nil?)
    assert(gz_redis.class.get_compressor_for_key('key:1') == 1)
  end

  test 'Value zipping' do
    gz_redis = Class.new(RedisSafety)
                   .prepend(MeRedis::ZipValues)
                   .configure(compress_namespaces: [:key, /hkey_[\d]+/]).new

    str, str2 = 'Zip me string', {str: 'str'}

    gz_redis.set(:key, str)

    assert(Zlib.inflate(redis.get(:key)) == str)
    assert(gz_redis.get(:key) == str)

    gz_redis.hset(:hkey_1, 1, str)
    assert(Zlib.inflate(redis.hget(:hkey_1, 1)) == str)
    assert(gz_redis.hget(:hkey_1, 1) == str)

    gz_redis.mset(:key, str2, :key1, str)

    assert(redis.mget(:key, :key1).map! {|vl| Zlib.inflate(vl)} == [str2.to_s, str])
    assert(gz_redis.mget(:key, :key1) == [str2.to_s, str])

    gz_redis.hmset(:hkey_1, 1, str2, 2, str)

    assert(redis.hmget(:hkey_1, 1, 2).map! {|vl| Zlib.inflate(vl)} == [str2.to_s, str])
    assert(gz_redis.hmget(:hkey_1, 1, 2) == [str2.to_s, str])

  end

  test 'GZ pipelined' do
    gz_redis = Class.new(RedisSafety)
                   .prepend(MeRedis::ZipValues)
                   .configure(compress_namespaces: :gz).new
    str, str2 = 'Zip me string', {str: str}

    gz_redis.set(:gz_key, str)

    check_future(gz_redis, str) {gz_future = gz_redis.get(:gz_key)}
    assert(Zlib.inflate(redis.get(:gz_key)) == str)

    gz_redis.pipelined {gz_redis.hset(:gz_hkey, 1, str)}
    assert(Zlib.inflate(redis.hget(:gz_hkey, 1)) == str)

    check_future(gz_redis, str) {gz_future = gz_redis.hget(:gz_hkey, 1)}

    gz_redis.pipelined {gz_redis.mset(:gz_key, str2, :gz_key1, str)}
    assert(redis.mget(:gz_key, :gz_key1).map {|vl| Zlib.inflate(vl)} == [str2.to_s, str])

    check_future(gz_redis, [str2.to_s, str]) {gz_redis.mget(:gz_key, :gz_key1)}

    gz_redis.pipelined {gz_redis.hmset(:gz_hkey, 1, str2, 2, str)}
    assert(redis.hmget(:gz_hkey, 1, 2).map {|vl| Zlib.inflate(vl)} == [str2.to_s, str])
    assert(gz_redis.hmget(:gz_hkey, 1, 2) == [str2.to_s, str])
  end

  test 'Key gzipping + GZ' do
    check_key_zipping(Class.new(RedisSafety)
                          .prepend(MeRedis::ZipValues)
                          .prepend(MeRedis::ZipKeys)
                          .new)
  end

  test 'Check gz and kz intersection' do
    gzkz_redis = Class.new(RedisSafety)
                     .prepend(MeRedis::ZipValues)
                     .prepend(MeRedis::ZipKeys)
                     .configure {|c|
                       c.compress_namespaces = :gz_kz
                       c.zip_crumbs = c.compress_namespaces
                     }.new

    str = 'Key zipped and also gzipped'

    gzkz_redis.set(:gz_kz_me, str)

    assert(Zlib::Inflate.inflate(redis.get(:g_me)) == gzkz_redis.get(:gz_kz_me))
    assert(Zlib::Inflate.inflate(redis.get(:g_me)) == str)
  end

  test 'Check gz and kz regexp intersection' do
    gzkz_redis = Class.new(RedisSafety)
                     .prepend(MeRedis::ZipValues)
                     .prepend(MeRedis::ZipKeys)
                     .configure(
                         zip_crumbs: :gz_kz,
                         compress_namespaces: /g:[\d]+/
                     ).new

    str = 'Key zipped and also gzipped'

    gzkz_redis.set('gz_kz:100', str)

    assert(Zlib::Inflate.inflate(redis.get('g:100')) == gzkz_redis.get('gz_kz:100'))
    assert(Zlib::Inflate.inflate(redis.get('g:100')) == str)

    gzkz_redis.class.configure(
        zip_crumbs: :gz_kz,
        compress_namespaces: /g:[\d]+/,
        integers_to_base62: true
    )
    gzkz_redis.flushdb
    # now compression would broke
    gzkz_redis.set('gz_kz:50', str)
    assert(redis.get('g:O') == str)

    gzkz_redis.class.configure(
        zip_crumbs: :gz_kz,
        compress_namespaces: /g:[a-zA-Z\d]+/,
        integers_to_base62: true
    )
    gzkz_redis.flushdb
    gzkz_redis.set('gz_kz:100', str)

    assert(Zlib::Inflate.inflate(redis.get('g:1C')) == gzkz_redis.get('gz_kz:100'))
    assert(Zlib::Inflate.inflate(redis.get('g:1C')) == str)

  end


  test 'Full House Intersection' do
    fh_redis = Class.new(RedisSafety)
                   .include(MeRedis)
                   .configure do |c|
      c.compress_namespaces = 'user'
      c.zip_crumbs = c.compress_namespaces
      c.hash_max_ziplist_entries = 64
      c.integers_to_base62 = true
    end.new

    str = 'Key zipped and also value gzipped'
    key, key2 = 'user:100', 'user:101'
    # 100 / 64 == 1, ( 100 % 64 ).to_base62 == 'A'
    split, split2 = ['u:1', 'A'], ['u:1', 'B']

    # it's a bad idea to use GZ COmpressor on integers, but for testing purpose
    fh_redis.me_incr(key)
    assert(fh_redis.me_get(key) == '1')

    assert (redis.hget(*split) == '1')
    assert(redis.hget(*split) == fh_redis.me_get(key))

    fh_redis.me_set(key, str)
    assert(Zlib::Inflate.inflate(redis.hget(*split)) == fh_redis.me_get(key))
    assert(Zlib::Inflate.inflate(redis.hget(*split)) == str)

    assert(fh_redis.me_getset(key, 'Cool!') == str)
    assert(fh_redis.me_get(key) == 'Cool!')
    assert(Zlib::Inflate.inflate(redis.hget(*split)) == fh_redis.me_get(key))

    assert(redis.hexists(*split))
    assert(fh_redis.me_exists?(key))

    fh_redis.me_del(key)
    assert(!fh_redis.me_exists?(key))
    assert(!redis.hexists(*split))

    fh_redis.me_setnx(key, 'start')
    assert(fh_redis.me_get(key) == 'start')

    fh_redis.me_setnx(key, 'finish')
    assert(fh_redis.me_get(key) == 'start')


    check_me_multi_methods(fh_redis, [key, key2], [split, split2])
  end

  test 'Migrator fallbacks' do
    hm_redis = Class.new(RedisSafety)
                   .include(MeRedisHotMigrator)
                   .configure(
                       hash_max_ziplist_entries: 64,
                       integers_to_base62: true,
                       zip_crumbs: :user).new

    assert(!hm_redis.me_get('user:100'))
    redis.set('user:100', 1)

    assert(!redis.hget(*hm_redis.send(:split_key, 'user:100')))
    assert(hm_redis.me_get('user:100') == '1')

    # fallback to long keys and hash methods before set
    redis.mset('user:100', 1, 'user:101', 2)
    assert(hm_redis.get('user:100') == '1')
    assert(hm_redis.exists('user:100'))
    assert(hm_redis.type('user:100') == 'none')
    assert(hm_redis.mget('user:100', 'user:101') == %w[1 2])
    assert(hm_redis.me_mget('user:100', 'user:101') == %w[1 2])

    assert(hm_redis.getset('user:100', 3) == '1')

    hm_redis.mset('user:101', 4)
    assert(redis.mget('user:100', 'user:101') == %w[3 2])
    assert(redis.mget('u:1C', 'u:1D') == %w[3 4])

    assert(hm_redis.mget('user:100', 'user:101') == %w[3 4])

    redis.flushdb
    hm_redis.me_mset('user:100', 5, 'user:101', 6)
    assert(hm_redis.me_mget('user:100', 'user:101') == %w[5 6])

    redis.flushdb
    redis.hset('user', 'A', 1)
    assert(hm_redis.hget('user', 'A') == '1')
    assert(hm_redis.hgetall('user') == {"A" => "1"})
  end

  test 'Migrator fallbacks with pipelines' do
    hm_redis = Class.new(RedisSafety)
                   .include(MeRedisHotMigrator)
                   .configure(
                       hash_max_ziplist_entries: 64,
                       integers_to_base62: true,
                       zip_crumbs: :user
                   ).new

    redis.set('user:100', 1)

    check_future(hm_redis, '1') {hm_redis.me_get('user:100')}
    check_future(hm_redis, '1') {hm_redis.get('user:100')}

    # fallback to long keys and hash methods before set
    redis.mset('user:100', 1, 'user:101', 2)
    check_future(hm_redis, true) {hm_redis.exists('user:100')}
    check_future(hm_redis, 'none') {hm_redis.type('user:100')}
    check_future(hm_redis, %w[1 2]) {hm_redis.mget('user:100', 'user:101')}

    ftr = nil
    hm_redis.pipelined {ftr = hm_redis.me_mget_p('user:100', 'user:101')}
    assert(ftr.map(&:value) == %w[1 2])

    check_future(hm_redis, '1') {hm_redis.getset('user:100', 3)}

    hm_redis.mset('user:101', 4)
    assert(redis.mget('user:100', 'user:101') == %w[3 2])
    assert(redis.mget('u:1C', 'u:1D') == %w[3 4])

    check_future(hm_redis, %w[3 4]) {hm_redis.mget('user:100', 'user:101')}

    redis.flushdb
    redis.hset('user', 'A', 1)
    check_future(hm_redis, '1') {hm_redis.hget('user', 'A')}

    check_future(hm_redis, {"A" => "1"}) {hm_redis.hgetall('user')}

    redis.flushdb
    hm_redis.me_mset('user:100', 5, 'user:101', 6)
    assert(hm_redis.me_mget('user:100', 'user:101') == %w[5 6])
  end

end
