# OddSockets Ruby SDK

Official Ruby SDK for OddSockets real-time messaging platform. Pub/sub, presence, message history.

## Install

```bash
gem install oddsockets
```

## Quick Start

```ruby
require 'oddsockets'

client = OddSockets::Client.new(api_key: 'YOUR_API_KEY', user_id: 'my-agent')
client.connect

channel = client.channel('my-channel')
channel.subscribe { |msg| puts "Received: #{msg}" }
channel.publish(text: 'Hello from Ruby')
```

## Token auth for game clients (`token_provider`)

Game and app clients should never ship a static API key. Instead, mint a
short-lived realtime token from your own backend and hand it to the SDK through a
`token_provider` callable. The client resolves a **fresh** token before every
(re)connect, presents it on the manager/worker handshake in place of an API key,
and silently refreshes it ahead of expiry.

The callable returns a token string, or a hash shaped like the mint response
(`{ 'token' => ..., 'expiresAt' => ..., 'exp' => ... }`) — so your backend can
exchange the player's session for a realtime token however it likes:

```ruby
require 'oddsockets'

client = OddSockets::Client.new(
  user_id: 'player-42',
  token_provider: lambda {
    # Your backend exchanges the player's session for a realtime token.
    resp = MyBackend.mint_realtime_token
    # => { 'token' => 'eyJ...', 'expiresAt' => '2026-01-01T00:00:00Z' }
    resp
  }
)

# Fired after each silent pre-expiry refresh.
client.on(:token_refreshed) { |info| puts "token refreshed, expires #{info[:expiresAt]}" }

client.connect
```

No `api_key` is required when a `token_provider` is set. Tune how early the token
refreshes with `token_refresh_lead_ms:` (default two minutes / `120_000`).

## Enhanced Features

Beyond core pub/sub, OddSockets ships a Slack-like **enhanced surface** — reactions,
typing indicators, threads, read receipts, presence/status, notifications, DMs,
channel management, message editing and search. It lives on `client.enhanced`.
The pattern is always the same:

1. **Send** an action with a `client.enhanced.*` method (snake_case).
2. **Receive** the paired broadcast with `client.on('<event>') { |e| ... }`.

```ruby
require 'oddsockets'

client = OddSockets::Client.new(api_key: 'YOUR_API_KEY', user_id: 'alice')
client.connect

channel = client.channel('room-42')
channel.subscribe(nil, { enable_presence: true }) { |msg| }

# Receive-path: broadcasts from other users on the channel
client.on('user_typing')    { |e| puts "#{e['userId']} is typing" }
client.on('reaction_added') { |e| puts "#{e['userId']} reacted #{e['emoji']}" }
client.on('thread_reply')   { |e| puts 'New reply' }

# Send-path: enhanced actions over the live socket
client.enhanced.start_typing('alice', 'room-42')
client.enhanced.add_reaction(
  message_id: 'msg-1', channel: 'room-42', emoji: ':thumbsup:',
  user_id: 'alice', user_name: 'Alice'
)
client.enhanced.thread_reply(
  channel: 'room-42', parent_message_id: 'msg-1',
  message: 'Replying in the thread', user_id: 'alice', user_name: 'Alice'
)
```

Each area exposes methods on `client.enhanced`; the worker broadcasts the paired
events which you handle with `client.on(...)`. Query methods (`get_*`, `search_*`)
take a block that yields the worker response.

| Area | Requests (`client.enhanced.*`) | Broadcast events (`client.on`) |
|------|--------------------------------|--------------------------------|
| Typing | `start_typing`, `stop_typing` | `user_typing`, `user_stopped_typing` |
| Reactions | `add_reaction`, `remove_reaction`, `get_reactions` | `reaction_added`, `reaction_removed` |
| Threads | `thread_reply`, `get_thread`, `subscribe_thread`, `follow_thread`, `mark_thread_read` | `thread_reply`, `thread_subscribed`, `thread_followed`, `thread_read_updated` |
| Read receipts | `mark_read`, `mark_all_read`, `get_unread_counts` | `user_read`, `unread_count_updated`, `all_marked_read` |
| Messages | `edit_message`, `delete_message`, `pin_message`, `unpin_message`, `get_pinned_messages`, `search_messages` | `message_edited`, `message_deleted`, `message_pinned`, `message_unpinned` |
| Presence & status | `set_status`, `set_custom_status`, `set_dnd`, `get_user_presence` | `user_status_changed`, `custom_status_updated`, `dnd_status_changed` |
| Channels | `create_channel`, `update_channel`, `archive_channel`, `invite_to_channel`, `join_channel`, `leave_channel` | `channel_created`, `channel_updated`, `user_invited`, `user_joined_channel`, `user_left_channel` |
| DMs | `create_dm`, `send_dm`, `get_dm_conversations` | `dm_created`, `dm_received` |
| Notifications | `subscribe_notifications`, `get_notifications`, `mark_notification_read`, `clear_notifications` | `notification`, `notification_read`, `notifications_cleared` |
| Search | `search_messages`, `search_in_channel`, `search_by_user`, `filter_messages` | (block results) |

For any worker event not wrapped above, subscribe with the raw
`client.on('<event>') { |e| ... }` API — all enhanced broadcasts are forwarded onto
the client surface.

## Get an API Key

```bash
curl -X POST https://oddsockets.com/api/agent-signup \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "agentName": "my-agent", "platform": "ruby"}'
curl -X POST https://oddsockets.com/api/agent-signup/verify \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "code": "123456", "agentName": "my-agent"}'
```

## Plans

No free tier — every plan starts with a 7-day free trial.

| | Starter | Pro | Scale | Enterprise |
|---|---|---|---|---|
| **Price** | $29/mo | $99/mo | $299/mo | Contact sales |
| **Messages/mo** | 5M | 25M | 100M | Unlimited |
| **Peak connections** | 200 | 1,000 | 5,000 | Unlimited |
| **MAU** | Unlimited | Unlimited | Unlimited | Unlimited |
| **Extra messages** | $2.50/M | $1.60/M | $1.00/M | Included |

Current pricing: [oddsockets.com/#pricing](https://oddsockets.com/#pricing).

## Get Accredited

<a href="https://tyga.games/accreditation"><img src="https://prodmedia.tyga.host/public/tyga.cloud/landing/tyga.games/tygagames-black-words.svg" alt="tyga.games accreditation" height="44"></a>

Prove you can build and operate real-time features on OddSockets — channels, presence, pub/sub, delivery guarantees and production liveops — on the stack itself. Three tiers (**TCU / TCA / TCP**), certified through **tyga.games** and delivered on ClassaaS.

[**Get accredited on tyga.games →**](https://tyga.games/accreditation)

## Support

- [Documentation](https://docs.oddsockets.com/sdks/ruby)
- [Issue Tracker](https://github.com/jyswee/oddsockets-ruby-sdk/issues)
- [Email Support](mailto:support@oddsockets.com)

## License

MIT License - Copyright (c) 2026 Joe Wee, Tyga.Cloud Ltd. See [LICENSE](LICENSE) for details.
