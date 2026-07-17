# frozen_string_literal: true

module OddSockets
  # Simple Manager Discovery Service
  # 
  # Always connects to the main manager endpoint which handles
  # all routing and load balancing transparently.
  class ManagerDiscovery
    # Default manager URL
    MANAGER_URL = 'https://connect.oddsockets.tyga.network'

    def initialize
      @manager_url = MANAGER_URL
    end

    # Get the manager URL (always returns the main endpoint)
    # @param api_key [String] The OddSockets API key (not used, kept for compatibility)
    # @return [String] The manager URL
    def discover_manager_url(api_key)
      @manager_url
    end

    # Clear cache (no-op, kept for compatibility)
    def clear_cache
      # No cache to clear in simplified version
    end
  end
end
