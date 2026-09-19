import SwiftData
import SwiftUI

/// Long-press on a drink: pick which one exactly (the generic, a brand of yours, or one from the UK catalogue),
/// star brands into the main picker, and optionally log it earlier, in another size, or several at once.
struct LogOptionsSheet: View {
    let base: Drink
    let day: Date
    let ledger: Ledger
    @Query private var drinks: [Drink]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String
    @State private var volume: Double
    @State private var count = 1
    @State private var time: Date
    @State private var search = ""
    @State private var editing: Drink?

    init(base: Drink, day: Date, ledger: Ledger) {
        self.base = base
        self.day = day
        self.ledger = ledger
        _selected = State(initialValue: base.id.uuidString)
        _volume = State(initialValue: base.volumeMl)
        _time = State(initialValue: ledger.clock.suggestedTime(for: day, after: ledger.pours(on: day).last?.timestamp))
    }

    var body: some View {
        let choices = self.choices
        let choice = choices.first { $0.id == selected } ?? choices[0]
        let sizes = Array(Set(choice.vessel.volumes + [choice.volumeMl])).sorted()

        NavigationStack {
            Form {
                Section {
                    ForEach(choices) { option in
                        ChoiceRow(choice: option, isSelected: option.id == choice.id) {
                            selected = option.id
                            volume = option.volumeMl
                        } onStar: {
                            star(option)
                        }
                        .contextMenu {
                            if let drink = option.drink {
                                Button("Edit \(drink.name)", systemImage: "pencil") { editing = drink }
                            }
                        }
                    }
                } header: {
                    Text("Which one?")
                }

                Section {
                    if sizes.count > 1 {
                        ChipRow(options: sizes, selection: $volume) { $0.volumeText }
                    }
                    Stepper("How many: \(count)", value: $count, in: 1...12)
                    if day == ledger.clock.today {
                        ChipRow(options: [0, 15, 30, 60, 120, 180], selection: minutesAgo) {
                            $0 == 0 ? "Now" : $0 < 60 ? "\(Int($0))m ago" : "\(Int($0 / 60))h ago"
                        }
                    }
                    DatePicker(count > 1 ? "First one at" : "At", selection: resolvedTime, displayedComponents: .hourAndMinute)
                } footer: {
                    let times = spreadTimes
                    if count > 1, let first = times.first, let last = times.last {
                        Text("Spread from \(first.formatted(date: .omitted, time: .shortened)) to \(last.formatted(date: .omitted, time: .shortened)).")
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a brand")
            .navigationTitle(base.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log \(count > 1 ? "\(count) " : "")· \((Units.of(ml: volume, abv: choice.abv) * Double(count)).unitsText) u", role: .confirm) {
                        let drink = resolve(choice)
                        for at in spreadTimes {
                            context.insert(Pour(drink: drink, at: at, volumeMl: volume))
                        }
                        context.setAlcoholFree(false, on: day)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $editing) { DrinkEditor(drink: $0) }
        }
        .animation(.snappy, value: count)
    }

    /// The pressed drink first, then your brands of the same kind, then catalogue ones you don't have yet.
    private var choices: [Choice] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let matches = { (name: String) in query.isEmpty || name.localizedStandardContains(query) }
        let sameKind = { (category: DrinkCategory, vessel: Vessel) in category == base.category && vessel == base.vessel }

        let yours = drinks
            .filter { !$0.isGeneric && $0.id != base.id && sameKind($0.category, $0.vessel) && matches($0.name) }
            .sorted { (ledger.lastPoured[$0.id] ?? .distantPast) > (ledger.lastPoured[$1.id] ?? .distantPast) }
        let catalog = (query.isEmpty ? Catalog.items : Catalog.search(query))
            .filter { item in
                sameKind(item.category, item.vessel) && !drinks.contains { $0.name == item.name && $0.vessel == item.vessel }
            }
        return [Choice(base)] + yours.map(Choice.init) + catalog.map(Choice.init)
    }

    private func star(_ choice: Choice) {
        if let drink = choice.drink {
            if drink.isGeneric { return }
            drink.isFavourite.toggle()
        } else {
            let drink = resolve(choice)
            drink.isFavourite = true
            selected = drink.id.uuidString
        }
    }

    /// Catalogue picks become your own drinks, so they can be starred, corrected, and come up first next time.
    private func resolve(_ choice: Choice) -> Drink {
        if let drink = choice.drink { return drink }
        let drink = Drink(name: choice.name, category: choice.category, vessel: choice.vessel, volumeMl: choice.volumeMl, abv: choice.abv)
        context.insert(drink)
        return drink
    }

    /// Several drinks run from the chosen time up to now (or 20 minutes apart on a past day).
    private var spreadTimes: [Date] {
        guard count > 1 else { return [time] }
        let now = Date.now
        let gap = day == ledger.clock.today && now > time
            ? now.timeIntervalSince(time) / Double(count - 1)
            : 20 * 60
        return (0..<count).map { time.addingTimeInterval(gap * Double($0)) }
    }

    private var minutesAgo: Binding<Double> {
        Binding(
            get: { (Date.now.timeIntervalSince(time) / 60 / 15).rounded() * 15 },
            set: { time = Date.now.addingTimeInterval(-$0 * 60) }
        )
    }

    private var resolvedTime: Binding<Date> {
        Binding(get: { time }, set: { time = ledger.clock.resolve($0, into: day) })
    }
}

/// One of your drinks or a catalogue entry, presented the same way.
private struct Choice: Identifiable {
    let id: String
    let name: String
    let category: DrinkCategory
    let vessel: Vessel
    let volumeMl: Double
    let abv: Double
    var drink: Drink?

    init(_ drink: Drink) {
        id = drink.id.uuidString
        name = drink.name
        category = drink.category
        vessel = drink.vessel
        volumeMl = drink.volumeMl
        abv = drink.abv
        self.drink = drink
    }

    init(_ item: CatalogItem) {
        id = item.id
        name = item.name
        category = item.category
        vessel = item.vessel
        volumeMl = item.volumeMl
        abv = item.abv
    }
}

private struct ChoiceRow: View {
    let choice: Choice
    let isSelected: Bool
    let onSelect: () -> Void
    let onStar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    DrinkGlyph(category: choice.category, vessel: choice.vessel, volumeMl: choice.volumeMl)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(choice.name).fontWeight(isSelected ? .semibold : .regular)
                        Text("\(choice.category.serving(ml: choice.volumeMl, abv: choice.abv)) · \(Units.of(ml: choice.volumeMl, abv: choice.abv).unitsText) u")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark").foregroundStyle(Color.grog).fontWeight(.semibold)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if choice.drink?.isGeneric != true {
                Button(choice.drink?.isFavourite == true ? "Unfavourite" : "Favourite", systemImage: choice.drink?.isFavourite == true ? "star.fill" : "star", action: onStar)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(choice.drink?.isFavourite == true ? Color.grog : .secondary)
                    .sensoryFeedback(.selection, trigger: choice.drink?.isFavourite)
            }
        }
    }
}

/// A row of pill buttons for picking one of a few values.
struct ChipRow<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button(label(option)) { selection = option }
                        .buttonStyle(.bordered)
                        .tint(option == selection ? .grog : .secondary)
                        .fontWeight(option == selection ? .semibold : .regular)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}
