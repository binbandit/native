import Foundation

/// Native's own celebrations, contributed by the built-in Celebrations plugin. They live here, with
/// the engine, so the tests run against the real calendar data. Sources and visual direction:
/// `docs/celebrations.md`.
public enum FirstPartyCelebrations {
    public static let halloweenID = CelebrationPreferences.halloween
    public static let diaDeMuertosID = CelebrationID("native.dia-de-muertos")

    /// The design-system marks Home draws for them.
    public enum HomeMark {
        public static let halloween = "native.halloween"
        public static let diaDeMuertos = "native.dia-de-muertos"
    }

    /// The confirmed editions first, then the rest of the catalogue with its artwork forthcoming.
    public static let celebrations: [CelebrationContribution] = [halloween, diaDeMuertos] + forthcoming
    public static let iconSets: [IconSetContribution] = [halloweenIcons, diaDeMuertosIcons]

    /// The ghost links in every channel, compiled into the app (`design/app-icon/Halloween*.icon`).
    public static let halloweenIcons = IconSetContribution(
        id: IconSetID("native.halloween"),
        name: "Halloween",
        icons: .channels(
            Dictionary(
                uniqueKeysWithValues: AppIconVariant.allCases.map { variant in
                    let name = "AppIcon-halloween-\(variant.rawValue)"
                    return (variant, IconSetImagePair(light: .asset("\(name)-light"), dark: .asset("\(name)-dark")))
                })),
        homeMark: HomeMark.halloween,
        palette: palette(light: ["#EF9A53", "#442A24"], dark: ["#FFF0D8", "#FFA052"]))

    /// Home only for now: the four channel icons are specified in `docs/celebrations-artwork.md`, and
    /// the icon applies once they're compiled in and listed here.
    public static let diaDeMuertosIcons = IconSetContribution(
        id: IconSetID("native.dia-de-muertos"),
        name: "Día de Muertos",
        icons: .forthcoming,
        homeMark: HomeMark.diaDeMuertos,
        palette: palette(light: ["#D9660B", "#B8326E"], dark: ["#FFB23F", "#F06AA4"]))

    /// 31 October, shown from 1 October through 7 November: the window agreed for the Halloween icons.
    public static let halloween = CelebrationContribution(
        id: halloweenID,
        title: "Halloween",
        aliases: ["Hallowe'en", "All Hallows' Eve", "Allhalloween"],
        summary: "Native's links as little ghosts, with the stars kept on Nightly.",
        tags: ["cultural", "autumn"],
        provenance: CelebrationProvenance(
            sources: urls("https://americanenglish.state.gov/files/ae/resource_files/halloween.pdf"),
            publisher: "U.S. Department of State, American English",
            reviewed: CivilDate(year: 2026, month: 10, day: 18)),
        calendar: CelebrationCalendar(
            rule: .fixed(start: monthDay(10, 31), end: monthDay(10, 31)), tradition: "Gregorian civil calendar"),
        display: CelebrationDisplay(
            windows: [
                CelebrationWindow(id: season, title: "Halloween season", daysBefore: 30, daysAfter: 7)
            ],
            defaultWindow: season),
        iconSet: halloweenIcons.id
    )

    /// 1 and 2 November, with an optional decorative window from 28 October through 3 November. The
    /// wider window is Native's product choice, not an observance rule, and it's labelled that way.
    public static let diaDeMuertos = CelebrationContribution(
        id: diaDeMuertosID,
        title: "Día de Muertos",
        aliases: ["Day of the Dead", "Día de los Muertos", "Dia de los Muertos", "Dia de Muertos"],
        summary: "Marigolds, candlelight and papel picado around the links, for remembering loved ones.",
        tags: ["cultural", "remembrance", "Mexico"],
        provenance: CelebrationProvenance(
            sources: urls(
                "https://www.oaxaca.gob.mx/comunicacion/tradiciones-y-colores-del-dia-de-muertos-en-oaxaca/",
                "https://www.americanhistory.si.edu/explore/stories/day-dead-smithsonian-its-not-halloween"),
            publisher: "Gobierno del Estado de Oaxaca; Smithsonian National Museum of American History",
            reviewed: CivilDate(year: 2026, month: 10, day: 18)),
        calendar: CelebrationCalendar(rule: .fixed(start: monthDay(11, 1), end: monthDay(11, 2)), tradition: "Mexico"),
        display: CelebrationDisplay(
            windows: [
                CelebrationWindow(id: extended, title: "Extended, decorative", daysBefore: 4, daysAfter: 1)
            ]),
        iconSet: diaDeMuertosIcons.id
    )

    public static let season = CelebrationWindow.ID("season")
    public static let extended = CelebrationWindow.ID("extended")

    // MARK: - Literals

    private static func monthDay(_ month: Int, _ day: Int) -> MonthDay {
        MonthDay(literal: month, day)
    }

    private static func urls(_ strings: String...) -> [URL] {
        strings.compactMap(URL.init(string:))
    }

    private static func palette(light: [String], dark: [String]) -> IconSetPalette {
        IconSetPalette(light: light.compactMap(HexColor.init), dark: dark.compactMap(HexColor.init))
    }
}
