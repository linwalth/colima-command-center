#!/usr/bin/env bash
#
# Generate AppIcon.iconset → AppIcon.icns for Colima Command Center.
# Draws a rounded-square gradient with a shipping-box glyph via Swift CoreGraphics.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES="$REPO_DIR/Resources"
ICONSET="$RESOURCES/AppIcon.iconset"
ICNS="$RESOURCES/AppIcon.icns"

mkdir -p "$ICONSET"

DRAW_SW="$ICONSET/_draw.swift"
cat > "$DRAW_SW" <<'SWIFT'
import AppKit
import Foundation
func draw(size: CGFloat) -> Data {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let path = CGMutablePath()
    path.addRoundedRect(in: rect, cornerWidth: size*0.22, cornerHeight: size*0.22)
    ctx.addPath(path); ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs, colors: [CGColor(red:0.2,green:0.4,blue:0.85,alpha:1),CGColor(red:0.1,green:0.65,blue:0.7,alpha:1)] as CFArray, locations:[0,1])!
    ctx.drawLinearGradient(grad, start:CGPoint(x:0,y:size), end:CGPoint(x:size,y:0), options:[])
    ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:0.95))
    let bw=size*0.5,bh=size*0.4,bx=(size-bw)/2,by=(size-bh)/2
    ctx.fill(CGRect(x:bx,y:by,width:bw,height:bh))
    let lidH=size*0.08
    ctx.fill(CGRect(x:bx-size*0.03,y:by+bh,width:bw+size*0.06,height:lidH))
    ctx.setLineWidth(size*0.04)
    ctx.setStrokeColor(CGColor(red:0.2,green:0.4,blue:0.85,alpha:0.6))
    ctx.move(to:CGPoint(x:bx+bw/2,y:by))
    ctx.addLine(to:CGPoint(x:bx+bw/2,y:by+bh+lidH))
    ctx.strokePath()
    img.unlockFocus()
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError("png conv") }
    return png
}
let px = CGFloat(Double(CommandLine.arguments[1])!)
try draw(size: px).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
SWIFT

generate() {
    local logical="$1" pixels="$2" suffix="$3"
    local out="$ICONSET/icon_${logical}x${logical}${suffix}.png"
    swift "$DRAW_SW" "$pixels" "$out" 2>/dev/null
    echo "  drew ${logical}px${suffix:+@2x} → $out"
}

echo "== Drawing sizes =="
generate 16  16  ""
generate 16  32  "@2x"
generate 32  32  ""
generate 32  64  "@2x"
generate 64  64  ""
generate 64  128 "@2x"
generate 128 128 ""
generate 128 256 "@2x"
generate 256 256 ""
generate 256 512 "@2x"
generate 512 512 ""
generate 512 1024 "@2x"

rm -f "$DRAW_SW"

echo "== Compiling icns =="
iconutil -c icns "$ICONSET" -o "$ICNS" 2>&1
echo "  → $ICNS ($(du -h "$ICNS" | cut -f1))"
