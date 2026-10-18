import Testing

@testable import AppAppearance

struct AppIconVariantTests {
    @Test func buildIdentitiesAndCelebrationArtworkNeverCollide() {
        let names = AppIconVariant.allCases.flatMap { variant in
            [false, true].flatMap { isDark in
                [variant.imageName(isDark: isDark)]
                    + FirstPartyCelebrations.iconSets.compactMap { set -> String? in
                        guard case .channels(let channels) = set.icons,
                            case .asset(let name)? = channels[variant].map({ isDark ? $0.dark : $0.light })
                        else { return nil }
                        return name
                    }
            }
        }
        #expect(Set(names).count == names.count)
        #expect(names.contains("AppIcon-halloween-dev-dark"))
    }
}
