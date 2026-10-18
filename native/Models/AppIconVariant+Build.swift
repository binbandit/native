import AppAppearance

extension AppIconVariant {
    static var current: Self {
        #if DEBUG
        .development
        #else
        switch ReleaseChannel.current {
        case .stable: .stable
        case .beta: .beta
        case .nightly: .nightly
        }
        #endif
    }
}
