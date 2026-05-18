#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'oddsockets'

# Basic usage example for OddSockets Ruby SDK
def main
  puts "OddSockets Ruby SDK - Basic Usage Example"
  puts "========================================"

  # Create client with API key
  client = OddSockets::Client.new(
    api_key: "ak_your_api_key_here",
    user_id: "ruby_example_user",
    auto_connect: false # Don't auto-connect for this example
  )

  # Set up event handlers
  client.on(:connecting) { puts "🔄 Connecting to OddSockets..." }
  client.on(:connected) { puts "✅ Connected to OddSockets!" }
  client.on(:disconnected) { |reason| puts "❌ Disconnected: #{reason}" }
  client.on(:error) { |error| puts "🚨 Error: #{error.message}" }
  
  client.on(:worker_assigned) do |data|
    puts "🎯 Assigned to worker: #{data[:worker_id]} at #{data[:worker_url]}"
    puts "📋 Session: #{data[:session]}"
  end

  begin
    # Connect to the platform
    puts "\n1. Connecting to OddSockets platform..."
    client.connect
    
    # Wait a moment for connection
    sleep(2)
    
    unless client.connected?
      puts "❌ Failed to connect. Check your API key and network connection."
      return
    end

    # Get a channel
    puts "\n2. Creating channel 'ruby-example'..."
    channel = client.channel("ruby-example")

    # Subscribe to the channel
    puts "\n3. Subscribing to channel..."
    channel.subscribe do |message|
      puts "📨 Received message: #{message['message']}"
      puts "   From: #{message['userId'] || 'Unknown'}"
      puts "   Time: #{message['timestamp']}"
    end.wait # Wait for subscription to complete

    puts "✅ Subscribed to channel!"

    # Publish some messages
    puts "\n4. Publishing messages..."
    
    messages = [
      "Hello from Ruby SDK! 👋",
      "This is message #2",
      { type: "notification", text: "Complex message with data", priority: "high" },
      "Final message from Ruby"
    ]

    messages.each_with_index do |message, index|
      puts "📤 Publishing message #{index + 1}..."
      result = channel.publish(message).wait
      puts "✅ Published: #{result['messageId']}"
      sleep(1) # Small delay between messages
    end

    # Demonstrate bulk publishing
    puts "\n5. Bulk publishing messages..."
    bulk_messages = [
      { channel: "ruby-example", message: "Bulk message 1" },
      { channel: "ruby-example", message: "Bulk message 2" },
      { channel: "ruby-example", message: "Bulk message 3" }
    ]

    results = client.publish_bulk(bulk_messages)
    results.each_with_index do |result, index|
      if result[:success]
        puts "✅ Bulk message #{index + 1} published"
      else
        puts "❌ Bulk message #{index + 1} failed: #{result[:error]}"
      end
    end

    # Get message history
    puts "\n6. Retrieving message history..."
    history = channel.history(count: 10).wait
    puts "📚 Retrieved #{history.length} messages from history"
    
    history.last(3).each do |msg|
      puts "  - #{msg['message']} (#{msg['timestamp']})"
    end

    # Get presence information
    puts "\n7. Getting presence information..."
    presence = channel.presence.wait
    puts "👥 Channel occupancy: #{presence['occupancy'] || 0} users"

    # Wait a bit to see any incoming messages
    puts "\n8. Listening for messages (5 seconds)..."
    sleep(5)

    # Unsubscribe
    puts "\n9. Unsubscribing from channel..."
    channel.unsubscribe.wait
    puts "✅ Unsubscribed from channel"

  rescue => e
    puts "🚨 Error occurred: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  ensure
    # Disconnect
    puts "\n10. Disconnecting..."
    client.disconnect
    puts "✅ Disconnected from OddSockets"
  end

  puts "\n🎉 Example completed!"
end

# Configuration example
def configuration_example
  puts "\nConfiguration Example:"
  puts "====================="

  # Configure globally
  OddSockets.configure do |config|
    config.manager_url = "https://manager1.oddsockets.tyga.network"
    config.timeout = 15
    config.log_level = :info
  end

  # Create client using global configuration
  client = OddSockets.client("ak_your_api_key_here", user_id: "configured_user")
  
  puts "✅ Client created with global configuration"
  puts "   Manager URL: #{OddSockets.configuration.manager_url}"
  puts "   Timeout: #{OddSockets.configuration.timeout}s"
  puts "   Log Level: #{OddSockets.configuration.log_level}"
end

# Utility examples
def utility_examples
  puts "\nUtility Examples:"
  puts "================"

  # Message type helpers
  chat_msg = OddSockets::MessageTypes.chat_message("Hello!", "ruby_user")
  puts "💬 Chat message: #{chat_msg}"

  notification = OddSockets::MessageTypes.notification_message(
    "New Update", 
    "Ruby SDK is working!", 
    "system", 
    "high"
  )
  puts "🔔 Notification: #{notification}"

  # Validation helpers
  valid_key = OddSockets::Utils.valid_api_key?("ak_test123456789")
  puts "🔑 API key valid: #{valid_key}"

  valid_channel = OddSockets::Utils.valid_channel_name?("ruby-example")
  puts "📺 Channel name valid: #{valid_channel}"

  # Version info
  version_info = OddSockets.version_info
  puts "ℹ️  SDK Version: #{version_info[:version]}"
  puts "   User Agent: #{version_info[:user_agent]}"
end

if __FILE__ == $0
  main
  configuration_example
  utility_examples
end
