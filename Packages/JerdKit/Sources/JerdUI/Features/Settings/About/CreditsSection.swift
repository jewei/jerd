import JerdDesign
import SwiftUI

/// The projects that Jerd uses, each a link to its home page.
struct CreditsSection: View {
    var body: some View {
        Section {
            ForEach(Credit.all) { credit in
                if let url = credit.url {
                    LabeledContent {
                        Text(credit.role)
                            .foregroundStyle(.secondary)
                    } label: {
                        Link(destination: url) {
                            HStack(spacing: Spacing.tight) {
                                Text(credit.name)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .help(credit.address)
                        .accessibilityLabel(Self.linkLabel(credit))
                    }
                }
            }
        } header: {
            Text("Credits")
        } footer: {
            FormFooter(
                "Made by Jerd contributors. These projects belong to their respective authors. Their license terms apply. License notices are included with the managed runtimes."
            )
        }
    }

    /// The spoken name of a credit link: the project only. The row value reads the role, so
    /// VoiceOver says each once.
    static func linkLabel(_ credit: Credit) -> String {
        credit.name
    }
}
