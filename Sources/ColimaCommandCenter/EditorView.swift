import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                ProgressView(L10n.tr("loading.config"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView {
                    CuratedTab(vm: viewModel)
                        .tabItem { Label(L10n.tr("tab.curated"), systemImage: "slider.horizontal.3") }
                    RawTab(vm: viewModel)
                        .tabItem { Label(L10n.tr("tab.raw"), systemImage: "doc.text") }
                }
                .padding()

                Divider()

                FooterBar(vm: viewModel)
                    .padding(12)
            }
        }
        .frame(minWidth: 680, minHeight: 360)
        .modifier(RestartAlertModifier(vm: viewModel))
    }
}

private struct CuratedTab: View {
    @ObservedObject var vm: EditorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Section(L10n.tr("section.resources")) {
                    StepperRow(label: L10n.tr("row.cpu"), value: $vm.cpu, range: 1...16, suffix: L10n.tr("unit.cores"))
                    StepperRow(label: L10n.tr("row.ram"), value: $vm.memory, range: 1...64, suffix: L10n.tr("unit.gib"))
                    StepperRow(label: L10n.tr("row.disk_container"), value: $vm.disk, range: max(1, vm.diskFloor)...max(500, vm.diskFloor + 1), suffix: L10n.tr("unit.gib"))
                    StepperRow(label: L10n.tr("row.root_disk"), value: $vm.rootDisk, range: max(1, vm.rootDiskFloor)...max(200, vm.rootDiskFloor + 1), suffix: L10n.tr("unit.gib"))
                    GrowOnlyHint(floorDisk: vm.diskFloor, floorRootDisk: vm.rootDiskFloor)
                }

                Section(L10n.tr("section.kubernetes")) {
                    Toggle(L10n.tr("k8s.enabled"), isOn: $vm.k8sEnabled)
                    HStack {
                        Picker(L10n.tr("k8s.version_label"), selection: $vm.k8sVersion) {
                            Text(L10n.tr("k8s.version_custom")).tag("")
                            ForEach(vm.availableK3sVersions, id: \.self) { ver in
                                Text(ver).tag(ver)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(!vm.k8sEnabled)
                        if vm.loadingVersions {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if vm.k8sVersion.isEmpty {
                        TextField(L10n.tr("k8s.version_placeholder"), text: $vm.k8sVersion)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!vm.k8sEnabled)
                    }
                }

                Section(L10n.tr("section.advanced")) {
                    Toggle(L10n.tr("toggle.mount_inotify"), isOn: $vm.mountInotify)
                    Toggle(L10n.tr("toggle.forward_agent"), isOn: $vm.forwardAgent)
                    Toggle(L10n.tr("toggle.rosetta"), isOn: $vm.rosetta)
                    Toggle(L10n.tr("toggle.binfmt"), isOn: $vm.binfmt)
                }

                Section(L10n.tr("section.network_dns")) {
                    DNSListView(items: $vm.dnsEntries)
                }

                Section(L10n.tr("section.docker_logging")) {
                    HStack {
                        Text(L10n.tr("docker.max_size"))
                        TextField("", text: $vm.dockerLogMaxSize)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text(L10n.tr("docker.max_file"))
                        TextField("", text: $vm.dockerLogFileCount)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }

                ImmutableBox()
            }
            .padding(.vertical)
        }
    }
}

private struct RawTab: View {
    @ObservedObject var vm: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("raw.description"))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $vm.rawYAML)
                .font(.system(.body, design: .monospaced))
                .border(Color.secondary.opacity(0.3))
        }
    }
}

private struct FooterBar: View {
    @ObservedObject var vm: EditorViewModel

    var body: some View {
        HStack {
            if let err = vm.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if vm.saved {
                Label(L10n.tr("msg.saved"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Spacer()
            Button(L10n.tr("btn.reload")) { vm.reload() }
            Button(L10n.tr("btn.save")) { vm.save() }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct StepperRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Stepper("\(value) \(suffix)", value: $value, in: range)
                .labelsHidden()
            Text("\(value) \(suffix)")
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
        }
    }
}

private struct ImmutableBox: View {
    var body: some View {
        GroupBox(L10n.tr("section.immutable_title")) {
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.tr("immutable.keys"), systemImage: "lock")
                    .foregroundStyle(.secondary)
                Text(L10n.tr("immutable.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }
}

private struct GrowOnlyHint: View {
    let floorDisk: Int
    let floorRootDisk: Int

    var body: some View {
        Label(L10n.tr("hint.grow_only", floorDisk, floorRootDisk), systemImage: "arrow.up.circle")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

private struct DNSListView: View {
    @Binding var items: [DNSEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($items) { $entry in
                HStack {
                    TextField(L10n.tr("dns.server_placeholder"), text: $entry.value)
                        .textFieldStyle(.roundedBorder)
                    Button(action: {
                        items.removeAll { $0.id == entry.id }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(L10n.tr("dns.add")) {
                items.append(DNSEntry(value: ""))
            }
        }
    }
}

private struct RestartAlertModifier: ViewModifier {
    @ObservedObject var vm: EditorViewModel

    func body(content: Content) -> some View {
        content.alert(L10n.tr("alert.title"), isPresented: $vm.showRestartPrompt) {
            Button(L10n.tr("alert.cancel"), role: .cancel) { vm.dismissRestart() }
            Button(L10n.tr("alert.restart"), role: .destructive) { vm.confirmRestart() }
        } message: {
            Text(L10n.tr("alert.message"))
        }
    }
}
