import Testing
@testable import KVMCore

@Suite struct BMPEncoderTests {
    // 2x2 image, RGBA rows top to bottom: red, green / blue, white
    let rgba: [UInt8] = [
        255, 0, 0, 255,   0, 255, 0, 255,
        0, 0, 255, 255,   255, 255, 255, 255,
    ]

    func u32(_ b: [UInt8], _ at: Int) -> UInt32 {
        UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
    }
    func u16(_ b: [UInt8], _ at: Int) -> UInt16 { UInt16(b[at]) | UInt16(b[at + 1]) << 8 }

    @Test func fileHeaderPointsPastAPlain40ByteInfoHeader() {
        let bmp = BMPEncoder.encode(rgba: rgba, width: 2, height: 2)
        #expect(bmp[0] == UInt8(ascii: "B") && bmp[1] == UInt8(ascii: "M"))
        #expect(u32(bmp, 2) == UInt32(bmp.count))
        #expect(u32(bmp, 10) == 54)      // what Deskflow's converter assumes
        #expect(u32(bmp, 14) == 40)      // BITMAPINFOHEADER, not V4/V5
    }

    @Test func infoHeaderIs24BitUncompressedBottomUp() {
        let bmp = BMPEncoder.encode(rgba: rgba, width: 2, height: 2)
        #expect(u32(bmp, 18) == 2)       // width
        #expect(u32(bmp, 22) == 2)       // positive height = bottom-up
        #expect(u16(bmp, 26) == 1)       // planes
        #expect(u16(bmp, 28) == 24)      // bpp
        #expect(u32(bmp, 30) == 0)       // BI_RGB
        #expect(u32(bmp, 34) == 16)      // image size: 2 rows x (6 bytes + 2 padding)
    }

    @Test func pixelsAreBGRBottomRowFirstWithRowPadding() {
        let bmp = BMPEncoder.encode(rgba: rgba, width: 2, height: 2)
        let pixels = Array(bmp[54...])
        #expect(pixels == [
            255, 0, 0,   255, 255, 255,   0, 0,   // bottom row: blue, white (BGR) + padding
            0, 0, 255,   0, 255, 0,       0, 0,   // top row: red, green (BGR) + padding
        ])
    }

    @Test func alphaIsFlattenedOntoWhite() {
        // half-transparent black over white -> mid grey, not black (Windows ignores alpha in 24-bit)
        let bmp = BMPEncoder.encode(rgba: [0, 0, 0, 128], width: 1, height: 1)
        #expect(Array(bmp[54..<57]) == [127, 127, 127])
    }
}
