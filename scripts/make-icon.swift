// Reproducible Island vector artwork, rendered into the macOS icon catalog.
import AppKit
import Foundation
let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("IslandCore/Assets.xcassets/AppIcon.appiconset")
let iconset = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("Island-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:iconset) }
var entries:[[String:String]] = []
for points in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = points*scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        bitmap.size = NSSize(width:pixels,height:pixels)
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
        let context=NSGraphicsContext.current!.cgContext
        context.scaleBy(x:CGFloat(pixels)/1024,y:CGFloat(pixels)/1024)
        let rect=CGRect(x:0,y:0,width:1024,height:1024)
        let shape=CGPath(roundedRect:rect.insetBy(dx:24,dy:24),cornerWidth:244,cornerHeight:244,transform:nil)
        context.addPath(shape);context.clip()
        let colors=[NSColor(calibratedRed:0.24,green:0.67,blue:1,alpha:1).cgColor,NSColor(calibratedRed:0.17,green:0.31,blue:0.9,alpha:1).cgColor] as CFArray
        let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1])!
        context.drawLinearGradient(gradient,start:CGPoint(x:0,y:1024),end:CGPoint(x:1024,y:0),options:[])
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(CGPath(roundedRect:CGRect(x:154,y:364,width:716,height:296),cornerWidth:148,cornerHeight:148,transform:nil));context.fillPath()
        context.setFillColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        context.addPath(CGPath(roundedRect:CGRect(x:260,y:536,width:154,height:41),cornerWidth:20,cornerHeight:20,transform:nil));context.fillPath()
        NSGraphicsContext.restoreGraphicsState()
        let name="icon_\(points)x\(points)"+(scale == 2 ? "@2x" : "")+".png"
        let data=bitmap.representation(using:.png,properties:[:])!
        try data.write(to:iconset.appendingPathComponent(name))
        try data.write(to:catalog.appendingPathComponent(name))
        entries.append(["filename":name,"idiom":"mac","scale":"\(scale)x","size":"\(points)x\(points)"])
    }
}
let data=try JSONSerialization.data(withJSONObject:["images":entries,"info":["author":"xcode","version":1]],options:[.prettyPrinted,.sortedKeys])
try data.write(to:catalog.appendingPathComponent("Contents.json"))
let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil");process.arguments=["--convert","icns","--output",root.appendingPathComponent("Assets/Island.icns").path,iconset.path]
try process.run();process.waitUntilExit();guard process.terminationStatus == 0 else { exit(1) }
print("Rendered ten Island icon variants and Island.icns.")
