import SwiftUI

/// The short hairline `StatusBarSurface` puts between two items.
public struct StatusBarSeparator: View {
    public init() {}

    public var body: some View {
        SeparatorLine(axis: .vertical)
            .frame(height: DS.StatusBar.separatorHeight)
    }
}
