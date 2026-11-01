#if DEBUG && canImport(UIKit) && canImport(SwiftData)
import SwiftData

extension ShotlistContext {
    /// An in-memory SwiftData container seeded from fixtures, so the app's real queries and
    /// views run over known content and the developer's own store is never touched.
    ///
    /// ```swift
    /// RootView().modelContainer(try context.inMemoryContainer(for: League.self, seed: Fixtures.seedLeagues))
    /// ```
    @MainActor
    public func inMemoryContainer(
        for types: any PersistentModel.Type...,
        seed: (ModelContext) throws -> Void = { _ in }
    ) throws -> ModelContainer {
        let schema = Schema(types)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        try seed(container.mainContext)
        try container.mainContext.save()
        return container
    }
}
#endif
