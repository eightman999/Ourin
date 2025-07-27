
import Foundation
import OurinICO

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: ourin-ico-demo <path.ico|path.cur>\n", stderr)
    exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try Data(contentsOf: url)
let image = try parseICOorCUR(data)
print("isCursor=\(image.isCursor) size=\(image.width)x\(image.height) hotspot=\(image.hotspotX),\(image.hotspotY)")
if let png = image.pngPayload {
    print("PNG payload \\(png.count) bytes (decode with Image I/O)")
} else if let rgba = image.rgba {
    print("RGBA decoded \\(rgba.count) bytes")
} else {
    print("No bitmap found")
}
