import CoreData
import Foundation
import SwiftUI

// MARK: - Sendable Data Transfer Object

public struct HistoryRecordDTO: Sendable, Identifiable, Equatable {
    public let id: String
    public let text: String
    public let language: String
    public let timestamp: Date

    public init(id: String, text: String, language: String, timestamp: Date) {
        self.id = id
        self.text = text
        self.language = language
        self.timestamp = timestamp
    }
}

// MARK: - Actor-Isolated Persistence Repository

/// Thread-safe actor wrapping NSPersistentContainer to prevent NSManagedObject instances
/// from escaping across concurrency boundaries into SwiftUI or ViewModels.
public actor PersistenceRepository {
    private let container: NSPersistentContainer

    public init(container: NSPersistentContainer) {
        self.container = container
    }

    public static func makeInMemory() -> PersistenceRepository {
        let container = NSPersistentContainer(name: "TypingPall", managedObjectModel: PersistenceController.model)
        if let description = container.persistentStoreDescriptions.first {
            description.url = URL(fileURLWithPath: "/dev/null")
            description.type = NSInMemoryStoreType
        }
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to initialize in-memory store: \(error)")
            }
        }
        return PersistenceRepository(container: container)
    }

    /// Persists a code snippet asynchronously, returning a Sendable DTO.
    @discardableResult
    public func saveScript(text: String, language: String, timestamp: Date = Date()) async throws -> HistoryRecordDTO {
        let context = container.newBackgroundContext()
        return try await context.perform {
            let item = NSEntityDescription.insertNewObject(forEntityName: "Item", into: context)
            item.setValue(text, forKey: "text")
            item.setValue(language, forKey: "language")
            item.setValue(timestamp, forKey: "timestamp")
            try context.save()
            let id = item.objectID.uriRepresentation().absoluteString
            return HistoryRecordDTO(id: id, text: text, language: language, timestamp: timestamp)
        }
    }

    /// Fetches recent scripts as immutable, Sendable DTOs sorted descending by timestamp.
    public func fetchRecentScripts(limit: Int = 50) async throws -> [HistoryRecordDTO] {
        let context = container.newBackgroundContext()
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Item")
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            request.fetchLimit = limit
            let results = try context.fetch(request)
            return results.compactMap { obj in
                guard let text = obj.value(forKey: "text") as? String,
                      let timestamp = obj.value(forKey: "timestamp") as? Date else { return nil }
                let language = (obj.value(forKey: "language") as? String) ?? "plainText"
                let id = obj.objectID.uriRepresentation().absoluteString
                return HistoryRecordDTO(id: id, text: text, language: language, timestamp: timestamp)
            }
        }
    }

    /// Deletes a script by its URI representation.
    public func deleteScript(id uriString: String) async throws -> Bool {
        let context = container.newBackgroundContext()
        return try await context.perform {
            guard let url = URL(string: uriString),
                  let objectID = self.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: url),
                  let object = try? context.existingObject(with: objectID) else {
                return false
            }
            context.delete(object)
            try context.save()
            return true
        }
    }

    /// Returns the total count of stored scripts.
    public func count() async throws -> Int {
        let context = container.newBackgroundContext()
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Item")
            return try context.count(for: request)
        }
    }
}

// MARK: - SwiftUI Environment Integration

public struct PersistenceRepositoryKey: EnvironmentKey {
    public static let defaultValue: PersistenceRepository = PersistenceRepository(container: PersistenceController.shared.container)
}

public extension EnvironmentValues {
    var persistenceRepository: PersistenceRepository {
        get { self[PersistenceRepositoryKey.self] }
        set { self[PersistenceRepositoryKey.self] = newValue }
    }
}
