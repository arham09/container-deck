import SwiftUI

/// Run/Create Container form (spec §20): basic fields with progressive
/// disclosure for advanced sections, live redacted command preview, and
/// validation before anything is executed.
struct RunContainerForm: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var configuration = ContainerRunConfiguration()
    @State private var validationMessage: String?
    @State private var savingName = ""
    @State private var showingSavePrompt = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Mode", selection: $configuration.mode) {
                        ForEach(ContainerRunConfiguration.Mode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Image", text: $configuration.image, prompt: Text("postgres:17"))
                    TextField("Name", text: $configuration.name, prompt: Text("Optional"))
                    TextField("Command", text: $configuration.commandLine, prompt: Text("Optional — overrides the image command"))
                    if configuration.mode == .run {
                        Toggle("Run detached", isOn: $configuration.detached)
                        if !configuration.detached {
                            Text("Attached runs stream the container's output into the operation panel until it exits.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Remove after stop", isOn: $configuration.removeAfterStop)
                }

                Section("Ports") {
                    ForEach($configuration.publishedPorts) { $port in
                        HStack {
                            TextField("Host IP", text: $port.hostIP, prompt: Text("any"))
                                .frame(width: 100)
                            TextField("Host", text: $port.hostPort, prompt: Text("8080"))
                                .frame(width: 60)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            TextField("Container", text: $port.containerPort, prompt: Text("80"))
                                .frame(width: 60)
                            Picker("", selection: $port.portProtocol) {
                                ForEach(PublishedPortSpec.PortProtocol.allCases, id: \.self) {
                                    Text($0.rawValue).tag($0)
                                }
                            }
                            .frame(width: 70)
                            removeButton { configuration.publishedPorts.removeAll { $0.id == port.id } }
                        }
                    }
                    Button("Add Port", systemImage: "plus") {
                        configuration.publishedPorts.append(PublishedPortSpec())
                    }
                }

                Section("Environment") {
                    ForEach($configuration.environment) { $entry in
                        HStack {
                            TextField("Key", text: $entry.key)
                                .frame(width: 160)
                            TextField("Value", text: $entry.value)
                            removeButton { configuration.environment.removeAll { $0.id == entry.id } }
                        }
                    }
                    Button("Add Variable", systemImage: "plus") {
                        configuration.environment.append(KeyValueEntry())
                    }
                    TextField("Environment file", text: $configuration.environmentFile, prompt: Text("Optional absolute path"))
                    Text("Values are redacted in previews, logs, and history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Volumes") {
                    ForEach($configuration.mounts) { $mount in
                        HStack {
                            TextField("Host path", text: $mount.source, prompt: Text("/Users/…"))
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            TextField("Container path", text: $mount.target, prompt: Text("/data"))
                            Toggle("RO", isOn: $mount.readOnly)
                                .help("Read-only")
                            removeButton { configuration.mounts.removeAll { $0.id == mount.id } }
                        }
                    }
                    Button("Add Mount", systemImage: "plus") {
                        configuration.mounts.append(MountSpec())
                    }
                }

                Section("Networks") {
                    ForEach($configuration.networks) { $network in
                        HStack {
                            TextField("Network name", text: $network.name, prompt: Text("default"))
                            removeButton { configuration.networks.removeAll { $0.id == network.id } }
                        }
                    }
                    Button("Add Network", systemImage: "plus") {
                        configuration.networks.append(NetworkAttachmentSpec())
                    }
                }

                Section("Resources") {
                    TextField("CPUs", text: $configuration.cpus, prompt: Text("4"))
                    TextField("Memory", text: $configuration.memory, prompt: Text("1G"))
                    TextField("Shared memory (/dev/shm)", text: $configuration.shmSize, prompt: Text("64M"))
                }

                Section("Runtime Options") {
                    TextField("Entrypoint", text: $configuration.entrypoint, prompt: Text("Optional"))
                    TextField("Working directory", text: $configuration.workingDirectory, prompt: Text("Optional absolute path"))
                    TextField("Architecture", text: $configuration.architecture, prompt: Text("arm64"))
                    TextField("Platform", text: $configuration.platform, prompt: Text("linux/arm64"))
                    Toggle("Run init process", isOn: $configuration.useInit)
                    Toggle("Read-only root filesystem", isOn: $configuration.readOnlyRootFilesystem)
                    ForEach($configuration.labels) { $label in
                        HStack {
                            TextField("Label key", text: $label.key)
                                .frame(width: 160)
                            TextField("Value", text: $label.value)
                            removeButton { configuration.labels.removeAll { $0.id == label.id } }
                        }
                    }
                    Button("Add Label", systemImage: "plus") {
                        configuration.labels.append(KeyValueEntry())
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 520, idealHeight: 600)
        .onAppear {
            if let prefill = env.containerActions.prefillImage {
                configuration.image = prefill
                env.containerActions.prefillImage = nil
            }
        }
        .alert("Save Configuration", isPresented: $showingSavePrompt) {
            TextField("Name", text: $savingName)
            Button("Save") {
                env.savedConfigurations.save(name: savingName, configuration: configuration)
                savingName = ""
            }
            .disabled(savingName.isEmpty)
            Button("Cancel", role: .cancel) { savingName = "" }
        } message: {
            Text("Environment variable values are not saved — only keys. Re-enter values after applying.")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if env.settings.showGeneratedCommands {
                ScrollView(.horizontal) {
                    Text(preview)
                        .font(.caption.monospaced())
                        .foregroundStyle(previewIsError ? .red : .secondary)
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                }
            }
            HStack {
                Menu("Saved") {
                    ForEach(env.savedConfigurations.configurations) { saved in
                        Button(saved.name) { configuration = saved.configuration }
                    }
                    if !env.savedConfigurations.configurations.isEmpty {
                        Divider()
                    }
                    Button("Save Current…") { showingSavePrompt = true }
                        .disabled(configuration.image.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .frame(width: 90)
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(configuration.mode == .run ? "Run" : "Create") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(configuration.image.trimmingCharacters(in: .whitespaces).isEmpty
                    || env.power.state != .running)
            }
            if env.power.state != .running {
                Text("Apple Container must be turned on before running containers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var previewIsError: Bool {
        (try? ContainerArgumentBuilder.build(configuration)) == nil
            && !configuration.image.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Live, redacted preview (display only — never executed as a string).
    private var preview: String {
        guard !configuration.image.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "container \(configuration.mode.rawValue) …"
        }
        do {
            let built = try ContainerArgumentBuilder.build(configuration)
            return "container " + built.redactedArguments.joined(separator: " ")
        } catch let error as ContainerEngineError {
            if case .invalidInput(let message) = error {
                return message
            }
            return "Invalid configuration"
        } catch {
            return "Invalid configuration"
        }
    }

    private func submit() {
        do {
            _ = try ContainerArgumentBuilder.build(configuration)
        } catch let error as ContainerEngineError {
            if case .invalidInput(let message) = error {
                validationMessage = message
            } else {
                validationMessage = "Invalid configuration"
            }
            return
        } catch {
            validationMessage = "Invalid configuration"
            return
        }
        validationMessage = nil
        env.containerActions.submitRunForm(configuration)
        dismiss()
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

struct RunContainerForm_Previews: PreviewProvider {
    static var previews: some View {
        RunContainerForm()
            .environment(AppEnvironment.preview(running: true))
    }
}
