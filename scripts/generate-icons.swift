// Original Lucent icon artwork. No reference image or asset is used.
import AppKit
import Foundation
import ImageIO
let styles: [(String, [NSColor])] = [
 ("Titanium", [.init(white:0.79,alpha:1),.init(white:0.46,alpha:1)]),
 ("Silver", [.init(white:0.96,alpha:1),.init(white:0.62,alpha:1)]),
 ("SpaceGrey", [.init(white:0.38,alpha:1),.init(white:0.13,alpha:1)]),
 ("Monochrom", [.white,.init(white:0.83,alpha:1)]),
 ("Pride2022", [.systemPink,.systemPurple,.systemBlue,.systemTeal]),
 ("Pride2021", [.systemRed,.systemOrange,.systemYellow,.systemGreen,.systemBlue,.systemPurple]),
 ("Aperture", [.systemTeal,.systemBlue]),
 ("MarkI", [.init(white:0.38,alpha:1),.init(white:0.13,alpha:1)])]
let fm = FileManager.default
let root = URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent("App/Assets.xcassets")
func render(_ colors:[NSColor], size:Int) -> Data {
 let ctx=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:false)
 ctx.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
 NSGradient(colors:colors)!.draw(in:NSBezierPath(rect:NSRect(x:0,y:0,width:1024,height:1024)),angle:70)
 // Six independently drawn iris blades surround Lucent's hexagonal opening.
 let ink=NSColor(calibratedRed:0.08,green:0.1,blue:0.12,alpha:0.9)
 for n in 0..<6 {
  let a=Double(n)*Double.pi/3
  func point(_ r:Double,_ angle:Double)->NSPoint { NSPoint(x:512+r*cos(a+angle),y:512+r*sin(a+angle)) }
  let p=NSBezierPath();p.move(to:point(310,0.04));p.line(to:point(310,0.95));p.line(to:point(123,1.18));p.line(to:point(123,0.24));p.close()
  ink.setFill();p.fill()
 }
 let ring=NSBezierPath(ovalIn:NSRect(x:163,y:163,width:698,height:698));ring.lineWidth=13
 ink.setStroke();ring.stroke()
 // A small light-ray breaks the ring and distinguishes the Lucent emblem.
 colors[0].setFill();NSBezierPath(roundedRect:NSRect(x:478,y:842,width:68,height:82),xRadius:22,yRadius:22).fill()
 NSGraphicsContext.restoreGraphicsState()
 let data=NSMutableData();let dest=CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil)!
 CGImageDestinationAddImage(dest,ctx.makeImage()!,nil);CGImageDestinationFinalize(dest)
 return data as Data
}
func write(_ name:String,_ colors:[NSColor],icon:Bool) throws {
 let dir=root.appendingPathComponent(name+(icon ? ".appiconset":".imageset"));try fm.createDirectory(at:dir,withIntermediateDirectories:true)
 let png=icon ? "icon.png":"preview.png";try render(colors,size:icon ? 1024:600).write(to:dir.appendingPathComponent(png))
 let entry:[String:String]=icon ? ["idiom":"universal","platform":"ios","size":"1024x1024","filename":png] : ["idiom":"universal","filename":png]
 let json:[String:Any] = ["images":[entry],"info":["version":1,"author":"Lucent"]]
 try JSONSerialization.data(withJSONObject:json,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("Contents.json"))
}
try Data("{\"info\":{\"version\":1,\"author\":\"Lucent\"}}".utf8).write(to:root.appendingPathComponent("Contents.json"))
for (n,c) in styles {try write(n == "Titanium" ? "AppIcon":"Icon"+n,c,icon:true);try write("IconPreview"+n,c,icon:false)}
