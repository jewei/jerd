import JerdDesign
import SwiftUI

/// The segmented section picker in the toolbar. Its size never changes, so it does not move
/// during navigation.
struct SectionPicker: View {
    let state: AppState

    var body: some View {
        Picker("Section", selection: selection) {
            ForEach(AppSection.allCases) { section in
                Text(section.title)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Choose a section (⌘1 to ⌘5)")
        .accessibilityIdentifier("workspace.section")
    }

    private var selection: Binding<AppSection> {
        Binding {
            state.navigation.section
        } set: { section in
            state.navigation.show(.section(section))
        }
    }
}
