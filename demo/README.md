# OddSockets Ruby SDK - Demo

A tiny, runnable program that proves a real real-time round-trip against OddSockets
using **two independent clients**: **connect -> subscribe -> publish -> receive**.

Because the subscriber (`alice`) and the publisher (`bob`) are separate connections,
a message that reaches the subscriber can only have travelled through the OddSockets
worker - so this doubles as an honest end-to-end regression test (no mocks, no local
echo). The SDK speaks genuine Socket.IO (Engine.IO v4) over a WebSocket to the
assigned worker, exactly like the JavaScript and Python SDKs.

## Proof it's real

`demo/PROOF.txt` is a captured transcript of this demo running in Docker against the
live platform. Reproduce it yourself in one command (see below) - here is a real run:

```
[connect] connecting both clients...
[alice] worker w002-oddsockets-1
[bob]   worker w002-oddsockets-1
[connect] alice = connected, bob = connected
[alice] subscribed to demo-870754 (presence on)
[alice] received bob's message (nonce matched) - real round-trip.
[bob] published, messageId = d35c1e2e-dae5-47ed-8bf8-e0d91c6bd98c
[alice] presence: 1 user(s).
[alice] unsubscribed.

OK - cross-client round-trip verified
```

## 1. Get a free API key

Two-step email verification (no card required):

```bash
# Step 1 - request a code
curl -X POST https://oddsockets.com/api/agent-signup \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","agentName":"demo","platform":"ruby"}'

# Step 2 - verify and receive your apiKey
curl -X POST https://oddsockets.com/api/agent-signup/verify \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","code":"123456","agentName":"demo"}'
```

The verify response contains your `apiKey` (starts with `ak_`).

## 2. Run it in Docker (recommended)

No local Ruby toolchain needed. Build from the repo root so the SDK source is in
context (the demo uses a Bundler path dependency - `gem 'oddsockets', path: '..'` - to
compile the SDK straight from the parent, without publishing anything):

```bash
docker build -f demo/Dockerfile -t oddsockets-ruby-demo .
docker run --rm -e ODDSOCKETS_API_KEY="ak_your_key_here" oddsockets-ruby-demo
```

Dependencies are installed at image-build time, so a broken SDK fails the build. A
successful run prints `OK - cross-client round-trip verified` and exits `0`.

## 2b. Run it locally with Bundler

Requires Ruby 3.x (the gem targets `>= 3.0`). The path dependency resolves the SDK
from the parent directory, so the demo is clone-and-run:

```bash
cd demo
bundle install
export ODDSOCKETS_API_KEY="ak_your_key_here"
bundle exec ruby demo.rb
```

The key is read from `ODDSOCKETS_API_KEY` and never hardcoded; if it is missing the
program prints the signup instructions above and exits non-zero.

## The code, step by step

Create two clients - a subscriber and a publisher - each on its own connection:

```ruby
alice = OddSockets::Client.new(api_key: api_key, user_id: 'alice', auto_connect: false)
bob   = OddSockets::Client.new(api_key: api_key, user_id: 'bob',   auto_connect: false)

alice.connect
bob.connect
```

Subscribe on the subscriber (presence enabled):

```ruby
inbox = alice.channel('my-channel')

inbox.subscribe(nil, { enable_presence: true }) do |message|
  puts message['message'].inspect
end.wait
```

Publish from the *other* client - this is what makes the test honest:

```ruby
outbox = bob.channel('my-channel')
future = outbox.publish({ 'text' => 'hello from bob', 'nonce' => nonce })
future.wait
puts "messageId = #{future.value['message_id']}"
```

Inspect presence, then tear down cleanly:

```ruby
presence = inbox.presence
presence.wait
puts "count: #{presence.value['count']}"
inbox.unsubscribe.wait

alice.disconnect
bob.disconnect
```

## What it demonstrates

- Manager discovery + automatic worker assignment (fully transparent)
- `client.channel(name)` -> `channel.subscribe { }` -> `channel.publish(msg)`
- **Cross-client delivery**: a message published by `bob` is delivered to `alice`'s
  subscription in real time - provably through the worker, not a local echo
- Presence tracking, unsubscribe, and graceful disconnect
- A 15-second timeout so a stalled round-trip is reported as a failure (non-zero exit)

## Files

- `Dockerfile` - builds the SDK from source and runs the two-client demo on `ruby:3.3-slim`.
- `PROOF.txt` - captured transcript of a real containerised run against the platform.
- `demo.rb` - the two-client round-trip program.
- `Gemfile` - resolves the SDK via a Bundler path dependency (`path: '..'`).
