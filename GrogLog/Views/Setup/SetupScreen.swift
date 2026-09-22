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
                Text("Pick how fast to cut down and get a daily and weekly unit budget.\n\nGrogLog doesn't recommend a plan — it keeps count of the one you set. Cutting down is safest with medical guidance, and stopping suddenly when you're dependent can be dangerous. Talk to your GP or an alcohol service about the right pace for you.")
            }

            Section {
                NavigationLink("Drinks") { DrinksScreen() }
                Button("Reset prices to the catalogue", systemImage: "sterlingsign.arrow.trianglehead.counterclockwise.rotate.90") { resettingPrices = true }
                Picker("Day ends at", selection: $prefs.rolloverHour) {
                    ForEach(0..<9) { Text(ledger.clock.hourLabel(Double($0 - prefs.rolloverHour))).tag($0) }
                }
                Picker("Currency", selection: $prefs.currency) {
                    ForEach(["GBP", "EUR", "USD"], id: \.self) { Text($0) }
                }
            } footer: {
                Text("Drinks after midnight count towards the night before, until the day ends.")
            }
            .onChange(of: prefs.rolloverHour) { database.logbook(prefs).rebuild(reassigningDays: true) }

            if Health.isAvailable {
                Section {
                    Toggle("Copy to Health", isOn: $prefs.mirrorsToHealth)
                } footer: {
                    Text("Drinks and calories go into Health as you log them, converted to the standard drinks Health counts — nearly two units each. Turning it off takes GrogLog's entries back out.")
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
                Text("Everything stays on this phone. Importing merges — nothing already here is overwritten.")
            }

            #if DEBUG
            Section {
                Toggle("Demo mode", isOn: $demoMode)
                Button("Rebuild daily totals") { database.logbook(prefs).rebuild() }
            } header: {
                Text("Developer")
            } footer: {
                Text("Demo mode swaps in four months of sample data, held in memory. Your own log is left alone and comes back when you switch it off.")
            }
            #endif
        }
        .navigationTitle("Setup")
        .sheet(isPresented: $settingGoal) { GoalSheet(goal: prefs.goal) }
        .confirmationDialog("Reset prices to the catalogue?", isPresented: $resettingPrices, titleVisibility: .visible) {
            Button("Reset prices", role: .destructive) { pricesReset = database.logbook(prefs).resetPrices() }
        } message: {
            Text("Every drink and Log tile goes back to what the catalogue charges, losing any price you set yourself. Drinks already logged keep what they cost at the time.")
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
        let every = Goal.periods.first { $0.days == goal.periodDays }?.label ?? "\(goal.periodDays) days"
        let amount = { (value: Double) in value.formatted(.number.precision(.fractionLength(0...1))) }
        // A linear taper comes off in units, not in shares, and this row could only ever say a share.
        return goal.taper == .linear
            ? "−\(amount(goal.reductionUnits)) u/\(every)"
            : "−\(amount(goal.reductionPercent))%/\(every)"
    }
}
