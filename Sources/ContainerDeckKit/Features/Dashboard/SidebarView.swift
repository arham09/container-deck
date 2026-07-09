import SwiftUI

/// Sidebar navigation (spec §15), styled to the Harbor design: grouped rows
/// with rounded hover/selection, count pills, an honest disk readout, and the
/// pinned power control. Custom rows (not `List(.sidebar)`) so we control the
/// selection/hover treatment; selection still drives `router.selection`.
struct SidebarView: View {
    @Environment(AppEnvironment.self) private var env

    private struct NavGroup {
        let title: String
        let items: [SidebarItem]
    }

    private let groups: [NavGroup] = [
        NavGroup(title: "System", items: [.dashboard, .activity]),
        NavGroup(title: "Containers", items: [.containers, .images, .builds]),
        NavGroup(title: "Resources", items: [.volumes, .networks, .registries]),
        NavGroup(title: "Linux", items: [.machines]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        DeckSectionLabel(group.title)
                            .padding(.horizontal, 10)
                            .padding(.top, index == 0 ? 4 : 14)
                            .padding(.bottom, 5)
                        ForEach(group.items) { item in
                            SidebarNavRow(
                                item: item,
                                selected: (env.router.selection ?? .dashboard) == item,
                                count: count(for: item),
                                accent: env.settings.accent.color
                            ) {
                                env.router.selection = item
                            }
                        }
                    }

                    if let disk = env.resources.disk {
                        diskCard(disk)
                            .padding(.top, 16)
                            .padding(.horizontal, 4)
                    }

                    settingsRow
                        .padding(.top, 8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            SidebarPowerControl()
        }
        .background(Color.deckSidebar)
        .navigationTitle("ContainerDeck")
    }

    private var settingsRow: some View {
        SettingsLink {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .frame(width: 20)
                    .foregroundStyle(Color.deckTextDim)
                Text("Settings")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.deckText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Honest disk readout (`system df`) — the one metric we have real data for.
    /// No capacity denominator exists, so this is a value pair, not a fake gauge.
    private func diskCard(_ disk: DiskUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            diskRow("Disk", ResourceFormatters.bytes(disk.totalBytes))
            diskRow("Reclaimable", ResourceFormatters.bytes(disk.reclaimableBytes))
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.deckCard2)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.deckBorder, lineWidth: DeckMetrics.hairline)
                )
        )
    }

    private func diskRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.deckTextDim)
            Spacer()
            Text(value)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color.deckText)
        }
    }

    /// Counters only when real (or mock) data is loaded — no fabricated numbers.
    private func count(for item: SidebarItem) -> Int? {
        guard env.resources.hasLoadedResources else { return nil }
        switch item {
        case .containers: return env.resources.containers.items.count
        case .images: return env.resources.images.items.count
        case .volumes: return env.resources.volumes.items.count
        case .machines: return env.resources.machines.items.count
        default: return nil
        }
    }
}

private struct SidebarNavRow: View {
    let item: SidebarItem
    let selected: Bool
    let count: Int?
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 15))
                    .frame(width: 20)
                    .foregroundStyle(selected ? accent : Color.deckTextDim)
                Text(item.title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.deckText)
                Spacer(minLength: 0)
                if let count {
                    DeckChip("\(count)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DeckMetrics.rowRadius)
                    .fill(selected ? accent.opacity(0.16) : (hovering ? Color.deckHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            Text("Detail")
        }
        .environment(AppEnvironment.preview(running: true))
        .frame(width: 900, height: 620)
    }
}
