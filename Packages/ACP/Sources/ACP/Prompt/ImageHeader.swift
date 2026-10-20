import Foundation

/// An image's type and pixel size as its file states them, read without decoding it: how attachments
/// tell whether a picture already fits what agents take where ImageIO isn't available.
///
/// PNG and GIF only, since both state their size at a fixed offset and end with a fixed trailer
/// (a cheap check that the file isn't cut short). JPEG and WebP would need their segments walked,
/// and JPEG its EXIF orientation honored, so those aren't read.
struct ImageHeader: Equatable {
    var mimeType: String
    var width: Int
    var height: Int

    init?(_ data: Data) {
        let start = [UInt8](data.prefix(24))
        if start.count == 24, start.starts(with: Self.pngSignature), start[12..<16].elementsEqual("IHDR".utf8),
            data.suffix(Self.pngEnd.count).elementsEqual(Self.pngEnd)
        {
            mimeType = "image/png"
            width = start[16..<20].reduce(0) { $0 << 8 | Int($1) }
            height = start[20..<24].reduce(0) { $0 << 8 | Int($1) }
        } else if start.count >= 10, start.starts(with: "GIF87a".utf8) || start.starts(with: "GIF89a".utf8),
            data.last == 0x3B
        {
            mimeType = "image/gif"
            width = Int(start[6]) | Int(start[7]) << 8
            height = Int(start[8]) | Int(start[9]) << 8
        } else {
            return nil
        }
        guard width > 0, height > 0 else { return nil }
    }

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    /// The empty `IEND` chunk every PNG ends with: length, type and CRC.
    private static let pngEnd: [UInt8] = [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
}
