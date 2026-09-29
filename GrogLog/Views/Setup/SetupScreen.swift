import GRDBQuery
import SwiftUI

struct SetupScreen: View {
    let ledger: Ledger
    @Environment(Prefs.self) private var prefs
    @Environment(\.databaseContext) private var database
    @State private var importing = false
    @AppStorage("demoMode") private var demoMode = false
    @State private var importResult: String?
    @State private var settingGoal = false
    @State private var resettingPrices = false
    @State private var pricesReset: Int?

    var body: some View {
        @Bindable var prefs = prefs

        Form {
            Section {
                Button { settingGoal = true } label: {
                    LabeledContent {
                        Text(goalSummary).foregroundStyle(Color.grog)
                    } label: {
                        Text("Goal").foregroundStyle(Color.primary)
                    }
                }
            } footer: {
                // The guidance the pace limits come from assumes a clinician judged the person suitable
                // and reviews them as they go. This does neither, and shouldn't be read as if it did.
                Text("Choose a rate of reduction to set a daily and weekly budget.\n\nGrogLog does not provide medical advice. It is intended to help you follow a plan agreed with your GP or alcohol service. If you are dependent on alcohol, do not stop suddenly without medical support.")
            }

            Section {
                NavigationLink("Drinks") { DrinksScreen() }
                Button("Reset prices to the catalogue", systemImage: "sterlingsign.arrow.trianglehead.counterclockwise.rotate.90") { resettingPrices = true }
                Picker("Day ends at", selection: $prefs.rolloverHour) {
                    ForEach(0..<9) { Text(ledger.clock.hourLabel(Double($0 - prefs.rolloverHour))).tag($0) }
                }
                Picker("Currency", selection: $prefs.currency) {
                    ForEach(Rates.currencies, id: \.self) { Text($0) }
                }
            } footer: {
                Text("Drinks after midnight count towards the evening before.")
            }
            // Every entry re-dayed and every day re-totted: seconds on a long log, and not while a picker settles.
            .onChange(of: prefs.rolloverHour) {
                let logbook = database.logbook(prefs)
                Task.detached { logbook.rebuild(reassigningDays: true) }
            }

            if Health.isAvailable {
                Section {
                    Toggle("Copy to Health", isOn: $prefs.mirrorsToHealth)
                } footer: {
                    Text("Your drinks and calories are added to Health as you log them. Health measures alcohol in US standard drinks, each about 1.8 UK units. Turning this off removes them.")
                }
                .onChange(of: prefs.mirrorsToHealth) { _, on in
                    let logbook = database.logbook(prefs)
                    Task {
                        if on {
                            prefs.mirrorsToHealth = await Health.shared.enable(logbook)
                        } else {
                            await Health.shared.disable()
                        }
                    }
                }

                Section {
                    Toggle("Heart readings from Health", isOn: $prefs.readsHeart)
                } footer: {
                    Text("Shows your heart rate during sleep, resting heart rate and HRV on Reports, alongside what you drank the night before. Requires a watch that records them in Health.")
                }
                .onChange(of: prefs.readsHeart) { _, on in
                    guard on else { return }
                    Task { prefs.readsHeart = await Health.shared.allowReading() }
                }

                Section {
                    Toggle("Sleep from Health", isOn: $prefs.readsSleep)
                } footer: {
                    Text("Shows each night's sleep by stage on Reports, alongside what you drank the evening before. Requires a watch that records sleep in Health.")
                }
                .onChange(of: prefs.readsSleep) { _, on in
                    guard on else { return }
                    Task { prefs.readsSleep = await Health.shared.allowReading() }
                }
            }

            Section {
                Toggle("iCloud sync", isOn: $prefs.syncsWithICloud)
            } footer: {
                Text("Keeps your log in your own iCloud account, so it comes back on a new iPhone. Nobody else, including GrogLog's developer, can read it. Turning this off stops syncing and deletes nothing.")
            }

            Section {
                ShareLink(item: ExportFile(kind: .markdown, reader: try! database.reader, prefs: prefs), preview: SharePreview("GrogLog log")) {
                    Label("Export for an LLM (Markdown)", systemImage: "text.bubble")
                }
                ShareLink(item: ExportFile(kind: .json, reader: try! database.reader, prefs: prefs), preview: SharePreview("GrogLog backup")) {
                    Label("Export backup (JSON)", systemImage: "curlybraces")
                }
                Button("Import backup", systemImage: "square.and.arrow.down") { importing = true }
            } header: {
                Text("Data")
            } footer: {
                Text(prefs.syncsWithICloud ? "Importing a backup adds to your log and never overwrites it." : "Your data stays on this phone. Importing a backup adds to your log and never overwrites it.")
            }

            #if DEBUG
            Section {
                Toggle("Demo mode", isOn: $demoMode)
                Button("Rebuild daily totals") {
                    let logbook = database.logbook(prefs)
                    Task.detached { logbook.rebuild() }
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("Replaces your log with four months of sample data. Your own log returns when this is turned off.")
            }
            #endif
        }
        .navigationTitle("Setup")
        .sheet(isPresented: $settingGoal) { GoalSheet(goal: prefs.goal) }
        .confirmationDialog("Reset prices to the catalogue?", isPresented: $resettingPrices, titleVisibility: .visible) {
            Button("Reset prices", role: .destructive) {
                let logbook = database.logbook(prefs)
                Task { pricesReset = await Task.detached { logbook.resetPrices() }.value }
            }
        } message: {
            Text("Every drink and Log tile returns to its catalogue price, including any you have changed. Drinks already logged keep the price you paid.")
        }
        .alert("Prices reset", isPresented: Binding(get: { pricesReset != nil }, set: { if !$0 { pricesReset = nil } })) {
            Button("OK") { pricesReset = nil }
        } message: {
            Text(pricesReset == 0 ? "Everything already matched the catalogue." : "^[\(pricesReset ?? 0) price](inflect: true) changed.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let added = try Exporter.restore(Data(contentsOf: url), writer: try database.writer, prefs: prefs)
                importResult = "Imported \(added) drinks."
            } catch {
                importResult = "Import failed: \(error.localizedDescription)"
            }
        }
        .alert(importResult ?? "", isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } })) {}
    }

    private var goalSummary: String {
        let goal = prefs.goal
        guard goal.isEnabled else { return "Off" }
        // The picker's own labels, so the row and the control it summarises can't drift apart.
        // A stepped taper has no period of its own; it's whichever rung the budget has reached today.
        let days = ledger.pace(on: ledger.today, goal: goal)
        let every = Goal.periods.first { $0.days == days }?.label ?? "\(days) days"
        let amount = { (value: Double) in value.formatted(.number.precision(.fractionLength(0...1))) }
        // A linear taper comes off in units, not in shares, and this row could only ever say a share.
        return goal.taper == .linear
            ? "−\(amount(goal.reductionUnits)) u/\(every)"
            : "−\(amount(goal.reductionPercent))%/\(every)"
    }
}
