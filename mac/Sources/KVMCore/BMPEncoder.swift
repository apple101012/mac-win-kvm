/// Encodes RGBA pixels as the plainest possible BMP file: 40-byte BITMAPINFOHEADER, 24-bit BI_RGB, bottom-up.
///
/// Why: macOS's own "com.microsoft.bmp" conversion uses V4/V5 headers, which Deskflow 1.26 truncates to 40 bytes,
/// so images copied on the Mac paste on Windows with garbage colours (upstream deskflow PR 9638, unmerged).
public enum BMPEncoder {
    /// rgba: rows top to bottom, 4 bytes per pixel, non-premultiplied. Alpha is flattened onto white.
    public static func encode(rgba: [UInt8], width: Int, height: Int) -> [UInt8] {
        precondition(rgba.count == width * height * 4)
        let rowSize = (width * 3 + 3) & ~3
        let imageSize = rowSize * height
        var out = [UInt8]()
        out.reserveCapacity(54 + imageSize)

        func le32(_ v: Int) { out += [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)] }
        func le16(_ v: Int) { out += [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }

        // BITMAPFILEHEADER
        out += [UInt8(ascii: "B"), UInt8(ascii: "M")]
        le32(54 + imageSize); le16(0); le16(0); le32(54)
        // BITMAPINFOHEADER
        le32(40); le32(width); le32(height); le16(1); le16(24); le32(0)
        le32(imageSize); le32(2835); le32(2835); le32(0); le32(0)

        let padding = [UInt8](repeating: 0, count: rowSize - width * 3)
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let a = Int(rgba[i + 3])
                func flat(_ c: UInt8) -> UInt8 { UInt8((Int(c) * a + 255 * (255 - a)) / 255) }
                out += [flat(rgba[i + 2]), flat(rgba[i + 1]), flat(rgba[i])]
            }
            out += padding
        }
        return out
    }
}
