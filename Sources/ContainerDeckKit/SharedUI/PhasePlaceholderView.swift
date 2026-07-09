import SwiftUI

/// Honest placeholder for sections whose functionality arrives in a later
/// phase. No fake data, no simulated controls (spec §11).
struct PhasePlaceholderView: View {
    let item: SidebarItem

    var body: some View {
        ContentUnavailableView {
            Label(item.title, systemImage: item.symbolName)
        } description: {
            if let phase = item.plannedPhase {
                Text("\(item.title) arrives in Phase \(phase). Phase 0 provides the application shell and Apple Container power control.")
            } else {
                Text("\(item.title) is not available yet.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.deckBg)
        .navigationTitle(item.title)
    }
}

struct PhasePlaceholderView_Previews: PreviewProvider {
    static var previews: some View {
        PhasePlaceholderView(item: .containers)
            .frame(width: 700, height: 500)
    }
}
