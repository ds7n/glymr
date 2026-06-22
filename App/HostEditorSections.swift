// SPDX-FileCopyrightText: 2026 True Positive LLC
// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import GlymrKit

// MARK: - Connection section

extension HostEditorView {

    /// Connection section: Tier-2 SSH options, all `Inherited<T>`, collapsed by default.
    var connectionSection: some View {
        DisclosureGroup(isExpanded: $connectionExpanded) {
            // serverAliveInterval — Inherited<Int>
            LabeledContent {
                TextField(
                    serverAliveIntervalPlaceholder,
                    text: Binding(
                        get: { inheritedIntToText(vm.host.serverAliveInterval) },
                        set: { vm.host.serverAliveInterval = textToInheritedInt($0) }
                    )
                )
                .keyboardType(.numberPad)
                .onChange(of: vm.host.serverAliveInterval) { _, _ in vm.revalidate() }
            } label: {
                Text("Keep-alive interval (s)")
                    .foregroundStyle(Color(theme.text.primary))
            }

            // serverAliveCountMax — Inherited<Int>
            LabeledContent {
                TextField(
                    serverAliveCountMaxPlaceholder,
                    text: Binding(
                        get: { inheritedIntToText(vm.host.serverAliveCountMax) },
                        set: { vm.host.serverAliveCountMax = textToInheritedInt($0) }
                    )
                )
                .keyboardType(.numberPad)
                .onChange(of: vm.host.serverAliveCountMax) { _, _ in vm.revalidate() }
            } label: {
                Text("Keep-alive retries")
                    .foregroundStyle(Color(theme.text.primary))
            }

            // compression — Inherited<Bool>: three-state Picker (Default / On / Off)
            Picker(selection: Binding(
                get: { inheritedBoolToSelection(vm.host.compression) },
                set: { vm.host.compression = selectionToInheritedBool($0); vm.revalidate() }
            )) {
                Text("Default").tag(Bool?.none)
                Text("On").tag(Bool?.some(true))
                Text("Off").tag(Bool?.some(false))
            } label: {
                Text("Compression")
                    .foregroundStyle(Color(theme.text.primary))
            }

            // forwardAgent — Inherited<Bool>: three-state Picker (Default / On / Off)
            Picker(selection: Binding(
                get: { inheritedBoolToSelection(vm.host.forwardAgent) },
                set: { vm.host.forwardAgent = selectionToInheritedBool($0); vm.revalidate() }
            )) {
                Text("Default").tag(Bool?.none)
                Text("On").tag(Bool?.some(true))
                Text("Off").tag(Bool?.some(false))
            } label: {
                Text("Agent forwarding")
                    .foregroundStyle(Color(theme.text.primary))
            }

            // strictHostKeyChecking — Inherited<StrictHostKeyChecking>: Picker
            Picker(selection: Binding(
                get: { inheritedSHKCToSelection(vm.host.strictHostKeyChecking) },
                set: { vm.host.strictHostKeyChecking = selectionToInheritedSHKC($0); vm.revalidate() }
            )) {
                Text("Default (inherit)").tag(StrictHostKeyChecking?.none)
                Text("yes").tag(StrictHostKeyChecking?.some(.yes))
                Text("accept-new").tag(StrictHostKeyChecking?.some(.acceptNew))
                Text("ask").tag(StrictHostKeyChecking?.some(.ask))
                Text("no").tag(StrictHostKeyChecking?.some(.no))
            } label: {
                Text("Host key checking")
                    .foregroundStyle(Color(theme.text.primary))
            }

            // preferredAuthentications — Inherited<[AuthMethod]>: toggles per method
            VStack(alignment: .leading, spacing: 6) {
                Text("Preferred auth")
                    .foregroundStyle(Color(theme.text.primary))

                // .inherit → show "Default (inherit)" hint; toggles promote to explicit
                // .explicit([]) or .explicit([...]) → individual method toggles control it
                if case .inherit = vm.host.preferredAuthentications {
                    Text("Default (inherit)")
                        .font(.caption)
                        .foregroundStyle(Color(theme.text.secondary))
                }

                ForEach([AuthMethod.publicKey, .password, .keyboardInteractive], id: \.self) { method in
                    let methodLabel: String = {
                        switch method {
                        case .publicKey: return "Public key"
                        case .password: return "Password"
                        case .keyboardInteractive: return "Keyboard-interactive"
                        }
                    }()
                    let isActive: Bool = vm.host.preferredAuthentications.value?.contains(method) ?? false

                    Toggle(isOn: Binding(
                        get: { isActive },
                        set: { newValue in
                            // Promote to explicit on first toggle, then toggle the method
                            var current: Set<AuthMethod> = inheritedAuthMethodsToSelection(
                                vm.host.preferredAuthentications
                            ) ?? Set()
                            if newValue {
                                current.insert(method)
                            } else {
                                current.remove(method)
                            }
                            vm.host.preferredAuthentications = selectionToInheritedAuthMethods(current)
                            vm.revalidate()
                        }
                    )) {
                        Text(methodLabel)
                            .font(.subheadline)
                            .foregroundStyle(Color(theme.text.primary))
                    }
                }
            }
            .padding(.vertical, 2)

        } label: {
            Text("Connection")
                .font(.headline)
                .foregroundStyle(Color(theme.text.primary))
        }
    }

    // MARK: Placeholder hints

    private var serverAliveIntervalPlaceholder: String {
        if let v = defaults.serverAliveInterval.value { return "Defaults · \(v)" }
        return "e.g. 30"
    }

    private var serverAliveCountMaxPlaceholder: String {
        if let v = defaults.serverAliveCountMax.value { return "Defaults · \(v)" }
        return "e.g. 3"
    }
}

// MARK: - Jump chain section

extension HostEditorView {

    /// Jump chain section: `proxyJump[]` list with per-hop mode toggle.
    var jumpChainSection: some View {
        DisclosureGroup(isExpanded: $jumpChainExpanded) {
            // Cycle banner — section-level hard issue
            if hasIssue(.jumpChainCycle) {
                IssueBanner(
                    message: "Jump chain contains a cycle.",
                    severity: .hardBlock
                )
            }

            let hops: [JumpHop] = vm.host.proxyJump.value ?? []

            ForEach(hops.indices, id: \.self) { idx in
                JumpHopRow(
                    hop: Binding(
                        get: { hops[idx] },
                        set: { newHop in
                            var updated = vm.host.proxyJump.value ?? []
                            updated[idx] = newHop
                            vm.host.proxyJump = .explicit(updated)
                            vm.revalidate()
                        }
                    ),
                    index: idx,
                    editingHostId: vm.host.id,
                    issues: vm.issues,
                    onRemove: {
                        var updated = vm.host.proxyJump.value ?? []
                        updated.remove(at: idx)
                        vm.host.proxyJump = .explicit(updated)
                        vm.revalidate()
                    }
                )
            }

            Button {
                var updated = vm.host.proxyJump.value ?? []
                updated.append(.inline(hostName: "", port: nil, user: nil, identities: nil))
                vm.host.proxyJump = .explicit(updated)
                vm.revalidate()
            } label: {
                Label("Add hop", systemImage: "plus.circle")
                    .foregroundStyle(Color(theme.accent.primary))
            }

        } label: {
            Text("Jump chain")
                .font(.headline)
                .foregroundStyle(Color(theme.text.primary))
        }
    }
}

// MARK: - Port forwarding section

extension HostEditorView {

    /// Port forwarding section: three sub-lists (local / remote / dynamic).
    var portForwardingSection: some View {
        DisclosureGroup(isExpanded: $portForwardingExpanded) {

            // ── Local forwards ──────────────────────────────────────────────
            Text("Local forwards")
                .font(.subheadline)
                .foregroundStyle(Color(theme.text.secondary))

            let localFwds: [LocalForward] = vm.host.localForwards.value ?? []
            ForEach(localFwds.indices, id: \.self) { idx in
                LocalForwardRow(
                    fwd: Binding(
                        get: { localFwds[idx] },
                        set: { newFwd in
                            var updated = vm.host.localForwards.value ?? []
                            updated[idx] = newFwd
                            vm.host.localForwards = .explicit(updated)
                            vm.revalidate()
                        }
                    ),
                    index: idx,
                    issues: vm.issues,
                    onRemove: {
                        var updated = vm.host.localForwards.value ?? []
                        updated.remove(at: idx)
                        vm.host.localForwards = .explicit(updated)
                        vm.revalidate()
                    }
                )
            }
            Button {
                var updated = vm.host.localForwards.value ?? []
                updated.append(LocalForward(bindAddress: nil, bindPort: 0, hostAddress: "", hostPort: 0))
                vm.host.localForwards = .explicit(updated)
                vm.revalidate()
            } label: {
                Label("Add local forward", systemImage: "plus.circle")
                    .foregroundStyle(Color(theme.accent.primary))
            }

            // ── Remote forwards ─────────────────────────────────────────────
            Text("Remote forwards")
                .font(.subheadline)
                .foregroundStyle(Color(theme.text.secondary))
                .padding(.top, 4)

            let remoteFwds: [RemoteForward] = vm.host.remoteForwards.value ?? []
            ForEach(remoteFwds.indices, id: \.self) { idx in
                RemoteForwardRow(
                    fwd: Binding(
                        get: { remoteFwds[idx] },
                        set: { newFwd in
                            var updated = vm.host.remoteForwards.value ?? []
                            updated[idx] = newFwd
                            vm.host.remoteForwards = .explicit(updated)
                            vm.revalidate()
                        }
                    ),
                    index: idx,
                    issues: vm.issues,
                    onRemove: {
                        var updated = vm.host.remoteForwards.value ?? []
                        updated.remove(at: idx)
                        vm.host.remoteForwards = .explicit(updated)
                        vm.revalidate()
                    }
                )
            }
            Button {
                var updated = vm.host.remoteForwards.value ?? []
                updated.append(RemoteForward(bindAddress: nil, bindPort: 0, hostAddress: "", hostPort: 0))
                vm.host.remoteForwards = .explicit(updated)
                vm.revalidate()
            } label: {
                Label("Add remote forward", systemImage: "plus.circle")
                    .foregroundStyle(Color(theme.accent.primary))
            }

            // ── Dynamic forwards ────────────────────────────────────────────
            Text("Dynamic forwards (SOCKS)")
                .font(.subheadline)
                .foregroundStyle(Color(theme.text.secondary))
                .padding(.top, 4)

            let dynFwds: [DynamicForward] = vm.host.dynamicForwards.value ?? []
            ForEach(dynFwds.indices, id: \.self) { idx in
                DynamicForwardRow(
                    fwd: Binding(
                        get: { dynFwds[idx] },
                        set: { newFwd in
                            var updated = vm.host.dynamicForwards.value ?? []
                            updated[idx] = newFwd
                            vm.host.dynamicForwards = .explicit(updated)
                            vm.revalidate()
                        }
                    ),
                    index: idx,
                    issues: vm.issues,
                    onRemove: {
                        var updated = vm.host.dynamicForwards.value ?? []
                        updated.remove(at: idx)
                        vm.host.dynamicForwards = .explicit(updated)
                        vm.revalidate()
                    }
                )
            }
            Button {
                var updated = vm.host.dynamicForwards.value ?? []
                updated.append(DynamicForward(bindAddress: nil, bindPort: 0))
                vm.host.dynamicForwards = .explicit(updated)
                vm.revalidate()
            } label: {
                Label("Add dynamic forward", systemImage: "plus.circle")
                    .foregroundStyle(Color(theme.accent.primary))
            }

        } label: {
            Text("Port forwarding")
                .font(.headline)
                .foregroundStyle(Color(theme.text.primary))
        }
    }
}

// MARK: - JumpHopRow

/// A single row in the jump chain list. Toggles between `.ref(hostId:)` and
/// `.inline(hostName:port:user:identities:)` modes.
private struct JumpHopRow: View {
    @Binding var hop: JumpHop
    let index: Int
    let editingHostId: UUID
    let issues: [ValidationIssue]
    let onRemove: () -> Void
    @Environment(\.theme) private var theme

    /// True when this row's inline hop has a missing hostName.
    private var hasInlineHostNameIssue: Bool {
        issues.contains { $0.kind == .inlineJumpHostMissingHostName(index: index) }
    }

    /// Whether the current hop is in "Pick host" mode.
    private var isRefMode: Bool {
        if case .ref = hop { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Mode toggle: Pick host vs Inline
                Picker("", selection: Binding<Bool>(
                    get: { isRefMode },
                    set: { wantsRef in
                        if wantsRef {
                            // Pre-select the first eligible (non-self) saved host so the
                            // Picker is never pointing at an arbitrary/invalid UUID.
                            let allHosts = (try? AppStores.shared.hosts.allHosts()) ?? []
                            let firstEligible = allHosts.first { $0.id != editingHostId }
                            hop = .ref(hostId: firstEligible?.id ?? UUID())
                        } else {
                            hop = .inline(hostName: "", port: nil, user: nil, identities: nil)
                        }
                    }
                )) {
                    Text("Pick host").tag(true)
                    Text("Inline").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)

                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Color(theme.state.broken))
                }
                .buttonStyle(.borderless)
            }

            if isRefMode {
                refModeContent
            } else {
                inlineModeContent
            }

            if hasInlineHostNameIssue {
                IssueBanner(
                    message: "Inline jump host requires a hostname.",
                    severity: .hardBlock
                )
            }
        }
        .padding(.vertical, 2)
    }

    /// Picker over all saved hosts except the one being edited.
    @ViewBuilder
    private var refModeContent: some View {
        // TODO(perf): allHosts() is re-fetched on every render; cache in the view model and observe store changes.
        let savedHosts: [GlymrKit.Host] = (try? AppStores.shared.hosts.allHosts())
            ?? []
        let eligible = savedHosts.filter { $0.id != editingHostId }

        if eligible.isEmpty {
            Text("No other saved hosts")
                .font(.caption)
                .foregroundStyle(Color(theme.text.secondary))
        } else {
            let currentId: UUID = {
                if case let .ref(id) = hop { return id }
                return eligible[0].id
            }()
            Picker("Host", selection: Binding<UUID>(
                get: { currentId },
                set: { hop = .ref(hostId: $0) }
            )) {
                ForEach(eligible, id: \.id) { h in
                    Text(h.label.isEmpty ? h.hostName : h.label).tag(h.id)
                }
            }
        }
    }

    /// Text fields for `user@host:port`.
    @ViewBuilder
    private var inlineModeContent: some View {
        let inlineHostName: String = {
            if case let .inline(hn, _, _, _) = hop { return hn }
            return ""
        }()
        let inlinePort: Int? = {
            if case let .inline(_, p, _, _) = hop { return p }
            return nil
        }()
        let inlineUser: String = {
            if case let .inline(_, _, u, _) = hop { return u ?? "" }
            return ""
        }()

        LabeledContent {
            TextField("hostname or IP", text: Binding(
                get: { inlineHostName },
                set: { newHN in
                    let (_, p, u, ids) = inlineFields
                    hop = .inline(hostName: newHN, port: p, user: u.isEmpty ? nil : u, identities: ids)
                }
            ))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
        } label: {
            Text("Host")
                .font(.subheadline)
                .foregroundStyle(Color(theme.text.primary))
        }

        LabeledContent {
            TextField("e.g. 22", text: Binding(
                get: { inlinePort.map { String($0) } ?? "" },
                set: { newText in
                    let (hn, _, u, ids) = inlineFields
                    let port = Int(newText).flatMap { $0 > 0 ? $0 : nil }
                    hop = .inline(hostName: hn, port: port, user: u.isEmpty ? nil : u, identities: ids)
                }
            ))
            .keyboardType(.numberPad)
        } label: {
            Text("Port")
                .font(.subheadline)
                .foregroundStyle(Color(theme.text.primary))
        }

        LabeledContent {
            TextField("e.g. ubuntu", text: Binding(
                get: { inlineUser },
                set: { newUser in
                    let (hn, p, _, ids) = inlineFields
                    hop = .inline(hostName: hn, port: p, user: newUser.isEmpty ? nil : newUser, identities: ids)
                }
            ))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        } label: {
            Text("User")
                .font(.subheadline)
                .foregroundStyle(Color(theme.text.primary))
        }
    }

    /// Destructure the current hop's inline fields (safe; returns empty defaults otherwise).
    private var inlineFields: (String, Int?, String, [IdentityRef]?) {
        if case let .inline(hn, p, u, ids) = hop {
            return (hn, p, u ?? "", ids)
        }
        return ("", nil, "", nil)
    }
}

// MARK: - LocalForwardRow

private struct LocalForwardRow: View {
    @Binding var fwd: LocalForward
    let index: Int
    let issues: [ValidationIssue]
    let onRemove: () -> Void
    @Environment(\.theme) private var theme

    private var hasMissingField: Bool {
        issues.contains { $0.kind == .localForwardMissingField(index: index) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Local \(index + 1)")
                    .font(.subheadline)
                    .foregroundStyle(Color(theme.text.secondary))
                Spacer()
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Color(theme.state.broken))
                }
                .buttonStyle(.borderless)
            }

            LabeledContent {
                TextField("optional", text: Binding(
                    get: { fwd.bindAddress ?? "" },
                    set: { fwd.bindAddress = $0.isEmpty ? nil : $0 }
                ))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            } label: {
                Text("Bind addr")
                    .font(.caption)
                    .foregroundStyle(Color(theme.text.primary))
            }

            LabeledContent {
                TextField("bind port", text: Binding(
                    get: { fwd.bindPort > 0 ? String(fwd.bindPort) : "" },
                    set: { fwd.bindPort = Int($0) ?? 0 }
                ))
                .keyboardType(.numberPad)
            } label: {
                Text("Bind port")
                    .font(.caption)
                    .foregroundStyle(Color(theme.text.primary))
            }

            LabeledContent {
                TextField("hostname or IP", text: Binding(
                    get: { fwd.hostAddress },
                    set: { fwd.hostAddress = $0 }
                ))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            } label: {
                Text("Host addr")
                    .font(.caption)
                    .foregroundStyle(Color(theme.text.primary))
            }

            LabeledContent {
                TextField("host port", text: Binding(
                    get: { fwd.hostPort > 0 ? String(fwd.hostPort) : "" },
                    set: { fwd.hostPort = Int($0) ?? 0 }
                ))
                .keyboardType(.numberPad)
            } label: {
                Text("Host port")
                    .font(.caption)
                    .foregroundStyle(Color(theme.text.primary))
            }

            if hasMissingField {
                IssueBanner(
                    message: "Bind port, host address, and host port are required.",
                    severity: .hardBlock
                )
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - RemoteForwardRow

private struct RemoteForwardRow: View {
    @Binding var fwd: RemoteForward
    let index: Int
    let issues: [ValidationIssue]
    let onRemove: () -> Void
    @Environment(\.theme) private var theme

    private var hasMissingField: Bool {
        issues.contains { $0.kind == .remoteForwardMissingField(index: index) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Remote \(index + 1)")
                    .font(.subheadline)
                    .foregroundStyle(Color(theme.text.secondary))
                Spacer()
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Color(theme.state.broken))
                }
                .buttonStyle(.borderless)
            }

            LabeledContent {
                TextField("optional", text: Binding(
                    get: { fwd.bindAddress ?? "" },
                    set: { fwd.bindAddress = $0.isEmpty ? nil : $0 }
                ))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            } label: {
                Text("Bind addr")
                    .font(.caption)
                    .foregroundStyle(Color(theme.text.primary))
            }

            LabeledContent {
                TextField("bind port", text: Binding(
                    get: { fwd.bindPort > 0 ? String(fwd.bindPort) : "" },
                    set: { fwd.bindPort = Int($0) ?? 0 }
                ))
                .keyboardType(.numberPad)
            } label: {
                Text("Bind port")
                    .font(.caption)
                    .foregroundStyle(Color(theme.text.primary))
            }

            LabeledContent {
                TextField("hostname or IP", text: Binding(
                    get: { fwd.hostAddress },
                    set: { fwd.hostAddress = $0 }
                ))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            } label: {
                Text("Host addr")
                    .font(.caption)
                    .foregroundStyle(Color(theme.text.primary))
            }

            LabeledContent {
                TextField("host port", text: Binding(
                    get: { fwd.hostPort > 0 ? String(fwd.hostPort) : "" },
                    set: { fwd.hostPort = Int($0) ?? 0 }
                ))
                .keyboardType(.numberPad)
            } label: {
                Text("Host port")
                    .font(.caption)
                    .foregroundStyle(Color(theme.text.primary))
            }

            if hasMissingField {
                IssueBanner(
                    message: "Bind port, host address, and host port are required.",
                    severity: .hardBlock
                )
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - DynamicForwardRow

private struct DynamicForwardRow: View {
    @Binding var fwd: DynamicForward
    let index: Int
    let issues: [ValidationIssue]
    let onRemove: () -> Void
    @Environment(\.theme) private var theme

    private var hasMissingField: Bool {
        issues.contains { $0.kind == .dynamicForwardMissingField(index: index) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Dynamic \(index + 1)")
                    .font(.subheadline)
                    .foregroundStyle(Color(theme.text.secondary))
                Spacer()
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Color(theme.state.broken))
                }
                .buttonStyle(.borderless)
            }

            LabeledContent {
                TextField("optional", text: Binding(
                    get: { fwd.bindAddress ?? "" },
                    set: { fwd.bindAddress = $0.isEmpty ? nil : $0 }
                ))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            } label: {
                Text("Bind addr")
                    .font(.caption)
                    .foregroundStyle(Color(theme.text.primary))
            }

            LabeledContent {
                TextField("bind port", text: Binding(
                    get: { fwd.bindPort > 0 ? String(fwd.bindPort) : "" },
                    set: { fwd.bindPort = Int($0) ?? 0 }
                ))
                .keyboardType(.numberPad)
            } label: {
                Text("Bind port")
                    .font(.caption)
                    .foregroundStyle(Color(theme.text.primary))
            }

            if hasMissingField {
                IssueBanner(
                    message: "Bind port is required.",
                    severity: .hardBlock
                )
            }
        }
        .padding(.vertical, 2)
    }
}

// `IssueBanner` is declared internal (not private) in HostEditorView.swift and is
// visible to this file. No duplicate declaration needed.
