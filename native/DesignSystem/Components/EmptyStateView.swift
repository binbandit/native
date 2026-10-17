import SwiftUI

/// A centered placeholder for an empty pane (the reference app's empty states: 20pt tertiary glyph, 13pt
/// medium title, 12pt secondary message, actions below).
public struct EmptyStateView<Actions: View>: View {
    let title: String
    let systemImage: String?
    let message: String?
    let actions: Actions

    public init(
        _ title: String,
        systemImage: String? = nil,
        message: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: DS.Space.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.dsTextTertiary)
                    .padding(.bottom, DS.Space.xs)
            }
            Text(title)
                .font(.dsCalloutMedium)
                .foregroundStyle(.dsTextPrimary)
            if let message {
                Text(message)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            HStack(spacing: DS.Space.md) {
                actions
            }
            .padding(.top, DS.Space.xs)
        }
        .tracking(DS.Tracking.tight)
        .padding(DS.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    public init(_ title: String, systemImage: String? = nil, message: String? = nil) {
        self.init(title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

#Preview("Empty state") {
    DSPreviewPair {
        EmptyStateView("No Sessions Yet", systemImage: "text.bubble", message: "Start one with ⌘N.") {
            Button("New Session") {}.buttonStyle(.ds(.primary))
        }
        .frame(width: 320, height: 200)
    }
}
