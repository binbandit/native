import NativeAutomation
import SwiftUI

/// One trigger in the automation editor, edited in place: a time for schedules, a count for
/// intervals, the event for event triggers.
struct AutomationTriggerRow: View {
    @Binding var trigger: AutomationTrigger
    let onRemove: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: trigger.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(.dsTextSecondary)
                .frame(width: DS.Size.rowLeading)
            content
                .font(.dsBody)
                .foregroundStyle(.dsTextPrimary)
            Spacer(minLength: DS.Space.md)
            IconButton("Remove Trigger", systemImage: "xmark", action: onRemove)
        }
        .frame(minHeight: DS.Size.controlSM)
    }

    @ViewBuilder private var content: some View {
        switch trigger {
        case .schedule(.daily(let hour, let minute)):
            Text("Every day at")
            timePicker(hour: hour, minute: minute) { trigger = .schedule(.daily(hour: $0, minute: $1)) }
        case .schedule(.weekly(let weekday, let hour, let minute)):
            Text("Every")
            Picker(
                "Day",
                selection: Binding(
                    get: { weekday }, set: { trigger = .schedule(.weekly(weekday: $0, hour: hour, minute: minute)) })
            ) {
                ForEach(Array(calendar.standaloneWeekdaySymbols.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index + 1)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Text("at")
            timePicker(hour: hour, minute: minute) {
                trigger = .schedule(.weekly(weekday: weekday, hour: $0, minute: $1))
            }
        case .schedule(.everyHours(let hours)):
            Stepper(value: Binding(get: { hours }, set: { trigger = .schedule(.everyHours($0)) }), in: 1...24) {
                Text(hours == 1 ? "Every hour" : "Every \(hours) hours")
                    .monospacedDigit()
            }
            .fixedSize()
        case .event(let kind):
            Picker("Event", selection: Binding(get: { kind }, set: { trigger = .event($0) })) {
                ForEach(AutomationEventKind.allCases, id: \.self) { kind in
                    Text("When " + kind.clause).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }

    private func timePicker(hour: Int, minute: Int, set: @escaping (Int, Int) -> Void) -> some View {
        let time = Binding<Date> {
            calendar.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        } set: { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            set(parts.hour ?? hour, parts.minute ?? minute)
        }
        return DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .fixedSize()
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Trigger rows") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            AutomationTriggerRowPreview(trigger: .schedule(.daily(hour: 9, minute: 0)))
            AutomationTriggerRowPreview(trigger: .schedule(.weekly(weekday: 2, hour: 8, minute: 30)))
            AutomationTriggerRowPreview(trigger: .schedule(.everyHours(4)))
            AutomationTriggerRowPreview(trigger: .event(.checksFailed))
        }
        .frame(width: 560)
    }
}

/// Holds the trigger the row edits.
private struct AutomationTriggerRowPreview: View {
    @State var trigger: AutomationTrigger

    var body: some View {
        AutomationTriggerRow(trigger: $trigger, onRemove: {})
    }
}
#endif
