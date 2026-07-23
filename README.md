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

## Get a Free API Key

```bash
curl -X POST https://oddsockets.com/api/agent-signup \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "agentName": "my-agent", "platform": "ruby"}'
curl -X POST https://oddsockets.com/api/agent-signup/verify \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "code": "123456", "agentName": "my-agent"}'
```

## Plans

| | Free | Starter | Pro |
|---|---|---|---|
| **Price** | $0/mo | $49.99/mo | $299/mo |
| **MAU** | 100 | 1,000 | 50,000 |
| **Concurrent connections** | 50 | 1,000 | Unlimited |
| **Messages/day** | 10,000 | 4,320,000 | Unlimited |
| **Channels** | 10 | Unlimited | Unlimited |
| **Storage** | 100MB (24h) | 50GB (6 months) | Unlimited |

## Support

- [Documentation](https://docs.oddsockets.com/sdks/ruby)
- [Issue Tracker](https://github.com/jyswee/oddsockets-ruby-sdk/issues)
- [Email Support](mailto:support@oddsockets.com)

## License

MIT License - Copyright (c) 2026 Joe Wee, Tyga.Cloud Ltd. See [LICENSE](LICENSE) for details.
