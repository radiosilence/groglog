import SwiftData
import SwiftUI

struct SetupScreen: View {
    let ledger: Ledger
    @Environment(Prefs.self) private var prefs
    @Environment(\.modelContext) private var context
    @State private var importing = false
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
            Section("Developer") {
                Button("Load sample data") { Seed.sample(context, prefs: prefs) }
                Button("Erase all history", role: .destructive) { Seed.eraseHistory(context) }
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
