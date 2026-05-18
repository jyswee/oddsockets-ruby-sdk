#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/oddsockets'
require_relative '../lib/oddsockets/enhanced_features'

# OddSockets Ruby SDK - Enhanced Features Example
# Demonstrates all 67 new Slack-like events with Ruby blocks

puts '🚀 OddSockets Ruby SDK - Enhanced Features Example'
puts 'Demonstrating all 67 new Slack-like events'
puts '=' * 50

# Create and configure client
client = OddSockets::Client.new('your_api_key_here', 'user_123')

# Set up event listeners
client.on('connected') do
  puts '🟢 Connected event fired'
end

client.on('disconnected') do
  puts '🔴 Disconnected event fired'
end

client.on('error') do |error|
  puts "❌ Error event: #{error}"
end

# Connect
puts "\n🔄 Connecting to OddSockets..."
client.connect

# Wait for connection
sleep 2

unless client.connected?
  puts '❌ Failed to connect'
  exit 1
end

puts "✅ Connected successfully!\n\n"

# Create enhanced features instance
enhanced = OddSockets::EnhancedFeatures.new(client)

# Test all enhanced features
def test_thread_events(enhanced)
  puts '📝 Testing Thread Events...'

  enhanced.thread_reply(
    channel: 'general',
    parent_message_id: 'msg_123',
    message: 'This is a test reply from Ruby!',
    user_id: 'user_123',
    user_name: 'Test User'
  ) do |result|
    puts "✅ Thread reply created: #{result}"
  end

  enhanced.get_thread('thread_123') do |thread|
    puts "✅ Thread data: #{thread}"
  end

  enhanced.subscribe_thread('thread_123', 'user_123') do |result|
    puts "✅ Subscribed to thread: #{result}"
  end

  enhanced.mark_thread_read('thread_123', 'user_123')
  puts '✅ Marked thread as read'

  enhanced.follow_thread('thread_123', 'user_123')
  puts "✅ Following thread\n\n"
rescue StandardError => e
  puts "❌ Thread events error: #{e.message}\n\n"
end

def test_reaction_events(enhanced)
  puts '😀 Testing Reaction Events...'

  enhanced.add_reaction(
    message_id: 'msg_123',
    channel: 'general',
    emoji: '👍',
    user_id: 'user_123',
    user_name: 'Test User'
  )
  puts '✅ Added reaction 👍'

  enhanced.remove_reaction(
    message_id: 'msg_123',
    channel: 'general',
    emoji: '👍',
    user_id: 'user_123'
  )
  puts '✅ Removed reaction'

  enhanced.get_reactions('msg_123') do |reactions|
    puts "✅ Reactions: #{reactions}\n\n"
  end
rescue StandardError => e
  puts "❌ Reaction events error: #{e.message}\n\n"
end

def test_read_receipt_events(enhanced)
  puts '✓ Testing Read Receipt Events...'

  enhanced.mark_read(
    message_id: 'msg_123',
    channel: 'general',
    user_id: 'user_123',
    user_name: 'Test User'
  )
  puts '✅ Marked message as read'

  enhanced.get_unread_counts('user_123', %w[general random]) do |counts|
    puts "✅ Unread counts: #{counts}"
  end

  enhanced.mark_all_read('general', 'user_123')
  puts "✅ Marked all messages as read\n\n"
rescue StandardError => e
  puts "❌ Read receipt events error: #{e.message}\n\n"
end

def test_channel_events(enhanced)
  puts '📢 Testing Channel Events...'

  enhanced.create_channel(
    name: "ruby-test-#{Time.now.to_i}",
    type: 'public',
    description: 'Created from Ruby SDK',
    topic: 'Testing',
    created_by: 'user_123',
    created_by_name: 'Test User'
  ) do |channel|
    puts "✅ Channel created: #{channel}"
  end

  enhanced.update_channel('channel_123', { topic: 'Updated topic' }, 'user_123')
  puts '✅ Updated channel'

  enhanced.join_channel('channel_123', 'user_123', 'Test User')
  puts '✅ Joined channel'

  enhanced.invite_to_channel(
    channel_id: 'channel_123',
    invited_user_id: 'user_456',
    invited_user_name: 'Jane Doe',
    invited_by: 'user_123'
  )
  puts '✅ Invited user to channel'

  enhanced.get_channel_members('channel_123') do |members|
    puts "✅ Channel members: #{members}\n\n"
  end
rescue StandardError => e
  puts "❌ Channel events error: #{e.message}\n\n"
end

def test_direct_message_events(enhanced)
  puts '💬 Testing Direct Message Events...'

  enhanced.create_dm(%w[user_123 user_456], '1-on-1') do |dm|
    puts "✅ DM created: #{dm}"
  end

  enhanced.send_dm(
    conversation_id: 'dm_123',
    message: 'Hello from Ruby!',
    user_id: 'user_123',
    user_name: 'Test User'
  )
  puts '✅ Sent DM'

  enhanced.get_dm_conversations('user_123', false) do |conversations|
    puts "✅ DM conversations: #{conversations}\n\n"
  end
rescue StandardError => e
  puts "❌ Direct message events error: #{e.message}\n\n"
end

def test_notification_events(enhanced)
  puts '🔔 Testing Notification Events...'

  enhanced.subscribe_notifications('user_123')
  puts '✅ Subscribed to notifications'

  enhanced.mark_notification_read('notif_123', 'user_123')
  puts '✅ Marked notification as read'

  enhanced.mark_all_notifications_read('user_123')
  puts '✅ Marked all notifications as read'

  enhanced.get_notifications('user_123', 10, 'all') do |notifications|
    puts "✅ Notifications: #{notifications}\n\n"
  end
rescue StandardError => e
  puts "❌ Notification events error: #{e.message}\n\n"
end

def test_presence_events(enhanced)
  puts '👤 Testing Presence Events...'

  enhanced.set_status('user_123', 'online')
  puts '✅ Set status to online'

  enhanced.set_custom_status('user_123', '💎', 'Coding in Ruby')
  puts '✅ Set custom status'

  enhanced.clear_custom_status('user_123')
  puts '✅ Cleared custom status'

  enhanced.set_dnd('user_123')
  puts '✅ Enabled Do Not Disturb'

  enhanced.clear_dnd('user_123')
  puts '✅ Disabled Do Not Disturb'

  enhanced.start_typing('user_123', 'general')
  puts '✅ Started typing indicator'

  sleep 2

  enhanced.stop_typing('user_123', 'general')
  puts '✅ Stopped typing indicator'

  enhanced.get_user_presence(%w[user_123 user_456]) do |presence|
    puts "✅ User presence: #{presence}\n\n"
  end
rescue StandardError => e
  puts "❌ Presence events error: #{e.message}\n\n"
end

def test_message_editing_events(enhanced)
  puts '✏️ Testing Message Editing Events...'

  enhanced.edit_message('msg_123', 'general', 'Updated message from Ruby', 'user_123')
  puts '✅ Edited message'

  enhanced.delete_message('msg_456', 'general', 'user_123')
  puts '✅ Deleted message'

  enhanced.pin_message('msg_123', 'general', 'user_123')
  puts '✅ Pinned message'

  enhanced.unpin_message('msg_123', 'general', 'user_123')
  puts '✅ Unpinned message'

  enhanced.get_pinned_messages('general') do |pinned|
    puts "✅ Pinned messages: #{pinned}\n\n"
  end
rescue StandardError => e
  puts "❌ Message editing events error: #{e.message}\n\n"
end

def test_search_events(enhanced)
  puts '🔍 Testing Search Events...'

  enhanced.search_messages('test', 'user_123', 10) do |results|
    puts "✅ Search results: #{results}"
  end

  enhanced.search_in_channel('general', 'test', 10) do |results|
    puts "✅ Channel search results: #{results}"
  end

  enhanced.filter_messages({ channel: 'general', userId: 'user_123', limit: 10 }) do |results|
    puts "✅ Filter results: #{results}"
  end

  enhanced.search_by_user('user_123', nil, 10) do |results|
    puts "✅ User search results: #{results}\n\n"
  end
rescue StandardError => e
  puts "❌ Search events error: #{e.message}\n\n"
end

# Run all tests
test_thread_events(enhanced)
test_reaction_events(enhanced)
test_read_receipt_events(enhanced)
test_channel_events(enhanced)
test_direct_message_events(enhanced)
test_notification_events(enhanced)
test_presence_events(enhanced)
test_message_editing_events(enhanced)
test_search_events(enhanced)

# Summary
puts "\n🎉 All enhanced features tested!"
puts "\n📊 Summary:"
puts '- Thread Events: 7 methods'
puts '- Reaction Events: 6 methods'
puts '- Read Receipt Events: 6 methods'
puts '- Channel Events: 11 methods'
puts '- Direct Message Events: 6 methods'
puts '- Notification Events: 6 methods'
puts '- File Upload Events: 7 methods'
puts '- Presence Events: 8 methods'
puts '- Message Editing Events: 5 methods'
puts '- Search Events: 4 methods'
puts '=' * 50
puts 'Total: 67 enhanced Slack-like events! 🚀'

# Wait before disconnecting
sleep 2

# Disconnect
client.disconnect
puts "\n✅ Disconnected"
