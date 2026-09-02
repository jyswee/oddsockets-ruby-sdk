#!/usr/bin/env ruby
# frozen_string_literal: true

# OddSockets Ruby SDK - CHALLENGE two-client honest regression (worker v1.2)
#
# Two clients (alice + bob), DISTINCT userId, SAME apiKey (shared owner scope),
# both subscribed to 'lobby'. Exercises all 10 challenge/leaderboard/achievement
# methods and asserts CROSS-CLIENT delivery (an event reaching the other client
# can only have travelled through the OddSockets worker).

require 'oddsockets'
require 'securerandom'

$stdout.sync = true

api_key     = ENV['OS_KEY'] || ENV['ODDSOCKETS_API_KEY']
manager_url = ENV['ODDSOCKETS_MANAGER_URL']
if api_key.nil? || api_key.empty?
  warn 'Missing OS_KEY'
  exit 1
end

CHAN = 'lobby'
CHALLENGE_ID   = "chal-#{SecureRandom.hex(4)}"
ACHIEVEMENT_ID = "ach-#{SecureRandom.hex(4)}"

# ---- assertion bookkeeping -------------------------------------------------
$results = []
def check(name, cond, detail = '')
  $results << [name, !!cond, detail]
  puts "  [#{cond ? 'PASS' : 'FAIL'}] #{name}#{detail.empty? ? '' : " -- #{detail}"}"
end

# captured cross-client events
captured = {
  alice_progress: nil, alice_rank_change: nil,
  bob_ach_progress: nil, bob_ach_unlock: nil,
  bob_invited: nil, alice_invited: false,
  alice_reply_received: nil, bob_invite_cancelled: nil
}

def fld(h, *keys)
  return nil unless h.is_a?(Hash)
  keys.each { |k| return h[k] if h.key?(k) }
  # Room-broadcast envelopes nest the payload under "data"
  # (e.g. {type:, identity:, data:{value:, status:, percentComplete:}}).
  inner = h['data']
  if inner.is_a?(Hash)
    keys.each { |k| return inner[k] if inner.key?(k) }
  end
  nil
end

puts "[connect] challengeId=#{CHALLENGE_ID} achievementId=#{ACHIEVEMENT_ID}"
alice = OddSockets::Client.new(api_key: api_key, manager_url: manager_url, user_id: 'alice', auto_connect: false)
bob   = OddSockets::Client.new(api_key: api_key, manager_url: manager_url, user_id: 'bob',   auto_connect: false)

alice.on(:worker_assigned) { |d| puts "[alice] worker #{d[:worker_id]}" }
bob.on(:worker_assigned)   { |d| puts "[bob]   worker #{d[:worker_id]}" }
alice.on(:error) { |e| puts "[alice][error] #{e.respond_to?(:message) ? e.message : e.inspect}" }
bob.on(:error)   { |e| puts "[bob][error] #{e.respond_to?(:message) ? e.message : e.inspect}" }

# ---- cross-client broadcast handlers --------------------------------------
# alice watches for bob's progress echoes to the room
alice.on('challenge_progress') do |d|
  captured[:alice_progress] = d
  puts "[alice] <- challenge_progress value=#{fld(d,'value')} by=#{fld(d,'identity','userId')}"
end
alice.on('leaderboard_rank_change') do |d|
  captured[:alice_rank_change] = d
  puts "[alice] <- leaderboard_rank_change #{d.inspect[0,160]}"
end

# bob watches for alice's achievement broadcasts
bob.on('achievement_progress') do |d|
  captured[:bob_ach_progress] = d
  puts "[bob]   <- achievement_progress pct=#{fld(d,'percentComplete')} status=#{fld(d,'status')}"
end
bob.on('achievement_unlock') do |d|
  captured[:bob_ach_unlock] = d
  puts "[bob]   <- achievement_unlock pct=#{fld(d,'percentComplete')} status=#{fld(d,'status')}"
end

# invite delivery: invitee=bob gets challenge_invited; inviter should NOT
bob.on('challenge_invited') do |d|
  captured[:bob_invited] = d
  puts "[bob]   <- challenge_invited from=#{fld(d,'fromUserId','from')} payload=#{fld(d,'payload').inspect}"
end
alice.on('challenge_invited') do |d|
  captured[:alice_invited] = true
  puts "[alice] <- challenge_invited (UNEXPECTED on inviter) #{d.inspect[0,120]}"
end
alice.on('challenge_reply_received') do |d|
  captured[:alice_reply_received] = d
  puts "[alice] <- challenge_reply_received accept=#{fld(d,'accept')} #{d.inspect[0,120]}"
end
bob.on('challenge_invite_cancelled') do |d|
  captured[:bob_invite_cancelled] = d
  puts "[bob]   <- challenge_invite_cancelled #{d.inspect[0,120]}"
end

alice.connect
bob.connect
sleep(0.6)
abort '[connect] alice failed to connect' unless alice.connected?
abort '[connect] bob failed to connect' unless bob.connected?
puts '[connect] alice = connected, bob = connected'

alice_ch = alice.channel(CHAN)
bob_ch   = bob.channel(CHAN)
alice_ch.subscribe(nil, { enable_presence: true }) { |_m| }.wait
bob_ch.subscribe(nil, { enable_presence: true }) { |_m| }.wait
puts "[both] subscribed to #{CHAN}"
sleep(0.6)

# ---- small ack helper (blocks on a one-shot) -------------------------------
def await_ack(timeout = 12)
  box = Concurrent::AtomicReference.new(nil)
  yield ->(data) { box.set(data || {}) }
  deadline = Time.now + timeout
  sleep(0.05) until box.get || Time.now > deadline
  box.get
end

def wait_until(timeout = 12)
  deadline = Time.now + timeout
  sleep(0.05) until (yield) || Time.now > deadline
  yield
end

# ========================= 1. create_challenge =============================
puts "\n[1] alice.create_challenge"
ack = await_ack do |cb|
  alice.enhanced.create_challenge(
    { challengeId: CHALLENGE_ID, metric: 'score', ranked: true, channel: CHAN }, &cb
  )
end
check('1 create_challenge acked', ack && !fld(ack, 'error') && fld(ack, 'challengeId') == CHALLENGE_ID,
      "ack=#{ack.inspect[0,140]}")

# ========================= 2. report_progress =============================
# alice=40, bob=55 => alice (the OTHER client) should see bob's echo to room.
puts "\n[2] report_progress alice=40 bob=55"
alice.enhanced.report_progress({ challengeId: CHALLENGE_ID, metric: 'score', value: 40, eventId: SecureRandom.uuid })
sleep(0.3)
# reset alice's capture so we specifically catch BOB's echo
captured[:alice_progress] = nil
captured[:alice_rank_change] = nil
bob.enhanced.report_progress({ challengeId: CHALLENGE_ID, metric: 'score', value: 55, eventId: SecureRandom.uuid })
wait_until(12) { captured[:alice_progress] && captured[:alice_rank_change] }
check('2 alice sees challenge_progress (bob echo)', captured[:alice_progress],
      "value=#{fld(captured[:alice_progress],'value')}")
check('2 alice sees leaderboard_rank_change', captured[:alice_rank_change])

# ========================= 3. get_standings ===============================
puts "\n[3] alice.get_standings"
sleep(0.4)
st = await_ack do |cb|
  alice.enhanced.get_standings({ challengeId: CHALLENGE_ID, limit: 20 }, &cb)
end
standings = fld(st, 'standings') || []
by_rank = standings.each_with_object({}) { |s, h| h[fld(s, 'rank')] = s }
r1 = by_rank[1]; r2 = by_rank[2]
your_rank = fld(st, 'yourRank')
check('3 standings rank1 = bob@55', r1 && fld(r1, 'value').to_i == 55,
      "rank1=#{r1.inspect[0,100]}")
check('3 standings rank2 = alice@40', r2 && fld(r2, 'value').to_i == 40,
      "rank2=#{r2.inspect[0,100]}")
check('3 yourRank (alice) = 2', your_rank.to_i == 2, "yourRank=#{your_rank.inspect}")

# ========================= 4. complete_challenge ==========================
puts "\n[4] complete_challenge alice(tied) bob(conceded)"
a_comp = await_ack do |cb|
  alice.enhanced.complete_challenge({ challengeId: CHALLENGE_ID, outcome: 'tied', eventId: SecureRandom.uuid }, &cb)
end
check('4 alice complete tied finalValue40 rank2',
      a_comp && fld(a_comp, 'outcome') == 'tied' && fld(a_comp, 'finalValue').to_i == 40 && fld(a_comp, 'rank').to_i == 2,
      "ack=#{a_comp.inspect[0,140]}")
b_comp = await_ack do |cb|
  bob.enhanced.complete_challenge({ challengeId: CHALLENGE_ID, outcome: 'conceded', eventId: SecureRandom.uuid }, &cb)
end
check('4 bob complete conceded finalValue55 rank1',
      b_comp && fld(b_comp, 'outcome') == 'conceded' && fld(b_comp, 'finalValue').to_i == 55 && fld(b_comp, 'rank').to_i == 1,
      "ack=#{b_comp.inspect[0,140]}")

# ========================= 5. unlock_achievement (progress) ================
puts "\n[5] alice.unlock_achievement 50% -> bob sees achievement_progress (no banner)"
captured[:bob_ach_progress] = nil
captured[:bob_ach_unlock] = nil
alice.enhanced.unlock_achievement(
  { achievementId: ACHIEVEMENT_ID, name: 'First Blood', percentComplete: 50, channel: CHAN }
)
wait_until(12) { captured[:bob_ach_progress] }
prog = captured[:bob_ach_progress]
check('5 bob sees achievement_progress in_progress', prog && fld(prog, 'status') == 'in_progress',
      "status=#{fld(prog,'status')} pct=#{fld(prog,'percentComplete')}")
check('5 no unlock banner at 50%', captured[:bob_ach_unlock].nil?)

# ========================= 6. unlock_achievement (unlock) ==================
puts "\n[6] alice.unlock_achievement 100% -> bob sees achievement_unlock (banner)"
captured[:bob_ach_unlock] = nil
alice.enhanced.unlock_achievement(
  { achievementId: ACHIEVEMENT_ID, name: 'First Blood', percentComplete: 100, channel: CHAN }
)
wait_until(12) { captured[:bob_ach_unlock] }
unl = captured[:bob_ach_unlock]
check('6 bob sees achievement_unlock unlocked', unl && fld(unl, 'status') == 'unlocked',
      "status=#{fld(unl,'status')} pct=#{fld(unl,'percentComplete')}")

# ========================= 7. get_achievements ============================
puts "\n[7] alice.get_achievements reflects 100/unlocked"
sleep(0.4)
gach = await_ack do |cb|
  alice.enhanced.get_achievements({ achievementId: ACHIEVEMENT_ID }, &cb)
end
achs = fld(gach, 'achievements') || []
mine = achs.find { |a| fld(a, 'achievementId') == ACHIEVEMENT_ID } || achs.first
check('7 get_achievements 100/unlocked',
      mine && fld(mine, 'percentComplete').to_i == 100 && fld(mine, 'status') == 'unlocked',
      "ach=#{mine.inspect[0,140]}")

# ========================= 8. send_challenge_invite =======================
puts "\n[8] alice.send_challenge_invite -> bob"
captured[:bob_invited] = nil
captured[:alice_invited] = false
inv_ack = await_ack do |cb|
  alice.enhanced.send_challenge_invite(
    { toUserId: 'bob', type: 'match', payload: { arena: 'dust2', wager: 100 }, ttl: 300 }, &cb
  )
end
invite_id = fld(inv_ack, 'inviteId')
check('8 invite acked pending', inv_ack && invite_id && fld(inv_ack, 'status') == 'pending' && fld(inv_ack, 'toUserId') == 'bob',
      "ack=#{inv_ack.inspect[0,160]}")
wait_until(12) { captured[:bob_invited] }
binv = captured[:bob_invited]
check('8 bob sees challenge_invited w/ payload', binv && fld(fld(binv, 'payload'), 'arena') == 'dust2',
      "invited=#{binv.inspect[0,160]}")
check('8 alice (inviter) did NOT get own invite', captured[:alice_invited] == false)

# ========================= 9. get_challenge_invites (bob) =================
puts "\n[9] bob.get_challenge_invites lists it"
sleep(0.4)
listed = await_ack do |cb|
  bob.enhanced.get_challenge_invites(&cb)
end
invites = fld(listed, 'invites') || []
found = invites.find { |i| fld(i, 'inviteId') == invite_id }
check('9 bob invites list contains it', !found.nil?, "count=#{invites.length} ids=#{invites.map { |i| fld(i,'inviteId') }.inspect[0,120]}")

# ========================= 10. reply_challenge_invite =====================
puts "\n[10] bob.reply_challenge_invite(accept) -> alice sees challenge_reply_received"
captured[:alice_reply_received] = nil
reply_ack = await_ack do |cb|
  bob.enhanced.reply_challenge_invite({ inviteId: invite_id, accept: true }, &cb)
end
check('10 reply acked', reply_ack && !fld(reply_ack, 'error'), "ack=#{reply_ack.inspect[0,140]}")
wait_until(12) { captured[:alice_reply_received] }
check('10 alice sees challenge_reply_received', captured[:alice_reply_received],
      "recv=#{captured[:alice_reply_received].inspect[0,140]}")

# ========================= 11. cancel_challenge_invite ====================
puts "\n[11] fresh invite + cancel -> bob sees challenge_invite_cancelled"
captured[:bob_invited] = nil
fresh_ack = await_ack do |cb|
  alice.enhanced.send_challenge_invite(
    { toUserId: 'bob', type: 'match', payload: { arena: 'mirage' }, ttl: 300 }, &cb
  )
end
fresh_id = fld(fresh_ack, 'inviteId')
wait_until(8) { captured[:bob_invited] }  # ensure delivered before cancel
captured[:bob_invite_cancelled] = nil
cancel_ack = await_ack do |cb|
  alice.enhanced.cancel_challenge_invite({ inviteId: fresh_id }, &cb)
end
check('11 cancel acked', cancel_ack && !fld(cancel_ack, 'error'), "ack=#{cancel_ack.inspect[0,140]}")
wait_until(12) { captured[:bob_invite_cancelled] }
check('11 bob sees challenge_invite_cancelled', captured[:bob_invite_cancelled],
      "cancel=#{captured[:bob_invite_cancelled].inspect[0,140]}")

# ---- teardown + summary ----------------------------------------------------
alice.disconnect
bob.disconnect

passed = $results.count { |_, ok, _| ok }
total  = $results.length
puts "\n==================== SUMMARY ===================="
$results.each { |name, ok, _| puts "  #{ok ? 'PASS' : 'FAIL'}  #{name}" }
puts "  #{passed}/#{total} assertions passed"
puts "================================================"
exit(passed == total ? 0 : 2)
