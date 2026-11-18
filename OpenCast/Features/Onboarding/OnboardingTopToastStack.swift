import SwiftUI

struct OnboardingTopToastStack: View {
    let importedSubscriptionsNotification: ImportedSubscriptionsNotification?

    var body: some View {
        VStack(spacing: 0) {
            if let importedSubscriptionsNotification {
                ImportedSubscriptionsNotificationBanner(notification: importedSubscriptionsNotification)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}
