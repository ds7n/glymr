// SPDX-FileCopyrightText: 2026 True Positive LLC
// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import GlymrSSHCoreFFI   // the UniFFI bridge to the Rust SSH core
import SwiftTerm         // terminal renderer (wired up in a later task)

/// Placeholder root view. Rendering `coreVersion()` proves the whole link chain
/// works end to end: SwiftUI app → GlymrSSHCoreFFI → GlymrSSHCore.xcframework →
/// Rust. The real connect form replaces this in a later task.
struct ConnectView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Glymr").font(.largeTitle).bold()
            Text("ssh core \(coreVersion())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
