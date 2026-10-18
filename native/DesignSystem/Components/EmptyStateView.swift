import SwiftUI

/// The one empty state: what this is (the title), why it's empty (the message) and the one action
/// that fills it, centered in the pane (Conductor's empty states: 20pt tertiary glyph, 13pt medium
/// title, 12pt secondary message, the action below). Never leave a pane blank.
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
                    // The why is the point: it wraps rather than truncating in a short frame.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
            }
            if Actions.self != EmptyView.self {
                HStack(spacing: DS.Space.md) {
                    actions
                }
                // The action is primary unless the caller styles it.
                .buttonStyle(.ds(.primary))
                .padding(.top, DS.Space.xs)
            }
        }
        .tracking(DS.Tracking.tight)
        .padding(DS.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == Button<Text> {
    /// An empty state with its one action as a primary button.
    public init(
        _ title: String, systemImage: String? = nil, message: String? = nil, actionTitle: String,
        action: @escaping () -> Void
    ) {
        self.init(title, systemImage: systemImage, message: message) {
            Button(actionTitle, action: action)
        }
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
