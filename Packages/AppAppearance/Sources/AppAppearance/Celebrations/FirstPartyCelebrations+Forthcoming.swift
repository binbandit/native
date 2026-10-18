/// The rest of Native's first-party catalogue (`docs/celebrations.md`), listed so it can be found
/// and its dates read, with no icon set yet: each shows "Artwork forthcoming" and can't be turned
/// on. Kinds other than `fixed` are calendars a later resolver will handle.
extension FirstPartyCelebrations {
    public static let forthcoming: [CelebrationContribution] = [
        entry("new-year", "New Year", ["New Year's Eve", "New Year's Day"], "cultural", fixed: (12, 31), to: (1, 1)),
        entry("valentines-day", "Valentine's Day", ["Saint Valentine's Day"], "cultural", fixed: (2, 14)),
        entry(
            "st-patricks-day", "St Patrick's Day", ["Saint Patrick's Day", "Lá Fhéile Pádraig"], "cultural",
            fixed: (3, 17)),
        entry(
            "spring-festival", "Spring Festival", ["Chinese New Year", "Chūnjié", "Lunar New Year"], "cultural",
            kind: "chinese-lunisolar"),
        entry("seollal", "Seollal", ["Korean New Year", "Lunar New Year"], "cultural", kind: "korean-lunisolar"),
        entry(
            "tet", "Tết Nguyên Đán", ["Tet", "Vietnamese New Year", "Lunar New Year"], "cultural",
            kind: "vietnamese-lunisolar"),
        entry("lantern-festival", "Lantern Festival", ["Yuánxiāo", "Yuanxiao"], "cultural", kind: "chinese-lunisolar"),
        entry(
            "mid-autumn", "Mid-Autumn Festival", ["Zhōngqiū", "Moon Festival"], "cultural", kind: "chinese-lunisolar"),
        entry("tet-trung-thu", "Tết Trung Thu", ["Tet Trung Thu"], "cultural", kind: "vietnamese-lunisolar"),
        entry("chuseok", "Chuseok", ["Hangawi"], "cultural", kind: "korean-lunisolar"),
        entry("nowruz", "Nowruz", ["Newroz", "Navruz", "Norooz"], "cultural", kind: "march-equinox"),
        entry("songkran", "Songkran", ["Thai New Year"], "cultural", kind: "table"),
        entry("matariki", "Matariki", ["Māori New Year"], "cultural", kind: "table"),
        entry("kwanzaa", "Kwanzaa", [], "cultural", fixed: (12, 26), to: (1, 1)),
        entry("pride", "Pride Month", ["Pride"], "community", fixed: (6, 1), to: (6, 30)),
        entry(
            "mardi-gras-new-orleans", "Mardi Gras in New Orleans", ["Carnival", "Fat Tuesday"], "cultural",
            kind: "western-easter"),
        entry("christmas", "Christmas", ["Noël", "Navidad", "Xmas"], "religious", fixed: (12, 25)),
        entry("christmas-julian", "Christmas (Julian calendar)", ["Orthodox Christmas"], "religious", kind: "julian"),
        entry("easter", "Easter", ["Western Easter"], "religious", kind: "western-easter"),
        entry("pascha", "Orthodox Pascha", ["Orthodox Easter", "Pascha"], "religious", kind: "orthodox-pascha"),
        entry("holi", "Holi", [], "religious", kind: "hindu-lunisolar"),
        entry("diwali", "Diwali", ["Deepavali", "Dipawali"], "religious", kind: "hindu-lunisolar"),
        entry("vaisakhi", "Vaisakhi", ["Baisakhi"], "religious", kind: "table"),
        entry("bandi-chhor-divas", "Bandi Chhor Divas", [], "religious", kind: "table"),
        entry(
            "guru-nanak-gurpurab", "Guru Nanak's Gurpurab", ["Guru Nanak Jayanti", "Prakash Utsav"], "religious",
            kind: "table"),
        entry(
            "eid-al-fitr", "Eid al-Fitr", ["Eid ul-Fitr", "Ramazan Bayramı", "Hari Raya Aidilfitri"], "religious",
            kind: "islamic"),
        entry("eid-al-adha", "Eid al-Adha", ["Eid ul-Adha", "Kurban Bayramı", "Bakrid"], "religious", kind: "islamic"),
        entry("hanukkah", "Hanukkah", ["Chanukah", "Hanukah"], "religious", kind: "hebrew"),
        entry("vesak", "Vesak", ["Wesak", "Buddha Day"], "religious", kind: "table"),
        entry("meskel", "Meskel", ["Finding of the True Cross"], "religious", kind: "ethiopic"),
        entry("timkat", "Timkat", ["Timket", "Ethiopian Epiphany"], "religious", kind: "ethiopic"),
        entry("earth-day", "Earth Day", [], "community", fixed: (4, 22)),
        entry("juneteenth", "Juneteenth", ["Emancipation Day"], "community", fixed: (6, 19)),
        entry("thanksgiving-canada", "Thanksgiving in Canada", ["Thanksgiving"], "community", kind: "nth-weekday"),
        entry(
            "thanksgiving-us", "Thanksgiving in the United States", ["Thanksgiving"], "community", kind: "nth-weekday"),
        entry("pi-day", "Pi Day", ["International Day of Mathematics"], "community", fixed: (3, 14)),
        entry("programmers-day", "Programmers' Day", [], "community", kind: "day-of-year"),
        entry("ada-lovelace-day", "Ada Lovelace Day", [], "community", kind: "nth-weekday"),
    ]

    private static func entry(
        _ slug: String, _ title: LocalizedText, _ aliases: [String], _ tag: String, fixed start: (Int, Int),
        to end: (Int, Int)? = nil
    ) -> CelebrationContribution {
        let first = MonthDay(literal: start.0, start.1)
        return contribution(
            slug, title, aliases, tag,
            rule: .fixed(start: first, end: end.map { MonthDay(literal: $0.0, $0.1) } ?? first))
    }

    private static func entry(
        _ slug: String, _ title: LocalizedText, _ aliases: [String], _ tag: String, kind: String
    )
        -> CelebrationContribution
    {
        contribution(slug, title, aliases, tag, rule: .unsupported(kind: kind))
    }

    private static func contribution(
        _ slug: String, _ title: LocalizedText, _ aliases: [String], _ tag: String, rule: CelebrationRule
    ) -> CelebrationContribution {
        CelebrationContribution(
            id: CelebrationID("native.\(slug)"), title: title, aliases: aliases, tags: [tag],
            calendar: CelebrationCalendar(rule: rule))
    }
}
