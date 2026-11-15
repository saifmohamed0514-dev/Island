import Foundation
@main struct PortableSmoke {
 static func main() throws {
  var count=0
  func check(_ ok:Bool) { precondition(ok,"Portable settings check \(count+1)");count+=1 }
  var value=IslandPortableSettings(layout:.init(modules:.init(),canvas:.init()))
  value.flags=["island.gesture.skip":true,"island.media.liveWaveform":true,"island.usage.enabled":true,"hudReplacement":true,"island.setup.completed":true]
  value.numbers=["island.hud.duration":400,"minimumHoverDuration":-1,"island.notes":42]
  value.choices=["island.hud.motion":"instant","island.connection.token":"secret"]
  try value.normalize();check(value.flags==["island.gesture.skip":true]);check(value.numbers==["island.hud.duration":8,"minimumHoverDuration":0.05]);check(value.choices==["island.hud.motion":"instant"])
  check(try IslandPortableSettings.decode(value.encoded())==value)
  var future=value;future.format=2;do { _=try IslandPortableSettings.decode(future.encoded());check(false) } catch { check(true) }
  do { _=try IslandPortableSettings.decode(Data(repeating:32,count:262145));check(false) } catch { check(true) }
  do { _=try IslandPortableSettings.decode(Data("{}".utf8));check(false) } catch { check(true) }
  let old=#"{"modules":{"order":["home","focus"],"enabled":["home"],"start":"home"},"canvas":{"enabled":false,"slots":["home",null,null,null]}}"#
  let oldSnapshot=try JSONDecoder().decode(IslandDesignerSnapshot.self,from:Data(old.utf8));check(oldSnapshot.duoActivities==nil && oldSnapshot.idleActivity==nil && oldSnapshot.hidePausedMusic==nil)
  var snapshot=oldSnapshot;snapshot.duoActivities=true;snapshot.idleActivity="wellbeing";snapshot.hidePausedMusic=true;check(try JSONDecoder().decode(IslandDesignerSnapshot.self,from:JSONEncoder().encode(snapshot))==snapshot)
  snapshot.idleActivity="unknown";snapshot.normalize();check(snapshot.idleActivity=="none")
  check(IslandVisibilityRules.hidden(bundle:"example.game",category:"public.app-category.games",hideGames:true,excluded:""))
  check(IslandVisibilityRules.hidden(bundle:"example.game",category:"public.app-category.action-games",hideGames:true,excluded:""))
  check(!IslandVisibilityRules.hidden(bundle:"com.valvesoftware.steam",category:"public.app-category.utilities",hideGames:true,excluded:""))
  check(!IslandVisibilityRules.hidden(bundle:nil,category:"public.app-category.games",hideGames:true,excluded:""))
  check(IslandVisibilityRules.hidden(bundle:"game",category:nil,hideGames:false,excluded:" player, game "))
  check(!IslandVisibilityRules.hidden(bundle:"org.islandapp.Island",category:nil,hideGames:false,excluded:"org.islandapp.Island"))
  check(IslandWaveformRules.amplitude(0,count:100)==0 && IslandWaveformRules.amplitude(1,count:16)==1)
  check(IslandWaveformRules.amplitude(.nan,count:16)==0 && IslandWaveformRules.amplitude(2,count:0)==0)
  check(IslandWaveformRules.smooth([0,1,0.5,.nan],incoming:[1,0,.infinity]).allSatisfy { $0.isFinite && (0...1).contains($0) })
  check(IslandWaveformRules.smooth([],incoming:[]).count==4)
  check(IslandSystemSoundRules.tone("missing")=="None")
  check(!IslandSystemSoundRules.shouldPlay(tone:"Ping",focused:true,quietFocus:true,locked:false,event:.charging))
  check(IslandSystemSoundRules.shouldPlay(tone:"Ping",focused:nil,quietFocus:true,locked:false,event:.charging))
  check(!IslandSystemSoundRules.shouldPlay(tone:"Ping",focused:false,quietFocus:false,locked:true,event:.charging))
  check(IslandSystemSoundRules.shouldPlay(tone:"Ping",focused:false,quietFocus:false,locked:true,event:.lock))
  let request=IslandBetterDisplayRules.parameters(display:42,feature:"brightness",value:nil)!
  let raw=try JSONSerialization.jsonObject(with:JSONEncoder().encode(IslandBetterDisplayRequest(uuid:"fixture",commands:["get"],parameters:request))) as! [String:Any]
  check((raw["parameters"] as? [String:Any])?["brightness"] is NSNull)
  check(IslandBetterDisplayRules.parameters(display:42,feature:"volume",value:0.5)!["volume"]=="0.5")
  check(IslandBetterDisplayRules.parameters(display:0,feature:"brightness",value:0.5)==nil)
  check(IslandBetterDisplayRules.parameters(display:42,feature:"hardwareFactoryReset",value:0)==nil)
  check(IslandBetterDisplayRules.parameters(display:42,feature:"brightness",value:.infinity)==nil)
  check(IslandBetterDisplayRules.level("0.75\n")==0.75 && IslandBetterDisplayRules.level("error")==nil && IslandBetterDisplayRules.level("1.1")==nil)
  let feedback=try JSONDecoder().decode(IslandBetterDisplayOSD.self,from:Data(#"{"displayID":42,"controlTarget":"hardwareBrightness","value":120,"maxValue":200}"#.utf8))
  check(feedback.fraction==0.6 && feedback.type=="brightness")
  let invalid=try JSONDecoder().decode(IslandBetterDisplayOSD.self,from:Data(#"{"systemIconID":3,"value":1,"maxValue":0}"#.utf8));check(invalid.fraction==nil && invalid.type=="volume")
  let dictionary=Data(#"<dictionary><suite><class name="track"><property name="liked" type="boolean"/><property name="explicit" type="boolean" access="r"/></class><class name="application"><property name="playback speed" type="real"/></class></suite></dictionary>"#.utf8)
  let capabilities=IslandPlayerCapabilities.parse(dictionary);check(capabilities.favoriteProperty=="liked" && capabilities.explicitProperty=="explicit" && capabilities.speedProperty=="playback speed")
  check(IslandPlayerCapabilities.parse(Data("invalid".utf8)) == .init())
  check(IslandTrackLink.safe("spotify:episode:abc123")?.absoluteString=="https://open.spotify.com/episode/abc123")
  check(IslandTrackLink.safe("javascript:alert(1)")==nil && IslandTrackLink.safe("https://open.spotify.com.evil.example/track/1")==nil)
  check(IslandTrackLink.safe("https://user:pass@open.spotify.com/track/1")==nil && IslandTrackLink.safe("spotify:track:abc/../1")==nil)
  print("PASS: \(count) portable-settings, saved-layout migration, app-visibility and real waveform-math checks; access/capture/credentials stay outside imports")
 }
}
