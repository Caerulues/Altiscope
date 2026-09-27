import AppKit
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
NSColor(red:0.055,green:0.065,blue:0.09,alpha:1).setFill()
NSBezierPath(rect:NSRect(x:0,y:0,width:size,height:size)).fill()
let purple = NSColor(red:0.64,green:0.49,blue:1,alpha:1)
for radius in [330.0,410.0] {
    let circle = NSBezierPath(ovalIn:NSRect(x:512-radius,y:512-radius,width:radius*2,height:radius*2))
    circle.lineWidth = 2; purple.withAlphaComponent(0.15).setStroke(); circle.stroke()
}
let route = NSBezierPath()
route.move(to:NSPoint(x:220,y:300)); route.curve(to:NSPoint(x:630,y:620),controlPoint1:NSPoint(x:650,y:130),controlPoint2:NSPoint(x:230,y:675))
route.lineWidth = 38; route.lineCapStyle = .round; purple.setStroke(); route.stroke()
let arrow = NSBezierPath()
arrow.move(to:NSPoint(x:744,y:820)); arrow.line(to:NSPoint(x:526,y:614)); arrow.line(to:NSPoint(x:640,y:639)); arrow.line(to:NSPoint(x:678,y:525)); arrow.close()
NSColor.white.setFill(); arrow.fill()
NSColor(red:0.45,green:0.88,blue:0.78,alpha:1).setFill()
NSBezierPath(ovalIn:NSRect(x:191,y:271,width:58,height:58)).fill()
NSGraphicsContext.restoreGraphicsState()
let url = URL(fileURLWithPath:CommandLine.arguments[1])
try rep.representation(using:.png,properties:[:])!.write(to:url)
