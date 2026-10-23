import SwiftUI

/// "Turn On a Country's Holidays": turns on, in one step, the catalogue's celebrations that are
/// official public holidays in the country the user picks. The Mac's region only puts that country
/// first ("Your region"); nothing is turned on until the user picks one (`docs/celebrations.md`).
struct CelebrationCountryMenu: View {
    /// How many celebrations each country (ISO 3166-1 alpha-2) has as public holidays.
    let counts: [String: Int]
    let onPick: (String) -> Void

    private var region: String? {
        Locale.current.region?.identifier
    }

    private var countries: [String] {
        counts.keys.sorted { Self.name($0).localizedStandardCompare(Self.name($1)) == .orderedAscending }
    }

    var body: some View {
        Menu {
            if let region, counts[region] != nil {
                Section("Your region") { item(region) }
            }
            Section("Countries") {
                ForEach(countries, id: \.self) { item($0) }
            }
        } label: {
            Text("Turn On a Country's Holidays")
        }
        .menuStyle(.button)
        .buttonStyle(.ds(.ghost, size: .medium))
        .fixedSize()
        .disabled(counts.isEmpty)
        .help("Turn on the celebrations that are official public holidays in a country you pick.")
    }

    private func item(_ code: String) -> some View {
        let count = counts[code] ?? 0
        return Button("\(Self.name(code)) (\(count))") { onPick(code) }
            .accessibilityLabel("\(Self.name(code)), \(count) public \(count == 1 ? "holiday" : "holidays")")
    }

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}
