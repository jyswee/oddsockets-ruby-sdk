# frozen_string_literal: true

require "zeitwerk"
require "json"
require "logger"
require "concurrent-ruby"
require "net/http"
require "uri"
require "websocket-client-simple"
require "digest"

# Set up Zeitwerk autoloader
loader = Zeitwerk::Loader.for_gem
loader.setup

# Main OddSockets module
#
# This module provides the main entry point for the OddSockets Ruby SDK.
# It includes configuration, client creation, and utility methods for
# real-time messaging with the OddSockets platform.
#
# @example Basic usage
#   require 'oddsockets'
#   
#   client = OddSockets::Client.new(api_key: "ak_your_api_key_here")
#   client.connect
#   
#   channel = client.channel("my-channel")
#   channel.subscribe { |message| puts "Received: #{message.data}" }
#   channel.publish("Hello, Ruby!")
#
# @example With configuration
#   OddSockets.configure do |config|
#     config.manager_url = "https://your-connect.oddsockets.tyga.network"
#     config.timeout = 15
#     config.heartbeat_interval = 45
#   end
#   
#   client = OddSockets::Client.new(api_key: "ak_your_api_key_here")
#
# @example Async usage
#   Async do
#     client = OddSockets::Client.new(api_key: "ak_your_api_key_here")
#     client.connect
#     
#     channel = client.channel("async-channel")
#     
#     # Publish multiple messages concurrently
#     tasks = 10.times.map do |i|
#       Async do
#         channel.publish("Message #{i}")
#       end
#     end
#     
#     tasks.each(&:wait)
#   end
#
module OddSockets
  # SDK configuration
  class Configuration
    attr_accessor :manager_url, :timeout, :heartbeat_interval, :reconnect_attempts, 
                  :auto_connect, :log_level, :user_agent

    def initialize
      @manager_url = "https://connect.oddsockets.tyga.network"
      @timeout = 10
      @heartbeat_interval = 30
      @reconnect_attempts = 5
      @auto_connect = true
      @log_level = :info
      @user_agent = "OddSockets-Ruby-SDK/1.0.0"
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.config
    configuration
  end

  # Error classes
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ConnectionError < Error; end
  class AuthenticationError < Error; end
  class ChannelError < Error; end
  class MessageError < Error; end
  class TimeoutError < Error; end

  # Connection states
  module ConnectionState
    DISCONNECTED = :disconnected
    CONNECTING = :connecting
    CONNECTED = :connected
    RECONNECTING = :reconnecting
    FAILED = :failed

    ALL = [DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING, FAILED].freeze

    # Check if state represents a connected state
    def self.connected?(state)
      state == CONNECTED
    end

    # Check if state represents a connecting state
    def self.connecting?(state)
      [CONNECTING, RECONNECTING].include?(state)
    end

    # Check if state represents a disconnected state
    def self.disconnected?(state)
      [DISCONNECTED, FAILED].include?(state)
    end
  end

  # Event types
  module EventType
    CONNECTED = :connected
    DISCONNECTED = :disconnected
    RECONNECTED = :reconnected
    ERROR = :error
    MESSAGE = :message
    PRESENCE = :presence
    WORKER_ASSIGNED = :worker_assigned
    MAX_RECONNECT_ATTEMPTS_REACHED = :max_reconnect_attempts_reached

    ALL = [
      CONNECTED, DISCONNECTED, RECONNECTED, ERROR, MESSAGE, 
      PRESENCE, WORKER_ASSIGNED, MAX_RECONNECT_ATTEMPTS_REACHED
    ].freeze

    # Check if event type is connection-related
    def self.connection_event?(type)
      [CONNECTED, DISCONNECTED, RECONNECTED, WORKER_ASSIGNED, MAX_RECONNECT_ATTEMPTS_REACHED].include?(type)
    end

    # Check if event type is message-related
    def self.message_event?(type)
      [MESSAGE, PRESENCE].include?(type)
    end
  end

  # Error codes
  module ErrorCode
    INVALID_API_KEY = "INVALID_API_KEY"
    CONNECTION_FAILED = "CONNECTION_FAILED"
    AUTHENTICATION_FAILED = "AUTHENTICATION_FAILED"
    CHANNEL_ACCESS_DENIED = "CHANNEL_ACCESS_DENIED"
    MESSAGE_DELIVERY_FAILED = "MESSAGE_DELIVERY_FAILED"
    INVALID_CONFIGURATION = "INVALID_CONFIGURATION"
    WORKER_ASSIGNMENT_FAILED = "WORKER_ASSIGNMENT_FAILED"
    MAX_RECONNECT_ATTEMPTS_REACHED = "MAX_RECONNECT_ATTEMPTS_REACHED"
    OPERATION_TIMEOUT = "OPERATION_TIMEOUT"
    INVALID_CHANNEL_NAME = "INVALID_CHANNEL_NAME"
    WEBSOCKET_ERROR = "WEBSOCKET_ERROR"

    ALL = [
      INVALID_API_KEY, CONNECTION_FAILED, AUTHENTICATION_FAILED,
      CHANNEL_ACCESS_DENIED, MESSAGE_DELIVERY_FAILED, INVALID_CONFIGURATION,
      WORKER_ASSIGNMENT_FAILED, MAX_RECONNECT_ATTEMPTS_REACHED,
      OPERATION_TIMEOUT, INVALID_CHANNEL_NAME, WEBSOCKET_ERROR
    ].freeze
  end

  # Utility methods
  module Utils
    # Generate a unique message ID
    #
    # @return [String] A unique message identifier
    def self.generate_message_id
      "msg_#{SecureRandom.hex(16)}"
    end

    # Generate a unique user ID
    #
    # @return [String] A unique user identifier
    def self.generate_user_id
      "user_#{SecureRandom.hex(16)}"
    end

    # Create a bulk message
    #
    # @param channel [String] The channel name
    # @param message [Object] The message data
    # @param options [Hash, nil] Publishing options
    # @return [BulkMessage] A bulk message object
    def self.bulk_message(channel, message, options = nil)
      BulkMessage.new(channel: channel, message: message, options: options)
    end

    # Create multiple bulk messages for the same channel
    #
    # @param channel [String] The channel name
    # @param messages [Array] Array of message data
    # @param options [Hash, nil] Publishing options
    # @return [Array<BulkMessage>] Array of bulk message objects
    def self.bulk_messages(channel, messages, options = nil)
      messages.map { |message| bulk_message(channel, message, options) }
    end

    # Validate API key format
    #
    # @param api_key [String] The API key to validate
    # @return [Boolean] True if valid format
    def self.valid_api_key?(api_key)
      api_key.is_a?(String) && api_key.start_with?("ak_") && api_key.length > 10
    end

    # Validate channel name
    #
    # @param channel_name [String] The channel name to validate
    # @return [Boolean] True if valid
    def self.valid_channel_name?(channel_name)
      channel_name.is_a?(String) && 
        !channel_name.empty? && 
        channel_name.match?(/\A[a-zA-Z0-9_-]+\z/)
    end

    # Convert Ruby hash to JSON with symbol keys converted to strings
    #
    # @param hash [Hash] The hash to convert
    # @return [String] JSON string
    def self.hash_to_json(hash)
      JSON.generate(deep_stringify_keys(hash))
    end

    # Deep stringify hash keys
    #
    # @param hash [Hash] The hash to process
    # @return [Hash] Hash with string keys
    def self.deep_stringify_keys(hash)
      case hash
      when Hash
        hash.each_with_object({}) do |(key, value), result|
          result[key.to_s] = deep_stringify_keys(value)
        end
      when Array
        hash.map { |item| deep_stringify_keys(item) }
      else
        hash
      end
    end

    # Deep symbolize hash keys
    #
    # @param hash [Hash] The hash to process
    # @return [Hash] Hash with symbol keys
    def self.deep_symbolize_keys(hash)
      case hash
      when Hash
        hash.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = deep_symbolize_keys(value)
        end
      when Array
        hash.map { |item| deep_symbolize_keys(item) }
      else
        hash
      end
    end
  end

  # Message type constructors
  module MessageTypes
    # Create a chat message
    #
    # @param text [String] The message text
    # @param username [String] The username
    # @param message_type [String, nil] The message type (default: "chat")
    # @return [Hash] Chat message structure
    def self.chat_message(text, username, message_type = nil)
      {
        text: text,
        username: username,
        message_type: message_type || "chat",
        timestamp: Time.now.utc.iso8601
      }
    end

    # Create a notification message
    #
    # @param title [String] The notification title
    # @param body [String] The notification body
    # @param category [String, nil] The notification category (default: "general")
    # @param priority [String, nil] The notification priority (default: "normal")
    # @param data [Hash, nil] Additional data
    # @return [Hash] Notification message structure
    def self.notification_message(title, body, category = nil, priority = nil, data = nil)
      message = {
        title: title,
        body: body,
        category: category || "general",
        priority: priority || "normal",
        timestamp: Time.now.utc.iso8601
      }
      message[:data] = data if data
      message
    end

    # Create a system message
    #
    # @param event [String] The system event
    # @param description [String] Event description
    # @param metadata [Hash, nil] Additional metadata
    # @return [Hash] System message structure
    def self.system_message(event, description, metadata = nil)
      message = {
        event: event,
        description: description,
        timestamp: Time.now.utc.iso8601
      }
      message[:metadata] = metadata if metadata
      message
    end

    # Create a data event message
    #
    # @param event_type [String] The event type
    # @param payload [Hash] The event payload
    # @param source [String, nil] The event source
    # @return [Hash] Data event message structure
    def self.data_event(event_type, payload, source = nil)
      message = {
        event_type: event_type,
        payload: payload,
        timestamp: Time.now.utc.iso8601
      }
      message[:source] = source if source
      message
    end
  end

  # Global configuration method
  #
  # @yield [config] Configuration block
  # @yieldparam config [Configuration] Configuration object
  # @return [void]
  #
  # @example
  #   OddSockets.configure do |config|
  #     config.manager_url = "https://custom-connect.oddsockets.tyga.network"
  #     config.timeout = 15
  #     config.log_level = :debug
  #   end
  def self.configure(&block)
    yield(configuration) if block_given?
  end

  # Create a new client with global configuration
  #
  # @param api_key [String] The API key
  # @param options [Hash] Additional client options
  # @return [Client] A new client instance
  #
  # @example
  #   client = OddSockets.client("ak_your_api_key_here")
  #   client = OddSockets.client("ak_your_api_key_here", user_id: "user123")
  def self.client(api_key, **options)
    Client.new(api_key: api_key, **options)
  end

  # Get SDK version information
  #
  # @return [Hash] Version information
  def self.version_info
    {
      version: "1.0.0",
      sdk_name: "OddSockets Ruby SDK",
      user_agent: "OddSockets-Ruby-SDK/1.0.0",
      api_version: "v1",
      ruby_version: RUBY_VERSION
    }
  end

  # Check if running in development mode
  #
  # @return [Boolean] True if in development
  def self.development?
    ENV["ODDSOCKETS_ENV"] == "development" || 
      ENV["RAILS_ENV"] == "development" ||
      ENV["RACK_ENV"] == "development"
  end

  # Check if running in production mode
  #
  # @return [Boolean] True if in production
  def self.production?
    ENV["ODDSOCKETS_ENV"] == "production" || 
      ENV["RAILS_ENV"] == "production" ||
      ENV["RACK_ENV"] == "production"
  end

  # Get default logger
  #
  # @return [Logger] Default logger instance
  def self.logger
    @logger ||= begin
      logger = Logger.new($stdout)
      logger.level = case config.log_level
                     when :debug then Logger::DEBUG
                     when :info then Logger::INFO
                     when :warn then Logger::WARN
                     when :error then Logger::ERROR
                     when :fatal then Logger::FATAL
                     else Logger::INFO
                     end
      logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime}] #{severity} -- #{progname}: #{msg}\n"
      end
      logger
    end
  end

  # Set custom logger
  #
  # @param logger [Logger] Custom logger instance
  # @return [Logger] The logger that was set
  def self.logger=(logger)
    @logger = logger
  end
end

# Require core files after module definition
require_relative "oddsockets/version"
require_relative "oddsockets/client"
require_relative "oddsockets/channel"
require_relative "oddsockets/manager_discovery"
