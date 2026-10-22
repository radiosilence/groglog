import Foundation
import GrogLogCore

/// The generic drinks the Log grid always offers, from the shared core rather than seeded. Each is the stored generic
/// of its kind when there is one, since the user may have edited or hidden it, else a drink under the generic's fixed
/// id that is stored when first logged or pinned (`Logbook.store`).
nonisolated enum Generics {
    private static let records = catalogGenerics()

    /// The Units drink as it is first stored.
    static let units = Drink(id: UUID(uuidString: catalogUnitsId())!, name: "Units", category: .units, abv: 100, vessel: .shot, volumeMl: 10, isGeneric: true, sortOrder: 99)

    /// The generic drinks in the core's order, then Units. Hidden ones are left out unless asked for, as Setup lists
    /// them to be shown again.
    static func drinks(_ stored: [Drink], includingHidden: Bool = false) -> [Drink] {
        // The lowest id of a kind, the one a sync merge keeps.
        let kept = stored.filter(\.isGeneric).sorted { $0.id.uuidString < $1.id.uuidString }
        let generics = records.enumerated().map { order, record in
            let category = DrinkCategory(record.category)
            let first = record.serves[0]
            return kept.first { $0.category == category }
                ?? Drink(id: UUID(uuidString: record.id)!, name: record.name, category: category, abv: category.defaultABV, vessel: Vessel(first.vessel), volumeMl: first.ml, price: first.price, isGeneric: true, sortOrder: 100 + order)
        }
        let all = generics + [stored.first { $0.category == .units } ?? units]
        return includingHidden ? all : all.filter { !$0.isHidden }
    }

    /// Those not yet stored, to offer alongside the stored drinks.
    static func unstored(_ stored: [Drink]) -> [Drink] {
        let ids = Set(stored.map(\.id))
        return drinks(stored).filter { !ids.contains($0.id) }
    }

    /// Each generic drink in its own size, then the other sizes it is commonly drunk in, then Units.
    static func serves(_ stored: [Drink]) -> [Serve] {
        drinks(stored).flatMap { drink -> [Serve] in
            guard let record = records.first(where: { DrinkCategory($0.category) == drink.category }) else { return [Serve(drink)] }
            var seen = Set<ServeSize>()
            return ([ServeSize(drink.vessel, drink.volumeMl)] + record.serves.map { ServeSize(Vessel($0.vessel), $0.ml) })
                .filter { seen.insert($0).inserted }
                .map { Serve(drink, $0.vessel, $0.ml) }
        }
    }
}
