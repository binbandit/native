import Foundation
import Testing

@testable import ACP

#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#endif

struct ImageHeaderTests {
    /// The smallest file `ImageHeader` reads as a PNG: the signature, the header chunk and the end
    /// chunk. It has no pixels, and its header's CRC is left zero, since neither is read.
    static func png(width: Int, height: Int) -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data += [0, 0, 0, 13] + Array("IHDR".utf8)
        for value in [width, height] {
            data += withUnsafeBytes(of: UInt32(value).bigEndian, Array.init)
        }
        // Bit depth, colour type, compression, filter, interlace; then the CRC.
        data += [8, 6, 0, 0, 0, 0, 0, 0, 0]
        data += [0, 0, 0, 0] + Array("IEND".utf8) + [0xAE, 0x42, 0x60, 0x82]
        return data
    }

    private func described(_ data: Data) -> String? {
        ImageHeader(data).map { "\($0.mimeType) \($0.width)x\($0.height)" }
    }

    @Test func readsAPNGsSize() {
        #expect(described(Self.png(width: 4096, height: 1024)) == "image/png 4096x1024")
    }

    @Test func readsAGIFsSize() {
        let gif = Data("GIF89a".utf8) + [0x2C, 0x01, 0xC8, 0x00] + Data(count: 3) + [0x3B]
        #expect(described(gif) == "image/gif 300x200")
    }

    /// A file cut short, an empty image, or a type it doesn't read isn't measured, so it goes by path.
    @Test func measuresNothingElse() {
        #expect(described(Self.png(width: 10, height: 10).dropLast()) == nil)
        #expect(described(Self.png(width: 0, height: 10)) == nil)
        #expect(described(Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10] + Array("JFIF".utf8))) == nil)
        #expect(described(Data()) == nil)
    }

    #if canImport(ImageIO)
    /// What a real encoder writes reads the same.
    @Test func readsWhatImageIOWrites() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        for type in [UTType.png, .gif] {
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
            #expect(described(data as Data) == "\(type.preferredMIMEType ?? "?") 300x200")
        }
    }
    #endif
}
