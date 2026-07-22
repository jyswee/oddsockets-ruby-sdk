#!/usr/bin/env ruby
# frozen_string_literal: true

# OddSockets Ruby SDK - two-client round-trip demo
#
# Proves a real real-time round-trip using TWO independent clients:
#   connect -> subscribe (alice) -> publish (bob) -> receive (alice)
#
# Because the subscriber (alice) and the publisher (bob) are separate
# connections, a message that reaches alice can only have travelled through
# the OddSockets worker - so this doubles as an honest end-to-end regression
# test (no mocks, no local echo). The SDK speaks genuine Socket.IO
# (Engine.IO v4) over a WebSocket to the assigned worker.
#
# Run:
#   export ODDSOCKETS_API_KEY="ak_..."   # get a free key: see README
#   bundle install
#   ruby demo.rb

require 'oddsockets'
require 'securerandom'

$stdout.sync = true

api_key = ENV['ODDSOCKETS_API_KEY']
if api_key.nil? || api_key.empty?
  warn 'Missing ODDSOCKETS_API_KEY. Get a free key (see README), then:'
  warn '  export ODDSOCKETS_API_KEY="ak_..."'
  exit 1
end

nonce = SecureRandom.hex(6)
channel_name = "demo-#{rand(1_000_000)}"
received = false

puts '[connect] connecting both clients...'
alice = OddSockets::Client.new(api_key: api_key, user_id: 'alice', auto_connect: false)
bob   = OddSockets::Client.new(api_key: api_key, user_id: 'bob',   auto_connect: false)

alice.on(:worker_assigned) { |d| puts "[alice] worker #{d[:worker_id]}" }
bob.on(:worker_assigned)   { |d| puts "[bob]   worker #{d[:worker_id]}" }
alice.on(:error) { |e| puts "[alice][error] #{e.message}" }
bob.on(:error)   { |e| puts "[bob][error] #{e.message}" }

alice.connect
bob.connect
sleep(0.5)
abort '[connect] alice failed to connect' unless alice.connected?
abort '[connect] bob failed to connect' unless bob.connected?
puts '[connect] alice = connected, bob = connected'

# Subscriber (alice) - presence enabled
inbox = alice.channel(channel_name)
inbox.subscribe(nil, { enable_presence: true }) do |message|
  body = message['message']
  if body.is_a?(Hash) && (body['nonce'] == nonce || body[:nonce] == nonce)
    received = true
    puts "[alice] received bob's message (nonce matched) - real round-trip."
  end
end.wait
puts "[alice] subscribed to #{channel_name} (presence on)"

# Publisher (bob) - a DIFFERENT connection
outbox = bob.channel(channel_name)
future = outbox.publish({ 'text' => 'hello from bob', 'nonce' => nonce })
future.wait
result = future.respond_to?(:value) ? future.value : future
message_id = result.is_a?(Hash) ? (result['message_id'] || result['messageId']) : result
puts "[bob] published, messageId = #{message_id}"

deadline = Time.now + 15
sleep(0.2) until received || Time.now > deadline

if received
  presence = inbox.presence
  presence.wait
  info = presence.respond_to?(:value) ? presence.value : presence
  count = info.is_a?(Hash) ? (info['count'] || info['occupancy']) : nil
  puts "[alice] presence: #{count} user(s)." if count
  inbox.unsubscribe.wait
  puts '[alice] unsubscribed.'
end

alice.disconnect
bob.disconnect

if received
  puts "\nOK - cross-client round-trip verified"
  exit 0
else
  puts "\nTIMEOUT - no cross-client delivery within 15s"
  exit 2
end
