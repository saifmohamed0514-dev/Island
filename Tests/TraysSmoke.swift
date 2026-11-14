import Foundation
@main struct TraysSmoke {
 @MainActor static func main() throws {
  var count=0
  func check(_ condition:Bool) { precondition(condition,"Tray check \(count+1)");count+=1 }
  var p=IslandActivityTrayPreferences()
  check(p.enabled == [.timer,.music,.agent])
  check(p.arrange([.music,.timer,.wellbeing]) == [.timer,.music])
  p.set(.timer,enabled:false);check(p.arrange([.timer,.music]) == [.music])
  p.set(.wellbeing,enabled:true);check(p.arrange([.timer,.wellbeing]) == [.wellbeing])
  p.move(.wellbeing,by:-2);check(p.arrange([.music,.wellbeing]) == [.wellbeing,.music])
  p.set(.wellbeing,enabled:true);check(p.enabled.filter { $0 == .wellbeing }.count==1)
  for v in IslandActivityTray.allCases { p.set(v,enabled:false) };check(p.arrange([.timer,.music,.wellbeing]).isEmpty)
  p.order=[.wellbeing,.wellbeing];p.normalize();check(p.order.count==7 && Set(p.order).count==7)
  p.move(.wellbeing,by:-100);check(p.order.first == .wellbeing);p.move(.wellbeing,by:100);check(p.order.last == .wellbeing)
  let suite="IslandTraysTests-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  defer { defaults.removePersistentDomain(forName:suite) }
  defaults.set(true,forKey:"island.live.calendar");defaults.set(true,forKey:"island.live.devices")
  let s=IslandActivityTrayStore(defaults:defaults);check(s.preferences.enabled.contains(.event) && s.preferences.enabled.contains(.device) && !s.preferences.enabled.contains(.notice))
  let original=s.preferences;s.set(.timer,enabled:false);s.set(.wellbeing,enabled:true);s.move(.wellbeing,by:-2)
  check(IslandActivityTrayStore(defaults:defaults).preferences == s.preferences)
  s.restore(original);check(IslandActivityTrayStore(defaults:defaults).preferences == original)
  defaults.set(Data("broken".utf8),forKey:"island.trays.activities");check(IslandActivityTrayStore(defaults:defaults).preferences == original)
  check(try JSONDecoder().decode(IslandActivityTrayPreferences.self,from:JSONEncoder().encode(p)) == p)
  var placed=IslandActivityTrayPreferences()
  check(placed.place(.timer,at:1) && placed.order.prefix(2) == [.music,.timer])
  check(placed.place(.wellbeing,at:0) && placed.order.first == .wellbeing && placed.enabled.first == .wellbeing)
  let beforeInvalid=placed;check(!placed.place(.agent,at:-1) && !placed.place(.agent,at:7) && placed == beforeInvalid)
  check(placed.place(.wellbeing,at:6) && placed.order.last == .wellbeing && Set(placed.order).count==7)
  s.restore(original);s.place(.notice,at:0);check(s.preferences.enabled.first == .notice)
  check(IslandActivityTrayStore(defaults:defaults).preferences == s.preferences)
  s.restore(original);check(s.preferences == original)
  let transfer=IslandActivityTrayTransfer(tray:.wellbeing)
  check(try JSONDecoder().decode(IslandActivityTrayTransfer.self,from:JSONEncoder().encode(transfer)).tray == .wellbeing)
  check((try? JSONDecoder().decode(IslandActivityTrayTransfer.self,from:Data("{\"tray\":\"unknown\"}".utf8))) == nil)
  print("PASS: \(count) production activity-tray checks; hiding timer, adding/reordering Wellbeing, empty trays, normalization, migration, private persistence, typed compact drops and Undo")
 }
}
