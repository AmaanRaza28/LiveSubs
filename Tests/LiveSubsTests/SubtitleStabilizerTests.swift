import Testing
@testable import LiveSubs

@Test
func waitsForASecondConsistentInterpretation() {
    var stabilizer = SubtitleStabilizer()

    #expect(stabilizer.ingest("When did you come home?") == nil)
    #expect(stabilizer.ingest("When did you come home?") == "When did you come home?")
}

@Test
func suppressesGrammarRewritesOfTheDisplayedThought() {
    var stabilizer = SubtitleStabilizer()
    _ = stabilizer.ingest("Did they leave you at the hostel?")
    _ = stabilizer.ingest("Did they leave you at the hostel?")

    #expect(stabilizer.ingest("Did they leave you in the hostel?") == nil)
    #expect(stabilizer.ingest("Did they leave you at that hostel?") == nil)
}

@Test
func advancesAfterNewSpeechIsConfirmed() {
    var stabilizer = SubtitleStabilizer()
    _ = stabilizer.ingest("Did they leave you at the hostel?")
    _ = stabilizer.ingest("Did they leave you at the hostel?")

    #expect(stabilizer.ingest("Is that a wound? I am cooking now.") == nil)
    #expect(
        stabilizer.ingest("Is this a wound? I am cooking now.")
            == "Is this a wound? I am cooking now."
    )
}
