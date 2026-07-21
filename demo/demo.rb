#!/usr/bin/env ruby
# frozen_string_literal: true

# OddSockets Ruby SDK - runnable demo
#
# A full pub/sub round-trip: connect -> subscribe -> publish -> receive.
# Uses the same SDK a consumer installs. No mocks.
#
# Run:
#   export ODDSOCKETS_API_KEY="ak_..."   # get a free key: see README
#   bundle install
#   ruby demo.rb

require 'oddsockets'
require 'securerandom'

api_key = ENV['ODDSOCKETS_API_KEY']
if api_key.nil? || api_key.empty?
  warn 'Missing ODDSOCKETS_API_KEY. Get a free key (see README), then:'
  warn '  export ODDSOCKETS_API_KEY="ak_..."'
  exit 1
end

user_id = ENV.fetch('ODDSOCKETS_USER_ID', 'demo-agent')
nonce = SecureRandom.hex(5)
channel_name = "demo-#{nonce}"
received = false

client = OddSockets::Client.new(api_key: api_key, user_id: user_id, auto_connect: false)
client.on(:worker_assigned) { |d| puts "[worker] assigned #{d[:worker_id]}" }
client.on(:error) { |e| puts "[error] #{e.message}" }

puts '[connect] connecting to OddSockets...'
client.connect
sleep(2)
abort '[connect] failed to connect' unless client.connected?
puts '[connect] connected'

channel = client.channel(channel_name)
channel.subscribe do |message|
  body = message['message']
  puts "[recv] #{body.inspect}"
  if body.is_a?(Hash) && (body['nonce'] == nonce || body[:nonce] == nonce)
    received = true
  end
end.wait
puts "[sub] subscribed to #{channel_name}"

future = channel.publish({ 'text' => 'hello from the Ruby demo', 'nonce' => nonce })
future.wait
result = future.respond_to?(:value) ? future.value : future
message_id = result.is_a?(Hash) ? (result['messageId'] || result[:messageId]) : result
puts "[pub] published, messageId=#{message_id}"

deadline = Time.now + 15
sleep(0.2) until received || Time.now > deadline

client.disconnect
if received
  puts "\nOK - round-trip verified: published message received back on #{channel_name}"
  exit 0
else
  puts "\nTIMEOUT - no echo received within 15s"
  exit 2
end
