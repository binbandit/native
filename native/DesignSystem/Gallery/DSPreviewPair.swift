import SwiftUI

/// Shows a preview's content in light and dark side by side, each on the content background.
struct DSPreviewPair<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                content
                    .padding(DS.Space.xl)
                    .frame(maxHeight: .infinity)
                    .background(.dsBackground)
                    .environment(\.colorScheme, scheme)
            }
        }
        .fixedSize()
    }
}
