# frozen_string_literal: true

require 'json'
require 'concurrent-ruby'

module OddSockets
  # Message size limits (industry standard - matches PubNub)
  MESSAGE_SIZE_LIMITS = {
    max_message_size: 32768, # 32KB in bytes
    max_message_size_kb: 32
  }.freeze

  # Channel class for pub/sub messaging
  # 
  # Provides methods for subscribing, publishing, and managing presence
  # on a specific channel within the OddSockets platform.
  class Channel
    attr_reader :name, :client, :subscribed, :subscribing, :options, :presence, 
                :message_history, :max_history_size

    # Create a Channel instance
    # @param name [String] Channel name
    # @param client [Client] Parent OddSockets client
    def initialize(name, client)
      @name = name
      @client = client
      @subscribed = false
      @subscribing = false
      @options = {}
      @presence = Concurrent::Map.new
      @message_history = []
      @max_history_size = 100
      @event_handlers = Concurrent::Map.new
      @mutex = Mutex.new
    end

    # Subscribe to the channel
    # @param callback [Proc] Message callback function
    # @param options [Hash] Subscription options
    # @option options [Integer] :max_history Maximum history messages to retain (default: 100)
    # @option options [Boolean] :retain_history Whether to retain message history (default: true)
    # @option options [Boolean] :enable_presence Whether to enable presence tracking (default: false)
    # @return [Promise] Promise that resolves when subscribed
    def subscribe(callback = nil, options = {}, &block)
      callback ||= block
      raise ArgumentError, 'Callback function is required' unless callback

      if @subscribed || @subscribing
        # Add callback to existing subscription
        on(:message, &callback)
        return Concurrent::Promises.fulfilled_future(nil)
      end

      raise ConnectionError, 'Client is not connected' unless @client.connected?

      @subscribing = true
      @options = {
        max_history: options[:max_history] || 100,
        retain_history: options.fetch(:retain_history, true),
        enable_presence: options[:enable_presence] || false
      }.merge(options)

      @max_history_size = @options[:max_history]

      promise = Concurrent::Promises.resolvable_future

      # Forward-declare so both closures capture the same locals
      subscribed_handler = nil
      error_handler = nil

      # Set up one-time listeners for subscription response
      subscribed_handler = proc do |data|
        if data['channel'] == @name
          @subscribed = true
          @subscribing = false
          on(:message, &callback)
          
          off(:subscribed, &subscribed_handler)
          off(:error, &error_handler)
          
          emit(:subscribed, data)
          promise.fulfill(nil)
        end
      end

      error_handler = proc do |error|
        @subscribing = false
        off(:subscribed, &subscribed_handler)
        off(:error, &error_handler)
        promise.reject(error)
      end

      on(:subscribed, &subscribed_handler)
      on(:error, &error_handler)

      # Send subscription request (worker reads camelCase option keys)
      send_message({
        type: 'subscribe',
        channel: @name,
        options: {
          maxHistory: @options[:max_history],
          retainHistory: @options[:retain_history],
          enablePresence: @options[:enable_presence]
        }
      })

      # Timeout fallback
      Thread.new do
        sleep(10)
        if @subscribing
          off(:subscribed, &subscribed_handler)
          off(:error, &error_handler)
          @subscribing = false
          promise.reject(TimeoutError.new('Subscription timeout'))
        end
      end

      promise
    end

    # Unsubscribe from the channel
    # @return [Promise] Promise that resolves when unsubscribed
    def unsubscribe
      return Concurrent::Promises.fulfilled_future(nil) unless @subscribed

      raise ConnectionError, 'Client is not connected' unless @client.connected?

      promise = Concurrent::Promises.resolvable_future

      unsubscribed_handler = nil
      error_handler = nil

      unsubscribed_handler = proc do |data|
        if data['channel'] == @name
          @subscribed = false
          remove_all_listeners(:message)
          
          off(:unsubscribed, &unsubscribed_handler)
          off(:error, &error_handler)
          
          emit(:unsubscribed, data)
          promise.fulfill(nil)
        end
      end

      error_handler = proc do |error|
        off(:unsubscribed, &unsubscribed_handler)
        off(:error, &error_handler)
        promise.reject(error)
      end

      on(:unsubscribed, &unsubscribed_handler)
      on(:error, &error_handler)

      send_message({
        type: 'unsubscribe',
        channel: @name
      })

      # Timeout fallback
      Thread.new do
        sleep(5)
        off(:unsubscribed, &unsubscribed_handler)
        off(:error, &error_handler)
        promise.reject(TimeoutError.new('Unsubscription timeout'))
      end

      promise
    end

    # Publish a message to the channel
    # @param message [Object] Message to publish (string, hash, or array)
    # @param options [Hash] Publishing options
    # @option options [Integer] :ttl Time to live in seconds
    # @option options [Hash] :metadata Additional message metadata
    # @return [Promise] Promise that resolves with publication result
    def publish(message, options = {})
      raise ConnectionError, 'Client is not connected' unless @client.connected?

      # Validate message size before publishing
      validate_message_size(message)

      promise = Concurrent::Promises.resolvable_future

      published_handler = nil
      error_handler = nil

      published_handler = proc do |data|
        if data['channel'] == @name
          off(:published, &published_handler)
          off(:error, &error_handler)
          promise.fulfill(data)
        end
      end

      error_handler = proc do |error|
        off(:published, &published_handler)
        off(:error, &error_handler)
        promise.reject(error)
      end

      on(:published, &published_handler)
      on(:error, &error_handler)

      send_message({
        type: 'publish',
        channel: @name,
        message: message,
        options: options
      })

      # Timeout fallback
      Thread.new do
        sleep(10)
        off(:published, &published_handler)
        off(:error, &error_handler)
        promise.reject(TimeoutError.new('Publish timeout'))
      end

      promise
    end

    # Get message history for the channel
    # @param options [Hash] History options
    # @option options [Integer] :count Number of messages to retrieve (default: 50)
    # @option options [String] :start Start time (ISO string)
    # @option options [String] :end End time (ISO string)
    # @return [Promise] Promise that resolves with message history
    def history(options = {})
      raise ConnectionError, 'Client is not connected' unless @client.connected?

      promise = Concurrent::Promises.resolvable_future

      history_handler = nil
      error_handler = nil

      history_handler = proc do |data|
        if data['channel'] == @name
          off(:history, &history_handler)
          off(:error, &error_handler)
          promise.fulfill(data['messages'] || [])
        end
      end

      error_handler = proc do |error|
        off(:history, &history_handler)
        off(:error, &error_handler)
        promise.reject(error)
      end

      on(:history, &history_handler)
      on(:error, &error_handler)

      send_message({
        type: 'get_history',
        channel: @name,
        count: options[:count] || 50,
        start: options[:start],
        end: options[:end]
      })

      # Timeout fallback
      Thread.new do
        sleep(10)
        off(:history, &history_handler)
        off(:error, &error_handler)
        promise.reject(TimeoutError.new('History request timeout'))
      end

      promise
    end

    # Get current presence information
    # @return [Promise] Promise that resolves with presence information
    def presence
      raise ConnectionError, 'Client is not connected' unless @client.connected?

      promise = Concurrent::Promises.resolvable_future

      presence_handler = nil
      error_handler = nil

      presence_handler = proc do |data|
        if data['channel'] == @name
          off(:presence, &presence_handler)
          off(:error, &error_handler)
          promise.fulfill(data)
        end
      end

      error_handler = proc do |error|
        off(:presence, &presence_handler)
        off(:error, &error_handler)
        promise.reject(error)
      end

      on(:presence, &presence_handler)
      on(:error, &error_handler)

      send_message({
        type: 'get_presence',
        channel: @name
      })

      # Timeout fallback
      Thread.new do
        sleep(5)
        off(:presence, &presence_handler)
        off(:error, &error_handler)
        promise.reject(TimeoutError.new('Presence request timeout'))
      end

      promise
    end

    # Update user state
    # @param state [Hash] User state object
    # @return [Promise] Promise that resolves when state is updated
    def update_state(state)
      raise ConnectionError, 'Client is not connected' unless @client.connected?

      promise = Concurrent::Promises.resolvable_future

      state_updated_handler = nil
      error_handler = nil

      state_updated_handler = proc do |data|
        off(:state_updated, &state_updated_handler)
        off(:error, &error_handler)
        promise.fulfill(data)
      end

      error_handler = proc do |error|
        off(:state_updated, &state_updated_handler)
        off(:error, &error_handler)
        promise.reject(error)
      end

      on(:state_updated, &state_updated_handler)
      on(:error, &error_handler)

      send_message({
        type: 'update_state',
        state: state
      })

      # Timeout fallback
      Thread.new do
        sleep(5)
        off(:state_updated, &state_updated_handler)
        off(:error, &error_handler)
        promise.reject(TimeoutError.new('State update timeout'))
      end

      promise
    end

    # Get channel subscription status
    # @return [Boolean] Whether channel is subscribed
    def subscribed?
      @subscribed
    end

    # Get current presence map
    # @return [Hash] Presence map
    def presence_map
      @presence.each_pair.to_h
    end

    # Get cached message history
    # @return [Array] Cached messages
    def cached_history
      @mutex.synchronize { @message_history.dup }
    end

    # Register event handler
    # @param event [Symbol] Event name
    # @param block [Proc] Event handler block
    def on(event, &block)
      @event_handlers.compute_if_absent(event) { [] } << block
    end

    # Remove event handler
    # @param event [Symbol] Event name
    # @param handler [Proc] Event handler to remove
    def off(event, &handler)
      handlers = @event_handlers[event]
      return unless handlers

      if handler
        handlers.delete(handler)
      else
        handlers.clear
      end
    end

    # Remove all listeners for an event
    # @param event [Symbol] Event name
    def remove_all_listeners(event)
      @event_handlers.delete(event)
    end

    # Internal: Handle incoming message
    # @param data [Hash] Message data
    def handle_message(data)
      # Add to history if enabled
      if @options[:retain_history]
        @mutex.synchronize do
          @message_history << data
          
          # Trim history if too large
          if @message_history.length > @max_history_size
            @message_history = @message_history.last(@max_history_size)
          end
        end
      end

      emit(:message, data)
    end

    # Internal: Handle subscription confirmation
    # @param data [Hash] Subscription data
    def handle_subscribed(data)
      emit(:subscribed, data)
    end

    # Internal: Handle unsubscription confirmation
    # @param data [Hash] Unsubscription data
    def handle_unsubscribed(data)
      emit(:unsubscribed, data)
    end

    # Internal: Handle publish confirmation
    # @param data [Hash] Publish confirmation data
    def handle_published(data)
      emit(:published, data)
    end

    # Internal: Handle presence information
    # @param data [Hash] Presence data
    def handle_presence(data)
      # Update presence map
      if data['occupants']
        @presence.clear
        data['occupants'].each do |occupant|
          @presence[occupant['userId']] = occupant
        end
      end

      emit(:presence, data)
    end

    # Internal: Handle presence changes
    # @param data [Hash] Presence change data
    def handle_presence_change(data)
      # Update presence map
      case data['action']
      when 'join'
        @presence[data['user']['userId']] = data['user']
      when 'leave'
        @presence.delete(data['user']['userId'])
      end

      emit(:presence_change, data)
    end

    # Internal: Handle message history
    # @param data [Hash] History data
    def handle_history(data)
      emit(:history, data)
    end

    private

    # Validate message size
    # @param message [Object] Message to validate
    # @raise [MessageError] If message exceeds size limit
    def validate_message_size(message)
      message_str = message.is_a?(String) ? message : JSON.generate(message)
      message_size = message_str.bytesize

      if message_size > MESSAGE_SIZE_LIMITS[:max_message_size]
        raise MessageError,
          "Message size (#{(message_size / 1024.0).round}KB) exceeds maximum allowed size of #{MESSAGE_SIZE_LIMITS[:max_message_size_kb]}KB. " \
          "This limit matches industry standards (PubNub, Socket.IO) for reliable real-time messaging."
      end

      message_size
    end

    # Send a request to the worker as a Socket.IO event
    # @param data [Hash] Message data (the :type key names the event)
    def send_message(data)
      payload = data.dup
      event = payload.delete(:type).to_s
      @client.send_event(event, payload)
    end

    # Emit event to registered handlers
    # @param event [Symbol] Event name
    # @param args [Array] Event arguments
    def emit(event, *args)
      handlers = @event_handlers[event]
      return unless handlers

      handlers.each do |handler|
        begin
          handler.call(*args)
        rescue => e
          # Log error but don't let it break other handlers
          puts "Error in channel event handler for #{event}: #{e.message}"
        end
      end
    end
  end
end
