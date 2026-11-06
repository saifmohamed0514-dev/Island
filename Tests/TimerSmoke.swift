import Foundation
@main struct TimerSmoke {
 static func main() throws {
  var s = IslandTimerState(); let now = Date(timeIntervalSince1970: 1000)
  precondition(s.remaining == 1500 && s.deadline == nil)
  s.start(at: now); precondition(s.deadline == now.addingTimeInterval(1500))
  _ = s.tick(at: now.addingTimeInterval(90)); precondition(s.remaining == 1410)
  s.pause(at: now.addingTimeInterval(100)); precondition(s.deadline == nil && s.remaining == 1400)
  s = try JSONDecoder().decode(IslandTimerState.self, from: JSONEncoder().encode(s))
  precondition(s.remaining == 1400 && s.deadline == nil)
  s.start(at: now.addingTimeInterval(200)); precondition(s.tick(at: now.addingTimeInterval(1601)))
  precondition(s.finished && !s.tick(at: now.addingTimeInterval(1700)))
  s.start(at: now); precondition(!s.finished && s.remaining == 1500)
  s.reset(seconds: .nan); precondition(s.remaining == 1500)
  s.reset(seconds: -1); precondition(s.duration == 60)
  s.reset(seconds: 1e10); precondition(s.duration == 86400)
  s.reset(seconds: 300); s.start(at: now)
  s = try JSONDecoder().decode(IslandTimerState.self, from: JSONEncoder().encode(s))
  precondition(s.tick(at: now.addingTimeInterval(86400)) && s.remaining == 0)
  print("PASS: 12 timer state, persistence, boundary and completion checks")
 }
}
