import AppKit
import KVMCore

/// While connected: when an image lands on the Mac pasteboard, add a plain 24-bit BMP ("com.microsoft.bmp")
/// so Deskflow sends that instead of macOS's V4/V5 BMP, which Deskflow 1.26 garbles on Windows. See BMPEncoder.
@MainActor
public final class ClipboardImageFixer {
    public var enabled = false
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?

    static let bmpType = NSPasteboard.PasteboardType("com.microsoft.bmp")
    static let markerType = NSPasteboard.PasteboardType("io.github.macwinkvm.bmp-fixed")
    static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
    static let maxPixels = 40_000_000

    public init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        guard enabled, let item = pb.pasteboardItems?.first, pb.pasteboardItems?.count == 1 else { return }
        let types = item.types
        // only plain image copies: leave file copies (Finder), rich documents and already-fixed items alone
        guard types.contains(where: Self.imageTypes.contains), !types.contains(.fileURL), !types.contains(Self.markerType),
              let bmp = Self.bmp(from: item) else { return }

        var copies: [(NSPasteboard.PasteboardType, Data)] = []
        for t in types where t != Self.bmpType {
            if let d = item.data(forType: t) { copies.append((t, d)) }
        }
        let fixed = NSPasteboardItem()
        for (t, d) in copies { fixed.setData(d, forType: t) }
        fixed.setData(bmp, forType: Self.bmpType)
        fixed.setData(Data(), forType: Self.markerType)
        pb.clearContents()
        pb.writeObjects([fixed])
        lastChange = pb.changeCount
    }

    private static func bmp(from item: NSPasteboardItem) -> Data? {
        guard let data = imageTypes.lazy.compactMap({ item.data(forType: $0) }).first,
              let rep = NSBitmapImageRep(data: data), let cg = rep.cgImage,
              cg.width * cg.height <= maxPixels else { return nil }
        let (w, h) = (cg.width, cg.height)
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = rgba.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        // un-premultiply so BMPEncoder can flatten onto white itself
        for i in stride(from: 0, to: rgba.count, by: 4) where rgba[i + 3] != 0 && rgba[i + 3] != 255 {
            let a = Int(rgba[i + 3])
            for c in 0..<3 { rgba[i + c] = UInt8(min(255, Int(rgba[i + c]) * 255 / a)) }
        }
        return Data(BMPEncoder.encode(rgba: rgba, width: w, height: h))
    }
}
