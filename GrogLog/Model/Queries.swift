import Combine
import Foundation
import GRDB
import GRDBQuery

/// Observed reads for SwiftUI's `@Query`. Each re-runs after any commit touching its tables, so screens update as
/// soon as a write lands, and each reads only what its screen shows.

/// A request that only notifies its screen when a fetch returns a different value. Observation is by table, so
/// logging a drink re-runs every entries request in the app, and without deduplication each screen would redraw
/// with an identical array. The tables read are fixed, so the region is computed once rather than per fetch.
nonisolated protocol ObservedRequest: Queryable, Sendable where Context == DatabaseContext, ValuePublisher == AnyPublisher<Value, any Error>, Value: Sendable & Equatable {
    func fetch(_ db: Database) throws -> Value
}

extension ObservedRequest {
    @MainActor func publisher(in context: DatabaseContext) -> ValuePublisher {
        do {
            return ValueObservation.trackingConstantRegion { try self.fetch($0) }
                .removeDuplicates()
                .publisher(in: try context.reader, scheduling: .immediate)
                .eraseToAnyPublisher()
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }
}

/// Every day's totals: the whole history in a few hundred rows a year.
nonisolated struct DaysRequest: ObservedRequest {
    static var defaultValue: [Day] { [] }

    func fetch(_ db: Database) throws -> [Day] {
        try Day.order(Column("number")).fetchAll(db)
    }
}

/// Log entries with their drinks for a range of days, oldest first.
nonisolated struct EntriesRequest: ObservedRequest {
    static var defaultValue: [Entry] { [] }
    var days: ClosedRange<DayKey>

    func fetch(_ db: Database) throws -> [Entry] {
        try Pour
            .filter((days.lowerBound.number...days.upperBound.number).contains(Column("day")))
            .including(required: Pour.drink)
            .order(Column("timestamp"))
            .asRequest(of: Entry.self)
            .fetchAll(db)
    }
}

/// The Log grid's pinned drink-and-size tiles.
nonisolated struct FavouritesRequest: ObservedRequest {
    static var defaultValue: [FavouriteItem] { [] }

    func fetch(_ db: Database) throws -> [FavouriteItem] {
        try Favourite
            .including(required: Favourite.drink)
            .order(Column("sortOrder"))
            .asRequest(of: FavouriteItem.self)
            .fetchAll(db)
    }
}

nonisolated struct DrinksRequest: ObservedRequest {
    static var defaultValue: [Drink] { [] }

    func fetch(_ db: Database) throws -> [Drink] {
        try Drink.order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db)
    }
}

/// How many times a drink has been logged, which decides whether it can be deleted.
nonisolated struct PourCountRequest: ObservedRequest {
    static var defaultValue: Int { 0 }
    var drinkId: UUID

    func fetch(_ db: Database) throws -> Int {
        try Pour.filter(Column("drinkId") == drinkId).fetchCount(db)
    }
}
