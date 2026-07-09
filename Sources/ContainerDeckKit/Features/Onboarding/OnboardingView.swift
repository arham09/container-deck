import SwiftUI
import UniformTypeIdentifiers

/// Shown when no Apple Container binary was found: installation guidance
/// plus manual binary selection and re-detection.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingFilePicker = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 44))
                .foregroundStyle(Color.deckTextFaint)
            Text("Apple Container Is Not Installed")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.deckText)
            Text(
                """
                ContainerDeck manages an existing Apple Container installation. \
                It could not find the `container` command-line tool on this Mac.
                """
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.deckTextDim)
            .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Install with Homebrew: `brew install --cask container`")
                } icon: {
                    Image(systemName: "terminal")
                }
                Label {
                    Text("Or download the installer from the [Apple Container releases page](https://github.com/apple/container/releases).")
                } icon: {
                    Image(systemName: "arrow.down.circle")
                }
                Label {
                    Text("Requires a Mac with Apple silicon.")
                } icon: {
                    Image(systemName: "cpu")
                }
            }
            .font(.callout)
            .foregroundStyle(Color.deckTextDim)
            .padding(16)
            .background(Color.deckCard2, in: RoundedRectangle(cornerRadius: DeckMetrics.controlRadius))

            HStack(spacing: 10) {
                Button("Re-detect") {
                    Task { await env.power.redetectBinary() }
                }
                Button("Locate Binary…") {
                    showingFilePicker = true
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.deckBg)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.unixExecutable, .executable, .item]
        ) { result in
            if case .success(let url) = result {
                Task { await env.power.adoptBinary(at: url) }
            }
        }
        .navigationTitle("Dashboard")
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environment(AppEnvironment.preview(running: false))
            .frame(width: 900, height: 620)
    }
}
