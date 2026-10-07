import JerdDesign
import JerdWeb
import SwiftUI

/// What Jerd checked for this site, and when. A check that did not run says so, so the page
/// never claims a result without evidence.
struct SiteChecksSection: View {
    let model: SitesModel
    let site: Site

    var body: some View {
        Section {
            ForEach(SiteCheck.checks(for: site, in: model), id: \.title) { check in
                LabeledContent(check.title) {
                    CheckResultLabel(check.result, passed: check.passed)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Connection Checks")
        } footer: {
            FormFooter("PHP-FPM and system HTTPS are checked each time the site starts.")
        }
    }
}
