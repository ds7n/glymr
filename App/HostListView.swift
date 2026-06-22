// SPDX-FileCopyrightText: 2026 True Positive LLC
// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import GlymrKit

/// Root host-library screen. Shows an empty-state CTA when no hosts exist;
/// otherwise a list where each row can be tapped to connect or swiped for
/// Edit / Delete actions.
struct HostListView: View {
    @StateObject private var vm = HostListViewModel()
    @Environment(\.theme) private var theme
    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.hosts.isEmpty {
                    emptyState
                } else {
                    hostList
                }
            }
            .navigationTitle("Hosts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                vm.reload()
            }
            // Editor sheet — placeholder until Task 3 ships HostEditorView.
            .sheet(isPresented: $showingEditor, onDismiss: { vm.reload() }) {
                HostEditorPlaceholder()
            }
            // Delete-refusal alert.
            .alert(
                "Cannot Delete Host",
                isPresented: Binding(
                    get: { vm.deleteError != nil },
                    set: { if !$0 { vm.deleteError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { vm.deleteError = nil }
            } message: {
                Text(vm.deleteError ?? "")
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Button {
                showingEditor = true
            } label: {
                Text("Add your first host")
                    .font(.headline)
                    .foregroundStyle(Color(theme.accent.primary))
            }
            .buttonStyle(.plain)

            Text("You'll need a hostname, username, and either a password or key.")
                .font(.subheadline)
                .foregroundStyle(Color(theme.text.secondary))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Host list

    private var hostList: some View {
        List {
            ForEach(vm.hosts, id: \.id) { host in
                Button {
                    // TODO(Task 8): connect-from-saved — wire ConnectionViewModel with saved Host credentials
                } label: {
                    HostRow(host: host)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // Delete action
                    Button(role: .destructive) {
                        vm.delete(host)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    // Edit action
                    // TODO(Task 3): replace with navigation/sheet to HostEditorView(host: host)
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(Color(theme.accent.primary))
                }
            }
        }
    }
}

// MARK: - Host row

/// A single row in the host list: label on top, hostname in muted text below.
private struct HostRow: View {
    let host: Host
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(host.label)
                .font(.body)
                .foregroundStyle(Color(theme.text.primary))
            Text(host.hostName)
                .font(.caption)
                .foregroundStyle(Color(theme.text.secondary))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Editor placeholder

/// Minimal stub shown until Task 3 delivers `HostEditorView`.
/// TODO(Task 3): replace with HostEditorView
private struct HostEditorPlaceholder: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            Text("Host editor coming in Task 3.")
                .foregroundStyle(Color(theme.text.secondary))
                .navigationTitle("New Host")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
