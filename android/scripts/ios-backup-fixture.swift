import Foundation

// A backup written by the iOS app's own `Backup` type and encoder settings, with the awkward cases in it: escapes,
// accents, a slash, whole and fractional numbers, exponents, empty lists and absent fields. ios-backup-fixture.sh
// compiles this against the iOS sources.
let d = { (s: String) in ISO8601DateFormatter().date(from: s)! }
let b = Backup(exportedAt: d("2026-10-12T09:30:00Z"), dayStartsAtHour: 5, currency: "GBP",
  goal: Goal(isEnabled: true, taper: .linear, baselineWeekly: 52.5, reductionUnits: 1.5, periodDays: 3, start: d("2026-09-01T04:00:00Z"), targetWeekly: 14),
  projectedStop: "2026-10-20",
  drinks: [.init(id: UUID(uuidString: "0B9C1E4A-6D2F-4C8E-9A51-3F7B2D8E1C40")!, name: "Rosé de Provence / Kölsch \"test\"\\ \u{1}", category: .rose, abv: 12.5, vessel: .wineGlass, volumeMl: 175, price: 8.5, isGeneric: false, isHidden: true),
           .init(id: UUID(uuidString: "5E2A7C91-0D34-4B6F-8E12-A9C4F07B3D65")!, name: "Beer", category: .beer, abv: 4, vessel: .pint, volumeMl: 568, price: 6.4, isGeneric: true, isHidden: false)],
  favourites: [.init(drinkID: UUID(uuidString: "5E2A7C91-0D34-4B6F-8E12-A9C4F07B3D65")!, vessel: .can, volumeMl: 440, price: 2.1, order: 101)],
  days: [
    .init(date: "2026-10-12", status: "in_progress", units: 0, kcal: 0, cost: 0, budget: 7.1, pours: []),
    .init(date: "2026-10-11", status: "drank", units: 4.65, kcal: 359, cost: 14.9, spentByHand: 20, budget: 7.14, pours: [
      .init(id: UUID(uuidString: "9F1D3B57-2C8A-4E06-B7D4-61A0E5C93F28")!, time: d("2026-10-11T19:05:42Z"), name: "Beer", category: .beer, vessel: .pint, volumeMl: 568, abv: 4, units: 2.27, kcal: 182, price: 6.4, drinkID: UUID(uuidString: "5E2A7C91-0D34-4B6F-8E12-A9C4F07B3D65")!),
      .init(id: UUID(uuidString: "C3E85A12-7B9F-4D21-A06E-2F4B8D17C590")!, time: d("2026-10-11T21:40:00Z"), name: "Rosé de Provence / Kölsch \"test\"\\ \u{1}", category: .rose, vessel: .wineGlass, volumeMl: 175, abv: 13.6, units: 2.38, kcal: 177, price: 8.5, drinkID: UUID(uuidString: "0B9C1E4A-6D2F-4C8E-9A51-3F7B2D8E1C40")!)]),
    .init(date: "2026-10-10", status: "alcohol_free", units: 0, kcal: 0, cost: 0, budget: 7.19, pours: []),
    .init(date: "2026-10-09", status: "not_logged", units: 0, kcal: 0, cost: 0, pours: []),
    .init(date: "2026-10-08", status: "drank", units: 0.1, kcal: 1e-7, cost: 1234567.891, budget: 0.3333333333333333, pours: [
      .init(id: UUID(uuidString: "1A2B3C4D-5E6F-4A8B-9C0D-1E2F3A4B5C6D")!, time: d("2026-10-08T23:59:59Z"), name: "Units", category: .units, vessel: .shot, volumeMl: 1, units: 0.1, kcal: 1e21, price: 0, drinkID: nil)]),
  ])
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
encoder.dateEncodingStrategy = .iso8601
FileHandle.standardOutput.write(try encoder.encode(b))
