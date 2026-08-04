import Testing
@testable import LiveSubs

@Test
func heliumIsRecognizedAsAPreferredBrowser() {
    #expect(ApplicationDiscovery.priority(for: "Helium") == 0)
    #expect(ApplicationDiscovery.priority(for: "Helium Helper (Renderer)") == 0)
}

@Test
func unknownCapturableAppsRemainAvailableAsFallbacks() {
    #expect(ApplicationDiscovery.priority(for: "A New Browser") == 1)
}
