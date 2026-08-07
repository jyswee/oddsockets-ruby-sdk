# frozen_string_literal: true

require 'uri'

module OddSockets
  # Manager Discovery Service
  #
  # Resolves the manager endpoint used for worker assignment. The manager
  # handles all routing and load balancing across workers transparently.
  class ManagerDiscovery
    # Hosted OddSockets manager endpoint.
    #
    # This applies only when no manager URL has been configured at all. It is
    # never used to recover from a configured manager that is unreachable:
    # silently redirecting a self-hosted or QA deployment at production would
    # make a broken setup look healthy and send traffic to the wrong cluster.
    DEFAULT_MANAGER_URL = 'https://connect.oddsockets.tyga.network'

    # Environment variable consulted when no manager URL is supplied in code
    MANAGER_URL_ENV_VAR = 'ODDSOCKETS_MANAGER_URL'

    # Resolve the manager URL to use
    #
    # Precedence: explicit value, then ODDSOCKETS_MANAGER_URL, then
    # DEFAULT_MANAGER_URL.
    #
    # @param manager_url [String, nil] Manager URL supplied by the caller
    # @return [String] The validated manager URL, without trailing slashes
    # @raise [ArgumentError] If the resolved value is not an absolute http(s) URL
    def self.resolve_manager_url(manager_url = nil)
      candidate = manager_url.to_s.strip
      candidate = ENV[MANAGER_URL_ENV_VAR].to_s.strip if candidate.empty?
      candidate = DEFAULT_MANAGER_URL if candidate.empty?

      normalised = candidate.sub(%r{/+\z}, '')

      begin
        uri = URI.parse(normalised)
      rescue URI::InvalidURIError
        raise ArgumentError, "Invalid managerUrl: #{candidate}"
      end

      unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
        raise ArgumentError, "Invalid managerUrl: #{candidate}"
      end

      normalised
    end

    attr_reader :manager_url

    # @param manager_url [String, nil] Manager URL to use (see .resolve_manager_url)
    def initialize(manager_url = nil)
      @manager_url = self.class.resolve_manager_url(manager_url)
    end

    # Get the manager URL to use for worker assignment
    # @param api_key [String] The OddSockets API key (not used, kept for compatibility)
    # @return [String] The configured manager URL
    def discover_manager_url(api_key)
      @manager_url
    end

    # Clear cache (no-op, kept for compatibility)
    def clear_cache
      # No cache to clear in simplified version
    end
  end
end
