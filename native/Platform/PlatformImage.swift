import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

extension Image {
    /// An image decoded from an encoded one (PNG, JPEG, ...), on the Mac and on iPad; nil if the
    /// bytes aren't an image.
    init?(decoding data: Data) {
        #if canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
        #endif
    }
}
