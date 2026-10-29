#if DEBUG
import CoreData
import Foundation
import OSLog
import SwiftData

/// Launch-arg tool: creates every synced record type, with every field, in
/// the iCloud container's Development environment, so the schema can be
/// deployed to Production from the CloudKit Console. SwiftData only creates
/// the types of records it happens to upload, and Production never creates
/// any; without a deployed schema every TestFlight export is rejected.
///
/// Runs against a throwaway store before the app opens its own, so the app's
/// data is untouched. It leaves one sample record per type in Development;
/// delete them in the Console afterwards.
enum CloudKitSchemaInitializer {
    nonisolated static let requestArgument = "--initialize-cloudkit-schema"

    private static let logger = Logger(subsystem: "mk.lan.opencast", category: "CloudKitSchemaInitializer")

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(requestArgument)
    }

    /// Blocks until CloudKit answers; a debug launch can afford it.
    static func run() {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(
            for: OpenCastModelContainerFactory.syncedModelTypes
        ) else {
            report("failed: could not build the managed object model")
            return
        }

        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitSchema-\(UUID().uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: OpenCastModelContainerFactory.cloudKitContainerIdentifier
        )
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "CloudKitSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        defer {
            let coordinator = container.persistentStoreCoordinator
            for store in coordinator.persistentStores {
                try? coordinator.remove(store)
            }
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(filePath: storeURL.path() + suffix))
            }
        }
        if let loadError {
            report("failed to open the scratch store: \(loadError)")
            return
        }

        do {
            try container.initializeCloudKitSchema()
            let names = model.entities.compactMap(\.name).map { "CD_\($0)" }.sorted()
            report("created \(names.joined(separator: ", ")) in Development")
        } catch {
            report("failed: \(error)")
        }
    }

    /// Logged and printed, so the result shows in Xcode's console either way.
    private static func report(_ message: String) {
        logger.log("CloudKit schema \(message, privacy: .public)")
        print("CloudKit schema \(message)")
    }
}
#endif
