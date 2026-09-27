import SwiftUI

struct DiskView: View {
    @ObservedObject var viewModel: DiskViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.isLoading && viewModel.blocks.isEmpty {
                ProgressView(L10n.tr("disk.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.available {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("disk.unavailable")).font(.title2.bold())
                    Text(L10n.tr("health.unavailable_hint"))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.blocks) { block in
                            ResourceBlock(block: block)
                        }
                        if let result = viewModel.cleanResult {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.tr("disk.cleanup_result"))
                                    .font(.headline)
                                Text(result)
                                    .font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(8)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 560, minHeight: 320)
        .alert(L10n.tr("disk.clean_confirm_title"), isPresented: $viewModel.showCleanConfirm) {
            Button(L10n.tr("alert.cancel"), role: .cancel) {}
            Button(L10n.tr("disk.clean_button"), role: .destructive) {
                viewModel.runClean()
            }
        } message: {
            Text(L10n.tr("disk.clean_confirm_msg"))
        }
    }

    private var header: some View {
        HStack {
            if let date = viewModel.lastUpdated {
                Text(L10n.tr("health.updated", DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.tr("health.refresh")) { viewModel.refresh() }
                .keyboardShortcut("r", modifiers: [.command])
            Button(L10n.tr("disk.clean_button")) { viewModel.showCleanConfirm = true }
                .keyboardShortcut("k", modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(viewModel.isCleaning || !viewModel.available)
        }
        .padding(10)
    }
}

private struct ResourceBlock: View {
    let block: DiskInspector.Block

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(block.title)
                .font(.headline)
            Text(block.raw)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
