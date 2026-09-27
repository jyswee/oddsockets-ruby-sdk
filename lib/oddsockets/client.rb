# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'websocket-client-simple'
require 'concurrent-ruby'
require 'digest'
require 'base64'
require 'time'

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
    # @option config [String] :manager_url Manager URL (defaults to
    #   OddSockets.configuration.manager_url)
    # @option config [String] :user_id User ID (defaults to API key's user)
    # @option config [Hash] :options Additional connection options
    # @option config [Boolean] :auto_connect Auto-connect on initialization (default: true)
    def initialize(config = {})
      # A game/app client authenticates with minted tokens via :token_provider
      # instead of a static :api_key (FEAT-2026-0824-0040); require one or the
      # other.
      unless config[:api_key] || config[:token_provider]
        raise ArgumentError, 'Either an API key or a token_provider is required'
      end

      # Resolved here so an invalid manager URL is rejected up front rather than
      # quietly sending traffic somewhere the caller did not ask for.
      @manager_discovery = ManagerDiscovery.new(
        config[:manager_url] || OddSockets.configuration.manager_url
      )

      @config = {
        api_key: config[:api_key],
        manager_url: @manager_discovery.manager_url,
        user_id: config[:user_id],
        options: config[:options] || {},
        auto_connect: config.fetch(:auto_connect, true),
        token_provider: config[:token_provider],
        token_refresh_lead_ms: config.fetch(:token_refresh_lead_ms, 120_000)
      }

      # Minted-token auth state (populated only in token mode).
      @current_token = nil
      @token_expires_at = nil # epoch ms
      @token_refresh_thread = nil

      @socket = nil
      @handshake_complete = false
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
        # Step 0: In token mode, fetch a FRESH minted token before anything else.
        # On a reconnect this is also the refresh path - a token that expired
        # during an outage is never replayed, because the provider is always
        # asked again here (FEAT-2026-0824-0040, "refresh on reconnect").
        resolve_token if token_mode?

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

      if @token_refresh_thread
        @token_refresh_thread.kill
        @token_refresh_thread = nil
      end

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

    # Fetch owner-scoped usage analytics for this tenant.
    #
    # Queries the manager's /api/tenant/usage endpoint with the configured API
    # key. Only key-mode clients can call this: a keyless/token client carries
    # no owner scope for the manager to attribute usage to.
    #
    # Each tile (:mau, :dau, :total_messages, :error_rate) is a number OR nil; a
    # nil tile is preserved and never coerced to 0.
    #
    # @return [Hash] with keys :mau, :dau, :total_messages, :error_rate,
    #   :owner_scope, :detail, :timestamp
    # @raise [ArgumentError] if the client is in token/keyless mode
    # @raise [ConnectionError] if the request fails or returns a non-2xx status
    def usage_stats
      if token_mode? || !@config[:api_key]
        raise ArgumentError,
              'usage_stats requires an apiKey (keyless/token clients have no owner scope to query)'
      end

      # Resolve the manager exactly as the worker-selection call does.
      manager_url = @manager_discovery.discover_manager_url(@config[:api_key])

      uri = URI("#{manager_url}/api/tenant/usage")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request['X-API-Key'] = @config[:api_key]
      request['User-Agent'] = 'OddSockets-Ruby-SDK/1.0.0'

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise ConnectionError, "Failed to fetch usage stats: #{response.code} #{response.message}"
      end

      data = JSON.parse(response.body) || {}
      tiles = data['tiles'] || {}

      # Preserve nulls: an absent/null tile stays nil, it is never made 0.
      {
        mau: tiles['mau'],
        dau: tiles['dau'],
        total_messages: tiles['totalMessages'],
        error_rate: tiles['errorRate'],
        owner_scope: data['ownerScope'],
        detail: data['detail'],
        timestamp: data['timestamp']
      }
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError
      raise ConnectionError, 'Manager is offline. Cannot fetch usage stats.'
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise ConnectionError, "Connection error: #{e.message}"
    end

    # Register event handler
    # @param event [Symbol] Event name
    # @param block [Proc] Event handler block
    def on(event, &block)
      @event_handlers.compute_if_absent(event) { [] } << block
    end

    # Register a one-shot event handler that removes itself after firing once.
    # Used by EnhancedFeatures to await a single worker response event.
    # @param event [Symbol, String] Event name
    # @param block [Proc] Event handler block
    def once(event, &block)
      return unless block_given?

      wrapper = nil
      wrapper = lambda do |*args|
        handlers = @event_handlers[event]
        handlers.delete(wrapper) if handlers
        block.call(*args)
      end
      @event_handlers.compute_if_absent(event) { [] } << wrapper
    end

    # Enhanced (Slack-like) features accessor: threads, reactions, presence,
    # notifications, search, DMs, channels. Actions are sent over the live
    # worker socket; broadcasts surface on this client's public event handlers.
    # @return [EnhancedFeatures]
    def enhanced
      @enhanced ||= EnhancedFeatures.new(self)
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

    # Internal: Emit a Socket.IO event to the worker (for Channel class)
    # Frames the event as an Engine.IO MESSAGE containing a Socket.IO EVENT:
    #   42["event", payload]
    # Null-valued keys are pruned because the worker destructures option
    # defaults only on `undefined`, and a JSON null would crash its handler.
    # @private
    def send_event(event, payload = {})
      return unless @socket

      body = JSON.generate([event, prune_nils(payload)])
      @socket.send("42#{body}")
    end

    # Internal: Check if connected (for Channel class)
    # @private
    def connected?
      @connection_state == CONNECTED && @handshake_complete && @socket && !@socket.closed?
    end

    private

    # Internal: Recursively drop nil-valued keys from a hash payload
    def prune_nils(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), acc|
          next if v.nil?
          acc[k] = prune_nils(v)
        end
      when Array
        value.map { |v| prune_nils(v) }
      else
        value
      end
    end

    # Internal: Get worker assignment from manager
    def get_worker_assignment
      # The configured manager is used as-is; there is no alternative endpoint
      # to fall back to if it is unreachable.
      manager_url = @manager_discovery.discover_manager_url(@config[:api_key])

      params = {
        userId: @config[:user_id] || @client_identifier,
        clientIdentifier: @client_identifier
      }
      if token_mode?
        # Token clients carry no API key - the manager picks a worker from the
        # minted token instead (FEAT-2026-0824-0040/0041).
        params[:token] = @current_token
      else
        params[:apiKey] = @config[:api_key]
      end

      uri = URI("#{manager_url}/api/cluster/select-worker")
      uri.query = URI.encode_www_form(params)

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

    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError
      # The configured manager is the only endpoint; when it cannot be reached
      # the call fails rather than being routed anywhere else.
      raise ConnectionError, 'Manager is offline. Cannot assign worker without session stickiness.'
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise ConnectionError, "Connection error: #{e.message}"
    end

    # Internal: Connect to assigned worker over Socket.IO (Engine.IO v4)
    def connect_to_worker
      raise ConnectionError, 'No worker URL available' unless @worker_url

      # The worker speaks genuine Socket.IO. Build the Engine.IO v4 WebSocket
      # endpoint from the assigned worker URL (http -> ws, https -> wss).
      ws_url = engine_io_url(@worker_url)

      @handshake_complete = false
      @socket = WebSocket::Client::Simple.connect(ws_url)

      setup_socket_event_handlers

      # Wait for the Socket.IO handshake (Engine.IO OPEN + namespace CONNECT ack)
      timeout = 15
      start_time = Time.now
      while !@handshake_complete && (Time.now - start_time) < timeout
        sleep(0.05)
      end

      unless @handshake_complete
        raise ConnectionError, 'Connection timeout'
      end
    end

    # Internal: Build the Engine.IO v4 WebSocket URL for a worker
    def engine_io_url(worker_url)
      uri = URI(worker_url)
      scheme = uri.scheme == 'https' ? 'wss' : 'ws'
      port = uri.port ? ":#{uri.port}" : ''
      "#{scheme}://#{uri.host}#{port}/socket.io/?EIO=4&transport=websocket"
    end

    # Internal: Setup Socket.IO (Engine.IO v4) frame handlers
    def setup_socket_event_handlers
      return unless @socket

      # websocket-client-simple runs these blocks via instance_exec, so inside
      # them `self` is the WebSocket client - route back to this Client.
      client = self

      @socket.on :close do |e|
        client.send(:handle_socket_close, e && e.code, e && e.reason)
      end

      @socket.on :error do |e|
        client.send(:handle_socket_error, e)
      end

      @socket.on :message do |msg|
        client.send(:handle_engine_io_frame, msg.data.to_s)
      end
    end

    # Internal: Handle a socket-level error
    def handle_socket_error(error)
      # The reader thread raises "stream closed" during an intentional
      # disconnect - that is expected teardown noise, not a real error.
      return if @connection_state == DISCONNECTED

      emit(:error, error)
    end

    # Internal: Handle the underlying socket closing
    def handle_socket_close(code, reason)
      @handshake_complete = false

      # An intentional disconnect already set DISCONNECTED - don't reconnect.
      return if @connection_state == DISCONNECTED

      @connection_state = DISCONNECTED
      emit(:disconnected, reason)
      schedule_reconnect unless code == 1000 # Normal closure
    end

    # Internal: Parse a raw Engine.IO v4 frame and dispatch accordingly
    def handle_engine_io_frame(frame)
      return if frame.empty?

      case frame[0]
      when '0' # Engine.IO OPEN -> send Socket.IO CONNECT with auth
        user_id = @config[:user_id] || @client_identifier
        # Token clients present the minted token; the worker's v1 handshake
        # branch reads socket.handshake.auth.token (FEAT-2026-0824-0039).
        auth = if token_mode? && @current_token
                 JSON.generate(token: @current_token, userId: user_id)
               else
                 JSON.generate(apiKey: @config[:api_key], userId: user_id)
               end
        @socket.send("40#{auth}")
      when '2' # Engine.IO PING -> PONG
        @socket.send('3')
      when '3' # Engine.IO PONG
        nil
      when '4' # Socket.IO message
        handle_socket_io_message(frame[1..])
      end
    rescue => e
      emit(:error, e)
    end

    # Internal: Handle a Socket.IO packet (frame with the leading Engine.IO '4' removed)
    def handle_socket_io_message(packet)
      return if packet.nil? || packet.empty?

      case packet[0]
      when '0' # CONNECT ack (namespace joined)
        @handshake_complete = true
      when '4' # CONNECT_ERROR
        body = packet[1..]
        details = body && !body.empty? ? (JSON.parse(body) rescue body) : 'connect error'
        @handshake_complete = false
        emit(:error, ConnectionError.new("Worker rejected connection: #{details.is_a?(Hash) ? details['message'] : details}"))
      when '2' # EVENT -> ["event", payload]
        decoded = JSON.parse(packet[1..])
        event = decoded[0]
        payload = decoded[1] || {}
        handle_message(adapt_incoming(event, payload))
      end
    rescue JSON::ParserError => e
      emit(:error, e)
    end

    # Internal: Normalise worker event payloads to the shape the Channel expects
    def adapt_incoming(event, payload)
      data = payload.is_a?(Hash) ? payload.dup : { 'value' => payload }
      data['type'] = event

      case event
      when 'published'
        data['message_id'] ||= data['messageId']
      when 'presence'
        data['count'] ||= data['occupancy']
      end

      data
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
      else
        # Enhanced (Slack-like) broadcasts - user_typing, reaction_added,
        # thread_reply, notifications, etc. Surface them on the public event
        # handlers so apps can `client.on('reaction_added') { ... }`.
        #
        # Challenge / leaderboard / achievement broadcasts flow through here too:
        #   challenge_progress, leaderboard_rank_change, challenge_complete,
        #   achievement_unlock, achievement_progress, challenge_invited,
        #   challenge_reply_received, challenge_invite_cancelled.
        emit(data['type'], data)
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

    # Internal: True when this client authenticates with minted tokens (a
    # token_provider callable) rather than a static API key.
    def token_mode?
      !@config[:token_provider].nil?
    end

    # Internal: Fetch a fresh minted token from the configured token_provider,
    # cache it with its expiry, and arm the pre-expiry refresh thread. Called
    # before every (re)connect and by that thread (FEAT-2026-0824-0040).
    #
    # The provider may return the token string directly, or a hash shaped like
    # the control-plane mint response ({ 'token' =>, 'expiresAt' =>, 'exp' => }).
    # String keys and symbol keys are both accepted.
    def resolve_token
      result = @config[:token_provider].call

      token = nil
      expires_at_ms = nil

      if result.is_a?(String)
        token = result
      elsif result.is_a?(Hash)
        token = result['token'] || result[:token]
        expires_at = result['expiresAt'] || result[:expiresAt]
        exp = result['exp'] || result[:exp]
        if !expires_at.nil?
          if expires_at.is_a?(Numeric)
            # Heuristic: values below 1e12 are epoch SECONDS, above are millis.
            expires_at_ms = expires_at < 1_000_000_000_000 ? (expires_at * 1000).to_i : expires_at.to_i
          else
            parsed = (Time.parse(expires_at.to_s) rescue nil)
            expires_at_ms = parsed ? (parsed.to_f * 1000).to_i : nil
          end
        elsif exp.is_a?(Numeric)
          expires_at_ms = (exp * 1000).to_i # JWT exp is epoch seconds
        end
      end

      unless token.is_a?(String) && !token.empty?
        raise AuthenticationError, 'token_provider must return a token string or a hash with a token key'
      end

      # No explicit expiry supplied - read `exp` out of the JWT so a refresh can
      # still be timed rather than letting the token lapse unnoticed.
      expires_at_ms ||= expiry_from_jwt(token)

      @current_token = token
      @token_expires_at = expires_at_ms
      schedule_token_refresh
      token
    end

    # Internal: Best-effort read of the `exp` claim (epoch seconds) from a JWT
    # WITHOUT verifying it - the worker is the verifier; the client only needs
    # exp to time its refresh. Returns epoch ms, or nil if unreadable.
    def expiry_from_jwt(token)
      parts = token.split('.')
      return nil if parts.length < 2

      payload = parts[1].tr('-_', '+/')
      payload += '=' * ((4 - payload.length % 4) % 4)
      json = Base64.decode64(payload)
      data = JSON.parse(json)
      exp = data['exp']
      exp.is_a?(Numeric) ? (exp * 1000).to_i : nil
    rescue StandardError
      nil
    end

    # Internal: Arm a one-shot thread to silently refresh the minted token
    # token_refresh_lead_ms before it expires (default 2 min). The refresh
    # updates the cached token; it does NOT tear down the current connection,
    # because the worker authenticates a token only at handshake and never
    # re-checks a live socket - the fresh token simply needs to be ready for the
    # next (re)connect (FEAT-2026-0824-0040).
    def schedule_token_refresh
      if @token_refresh_thread
        @token_refresh_thread.kill
        @token_refresh_thread = nil
      end
      return unless token_mode? && @token_expires_at

      lead = @config[:token_refresh_lead_ms]
      delay_ms = [@token_expires_at - now_ms - lead, 0].max

      @token_refresh_thread = Thread.new do
        sleep(delay_ms / 1000.0)
        begin
          resolve_token
          emit(:token_refreshed, { expiresAt: @token_expires_at })
        rescue StandardError => e
          # Surface but don't crash: the existing connection stays up on its
          # already-accepted token; the next reconnect retries the provider.
          emit(:error, e)
        end
      end
    end

    # Internal: Current wall-clock time in epoch milliseconds.
    def now_ms
      (Time.now.to_f * 1000).to_i
    end

    # Internal: Generate consistent client identifier for session stickiness
    def generate_client_identifier
      base_id = @config[:user_id] || 'default'
      # Token clients carry no API key to seed the hash from.
      api_key_hash = hash_string(@config[:api_key] || 'token-client')
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

      # dup so a one-shot handler removing itself mid-dispatch is safe.
      handlers.dup.each do |handler|
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
