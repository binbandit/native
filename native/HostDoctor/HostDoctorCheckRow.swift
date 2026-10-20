import NativeHostProtocol
import SwiftUI

/// One doctor check: its status, what was found, and the fix, with its command ready to copy.
struct HostDoctorCheckRow: View {
    let check: HostDoctorCheck

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            Image(systemName: check.status.symbol)
                .font(.dsBody)
                .foregroundStyle(check.status.color)
                .accessibilityLabel(check.status.accessibilityLabel)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(check.title)
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                DSInlineCodeText(check.detail)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let fix = check.fix {
                    fixView(fix)
                        .padding(.top, DS.Space.xs)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.sm)
        .accessibilityElement(children: .contain)
    }

    private func fixView(_ fix: HostDoctorFix) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            if let setting = fix.setting {
                DSInlineCodeText(setting)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let command = fix.command {
                HStack(spacing: DS.Space.sm) {
                    Text(command)
                        .codeTextStyle(.compact)
                        .foregroundStyle(.dsTextPrimary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: DS.Space.sm)
                    IconButton("Copy Command", systemImage: "doc.on.doc") {
                        DSPasteboard.copy(command)
                    }
                    .help("Copy the command")
                }
                .padding(.leading, DS.Space.md)
                .padding(.trailing, DS.Space.xxs)
                .padding(.vertical, DS.Space.xxs)
                .background(.dsCodeBlockBackground, in: .rect(cornerRadius: DS.Radius.control))
            }
        }
    }
}

extension HostDoctorCheck.Status {
    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .ok: .dsSuccess
        case .info, .unknown: .dsTextTertiary
        case .warning: .dsWarning
        case .failed: .dsDanger
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .ok: "OK"
        case .info: "Note"
        case .warning: "Warning"
        case .failed: "Problem"
        case .unknown: "Unknown"
        }
    }
}
