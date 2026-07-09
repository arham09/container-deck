import SwiftUI

/// Registry logins (spec §25). Entry schema is unverified (empty on the
/// reference install), so entries render their display string with raw JSON
/// available. Styled to the Harbor design.
struct RegistriesView: View {
    @Environment(AppEnvironment.self) private var env

    // Leading icon-tile column width, shared by the header and the rows.
    private enum Col {
        static let icon: CGFloat = 26
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Registries")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.deckText)
                Text("\(env.resources.registries.items.count) logins")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.deckTextDim)
            }
            rowList
                .resourcePhase(
                    env.resources.registries,
                    label: "Registry Logins",
                    symbol: "building.columns",
                    emptyDescription: "Registries you log in to appear here."
                )
                .deckCard()
        }
        .padding(.horizontal, DeckMetrics.sectionPaddingH)
        .padding(.vertical, DeckMetrics.sectionPaddingV)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.deckBg)
        .toolbar {
            ToolbarItemGroup {
                Button("Log In", systemImage: "person.badge.key") {
                    env.imageActions.loginSheetPresented = true
                }
                .disabled(env.power.state != .running)
                RefreshToolbarButton()
            }
        }
        .modifier(ImageActionDialogs())
        .navigationTitle("Registries")
        .task {
            if env.resources.registries.phase == .initial {
                await env.resources.registries.refresh()
            }
        }
    }

    private var rowList: some View {
        VStack(spacing: 0) {
            if !env.resources.registries.items.isEmpty {
                columnHeader
                Rectangle().fill(Color.deckBorder).frame(height: DeckMetrics.hairline)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(env.resources.registries.items) { entry in
                        registryRow(entry)
                        Rectangle().fill(Color.deckBorder)
                            .frame(height: DeckMetrics.hairline)
                            .padding(.leading, DeckList.padH)
                    }
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: DeckList.colSpacing) {
            Color.clear.frame(width: Col.icon, height: 1)
            DeckColHeader("Registry")
            DeckColHeader("Details")
        }
        .padding(.horizontal, DeckList.padH)
        .frame(height: 34)
    }

    private func registryRow(_ entry: RegistryEntry) -> some View {
        DeckHoverRow(onOpen: nil) {
            HStack(spacing: DeckList.colSpacing) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.deckCard2)
                    .frame(width: Col.icon, height: Col.icon)
                    .overlay(
                        Image(systemName: "building.columns")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.deckTextFaint)
                    )
                Text(entry.display)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.deckText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .deckColumn()
                    .deckTooltip(entry.display)
                Text(entry.rawJSON)
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(Color.deckTextFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .deckColumn()
                    .deckTooltip(entry.rawJSON)
            }
        } actions: {
            DeckRowIconButton(systemImage: "doc.on.doc", help: "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.display, forType: .string)
            }
            DeckRowIconButton(
                systemImage: "rectangle.portrait.and.arrow.right", help: "Log Out…", tint: .deckRed
            ) {
                env.imageActions.pendingLogout = entry
            }
        }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.display, forType: .string)
            }
            Button("Log Out…", role: .destructive) {
                env.imageActions.pendingLogout = entry
            }
        }
    }
}

/// Builder status and build history (spec §24), styled to the Harbor design.
struct BuildsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Builds")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.deckText)
                builderSection
                historySection
            }
            .padding(.horizontal, DeckMetrics.sectionPaddingH)
            .padding(.vertical, DeckMetrics.sectionPaddingV)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.deckBg)
        .toolbar {
            ToolbarItemGroup {
                Button("Build Image", systemImage: "hammer") {
                    env.imageActions.buildSheetPresented = true
                }
                .disabled(env.power.state != .running)
                RefreshToolbarButton()
            }
        }
        .modifier(ImageActionDialogs())
        .navigationTitle("Builds")
    }

    @ViewBuilder
    private var builderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let builder = env.resources.builder {
                HStack(spacing: 9) {
                    StatusDot(color: builder.isRunning ? .deckGreen : .deckTextFaint)
                    Text("BuildKit Builder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.deckText)
                    Text(builder.isRunning ? "Running" : "Not Running")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.deckTextDim)
                    Spacer()
                    if builder.isRunning {
                        Button("Stop") { env.imageActions.stopBuilder() }
                        Button("Delete", role: .destructive) { env.imageActions.deleteBuilder() }
                    } else {
                        Button("Start Builder") { env.imageActions.startBuilder() }
                            .buttonStyle(.borderedProminent)
                            .disabled(env.power.state != .running)
                    }
                }
                .controlSize(.small)
                .disabled(env.imageActions.builderBusy)
                if builder.isRunning {
                    JSONInspectView(rawJSON: builder.rawJSON, suggestedFileName: "builder-status.json")
                        .frame(minHeight: 160, maxHeight: 260)
                } else {
                    Text("The builder starts automatically with the first image build; starting it ahead of time pulls the BuildKit image once.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.deckTextDim)
                }
            } else {
                Label("Builder status loads when Apple Container is running.", systemImage: "info.circle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.deckTextDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deckCard(padded: true)
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Build History")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.deckText)
                Spacer()
                if !env.imageActions.buildHistory.records.isEmpty {
                    Button("Clear") { env.imageActions.buildHistory.clear() }
                        .controlSize(.small)
                }
            }
            let records = env.imageActions.buildHistory.records
            if records.isEmpty {
                Text("Builds you run appear here and survive restarts.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.deckTextDim)
            } else {
                ForEach(records) { record in
                    HStack(spacing: 9) {
                        Image(systemName: record.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(record.succeeded ? Color.deckGreen : Color.deckRed)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.tag)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.deckText)
                            Text(record.contextDirectory)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.deckTextFaint)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(record.startedAt, format: .dateTime.day().month().hour().minute())
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(Color.deckTextFaint)
                        Text(ResourceFormatters.duration(record.duration))
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(Color.deckTextFaint)
                    }
                    .padding(.vertical, 3)
                    .contextMenu {
                        Button("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.redactedCommand, forType: .string)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deckCard(padded: true)
    }
}

/// Networks (spec §27). On the verified installation the `container network`
/// subcommand requires a plugin that is not installed — reported honestly.
struct NetworksView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            switch env.resources.capabilities?.networks {
            case .unavailable(let reason):
                ContentUnavailableView {
                    Label("Networks Unavailable", systemImage: "network.slash")
                } description: {
                    Text(reason)
                }
            case .supported, .supportedWithLimitations, .experimental:
                ContentUnavailableView {
                    Label("Networks", systemImage: "network")
                } description: {
                    Text("Network browsing is pending schema verification for the installed CLI version.")
                }
            case nil:
                ContentUnavailableView {
                    Label("Networks", systemImage: "network")
                } description: {
                    Text("Network availability is checked while Apple Container is running.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.deckBg)
        .toolbar { RefreshToolbarButton() }
        .navigationTitle("Networks")
    }
}

struct RegistriesView_Previews: PreviewProvider {
    static var previews: some View {
        RegistriesView()
            .environment(AppEnvironment.preview(running: true))
            .frame(width: 800, height: 500)
    }
}
