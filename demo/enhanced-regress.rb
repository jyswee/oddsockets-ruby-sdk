#!/usr/bin/env ruby
# frozen_string_literal: true

# OddSockets Ruby SDK - enhanced-events two-client regression
#
# Proves the RECEIVE path for enhanced (Slack-like) events: an action fired by
# one client (bob) is broadcast by the worker and surfaces on the OTHER
# client's public event handler (alice). Because publisher and subscriber are
# separate connections, an event reaching alice can only have travelled through
# the OddSockets worker - an honest end-to-end test, no local echo.
#
#   bob.enhanced.start_typing(...)  -> alice.on('user_typing')
#   bob.enhanced.add_reaction(...)  -> alice.on('reaction_added')
#
# Run:
#   export ODDSOCKETS_API_KEY="ak_..."
#   bundle install
#   ruby enhanced-regress.rb

require 'oddsockets'
require 'securerandom'

$stdout.sync = true

api_key = ENV['ODDSOCKETS_API_KEY']
if api_key.nil? || api_key.empty?
  warn 'Missing ODDSOCKETS_API_KEY'
  exit 1
end

channel_name = "enh-#{SecureRandom.hex(5)}"
got_typing = false
got_reaction = false

puts '[connect] connecting both clients...'
alice = OddSockets::Client.new(api_key: api_key, user_id: 'alice', auto_connect: false)
bob   = OddSockets::Client.new(api_key: api_key, user_id: 'bob',   auto_connect: false)

alice.on(:worker_assigned) { |d| puts "[alice] worker #{d[:worker_id]}" }
bob.on(:worker_assigned)   { |d| puts "[bob]   worker #{d[:worker_id]}" }
alice.on(:error) { |e| puts "[alice][error] #{e.message}" }
bob.on(:error)   { |e| puts "[bob][error] #{e.message}" }

# Enhanced broadcasts must surface on alice's PUBLIC event handlers.
alice.on('user_typing') do |d|
  if d.is_a?(Hash) && d['userId'] == 'bob'
    got_typing = true
    puts "[alice] received 'user_typing' from bob (channel #{d['channel']}) - broadcast round-trip."
  end
end
alice.on('reaction_added') do |d|
  if d.is_a?(Hash) && d['emoji']
    got_reaction = true
    puts "[alice] received 'reaction_added' (#{d['emoji']}) from #{d['userId']} - broadcast round-trip."
  end
end

alice.connect
bob.connect
sleep(0.5)
abort '[connect] alice failed to connect' unless alice.connected?
abort '[connect] bob failed to connect' unless bob.connected?
puts '[connect] alice = connected, bob = connected'

alice_ch = alice.channel(channel_name)
bob_ch   = bob.channel(channel_name)
alice_ch.subscribe(nil, { enable_presence: true }) { |_m| }.wait
bob_ch.subscribe(nil, { enable_presence: true }) { |_m| }.wait
puts "[both] subscribed to #{channel_name}"

# Let room membership settle, then fire enhanced actions.
sleep(0.5)

puts '[bob] enhanced.start_typing(bob) ...'
bob.enhanced.start_typing('bob', channel_name)

future = bob_ch.publish({ 'text' => 'react to me' })
future.wait
result = future.respond_to?(:value) ? future.value : future
msg_id = result.is_a?(Hash) ? (result['message_id'] || result['messageId']) : result
puts "[bob] published messageId=#{msg_id}, enhanced.add_reaction :thumbsup: ..."
bob.enhanced.add_reaction(
  message_id: msg_id,
  channel: channel_name,
  emoji: ':thumbsup:',
  user_id: 'bob',
  user_name: 'Bob'
)

deadline = Time.now + 20
sleep(0.2) until (got_typing && got_reaction) || Time.now > deadline

alice.disconnect
bob.disconnect

if got_typing && got_reaction
  puts "\nOK - enhanced broadcast receive-path verified (user_typing + reaction_added)"
  exit 0
else
  puts "\nTIMEOUT - enhanced broadcast not received within 20s (typing=#{got_typing} reaction=#{got_reaction})"
  exit 2
end
