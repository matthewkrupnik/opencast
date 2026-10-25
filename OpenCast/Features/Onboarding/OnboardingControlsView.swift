import SwiftUI

struct OnboardingControlsView: View {
    let page: OnboardingPage
    let canGoBack: Bool
    let isPrimaryDisabled: Bool
    let onBack: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                if canGoBack {
                    Button("Back", systemImage: "chevron.left", action: onBack)
                        .buttonStyle(.glass)
                }

                Spacer()

                if page.isPrimaryActionSecondary {
                    primaryButton
                        .buttonStyle(.glass)
                } else {
                    primaryButton
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .accessibilityIdentifier("Onboarding Controls")
    }

    private var primaryButton: some View {
        Button(page.primaryActionTitle, systemImage: page.primaryActionSystemImage, action: onPrimary)
            .disabled(isPrimaryDisabled)
    }
}
