# Agent Integration Guide — Ruby
POST https://oddsockets.com/api/agent-signup then /verify with 6-digit code.
```ruby
client = OddSockets::Client.new(api_key: 'ak_...')
client.connect
ch = client.channel('agent-coordination')
ch.subscribe { |msg| puts msg }
ch.publish(task: 'summarize')
```
Free: 100 MAU | 50 connections | 10K msg/day | 10 channels | 100MB/24h
