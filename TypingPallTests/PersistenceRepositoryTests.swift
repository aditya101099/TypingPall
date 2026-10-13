import Foundation
import Testing
@testable import TypingPall

@Suite("PersistenceRepository Actor & Sendable Concurrency Verification")
struct PersistenceRepositoryTests {

    @Test("Save and fetch scripts concurrently across actor boundaries")
    func saveAndFetchScripts() async throws {
        let repo = PersistenceRepository.makeInMemory()

        let script1 = try await repo.saveScript(
            text: "fmt.Println(\"Hello, Go\")",
            language: "go"
        )
        let script2 = try await repo.saveScript(
            text: "puts 'Hello, Ruby'",
            language: "ruby"
        )

        let allScripts = try await repo.fetchRecentScripts(limit: 10)
        #expect(allScripts.count == 2)
        #expect(allScripts.first?.text == script2.text)
        #expect(allScripts.last?.text == script1.text)

        let count = try await repo.count()
        #expect(count == 2)
    }

    @Test("Delete script removes record safely")
    func deleteScriptSafely() async throws {
        let repo = PersistenceRepository.makeInMemory()

        let script = try await repo.saveScript(
            text: "console.log('JS')",
            language: "javascript"
        )
        #expect(try await repo.count() == 1)

        let deleted = try await repo.deleteScript(id: script.id)
        #expect(deleted == true)
        #expect(try await repo.count() == 0)

        let deletedAgain = try await repo.deleteScript(id: script.id)
        #expect(deletedAgain == false)
    }
}
