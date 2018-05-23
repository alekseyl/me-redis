# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'me_redis/version'

Gem::Specification.new do |spec|
  spec.name          = "me-redis"
  spec.version       = MeRedis::VERSION
  spec.authors       = ["alekseyl"]
  spec.email         = ["leshchuk@gmail.com"]

  spec.summary       = %q{Memory efficient redis extention}
  spec.description   = %q{Enable to zip keys, zip values and replace simple storage key/value pairs with hash storing}
  spec.homepage      = "https://github.com/alekseyl/me-redis"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'redis', '>= 3.0'
  spec.add_dependency 'base62-rb'

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest"
end
