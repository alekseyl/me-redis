require 'me_redis/version'
require 'me_redis/zip_keys'
require 'me_redis/zip_to_hash'
require 'me_redis/zip_values'
require 'me_redis/me_redis_hot_migrator'
require 'me_redis/integer'
require 'me_redis/hash'

require 'zlib'

# Main ideas:
# 1) less memory on redis is better than performance on ruby code
# 2) more result with less code changes,
#    i.e. overriding old methods with proper configure is preferred over mixin new methods
# 3) rails-less

module MeRedis
  module ClassMethods

    def configure( config = nil )
      # at start they are nils, but at subsequent calls they may not be nils
      me_config.key_zip_regxp = nil
      me_config.compress_ns_regexp = nil
      @zip_ns_finder = nil

      config.each{ |key,value| me_config.send( "#{key}=", value ) } if config

      yield( me_config ) if block_given?


      prepare_zip_crumbs
      prepare_compressors

      # useful for chaining with dynamic class creations
      self
    end

    def me_config
      @me_config ||= Struct.new(
          # if set - configures Redis hash_max_ziplist_entries value,
          # otherwise it will be filled from Redis hash-max-ziplist-value
          :hash_max_ziplist_entries,
          # array or hash or string/sym of key crumbs to zip, if a hash given it used as is,
          # otherwise meredis tries to construct hash by using first char from each key + integer in base62 form for
          # subsequent appearence of a crumb starting with same char
          :zip_crumbs,
          # zip integers in keys to base62 form
          :integers_to_base62,
          # regex composed from zip_crumbs keys and integer regexp if integers_to_base62 is set
          :key_zip_regxp,
          # prefixes/namespaces for keys need zipping,
          # acceptable formats:
          # 1. single string/sym will map it to defauilt compressor
          # 2. array of string/syms will map it to defauilt compressor
          # 3. hash maps different kinds of 1 and 2 to custom compressors
          :compress_namespaces,
          # if configured than default_compressor used for compression of all keys matched and compress_namespaces is ignored
          :compress_ns_regexp,

          :default_compressor
      ).new(512)
    end

    def zip_crumbs; me_config.zip_crumbs end

    def key_zip_regxp
      return me_config.key_zip_regxp if me_config.key_zip_regxp
      regexp_parts = []
      #reverse order just to be sure we replaced longer strings before shorter
      # also we need to sort by length, not just sort, because we must try to replace 'z_key_a'  first,
      # and only after that we can replace 'key'
      regexp_parts <<  "(#{zip_crumbs.keys.sort_by(&:length).reverse.join('|')})" if zip_crumbs
      regexp_parts << '(\d+)' if me_config.integers_to_base62
      me_config.key_zip_regxp ||= /#{regexp_parts.join('|')}/
    end

    def get_compressor_namespace_from_key( key )
      ns_matched = zip_ns_finder[:rgxps_ns] && key.match(zip_ns_finder[:rgxps_ns])
      if ns_matched&.captures
        zip_ns_finder[:rgxps_arr][ns_matched.captures.each_with_index.find{|el,i| el}[1]]
      else
        zip_ns_finder[:string_ns] && key.match(zip_ns_finder[:string_ns])&.send(:[], 0)
      end
    end

    def zip?(key)
      me_config.compress_ns_regexp&.match?(key) ||
          zip_ns_finder[:string_ns]&.match?(key) ||
          zip_ns_finder[:rgxps_ns]&.match?(key)
    end

    def zip_ns_finder
      return @zip_ns_finder if @zip_ns_finder
      regexps_compress_ns = me_config.compress_namespaces.keys.select{|key| key.is_a?(Regexp) }
      strs_compress_ns = me_config.compress_namespaces.keys.select{|key| !key.is_a?(Regexp) }

      @zip_ns_finder = {
          string_ns: strs_compress_ns.length == 0 ? nil : /\A(#{strs_compress_ns.sort_by(&:length).reverse.join('|')})/,
          rgxps_ns: regexps_compress_ns.length == 0 ? nil : /\A#{regexps_compress_ns.map{|rgxp| "(#{rgxp})" }.join('|')}/,
          rgxps_arr: regexps_compress_ns
      }
    end

    def get_compressor_for_key( key )
      if me_config.compress_ns_regexp
        me_config.default_compressor
      else
        me_config.compress_namespaces[get_compressor_namespace_from_key( key )]
      end
    end

    private

    def prepare_zip_crumbs
      if zip_crumbs.is_a?( Array )
        result = {}
        me_config.zip_crumbs.map!(&:to_s).each do |sub|
          if result[sub[0]]
            i = 0
            begin i += 1 end while( result["#{sub[0]}#{i.to_base62}"] )
            result["#{sub[0]}#{i.to_base62}"] = sub.to_s
          else
            result[sub[0]] = sub
          end
        end
        me_config.zip_crumbs = result.invert
      elsif zip_crumbs.is_a?( String ) || zip_crumbs.is_a?( Symbol )
        me_config.zip_crumbs = { me_config.zip_crumbs.to_s => me_config.zip_crumbs[0] }
      elsif zip_crumbs.is_a?( Hash )
        me_config.zip_crumbs = zip_crumbs.transform_keys(&:to_s).transform_values(&:to_s)
        raise ArgumentError.new("pack subs cannot be inverted properly.
                repack subs: #{zip_crumbs}, repack keys invert: #{zip_crumbs.invert}") unless zip_crumbs.invert.invert == zip_crumbs
      elsif zip_crumbs
        raise ArgumentError.new("Wrong class for zip_crumbs, expected Array, Hash, String or Symbol! Got: #{zip_crumbs.class.to_s}")
      end

      key_zip_regxp
    end

    def prepare_compressors

      me_config.default_compressor ||= MeRedis::ZipValues::EmptyCompressor

      me_config.compress_namespaces = case me_config.compress_namespaces
                                        when Array
                                          me_config.compress_namespaces.map{|ns| [replace_ns(ns), me_config.default_compressor] }.to_h
                                        when String, Symbol, Regexp
                                          { replace_ns( me_config.compress_namespaces ) => me_config.default_compressor }
                                        when Hash
                                          me_config.compress_namespaces.inject({}) do |sum, (name_space, compressor)|
                                            name_space.is_a?( Array ) ?
                                                sum.merge!( name_space.map{ |ns| [replace_ns( ns), compressor] }.to_h )
                                                : sum[replace_ns(name_space)] = compressor
                                            sum
                                          end
                                        else
                                          raise ArgumentError.new(<<~NS_ERR) if me_config.compress_namespaces
            Wrong class for compress_namespaces, expected Array, 
                                Hash, String or Symbol! Got: #{me_config.compress_namespaces.class.to_s}
                                          NS_ERR
                                          {}
                                      end

      zip_ns_finder
    end

    def replace_ns(ns)
      ( zip_crumbs && zip_crumbs[ns.to_s] ) || ( check_ns_type!(ns) && ( ns.is_a?(Regexp) ? ns : ns.to_s ) )
    end

    def check_ns_type!( ns )
      case ns
        when String, Symbol, Regexp
          true
        else
          raise 'Must be Symbol, String or Regexp!'
      end
    end
  end

  #include
  def self.included(base)
    base.prepend( MeRedis::ZipValues )
    base.prepend( MeRedis::ZipKeys )
    base.include( MeRedis::ZipToHash )
  end
end