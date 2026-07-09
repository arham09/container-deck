import SwiftUI

/// Images list (spec §23 read-only subset). Pull/tag/delete arrive in Phase 3.
struct ImagesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var search = ""
    @State private var detail: ImageDetails?
    @State private var detailError: String?

    private var rows: [ImageSummary] {
        let base = env.resources.images.items
        let filtered = search.isEmpty ? base : base.filter {
            $0.reference.localizedCaseInsensitiveContains(search)
        }
        return filtered.sorted { $0.reference.localizedStandardCompare($1.reference) == .orderedAscending }
    }

    private var totalSizeText: String {
        let total = env.resources.images.items.compactMap(\.sizeBytes).reduce(0, +)
        return ResourceFormatters.bytes(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            rowList
                .resourcePhase(
                    env.resources.images,
                    label: "Images",
                    symbol: "opticaldisc",
                    emptyDescription: "Pulled and built images appear here."
                )
                .deckCard()
        }
        .padding(.horizontal, DeckMetrics.sectionPaddingH)
        .padding(.vertical, DeckMetrics.sectionPaddingV)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.deckBg)
        .searchable(text: $search, placement: .toolbar, prompt: "Reference")
        .inspector(isPresented: detailPresented) {
            detailView
                .inspectorColumnWidth(min: 320, ideal: 380)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Pull Image", systemImage: "square.and.arrow.down") {
                    env.imageActions.pullSheetPresented = true
                }
                .disabled(env.power.state != .running)
                .help("Pull an image from a registry")
                Button("Load Archive", systemImage: "tray.and.arrow.down") {
                    loadArchive()
                }
                .disabled(env.power.state != .running)
                .help("Load images from an OCI tar archive")
                Button("Prune", systemImage: "trash.slash") {
                    env.imageActions.pendingPrune = true
                }
                .disabled(env.power.state != .running)
                .help("Remove dangling images")
                RefreshToolbarButton()
            }
        }
        .modifier(ImageActionDialogs())
        .navigationTitle("Images")
        .task {
            if env.resources.images.phase == .initial {
                await env.resources.images.refresh()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Images")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.deckText)
            Text("\(env.resources.images.items.count) images · \(totalSizeText) total")
                .font(.system(size: 13))
                .foregroundStyle(Color.deckTextDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Column widths shared by the header and the rows so they line up.
    private enum Col {
        static let icon: CGFloat = 26
        static let tag: CGFloat = 118
        static let arch: CGFloat = 148
        static let size: CGFloat = 76
        static let created: CGFloat = 104
    }

    private var rowList: some View {
        VStack(spacing: 0) {
            if !env.resources.images.items.isEmpty {
                columnHeader
                Rectangle().fill(Color.deckBorder).frame(height: DeckMetrics.hairline)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { image in
                        imageRow(image)
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
            DeckColHeader("Repository")
            DeckColHeader("Tag", width: Col.tag)
            DeckColHeader("Architectures", width: Col.arch)
            DeckColHeader("Size", width: Col.size, alignment: .trailing)
            DeckColHeader("Created", width: Col.created)
        }
        .padding(.horizontal, DeckList.padH)
        .frame(height: 34)
    }

    private func imageRow(_ image: ImageSummary) -> some View {
        let disabled = env.power.state != .running
        return DeckHoverRow(
            onOpen: { openDetail(image) }
        ) {
            HStack(spacing: DeckList.colSpacing) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.deckCard2)
                    .frame(width: Col.icon, height: Col.icon)
                    .overlay(
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.deckTextFaint)
                    )
                Text(image.repository)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.deckText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .deckColumn()
                    .deckTooltip(image.repository)
                Text(image.tag)
                    .font(.system(size: 12.5).monospaced())
                    .foregroundStyle(Color.deckTextDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .deckColumn(width: Col.tag)
                    .deckTooltip(image.tag)
                Text(image.architecturesText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.deckTextFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .deckColumn(width: Col.arch)
                    .deckTooltip(image.architecturesText)
                Text(image.sizeText)
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Color.deckTextDim)
                    .deckColumn(width: Col.size, alignment: .trailing)
                Text(image.createdText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.deckTextFaint)
                    .lineLimit(1)
                    .deckColumn(width: Col.created)
            }
        } actions: {
            DeckRowIconButton(systemImage: "play.fill", help: "Run…", tint: .deckGreen, disabled: disabled) {
                runImage(image)
            }
            DeckRowIconButton(systemImage: "trash", help: "Delete…", tint: .deckRed) {
                env.imageActions.pendingDelete = image
            }
            DeckRowMenu { imageMenu(for: image) }
        }
        .contextMenu { imageMenu(for: image) }
    }

    @ViewBuilder
    private func imageMenu(for image: ImageSummary) -> some View {
        Button("Run…") { runImage(image) }
            .disabled(env.power.state != .running)
        Divider()
        Button("Tag…") { env.imageActions.tagTarget = image }
        Button("Save…") { saveImage(image) }
        Button("Inspect") { openDetail(image) }
        Button("Copy Reference") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(image.reference, forType: .string)
        }
        Divider()
        Button("Delete…", role: .destructive) {
            env.imageActions.pendingDelete = image
        }
    }

    private func runImage(_ image: ImageSummary) {
        env.containerActions.prefillImage = image.reference
        env.router.selection = .containers
        env.containerActions.runFormPresented = true
    }

    private func saveImage(_ image: ImageSummary) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(image.tag).tar"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        env.imageActions.save(image: image, to: url.path)
    }

    private func loadArchive() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        env.imageActions.load(from: url.path)
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

    private func openDetail(_ image: ImageSummary) {
        detail = nil
        detailError = nil
        Task {
            do {
                detail = try await env.engine.inspectImage(reference: image.reference)
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
                    Text(detail.summary.reference)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.deckText)
                        .textSelection(.enabled)
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Size", value: detail.summary.sizeText)
                        LabeledContent("Created", value: detail.summary.createdText)
                        LabeledContent("Architectures", value: detail.summary.architecturesText)
                        if let digest = detail.summary.digest {
                            LabeledContent("Digest") {
                                Text(digest)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .lineLimit(1)
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
                        suggestedFileName: "\(detail.summary.tag)-inspect.json"
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

extension ImageSummary {
    var sizeText: String { sizeBytes.map { ResourceFormatters.bytes($0) } ?? "–" }
    var createdText: String {
        createdAt.map { $0.formatted(.relative(presentation: .named)) } ?? "–"
    }
    var architecturesText: String {
        architectures.isEmpty ? "–" : architectures.joined(separator: ", ")
    }
}

struct ImagesView_Previews: PreviewProvider {
    static var previews: some View {
        ImagesView()
            .environment(AppEnvironment.preview(running: true))
            .frame(width: 980, height: 620)
    }
}
