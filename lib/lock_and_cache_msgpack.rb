require 'logger'
require 'timeout'
require 'digest/sha1'
require 'base64'
require 'redis'
require 'redlock'
require 'active_support'
require 'active_support/core_ext'
require 'msgpack'
require 'messagepack_ext'

require_relative 'lock_and_cache_msgpack/version'
require_relative 'lock_and_cache_msgpack/action'
require_relative 'lock_and_cache_msgpack/key'

# Lock and cache using redis!
#
# Most caching libraries don't do locking, meaning that >1 process can be calculating a cached value at the same time. Since you presumably cache things because they cost CPU, database reads, or money, doesn't it make sense to lock while caching?
module LockAndCacheMsgpack
  DEFAULT_MAX_LOCK_WAIT = 60 * 60 * 24 # 1 day in seconds

  DEFAULT_HEARTBEAT_EXPIRES = 32 # 32 seconds

  class TimeoutWaitingForLock < StandardError; end

  # @param redis_connection [Redis || lambda] A redis connection to be used for lock and cached value storage. Lazy evaluated if wrapped in a lambda
  def LockAndCacheMsgpack.storage=(redis_connection)
    @redis_connection = redis_connection
  end

  # @return [Redis] The redis connection used for lock and cached value storage
  def LockAndCacheMsgpack.storage
    @storage ||=
      begin
        connection = @redis_connection.class == Proc ? @redis_connection.call : @redis_connection
        raise "only redis for now" unless connection.class.to_s == 'Redis'
        @lock_manager = Redlock::Client.new [connection], retry_count: 1
        connection
      end
  end

  # @param logger [Logger] A logger.
  def LockAndCacheMsgpack.logger=(logger)
    @logger = logger
  end

  # @return [Logger] The logger.
  def LockAndCacheMsgpack.logger
    @logger
  end

  # Flush LockAndCacheMsgpack's storage.
  #
  # @note If you are sharing a redis database, it will clear it...
  #
  # @note If you want to clear a single key, try `LockAndCacheMsgpack.clear(key)` (standalone mode) or `#lock_and_cache_clear(method_id, *key_parts)` in context mode.
  def LockAndCacheMsgpack.flush
    storage.flushdb
  end

  # Lock and cache based on a key.
  #
  # @param key_parts [*] Parts that should be used to construct a key.
  #
  # @note Standalone mode. See also "context mode," where you mix LockAndCacheMsgpack into a class and call it from within its methods.
  #
  # @note A single hash arg is treated as a cache key, e.g. `LockAndCacheMsgpack.lock_and_cache(foo: :bar, expires: 100)` will be treated as a cache key of `foo: :bar, expires: 100` (which is probably wrong!!!). Try `LockAndCacheMsgpack.lock_and_cache({ foo: :bar }, expires: 100)` instead. This is the opposite of context mode.
  def LockAndCacheMsgpack.lock_and_cache(*key_parts_and_options, &blk)
    options = (key_parts_and_options.last.is_a?(Hash) && key_parts_and_options.length > 1) ? key_parts_and_options.pop : {}
    raise "need a cache key" unless key_parts_and_options.length > 0
    key = LockAndCacheMsgpack::Key.new key_parts_and_options
    action = LockAndCacheMsgpack::Action.new key, options, blk
    action.perform
  end

  # Clear a single key
  #
  # @note Standalone mode. See also "context mode," where you mix LockAndCacheMsgpack into a class and call it from within its methods.
  def LockAndCacheMsgpack.clear(*key_parts)
    key = LockAndCacheMsgpack::Key.new key_parts
    key.clear
  end

  # Check if a key is locked
  #
  # @note Standalone mode. See also "context mode," where you mix LockAndCacheMsgpack into a class and call it from within its methods.
  def LockAndCacheMsgpack.locked?(*key_parts)
    key = LockAndCacheMsgpack::Key.new key_parts
    key.locked?
  end

  # Check if a key is cached already
  #
  # @note Standalone mode. See also "context mode," where you mix LockAndCacheMsgpack into a class and call it from within its methods.
  def LockAndCacheMsgpack.cached?(*key_parts)
    key = LockAndCacheMsgpack::Key.new key_parts
    key.cached?
  end

  # @param seconds [Numeric] Maximum wait time to get a lock
  #
  # @note Can be overridden by putting `max_lock_wait:` in your call to `#lock_and_cache`
  def LockAndCacheMsgpack.max_lock_wait=(seconds)
    @max_lock_wait = seconds.to_f
  end

  # @private
  def LockAndCacheMsgpack.max_lock_wait
    @max_lock_wait || DEFAULT_MAX_LOCK_WAIT
  end

  # @param seconds [Numeric] How often a process has to heartbeat in order to keep a lock
  #
  # @note Can be overridden by putting `heartbeat_expires:` in your call to `#lock_and_cache`
  def LockAndCacheMsgpack.heartbeat_expires=(seconds)
    memo = seconds.to_f
    raise "heartbeat_expires must be greater than 2 seconds" unless memo >= 2
    @heartbeat_expires = memo
  end

  # @private
  def LockAndCacheMsgpack.heartbeat_expires
    @heartbeat_expires || DEFAULT_HEARTBEAT_EXPIRES
  end

  # @private
  def LockAndCacheMsgpack.lock_manager
    @lock_manager
  end

  # Check if a method is locked on an object.
  #
  # @note Subject mode - this is expected to be called on an object whose class has LockAndCacheMsgpack mixed in. See also standalone mode.
  def lock_and_cache_locked?(method_id, *key_parts)
    key = LockAndCacheMsgpack::Key.new key_parts, context: self, method_id: method_id
    key.locked?
  end

  # Clear a lock and cache given exactly the method and exactly the same arguments
  #
  # @note Subject mode - this is expected to be called on an object whose class has LockAndCacheMsgpack mixed in. See also standalone mode.
  def lock_and_cache_clear(method_id, *key_parts)
    key = LockAndCacheMsgpack::Key.new key_parts, context: self, method_id: method_id
    key.clear
  end

  # Lock and cache a method given key parts.
  #
  # The cache key will automatically include the class name of the object calling it (the context!) and the name of the method it is called from.
  #
  # @param key_parts_and_options [*] Parts that you want to include in the lock and cache key. If the last element is a Hash, it will be treated as options.
  #
  # @return The cached value (possibly newly calculated).
  #
  # @note Subject mode - this is expected to be called on an object whose class has LockAndCacheMsgpack mixed in. See also standalone mode.
  #
  # @note A single hash arg is treated as an options hash, e.g. `lock_and_cache(expires: 100)` will be treated as options `expires: 100`. This is the opposite of standalone mode.
  def lock_and_cache(*key_parts_and_options, &blk)
    options = key_parts_and_options.last.is_a?(Hash) ? key_parts_and_options.pop : {}
    key = LockAndCacheMsgpack::Key.new key_parts_and_options, context: self, caller: caller
    action = LockAndCacheMsgpack::Action.new key, options, blk
    action.perform
  end
end

logger = Logger.new $stderr
logger.level = (ENV['LOCK_AND_CACHE_DEBUG'] == 'true') ? Logger::DEBUG : Logger::INFO
LockAndCacheMsgpack.logger = logger
