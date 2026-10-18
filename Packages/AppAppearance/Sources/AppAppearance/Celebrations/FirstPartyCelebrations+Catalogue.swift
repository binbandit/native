import Foundation

/// The rest of Native's first-party catalogue (`docs/celebrations.md`). Each edition's icons are a
/// pack downloaded when it's chosen (`CelebrationAssets`), with a small thumbnail bundled for the
/// catalogue. An edition whose calendar has no resolver or verified table yet is listed as coming
/// soon and can't be turned on.
extension FirstPartyCelebrations {
    /// The editions, in catalogue order, each with its icon set.
    static let catalogue: [(celebration: CelebrationContribution, icons: IconSetContribution)] = [
        edition("new-year", "New Year", ["New Year's Eve", "New Year's Day"], "cultural", .fixed(12, 31, to: 1, 1)),
        edition("valentines-day", "Valentine's Day", ["Saint Valentine's Day"], "cultural", .fixed(2, 14)),
        edition(
            "st-patricks-day", "St Patrick's Day", ["Saint Patrick's Day", "Lá Fhéile Pádraig"], "cultural",
            .fixed(3, 17)),
        edition(
            "spring-festival", "Spring Festival", ["Chinese New Year", "Chūnjié", "Lunar New Year"], "cultural",
            .published),
        edition("seollal", "Seollal", ["Korean New Year", "Lunar New Year"], "cultural", .published),
        edition(
            "tet", "Tết Nguyên Đán", ["Tet", "Vietnamese New Year", "Lunar New Year"], "cultural",
            .published),
        edition(
            "lantern-festival", "Lantern Festival", ["Yuánxiāo", "Yuanxiao"], "cultural", .published),
        edition(
            "mid-autumn", "Mid-Autumn Festival", ["Zhōngqiū", "Moon Festival"], "cultural", .published),
        edition("tet-trung-thu", "Tết Trung Thu", ["Tet Trung Thu"], "cultural", .published),
        edition("chuseok", "Chuseok", ["Hangawi"], "cultural", .published),
        edition("nowruz", "Nowruz", ["Newroz", "Navruz", "Norooz"], "cultural", .published),
        edition("songkran", "Songkran", ["Thai New Year"], "cultural", .published),
        edition("matariki", "Matariki", ["Māori New Year"], "cultural", .published),
        edition("kwanzaa", "Kwanzaa", [], "cultural", .fixed(12, 26, to: 1, 1)),
        edition("pride", "Pride Month", ["Pride"], "community", .fixed(6, 1, to: 6, 30)),
        edition(
            "carnival", "Mardi Gras", ["Carnival", "Fat Tuesday", "Shrove Tuesday"], "cultural",
            .rule(.easter(.western, offset: -47, length: 1)), tradition: "New Orleans: 47 days before Western Easter"),
        edition(
            "christmas", "Christmas", ["Noël", "Navidad", "Xmas"], "religious", .fixed(12, 25),
            tradition: "Gregorian church calendar"),
        edition(
            "christmas-julian", "Christmas (Julian calendar)", ["Orthodox Christmas"], "religious", .fixed(1, 7),
            tradition: "Julian church calendar: 7 January from 1901 to 2099", icons: "christmas"),
        edition(
            "easter", "Easter", ["Western Easter"], "religious", .rule(.easter(.western, offset: 0, length: 1)),
            tradition: "Western churches"),
        edition(
            "orthodox-pascha", "Orthodox Pascha", ["Orthodox Easter", "Pascha"], "religious",
            .rule(.easter(.orthodox, offset: 0, length: 1)), tradition: "Orthodox churches (Julian computus)"),
        edition("holi", "Holi", [], "religious", .published),
        edition("diwali", "Diwali", ["Deepavali", "Dipawali"], "religious", .published),
        edition("vaisakhi", "Vaisakhi", ["Baisakhi"], "religious", .published),
        edition("bandi-chhor-divas", "Bandi Chhor Divas", [], "religious", .published),
        edition(
            "guru-nanak-gurpurab", "Guru Nanak's Gurpurab", ["Guru Nanak Jayanti", "Prakash Utsav"], "religious",
            .published),
        edition(
            "eid-al-fitr", "Eid al-Fitr", ["Eid ul-Fitr", "Ramazan Bayramı", "Hari Raya Aidilfitri"], "religious",
            .published),
        edition(
            "eid-al-adha", "Eid al-Adha", ["Eid ul-Adha", "Kurban Bayramı", "Bakrid"], "religious", .published),
        edition("hanukkah", "Hanukkah", ["Chanukah", "Hanukah"], "religious", .published),
        edition("vesak", "Vesak", ["Wesak", "Buddha Day"], "religious", .published),
        edition(
            "meskel", "Meskel", ["Finding of the True Cross", "Demera"], "religious",
            .rule(.ethiopic(month: 1, day: 17, length: 1)),
            tradition: "Ethiopian calendar, 17 Meskerem; the Demera bonfire is the evening before"),
        edition(
            "timkat", "Timkat", ["Timket", "Ethiopian Epiphany"], "religious", .rule(.ethiopic(month: 5, day: 11, length: 1)),
            tradition: "Ethiopian calendar, 11 Tir; the Ketera eve is the day before"),
        edition("earth-day", "Earth Day", [], "community", .fixed(4, 22)),
        edition("juneteenth", "Juneteenth", ["Emancipation Day"], "community", .fixed(6, 19)),
        edition(
            "us-independence-day", "Fourth of July", ["Independence Day", "July 4th"], "community", .fixed(7, 4),
            tradition: "United States"),
        edition(
            "thanksgiving-canada", "Thanksgiving in Canada", ["Thanksgiving", "Action de grâce"], "community",
            .rule(.nthWeekday(month: 10, weekday: 2, ordinal: 2, length: 1)),
            tradition: "Canada: the second Monday in October"),
        edition(
            "thanksgiving-us", "Thanksgiving in the United States", ["Thanksgiving"], "community",
            .rule(.nthWeekday(month: 11, weekday: 5, ordinal: 4, length: 1)),
            tradition: "United States: the fourth Thursday in November"),
        edition(
            "mathematics-day", "Pi Day", ["International Day of Mathematics", "π Day"], "community", .fixed(3, 14)),
        edition(
            "programmers-day", "Programmers' Day", ["Day of the Programmer"], "community",
            .rule(.dayOfYear(day: 256, length: 1)),
            tradition: "The 256th day of the year"),
        edition(
            "ada-lovelace-day", "Ada Lovelace Day", [], "community",
            .rule(.nthWeekday(month: 10, weekday: 3, ordinal: 2, length: 1)),
            tradition: "The second Tuesday in October"),
    ]

    /// How an edition's dates come about, written compactly.
    enum Dates {
        case rule(CelebrationRule)
        /// The edition's published annual dates (`publishedDates`), by its slug.
        case published
        /// A calendar awaiting its resolver or verified table.
        case soon(String)

        static func fixed(_ month: Int, _ day: Int, to endMonth: Int? = nil, _ endDay: Int? = nil) -> Dates {
            let start = MonthDay(literal: month, day)
            let end = endMonth.flatMap { month in endDay.map { MonthDay(literal: month, $0) } } ?? start
            return .rule(.fixed(start: start, end: end))
        }

        func calendar(_ slug: String, tradition: String?) -> (CelebrationCalendar, CelebrationProvenance) {
            switch self {
            case .rule(let rule):
                return (CelebrationCalendar(rule: rule, tradition: tradition), CelebrationProvenance())
            case .soon(let kind):
                return (CelebrationCalendar(rule: .unsupported(kind: kind), tradition: tradition), CelebrationProvenance())
            case .published:
                guard let table = publishedDates[slug] else {
                    return (CelebrationCalendar(rule: .unsupported(kind: "table"), tradition: tradition), CelebrationProvenance())
                }
                let ranges = table.ranges
                let years = ranges.map(\.first.year)
                return (
                    CelebrationCalendar(rule: .table(ranges), tradition: table.tradition, isProvisional: table.isProvisional),
                    CelebrationProvenance(
                        sources: table.sources.compactMap(URL.init(string:)), authority: table.authority,
                        dataVersion: "2026-10-18", reviewed: CivilDate(year: 2026, month: 10, day: 18),
                        coverage: years.min().flatMap { first in years.max().map { .init(from: first, through: $0) } },
                        note: table.note)
                )
            }
        }

    private static func edition(
        _ slug: String, _ title: LocalizedText, _ aliases: [String], _ tag: String, _ dates: Dates,
        tradition: String? = nil, icons pack: String? = nil
    ) -> (celebration: CelebrationContribution, icons: IconSetContribution) {
        let pack = pack ?? slug
        let (calendar, provenance) = dates.calendar(slug, tradition: tradition)
        return (
            CelebrationContribution(
                id: CelebrationID("native.\(slug)"), title: title, aliases: aliases, tags: [tag], provenance: provenance,
                calendar: calendar,
                iconSet: IconSetID("native.\(pack)")),
            IconSetContribution(
                id: IconSetID("native.\(pack)"), name: title, icons: .pack(pack),
                thumbnail: thumbnail(pack))
        )
    }
}
