import CoreGraphics
import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// A rendered icon as an `Image` that system menus draw properly. Menus only tint an icon to their
/// text color (white in dark mode, gray when disabled) when the platform image is marked as a
/// template; SwiftUI's own `renderingMode(.template)` doesn't reach them.
enum AgentIconMenuImage {
    static func image(_ cgImage: CGImage, scale: CGFloat, isTemplate: Bool) -> Image {
        #if canImport(AppKit)
        let size = CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = isTemplate
        return Image(nsImage: image)
        #else
        let image = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        return Image(uiImage: isTemplate ? image.withRenderingMode(.alwaysTemplate) : image)
        #endif
    }
}
