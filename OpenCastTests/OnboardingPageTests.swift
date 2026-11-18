import Foundation
import Testing
@testable import OpenCast

@MainActor
@Suite("Onboarding pages")
struct OnboardingPageTests {
    @Test("Setup goes from shows straight to notifications: the Whisper model ships with the app")
    func standardPagesHaveNoModelDownloadStep() {
        let pages = OnboardingPage.allCases

        #expect(pages == [.welcome, .importOPML, .podcastSetup, .notificationSetup])
        #expect(OnboardingPage.podcastSetup.next(in: pages) == .notificationSetup)
        #expect(OnboardingPage.notificationSetup.previous(in: pages) == .podcastSetup)
        #expect(OnboardingPage.notificationSetup.next(in: pages) == nil)
    }

    @Test("Navigation outside the page list returns nil")
    func navigationOutsideListReturnsNil() {
        let pages: [OnboardingPage] = [.welcome, .importOPML, .podcastSetup]

        #expect(OnboardingPage.notificationSetup.next(in: pages) == nil)
        #expect(OnboardingPage.welcome.previous(in: pages) == nil)
    }

    @Test("Primary button labels match page position")
    func primaryButtonLabelsMatchPagePosition() {
        #expect(OnboardingPage.welcome.primaryActionTitle == "Continue")
        #expect(OnboardingPage.importOPML.primaryActionTitle == "Skip")
        #expect(OnboardingPage.podcastSetup.primaryActionTitle == "Continue")
        #expect(OnboardingPage.notificationSetup.primaryActionTitle == "Done")
    }
}
