class MockRedis
  def self.single_db( db )
    @single_db ||= db
  end

  def self.mock_config
    @config ||= {'hash-max-ziplist-entries' => '512'}
  end

  def initialize(*args)
    @options = _parse_options(args.first)

    @db = MockRedis.single_db( PipelinedWrapper.new(
        TransactionWrapper.new(
            ExpireWrapper.new(
                MultiDbWrapper.new(
                    Database.new(self, *args)
                )
            )
        )
    )
    )
    @client = self
  end

  def config( action, *args )
    if action.to_s == 'get'
      self.class.mock_config[ args[0] ]
    elsif action.to_s == 'set'
      self.class.mock_config[ args[0] ] = args[1].to_s
      'OK'
    else
      raise ArgumentError "Wrong action #{action}"
    end
  end

  class Future
    def _command; @command end
    def store_result(result)
      @result_set = true
      @result = @transformation ? @transformation.call(result) : result
    end
  end

  class PipelinedWrapper
    def futures; @pipelined_futures end
  end
end
