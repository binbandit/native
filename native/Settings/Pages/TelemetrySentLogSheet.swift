import NativeTelemetry
import SwiftUI

/// Settings ▸ Privacy ▸ Show What Native Sends: each batch with its destination and every event's
/// fields, as sent.
struct TelemetrySentLogSheet: View {
    let entries: [TelemetrySentLog.Entry]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("What Native Sends")
                    .settingsText(.bodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.ds(.secondary, size: .medium))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Space.xl)
            SeparatorLine()
            if entries.isEmpty {
                EmptyStateView(
                    "Nothing Sent", systemImage: "tray",
                    message: "Nothing has been sent from this Mac. Batches appear here as they're sent.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.Space.xl) {
                        ForEach(entries) { entry in
                            EntryView(entry: entry)
                        }
                    }
                    .padding(DS.Space.xl)
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 360, idealHeight: 480)
        .background(.dsBackground)
    }
}

private struct EntryView: View {
    let entry: TelemetrySentLog.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("\(entry.date.formatted(date: .abbreviated, time: .standard)) · to \(entry.destination.description)")
                .settingsText(.caption)
                .foregroundStyle(.dsTextSecondary)
            ForEach(Array(entry.records.enumerated()), id: \.offset) { _, record in
                Text(line(for: record))
                    .font(SettingsTextStyle.mono.font)
                    .foregroundStyle(.dsTextPrimary)
                    .textSelection(.enabled)
            }
        }
    }

    private func line(for record: TelemetryRecord) -> String {
        ([record.name.rawValue] + record.attributes.map { "\($0.key.rawValue)=\($0.value)" }).joined(separator: "  ")
    }
}
