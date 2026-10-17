#if EXPEDITIONS_WIP
import NativeAutomation
import NativeExpeditions
import SwiftUI

/// One assignment of a proposed route, edited in place: title, assignee, brief and "done when",
/// with what it comes after. Removing it strikes it through until the route is approved, so it's
/// one click to bring back.
struct RouteAssignmentEditor: View {
    @Binding var assignment: Route.Assignment
    let agents: [WorkflowAgent]
    let isRemoved: Bool
    /// New or changed since the lead's previous route.
    let isChanged: Bool
    let toggleRemoved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                TextField("Title", text: $assignment.title)
                    .textFieldStyle(.plain)
                    .font(.dsCalloutMedium)
                    .foregroundStyle(.dsTextPrimary)
                    .strikethrough(isRemoved)
                if isChanged {
                    Badge("Changed", tone: .info, style: .soft)
                }
                Spacer(minLength: DS.Space.md)
                Picker("Assignee", selection: $assignment.assignee) {
                    ForEach(agents) { Label($0.name, systemImage: $0.symbol).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(isRemoved)
                .help("Who builds it")
                Button(isRemoved ? "Restore" : "Remove", systemImage: isRemoved ? "arrow.uturn.backward" : "trash", action: toggleRemoved)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.ds(.ghost))
                    .help(isRemoved ? "Keep this assignment" : "Leave this assignment out of the route")
            }
            if !isRemoved {
                TextField("Brief", text: $assignment.brief, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1...8)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Done when")
                        .font(.dsCaptionMedium)
                        .foregroundStyle(.dsTextTertiary)
                    ForEach(assignment.doneWhen.indices, id: \.self) { index in
                        HStack(spacing: DS.Space.sm) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.dsTextTertiary)
                            TextField("Criterion", text: $assignment.doneWhen[index])
                                .textFieldStyle(.plain)
                                .font(.dsBody)
                        }
                    }
                }
                if !assignment.after.isEmpty {
                    Text("After " + assignment.after.joined(separator: ", "))
                        .font(.dsMonoCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
        }
        .padding(DS.Space.lg)
        .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
        .overlay { RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(isChanged ? .dsInfo.opacity(0.5) : .dsSeparator, lineWidth: 1) }
        .opacity(isRemoved ? 0.6 : 1)
    }
}
#endif
