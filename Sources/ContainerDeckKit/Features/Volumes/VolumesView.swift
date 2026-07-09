import SwiftUI

/// Volumes screen (spec §26), Harbor card grid. "Size" is the provisioned
/// (sparse) size the CLI reports, not current usage. In-use/anonymous badges
/// wait for a verified mount schema, so they are not shown.
struct VolumesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var search = ""
    @State private var selection: VolumeSummary.ID?
    @State private var detail: VolumeDetails?
    @State private var detailError: String?

    private var rows: [VolumeSummary] {
        let base = env.resources.volumes.items
        let filtered = search.isEmpty ? base : base.filter {
            $0.name.localizedCaseInsensitiveContains(search)
        }
        return filtered.sorted(using: KeyPathComparator(\VolumeSummary.name))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2),
                    spacing: 14
                ) {
                    ForEach(rows) { volume in
                        VolumeCard(volume: volume) { openDetail(name: volume.id) }
                    }
                }
            }
            .padding(.horizontal, DeckMetrics.sectionPaddingH)
            .padding(.vertical, DeckMetrics.sectionPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.deckBg)
        .searchable(text: $search, placement: .toolbar, prompt: "Name")
        .resourcePhase(
            env.resources.volumes,
            label: "Volumes",
            symbol: "externaldrive",
            emptyDescription: "Volumes you create appear here."
        )
        .inspector(isPresented: detailPresented) {
            detailView
                .inspectorColumnWidth(min: 320, ideal: 380)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Create Volume", systemImage: "plus") {
                    env.volumeActions.createSheetPresented = true
                }
                .disabled(env.power.state != .running)
                Button("Prune", systemImage: "trash.slash") {
                    env.volumeActions.pendingPrune = true
                }
                .disabled(env.power.state != .running || env.resources.volumes.items.isEmpty)
                .help("Remove volumes with no container references")
                RefreshToolbarButton()
            }
        }
        .modifier(VolumeActionDialogs())
        .navigationTitle("Volumes")
        .task {
            if env.resources.volumes.phase == .initial {
                await env.resources.volumes.refresh()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Volumes")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.deckText)
            Text("\(env.resources.volumes.items.count) volumes")
                .font(.system(size: 13))
                .foregroundStyle(Color.deckTextDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailPresented: Binding<Bool> {
        Binding(
            get: { detail != nil || detailError != nil },
            set: { presented in
                if !presented {
                    detail = nil
                    detailError = nil
                }
            }
        )
    }

    private func openDetail(name: String) {
        selection = name
        detail = nil
        detailError = nil
        Task {
            do {
                detail = try await env.engine.inspectVolume(name: name)
            } catch let error as ContainerEngineError {
                detailError = UserFacingError.make(from: error).explanation
            } catch {
                detailError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(detail.summary.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.deckText)
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Provisioned size", value: detail.summary.sizeText)
                        LabeledContent("Driver", value: detail.summary.driverText)
                        LabeledContent("Format", value: detail.summary.formatText)
                        LabeledContent("Created", value: detail.summary.createdText)
                        if let source = detail.summary.sourcePath {
                            LabeledContent("Source") {
                                Text(source)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .font(.callout)
                    Divider()
                    Text("Inspect")
                        .font(.headline)
                    JSONInspectView(
                        rawJSON: detail.rawJSON,
                        suggestedFileName: "\(detail.summary.name)-inspect.json"
                    )
                    .frame(minHeight: 300)
                }
                .padding(14)
            }
        } else if let detailError {
            ContentUnavailableView {
                Label("Could Not Inspect", systemImage: "exclamationmark.triangle")
            } description: {
                Text(detailError)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct VolumeCard: View {
    @Environment(AppEnvironment.self) private var env
    let volume: VolumeSummary
    let onInspect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.deckCard2)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "externaldrive")
                            .font(.system(size: 15))
                            .foregroundStyle(env.settings.accent.color)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color.deckText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(volume.driverText) · \(volume.sizeText)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.deckTextFaint)
                }
                Spacer(minLength: 0)
                Button {
                    env.volumeActions.pendingDelete = volume
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.deckTextFaint)
                }
                .buttonStyle(.plain)
                .disabled(env.power.state != .running)
                .help("Delete volume")
            }
            if let source = volume.sourcePath {
                Text(source)
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(Color.deckTextDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deckCard(padded: true, hoverHighlight: true)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onInspect)
        .contextMenu {
            Button("Inspect", action: onInspect)
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(volume.id, forType: .string)
            }
            Divider()
            Button("Delete…", role: .destructive) {
                env.volumeActions.pendingDelete = volume
            }
            .disabled(env.power.state != .running)
        }
    }
}

extension VolumeSummary {
    var sizeText: String { sizeBytes.map { ResourceFormatters.bytes($0) } ?? "–" }
    var driverText: String { driver ?? "–" }
    var formatText: String { format ?? "–" }
    var createdText: String {
        createdAt.map { $0.formatted(.relative(presentation: .named)) } ?? "–"
    }
}

struct VolumesView_Previews: PreviewProvider {
    static var previews: some View {
        VolumesView()
            .environment(AppEnvironment.preview(running: true))
            .frame(width: 980, height: 620)
    }
}
