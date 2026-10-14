// Tekent het Wallastream-appicoon: een koala waarvan de oren speakers zijn.
// Gebruik: swift scripts/make-icon.swift Resources/AppIcon.png   (1024×1024)
// Daarna .icns maken:
//   mkdir AppIcon.iconset && for s in 16 32 128 256 512; do
//     sips -z $s $s Resources/AppIcon.png --out AppIcon.iconset/icon_${s}x${s}.png
//     sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out AppIcon.iconset/icon_${s}x${s}@2x.png; done
//   iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h))
}

func radial(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ inner: CGColor, _ outer: CGColor) {
    let g = CGGradient(colorsSpace: cs, colors: [inner, outer] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    ctx.clip()
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x - r * 0.3, y: y + r * 0.35), startRadius: 0,
                           endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
    ctx.restoreGState()
}

// MARK: Achtergrond (macOS-raster: 824 pt tegel met afgeronde hoeken, gecentreerd)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.28))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x3E8E6E))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0xA8E0B4), rgb(0x3C8F72)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])

// Eucalyptusblaadjes als subtiel patroon
func leaf(_ x: CGFloat, _ y: CGFloat, _ angle: CGFloat, _ len: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.rotate(by: angle)
    let p = CGMutablePath()
    p.move(to: .zero)
    p.addQuadCurve(to: CGPoint(x: len, y: 0), control: CGPoint(x: len / 2, y: len * 0.32))
    p.addQuadCurve(to: .zero, control: CGPoint(x: len / 2, y: -len * 0.32))
    ctx.addPath(p)
    ctx.setFillColor(rgb(0xFFFFFF, 0.13))
    ctx.fillPath()
    ctx.restoreGState()
}
leaf(120, 150, 0.45, 150)
leaf(135, 125, 1.15, 105)
leaf(904, 150, 2.69, 150)
leaf(889, 125, 1.99, 105)

// MARK: Geluidsgolven vanuit de oren
let earL = CGPoint(x: 318, y: 668), earR = CGPoint(x: 706, y: 668)
ctx.setLineCap(.round)
for (i, r) in [CGFloat(178), 226].enumerated() {
    ctx.setStrokeColor(rgb(0xFFFFFF, i == 0 ? 0.85 : 0.55))
    ctx.setLineWidth(22)
    ctx.addArc(center: earL, radius: r, startAngle: .pi * 0.60, endAngle: .pi * 0.84, clockwise: false)
    ctx.strokePath()
    ctx.addArc(center: earR, radius: r, startAngle: .pi * 0.16, endAngle: .pi * 0.40, clockwise: false)
    ctx.strokePath()
}

// MARK: Koala
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x0B3D2C, 0.35))

// Oren = speakers
for ear in [earL, earR] {
    circle(ear.x, ear.y, 140, rgb(0x8D97A3))                      // vacht
    circle(ear.x, ear.y, 118, rgb(0xE4E8EE))                      // pluizige binnenkant
}
ctx.setShadow(offset: .zero, blur: 0, color: nil)
for ear in [earL, earR] {
    radial(ear.x, ear.y, 92, rgb(0x4A5466), rgb(0x1F242D))       // speakerconus
    ctx.setStrokeColor(rgb(0x5D687C, 0.9))
    ctx.setLineWidth(5)
    ctx.strokeEllipse(in: CGRect(x: ear.x - 66, y: ear.y - 66, width: 132, height: 132))
    radial(ear.x, ear.y, 36, rgb(0x5B667A), rgb(0x161A21))       // stofkap
    circle(ear.x - 12, ear.y + 13, 9, rgb(0xFFFFFF, 0.55))         // glimlicht
}

// Hoofd
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x0B3D2C, 0.35))
ellipse(512, 455, 530, 470, rgb(0x9AA4B0))
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: 512 - 265, y: 455 - 235, width: 530, height: 470))
ctx.clip()
let head = CGGradient(colorsSpace: cs, colors: [rgb(0xB7C0CA), rgb(0x8A94A0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(head, start: CGPoint(x: 0, y: 690), end: CGPoint(x: 0, y: 220), options: [])
ctx.restoreGState()
ellipse(512, 345, 300, 190, rgb(0xC9D0D8, 0.75))                  // lichte snuit

// Wangetjes
circle(355, 390, 42, rgb(0xF4A3B4, 0.45))
circle(669, 390, 42, rgb(0xF4A3B4, 0.45))

// Ogen
for x in [CGFloat(408), 616] {
    circle(x, 505, 30, rgb(0x1E222A))
    circle(x + 9, 516, 10, rgb(0xFFFFFF))
}

// Neus
let nose = CGMutablePath()
nose.move(to: CGPoint(x: 512, y: 318))
nose.addCurve(to: CGPoint(x: 448, y: 430), control1: CGPoint(x: 450, y: 318), control2: CGPoint(x: 438, y: 372))
nose.addCurve(to: CGPoint(x: 576, y: 430), control1: CGPoint(x: 458, y: 488), control2: CGPoint(x: 566, y: 488))
nose.addCurve(to: CGPoint(x: 512, y: 318), control1: CGPoint(x: 586, y: 372), control2: CGPoint(x: 574, y: 318))
ctx.addPath(nose)
ctx.setFillColor(rgb(0x2A2F38))
ctx.fillPath()
ellipse(490, 438, 38, 20, rgb(0xFFFFFF, 0.35))

// Glimlachje
ctx.setStrokeColor(rgb(0x2A2F38))
ctx.setLineWidth(10)
ctx.addArc(center: CGPoint(x: 512, y: 308), radius: 30, startAngle: .pi * 1.2, endAngle: .pi * 1.8, clockwise: false)
ctx.strokePath()

ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Geschreven: \(out)")
