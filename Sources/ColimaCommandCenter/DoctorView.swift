import SwiftUI

struct DoctorView: View {
    @StateObject private var viewModel = DoctorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 560, minHeight: 300)
        .alert(L10n.tr("doctor.confirm_title"), isPresented: $viewModel.showConfirm) {
            Button(L10n.tr("alert.cancel"), role: .cancel) {}
            Button(L10n.tr("doctor.run_button"), role: .destructive) {
                viewModel.runDoctor()
            }
        } message: {
            Text(L10n.tr("doctor.confirm_msg"))
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isRunning {
            ProgressView(L10n.tr("doctor.running"))
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.output.isEmpty {
            PlaceholderView(
                icon: "stethoscope",
                title: L10n.tr("doctor.placeholder_title"),
                hint: L10n.tr("doctor.placeholder_hint")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.failed {
                        Label(L10n.tr("doctor.failed", 0), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    Text(viewModel.output)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button(L10n.tr("doctor.run_button")) { viewModel.showConfirm = true }
                .keyboardShortcut("d", modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunning)
        }
        .padding(10)
    }
}

private struct PlaceholderView: View {
    let icon: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(hint)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
