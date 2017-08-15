$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'lock_and_cache_msgpack'

require 'timeout'

require 'redis'
LockAndCacheMsgpack.storage = -> { Redis.new }

require 'thread/pool'

require 'pry'
