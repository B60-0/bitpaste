#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/dist/BitPaste.icns}"
ICONSET="$ROOT/dist/BitPaste.iconset"
TMP_SWIFT="$(mktemp -t bitpaste-icon.XXXXXX.swift)"

rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$(dirname "$OUT")"

cat > "$TMP_SWIFT" <<'SWIFT'
import AppKit
import Foundation

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let specs: [(points: Int, scale: Int, name: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png")
]

func font(size: CGFloat) -> NSFont {
    NSFont(name: "AvenirNext-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
}

for spec in specs {
    let pixels = spec.points * spec.scale
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)

    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font(size: CGFloat(pixels) * 0.17),
        .foregroundColor: NSColor.black,
        .paragraphStyle: paragraph
    ]
    let text = NSAttributedString(string: "Cmd + V", attributes: attributes)
    let textSize = text.size()
    let rect = NSRect(
        x: (CGFloat(pixels) - textSize.width) / 2,
        y: (CGFloat(pixels) - textSize.height) / 2,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: rect)
    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        fatalError("Could not render \(spec.name)")
    }

    try png.write(to: iconset.appendingPathComponent(spec.name))
}
SWIFT

swift "$TMP_SWIFT" "$ICONSET"
rm -f "$TMP_SWIFT"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "$OUT"
