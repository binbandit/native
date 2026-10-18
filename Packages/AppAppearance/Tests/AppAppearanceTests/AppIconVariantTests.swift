import Testing

@testable import AppAppearance

struct AppIconVariantTests {
    @Test func buildIdentitiesAndSeasonalArtworkNeverCollide() {
        let names = AppIconVariant.allCases.flatMap { variant in
            [false, true].flatMap { isDark in
                [variant.imageName(isDark: isDark), variant.halloweenImageName(isDark: isDark)]
            }
        }
        #expect(Set(names).count == names.count)
    }
}
