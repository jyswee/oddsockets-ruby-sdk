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
