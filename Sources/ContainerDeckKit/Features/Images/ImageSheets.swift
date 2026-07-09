import SwiftUI

/// Pull Image sheet (spec §23).
struct PullImageSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var reference = ""
    @State private var platform = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pull Image")
                .font(.headline)
            Form {
                TextField("Image", text: $reference, prompt: Text("ghcr.io/org/app:latest"))
                TextField("Platform", text: $platform, prompt: Text("Automatic"))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Pull") {
                    env.imageActions.pull(reference: reference.trimmingCharacters(in: .whitespaces), platform: platform)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(reference.trimmingCharacters(in: .whitespaces).isEmpty
                    || env.power.state != .running)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

/// Tag Image sheet.
struct TagImageSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let source: ImageSummary
    @State private var target = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tag \(source.reference)")
                .font(.headline)
            TextField("New reference", text: $target, prompt: Text("my-app:v2"))
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Tag") {
                    env.imageActions.tag(source: source, target: target.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(target.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

/// Build Image sheet (spec §23) with verified flags and a redacted preview.
struct BuildImageSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = BuildConfiguration()
    @State private var showingContextPicker = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField("Context", text: $configuration.contextDirectory, prompt: Text("/Users/…/my-app"))
                        Button("Choose…") { showingContextPicker = true }
                    }
                    TextField("Dockerfile", text: $configuration.dockerfilePath, prompt: Text("Optional — defaults to Dockerfile in context"))
                    TextField("Tag", text: $configuration.tag, prompt: Text("my-app:latest"))
                    TextField("Platform", text: $configuration.platform, prompt: Text("Optional, e.g. linux/arm64"))
                }
                Section("Options") {
                    TextField("Target stage", text: $configuration.target, prompt: Text("Optional"))
                    Toggle("No cache", isOn: $configuration.noCache)
                    Toggle("Pull latest base image", isOn: $configuration.pullBaseImage)
                    TextField("Builder CPUs", text: $configuration.cpus, prompt: Text("Optional"))
                    TextField("Builder memory", text: $configuration.memory, prompt: Text("Optional, e.g. 4G"))
                }
                Section("Build Arguments") {
                    ForEach($configuration.buildArguments) { $argument in
                        HStack {
                            TextField("Key", text: $argument.key)
                                .frame(width: 140)
                            TextField("Value", text: $argument.value)
                            Button(role: .destructive) {
                                configuration.buildArguments.removeAll { $0.id == argument.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Add Build Argument", systemImage: "plus") {
                        configuration.buildArguments.append(KeyValueEntry())
                    }
                    Text("Build-argument values are redacted in previews and history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if env.settings.showGeneratedCommands {
                    Text(preview)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Build") {
                    env.imageActions.build(configuration)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(configuration.tag.isEmpty || configuration.contextDirectory.isEmpty
                    || env.power.state != .running)
            }
            .padding(12)
        }
        .frame(minWidth: 560, minHeight: 460)
        .fileImporter(isPresented: $showingContextPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                configuration.contextDirectory = url.path
            }
        }
    }

    private var preview: String {
        guard let built = try? BuildArgumentBuilder.build(configuration) else {
            return "container build …"
        }
        return "container " + built.redactedArguments.joined(separator: " ")
    }
}

/// Registry login sheet (spec §25): password over stdin, never stored.
struct RegistryLoginSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Registry Login")
                .font(.headline)
            Form {
                TextField("Server", text: $server, prompt: Text("ghcr.io"))
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
            }
            Text("The password is sent to the CLI over stdin and is never stored or logged by ContainerDeck. Apple Container manages its own credential storage.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Log In") {
                    env.imageActions.login(
                        server: server.trimmingCharacters(in: .whitespaces),
                        username: username,
                        password: password
                    )
                    password = ""
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(server.isEmpty || username.isEmpty || password.isEmpty
                    || env.power.state != .running)
            }
        }
        .padding(16)
        .frame(width: 440)
    }
}

/// Alerts and sheets shared by the image/build/registry screens.
struct ImageActionDialogs: ViewModifier {
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        @Bindable var actions = env.imageActions
        content
            .sheet(isPresented: $actions.pullSheetPresented) { PullImageSheet() }
            .sheet(isPresented: $actions.buildSheetPresented) { BuildImageSheet() }
            .sheet(isPresented: $actions.loginSheetPresented) { RegistryLoginSheet() }
            .sheet(item: $actions.tagTarget) { image in
                TagImageSheet(source: image)
            }
            .alert(
                "Delete image?",
                isPresented: Binding(
                    get: { actions.pendingDelete != nil },
                    set: { if !$0 { actions.pendingDelete = nil } }
                ),
                presenting: actions.pendingDelete
            ) { _ in
                Button("Delete", role: .destructive) { actions.confirmDelete() }
                Button("Cancel", role: .cancel) { actions.pendingDelete = nil }
            } message: { image in
                Text("“\(image.reference)” will be removed, freeing its disk space. Containers created from it are not affected.")
            }
            .alert("Prune unused images?", isPresented: $actions.pendingPrune) {
                Button("Prune", role: .destructive) { actions.confirmPrune() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Dangling images (not referenced by any tag or container) will be permanently removed. The operation reports how much space was reclaimed.")
            }
            .alert(
                "Log out of registry?",
                isPresented: Binding(
                    get: { actions.pendingLogout != nil },
                    set: { if !$0 { actions.pendingLogout = nil } }
                ),
                presenting: actions.pendingLogout
            ) { _ in
                Button("Log Out", role: .destructive) { actions.confirmLogout() }
                Button("Cancel", role: .cancel) { actions.pendingLogout = nil }
            } message: { entry in
                Text("Credentials for \(entry.display) will be removed from Apple Container.")
            }
            .alert(
                actions.lastError?.title ?? "Error",
                isPresented: Binding(
                    get: { actions.lastError != nil },
                    set: { if !$0 { actions.lastError = nil } }
                ),
                presenting: actions.lastError
            ) { error in
                Button("Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error.diagnostics, forType: .string)
                }
                Button("OK", role: .cancel) {}
            } message: { error in
                Text("\(error.explanation)\n\n\(error.recommendedAction)")
            }
    }
}
