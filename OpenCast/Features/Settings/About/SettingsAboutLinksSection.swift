import SwiftUI

struct SettingsAboutLinksSection: View {
    var body: some View {
        Section {
            SettingsAboutRateRow()
        } footer: {
            Text("opencast is open source under the MIT license.")
        }
    }
}
