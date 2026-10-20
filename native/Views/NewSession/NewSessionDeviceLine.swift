import SwiftUI

/// Where a new task runs, under where it works: "Runs on" and the device pill, which opens the
/// picker of This Mac and each paired host. Choosing another device moves the task there.
struct NewSessionDeviceLine: View {
    let device: NewSessionContext.Device
    let projectName: String

    @State private var isPickerOpen = false
    @State private var selection = SessionDevice.thisMac

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text("Runs on")
                .font(.dsCallout)
                .foregroundStyle(.dsTextTertiary)
            HostDevicePill(
                options: device.options, projectName: projectName, selection: $selection,
                isPickerOpen: $isPickerOpen)
        }
        .onAppear { selection = device.selection }
        .onChange(of: device.selection) { _, current in selection = current }
        .onChange(of: selection) { _, chosen in
            if chosen != device.selection { device.choose(chosen) }
        }
    }
}
