import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code for `text`, drawn with sharp modules. It's always dark on light, whatever the
/// appearance: inverted codes scan unreliably, so the code carries its own white field.
struct PairingQRCodeImage: View {
    let text: String
    let size: CGFloat

    var body: some View {
        if let image = Self.render(text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .accessibilityLabel("Pairing QR code")
        } else {
            Image(systemName: "qrcode")
                .font(.ds(size / 3, weight: .light))
                .foregroundStyle(.dsTextTertiary)
                .frame(width: size, height: size)
        }
    }

    private static let context = CIContext()

    private static func render(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        // Scaled up by whole pixels here, so the view's nearest-neighbour resize stays crisp.
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        return context.createCGImage(output, from: output.extent)
    }
}
