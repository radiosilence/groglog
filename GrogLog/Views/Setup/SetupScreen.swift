import SwiftData
import SwiftUI

struct SetupScreen: View {
    let ledger: Ledger
    @Environment(Prefs.self) private var prefs
    @Environment(\.modelContext) private var context
    @State private var importing = false
    @AppStorage("demoMode") private var demoMode = false
    @State private var importResult: String?

    var body: some View {
        @Bindable var prefs = prefs

        Form {
            GoalEditor(ledger: ledger)

            Section {
                NavigationLink("Drinks") { DrinksScreen() }
                Picker("Day ends at", selection: $prefs.rolloverHour) {
                    ForEach(0..<9) { Text(ledger.clock.hourLabel(Double($0 - prefs.rolloverHour))).tag($0) }
                }
                Picker("Currency", selection: $prefs.currency) {
                    ForEach(["GBP", "EUR", "USD"], id: \.self) { Text($0) }
                }
            } footer: {
                Text("Drinks after midnight count towards the night before, until the day ends.")
            }
            .onChange(of: prefs.rolloverHour) { context.logbook(prefs).rebuild(reassigningDays: true) }

            Section {
                ShareLink(item: ExportFile(kind: .markdown, container: context.container), preview: SharePreview("GrogLog log")) {
                    Label("Export for an LLM (Markdown)", systemImage: "text.bubble")
                }
                ShareLink(item: ExportFile(kind: .json, container: context.container), preview: SharePreview("GrogLog backup")) {
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
                Button("Rebuild daily totals") { context.logbook(prefs).rebuild() }
            } header: {
                Text("Developer")
            } footer: {
                Text("Demo mode swaps in four months of sample data, held in memory. Your own log is left alone and comes back when you switch it off.")
            }
            #endif
        }
        .navigationTitle("Setup")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let added = try Exporter.restore(Data(contentsOf: url), into: context, prefs: prefs)
                importResult = "Imported \(added) drinks."
            } catch {
                importResult = "Import failed: \(error.localizedDescription)"
            }
        }
        .alert(importResult ?? "", isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } })) {}
    }
}
