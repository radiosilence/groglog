import Combine
import Foundation
import GRDB
import GRDBQuery

/// Observed reads for SwiftUI's `@Query`. Each re-runs after any commit touching its tables, so screens update the
/// moment a write lands — and each reads only what its screen shows.

/// Every day's totals — the whole history in a few hundred rows a year.
nonisolated struct DaysRequest: ValueObservationQueryable {
    static var defaultValue: [Day] { [] }

    func fetch(_ db: Database) throws -> [Day] {
        try Day.order(Column("number")).fetchAll(db)
    }
}

/// Log entries with their drinks for a range of days, oldest first.
nonisolated struct EntriesRequest: ValueObservationQueryable {
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
nonisolated struct FavouritesRequest: ValueObservationQueryable {
    static var defaultValue: [FavouriteItem] { [] }

    func fetch(_ db: Database) throws -> [FavouriteItem] {
        try Favourite
            .including(required: Favourite.drink)
            .order(Column("sortOrder"))
            .asRequest(of: FavouriteItem.self)
            .fetchAll(db)
    }
}

nonisolated struct DrinksRequest: ValueObservationQueryable {
    static var defaultValue: [Drink] { [] }

    func fetch(_ db: Database) throws -> [Drink] {
        try Drink.order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db)
    }
}

/// How many times a drink has been logged — whether it can be deleted.
nonisolated struct PourCountRequest: ValueObservationQueryable {
    static var defaultValue: Int { 0 }
    var drinkId: UUID

    func fetch(_ db: Database) throws -> Int {
        try Pour.filter(Column("drinkId") == drinkId).fetchCount(db)
    }
}
