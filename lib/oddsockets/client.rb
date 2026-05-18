# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'websocket-client-simple'
require 'concurrent-ruby'
require 'digest'

module OddSockets
  # OddSockets Ruby SDK Client
  # 
  # Provides a simple interface to the OddSockets real-time messaging platform.
  # Automatically handles manager discovery and Worker load balancing internally.
  class Client
    include Concurrent::Async

    # Connection states
    DISCONNECTED = :disconnected
    CONNECTING = :connecting
    CONNECTED = :connected
    RECONNECTING = :reconnecting

    attr_reader :config, :connection_state, :worker_url, :worker_id, :channels, 
                :client_identifier, :session_info, :reconnect_attempts

    # Create an OddSockets client
    # @param config [Hash] Configuration options
    # @option config [String] :api_key Your OddSockets API key (required)
    # @option config [String] :user_id User ID (defaults to API key's user)
    # @option config [Hash] :options Additional connection options
    # @option config [Boolean] :auto_connect Auto-connect on initialization (default: true)
    def initialize(config = {})
      raise ArgumentError, 'API key is required' unless config[:api_key]

      @config = {
        api_key: config[:api_key],
        user_id: config[:user_id],
        options: config[:options] || {},
        auto_connect: config.fetch(:auto_connect, true)
      }

      @socket = nil
      @worker_url = nil
      @worker_id = nil
      @channels = Concurrent::Map.new
      @connection_state = DISCONNECTED
      @reconnect_attempts = 0
      @max_reconnect_attempts = 5
      @reconnect_delay = 1.0 # Start with 1 second
      @client_identifier = generate_client_identifier
      @session_info = nil
      @event_handlers = Concurrent::Map.new
      @manager_discovery = ManagerDiscovery.new

      # Auto-connect by default
      connect if @config[:auto_connect]
    end

    # Connect to the OddSockets platform
    # Handles the Manager → Worker assignment internally
    def connect
      return if @connection_state == CONNECTING || @connection_state == CONNECTED

      @connection_state = CONNECTING
      emit(:connecting)

      begin
        # Step 1: Get worker assignment from manager
        get_worker_assignment

        # Step 2: Connect to assigned worker
        connect_to_worker

        @connection_state = CONNECTED
        @reconnect_attempts = 0
        @reconnect_delay = 1.0
        emit(:connected)

      rescue => error
        @connection_state = DISCONNECTED
        emit(:error, error)

        # Auto-reconnect with exponential backoff
        if @reconnect_attempts < @max_reconnect_attempts
          schedule_reconnect
        else
          emit(:max_reconnect_attempts_reached)
        end
      end
    end

    # Disconnect from the platform
    def disconnect
      @connection_state = DISCONNECTED

      if @socket
        @socket.close
        @socket = nil
      end

      @worker_url = nil
      @worker_id = nil
      emit(:disconnected)
    end

    # Get or create a channel
    # @param channel_name [String] Name of the channel
    # @return [Channel] Channel instance
    def channel(channel_name)
      raise ArgumentError, 'Channel name must be a non-empty string' unless channel_name.is_a?(String) && !channel_name.empty?

      @channels.compute_if_absent(channel_name) do
        Channel.new(channel_name, self)
      end
    end

    # Get current connection state
    # @return [Symbol] Connection state
    def state
      @connection_state
    end

    # Get assigned worker information
    # @return [Hash, nil] Worker info
    def worker_info
      return nil unless @worker_id && @worker_url

      {
        worker_id: @worker_id,
        worker_url: @worker_url
      }
    end

    # Publish multiple messages at once
    # @param messages [Array] Array of message objects with {channel:, message:, options:} structure
    # @return [Array] Array of publish results
    def publish_bulk(messages)
      raise ArgumentError, 'Messages must be an array' unless messages.is_a?(Array)
      raise ConnectionError, 'Not connected to OddSockets' unless connected?

      results = []

      messages.each do |msg|
        begin
          unless msg[:channel] && msg.key?(:message)
            results << {
              success: false,
              error: 'Missing channel or message'
            }
            next
          end

          channel_obj = channel(msg[:channel])
          result = channel_obj.publish(msg[:message], msg[:options] || {})
          results << {
            success: true,
            result: result
          }

        rescue => error
          results << {
            success: false,
            error: error.message
          }
        end
      end

      results
    end

    # Register event handler
    # @param event [Symbol] Event name
    # @param block [Proc] Event handler block
    def on(event, &block)
      @event_handlers.compute_if_absent(event) { [] } << block
    end

    # Get client identifier used for session stickiness
    # @return [String] Client identifier
    def client_identifier
      @client_identifier
    end

    # Get session information
    # @return [Hash, nil] Session info
    def session_info
      @session_info
    end

    # Internal: Get socket instance (for Channel class)
    # @private
    def socket
      @socket
    end

    # Internal: Check if connected (for Channel class)
    # @private
    def connected?
      @connection_state == CONNECTED && @socket && !@socket.closed?
    end

    private

    # Internal: Get worker assignment from manager
    def get_worker_assignment
      # Discover the optimal manager URL automatically
      manager_url = @manager_discovery.discover_manager_url(@config[:api_key])

      uri = URI("#{manager_url}/api/cluster/select-worker")
      uri.query = URI.encode_www_form({
        apiKey: @config[:api_key],
        userId: @config[:user_id] || @client_identifier,
        clientIdentifier: @client_identifier
      })

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = 'OddSockets-Ruby-SDK/1.0.0'

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise ConnectionError, "Failed to get worker assignment: #{response.code} #{response.message}"
      end

      data = JSON.parse(response.body)

      unless data['url']
        raise ConnectionError, 'Invalid worker assignment response'
      end

      @worker_url = data['url']
      @worker_id = data['workerId']
      @session_info = data['session']

      emit(:worker_assigned, {
        worker_id: @worker_id,
        worker_url: @worker_url,
        session: @session_info,
        client_identifier: @client_identifier,
        manager_url: manager_url
      })

    rescue Net::TimeoutError, Errno::ECONNREFUSED, Errno::ENOTFOUND => e
      if e.is_a?(Errno::ECONNREFUSED) || e.is_a?(Errno::ENOTFOUND)
        raise ConnectionError, 'Manager is offline. Cannot assign worker without session stickiness.'
      end
      raise ConnectionError, "Connection error: #{e.message}"
    end

    # Internal: Connect to assigned worker
    def connect_to_worker
      raise ConnectionError, 'No worker URL available' unless @worker_url

      @socket = WebSocket::Client::Simple.connect(@worker_url, {
        headers: {
          'Authorization' => "Bearer #{@config[:api_key]}",
          'X-User-ID' => @config[:user_id] || @client_identifier
        }
      })

      setup_socket_event_handlers

      # Wait for connection to be established
      timeout = 15
      start_time = Time.now
      while !@socket.open? && (Time.now - start_time) < timeout
        sleep(0.1)
      end

      unless @socket.open?
        raise ConnectionError, 'Connection timeout'
      end
    end

    # Internal: Setup socket event handlers
    def setup_socket_event_handlers
      return unless @socket

      @socket.on :close do |e|
        @connection_state = DISCONNECTED
        emit(:disconnected, e.reason)

        # Auto-reconnect unless manually disconnected
        unless e.code == 1000 # Normal closure
          schedule_reconnect
        end
      end

      @socket.on :error do |e|
        emit(:error, e)
      end

      @socket.on :message do |msg|
        begin
          data = JSON.parse(msg.data)
          handle_message(data)
        rescue JSON::ParserError => e
          emit(:error, e)
        end
      end
    end

    # Internal: Handle incoming messages
    def handle_message(data)
      case data['type']
      when 'message'
        channel_obj = @channels[data['channel']]
        channel_obj.handle_message(data) if channel_obj
      when 'subscribed'
        channel_obj = @channels[data['channel']]
        channel_obj.handle_subscribed(data) if channel_obj
      when 'unsubscribed'
        channel_obj = @channels[data['channel']]
        channel_obj.handle_unsubscribed(data) if channel_obj
      when 'published'
        channel_obj = @channels[data['channel']]
        channel_obj.handle_published(data) if channel_obj
      when 'presence'
        channel_obj = @channels[data['channel']]
        channel_obj.handle_presence(data) if channel_obj
      when 'presence_change'
        channel_obj = @channels[data['channel']]
        channel_obj.handle_presence_change(data) if channel_obj
      when 'history'
        channel_obj = @channels[data['channel']]
        channel_obj.handle_history(data) if channel_obj
      end
    end

    # Internal: Schedule reconnection with exponential backoff
    def schedule_reconnect
      return if @connection_state == CONNECTED

      @connection_state = RECONNECTING
      @reconnect_attempts += 1

      delay = [@reconnect_delay * (2 ** (@reconnect_attempts - 1)), 30.0].min

      emit(:reconnecting, {
        attempt: @reconnect_attempts,
        max_attempts: @max_reconnect_attempts,
        delay: delay
      })

      Thread.new do
        sleep(delay)
        connect if @connection_state == RECONNECTING
      end
    end

    # Internal: Generate consistent client identifier for session stickiness
    def generate_client_identifier
      base_id = @config[:user_id] || 'default'
      api_key_hash = hash_string(@config[:api_key])
      "#{api_key_hash}_#{base_id}"
    end

    # Internal: Simple hash function for API key
    def hash_string(str)
      Digest::SHA256.hexdigest(str)[0, 8]
    end

    # Internal: Emit event to registered handlers
    def emit(event, *args)
      handlers = @event_handlers[event]
      return unless handlers

      handlers.each do |handler|
        begin
          handler.call(*args)
        rescue => e
          # Log error but don't let it break other handlers
          puts "Error in event handler for #{event}: #{e.message}"
        end
      end
    end
  end
end
