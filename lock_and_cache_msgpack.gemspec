# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'lock_and_cache_msgpack/version'

Gem::Specification.new do |spec|
  spec.name          = "lock_and_cache_msgpack"
  spec.version       = LockAndCacheMsgpack::VERSION
  spec.authors       = ["Seamus Abshere", "Matt E. Patterson"]
  spec.email         = ["seamus@abshere.net", "mpatterson@skillsengine.com"]
  spec.summary       = %q{Lock and cache methods, with MessagePack.}
  spec.description   = %q{Lock and cache methods, in case things should only be calculated once across processes.}
  spec.homepage      = "https://github.com/c4eo/lock_and_cache_msgpack"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency 'activesupport'
  spec.add_runtime_dependency 'redis'
  # temporary until https://github.com/leandromoreira/redlock-rb/pull/20 is merged
  spec.add_runtime_dependency 'redlock', '>=0.1.3'
  spec.add_runtime_dependency 'msgpack', '~> 1.1.0'

  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'bundler', '~> 1.6'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'thread'
  spec.add_development_dependency 'yard', '~> 0.9.11'
  spec.add_development_dependency 'redcarpet'
end
