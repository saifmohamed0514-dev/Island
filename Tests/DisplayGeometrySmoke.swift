import Foundation
@main struct DisplayGeometrySmoke {
 @MainActor static func main() {
  var count=0
  func check(_ value:Bool) { precondition(value,"Display geometry check \(count+1)");count+=1 }
  check(IslandDisplayGeometry.height(requested:10,physical:33.5,scale:2)==33.5)
  check(IslandDisplayGeometry.height(requested:40,physical:33.5,scale:2)==40)
  check(IslandDisplayGeometry.height(requested:33.6,physical:33.5,scale:2)==34)
  check(IslandDisplayGeometry.height(requested:.nan,physical:33.5,scale:2)==33.5)
  check(IslandDisplayGeometry.height(requested:32,physical:0,scale:2)==32)
  check(IslandDisplayGeometry.height(requested:32,physical:.nan,scale:.nan)==32)
  let size=CGSize(width:680,height:236),screen=CGRect(x:0,y:0,width:1710,height:1107)
  let frame=IslandDisplayGeometry.frame(screen:screen,size:size,scale:2)
  check(frame.maxY==screen.maxY && frame.midX==screen.midX)
  let left=CGRect(x:-1920,y:0,width:1920,height:1080),above=CGRect(x:0,y:1080,width:1920,height:1080)
  check(IslandDisplayGeometry.frame(screen:left,size:size,scale:1).maxY==left.maxY)
  check(IslandDisplayGeometry.frame(screen:above,size:size,scale:2).maxY==above.maxY)
  let metric=IslandDisplayMetrics(id:"display",frame:screen,safeTop:33.5,scale:2)
  check(metric != IslandDisplayMetrics(id:"display",frame:screen,safeTop:32,scale:2))
  check(metric != IslandDisplayMetrics(id:"display",frame:screen,safeTop:33.5,scale:1))
  let vm=GeometryModel();vm.refreshClosedGeometry()
  check(vm.closedNotchSize==fixtureSize && vm.notchSize==fixtureSize)
  vm.notchState = .open;vm.notchSize=CGSize(width:680,height:216);fixtureSize=CGSize(width:185,height:40);vm.refreshClosedGeometry()
  check(vm.closedNotchSize==fixtureSize && vm.notchSize==CGSize(width:680,height:216))
  print("PASS: \(count) production display-geometry checks; physical-height clamp, pixel sizing, top-edge frames, negative/above screens, scale/safe-area snapshots and closed/open geometry refresh")
 }
}
