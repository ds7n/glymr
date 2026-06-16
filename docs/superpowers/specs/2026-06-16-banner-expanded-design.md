# Connection-status banner — expanded view design

**Date:** 2026-06-16
**Status:** Locked
**Replaces:** README "Unresolved" bullet — *Connection-status banner expanded view*

## Goal

Specify the tap-to-expand behavior of the transient connection-status
banner. Defines what the user sees when they tap a banner that says
something is wrong, so they can either (a) understand what is going
wrong or (b) act on it.

## What is already locked (not re-litigated)

From `docs/brainstorming-decisions.md` → *Connection status* and
*Degraded mode & tmux requirements*:

- Banner is **transient** and **visible only when something is wrong**.
- States the banner can show: **disconnected · reconnecting (mosh
  roaming) · high latency / degraded · auth failure · host
  unreachable**. **tmux crashed** has its own persistent red banner with
  inline Reattach / Start new tmux / Dismiss actions and is **out of
  scope for this spec** — it never expands.
- Reconnecting label counts up: `last seen 4s ago → 12s → 1m 20s`.
- Multi-connection: banner is single-subject (foreground); background
  health surfaces as a picker-row dot.
- Banner auto-dismisses on return-to-healthy.
- User can swipe to dismiss persistent issues; re-appears if state
  changes.

This spec covers only the **expanded view** triggered from those five
transient states.

## Layout — expand in place

The banner itself grows downward. The terminal scrolls underneath. There
is no separate sheet, no separate modal — the banner *is* the
connection-status surface, and the expanded view is "more of it."

```
┌────────────────────────────────┐
│ ● Reconnecting   12s    ⌄      │  ← banner header (collapsed = just this line)
├────────────────────────────────┤
│  Protocol     mosh             │
│  Host         example.com      │  ← stat grid (2 columns)
│  Last seen    12s ago          │
│  RTT (last)   428 ms           │
│  ...                           │
│ ┌────────────────────────────┐ │
│ │ RTT (60s)  min 38 / max …  │ │  ← inline graph (Template 1 only)
│ └────────────────────────────┘ │
├────────────────────────────────┤
│ [Retry now] [Copy diag] [Disc] │  ← action row
├────────────────────────────────┤
│            ↑ ▬                 │  ← grab handle, swipe UP to collapse
└────────────────────────────────┘
```

### Why expand-in-place beat half-sheet and full-sheet

- **Single mental model.** The banner is the surface; the expanded view
  is "more of the banner." A half-sheet introduces a second concept for
  what should feel like one thing.
- **Auto-collapse just works.** When the connection recovers, the
  banner goes away — the expanded view collapses with it. No orphaned
  sheet to dismiss.
- **Room for graphs.** The 60s RTT chart fits comfortably; a half-sheet
  would crop it.

(Compared mockup: `mockups/drafts/banner-expanded-layouts.html`.)

### Obscured terminal — accepted

When fully expanded with the RTT graph, the expanded view occupies most
of the visible screen. That is **acceptable**: the user explicitly
tapped a "something is wrong" banner. Privacy of the terminal contents
is not relevant — the same user looking at it just chose to.

## Two templates

Five states fold into two visual templates. Choosing per-state custom
layouts (five) is over-design; using one template (five) leaves
auth-failure with an empty RTT graph that reads as a bug.

### Template 1 — "Live in trouble" (amber)

States: **reconnecting · high latency / degraded**.

Header reads `Reconnecting · mosh` (with a `Xs` last-seen stamp) or
`High latency · ssh` (with a `RTT 612 ms` stamp).

Body fields (in display order, two columns):

| Field          | When shown                | Source                                  |
|----------------|---------------------------|-----------------------------------------|
| Protocol       | always                    | session model                           |
| Host           | always                    | host config (label or hostName)         |
| State          | header only               | banner state                            |
| Last seen      | reconnecting              | mosh heartbeat / SSH keepalive          |
| RTT (last)     | always                    | mosh / ICMP / SSH keepalive RTT         |
| Keepalive      | SSH only                  | last successful keepalive timestamp     |
| Frames sent    | mosh only                 | mosh client counter                     |
| Frames acked   | mosh only                 | mosh client counter                     |
| Last roam      | mosh only                 | mosh roam log                           |
| Network        | mosh only, when known     | iOS `NWPathMonitor` / SSID              |

Below the stat grid: an **inline RTT graph** over the last 60 seconds,
with min / max overlay text. SVG path, no animation beyond a once-per-
second value update.

Actions (three buttons, left to right):

- **Retry now** (primary, amber) — force a heartbeat / re-handshake.
- **Copy diagnostics** — see *Copy diagnostics payload* below.
- **Disconnect** (destructive) — same client-side-abandon semantics as
  the picker swipe; session demotes to Recent.

### Template 2 — "Connection failed" (red)

States: **auth failure · host unreachable · disconnected**.

Header reads `Authentication failed` / `Host unreachable` /
`Disconnected` with the host label as a stamp.

Body fields:

| Field             | When shown            | Notes                                              |
|-------------------|-----------------------|----------------------------------------------------|
| Protocol          | always                |                                                    |
| Host              | always                | with port: `host:22`                               |
| DNS               | always                | resolved IP, or "could not resolve"                |
| TCP               | always                | `connected` / `SYN · no reply` / `refused` / `closed` |
| Method tried      | auth failure          | `publickey` / `password` / etc.                    |
| Identity          | auth failure          | identity display name                              |
| Attempts          | host unreachable      | `3 of 3`                                           |
| Last try          | host unreachable      | `2s ago`                                           |
| Tailscale         | host unreachable + `tailscale.required` | inline note in error strip   |

Below the stat grid: a **red-tinted error strip** showing the
underlying error string verbatim (libssh / mosh / network stack). Mono
font, small, word-break. Useful for power users and for bug-report
copy-paste.

Actions (four buttons, left to right):

- **Retry** (primary, red) — re-attempt connection from scratch.
- **Edit host** — push to the host CRUD form for the failing host.
- **Copy diagnostics**
- **Disconnect** (destructive) — abandons, moves to Recent.

### Why two templates

"Live but struggling" and "dead" are different kinds of bad. A graph
helps the first; it is misleading-empty for the second. Fault details
(DNS / TCP / auth method) help the second; they are noise during a
healthy session that just hit a momentary latency spike.

(Mockup: `mockups/drafts/banner-expanded-templates.html` — four phone
frames, two per template.)

## Dismissal triggers

Four ways out. Three derive from existing locked behavior; only the
fourth is new.

1. **Tap the header.** Collapses back to the standard banner.
2. **Swipe up on the grab-handle** at the bottom of the expanded panel.
   Same effect as tap-header. The handle visual includes a small upward
   chevron (`↑`) to make the direction obvious — the banner came from
   the top, so "back to the top" is the gesture.
3. **Auto-collapse on recovery.** When the underlying state returns to
   healthy, the banner itself disappears (already-locked transient
   behavior); the expanded view goes with it.
4. **Swipe up on the collapsed banner.** Already-locked "swipe to
   dismiss persistent issues" — same gesture direction as collapse, so
   the rule is consistent: **up = away**. Re-appears if state changes.

### Why up and not down

The banner enters by sliding down from the top safe area. To send it
"back where it came from," the natural direction is up. iOS Notification
Center uses the same convention. Drag-down would imply "make it bigger"
or "pull it further down," not "dismiss."

## Copy diagnostics payload

`Copy diagnostics` writes a JSON snapshot to the system clipboard:

```json
{
  "copiedAt": "2026-06-16T19:54:14Z",
  "app":      { "version": "1.0.0", "build": 1234 },
  "device":   { "iOSVersion": "18.4", "model": "iPhone16,2" },
  "state":    "reconnecting",
  "protocol": "mosh",
  "host":     "example.com",
  "fields": {
    "lastSeenSeconds": 12,
    "rttLastMs":       428,
    "rttMin60sMs":     38,
    "rttMax60sMs":     612,
    "framesSent":      1284,
    "framesAcked":     1261,
    "lastRoamSecondsAgo": 840,
    "networkType":     "wifi",
    "networkSsid":     "Cafe"
  },
  "error": null
}
```

For Template 2 the `fields` object is replaced with the fault details
(`dnsResolved`, `tcpResult`, `methodTried`, `identityName`, `attempts`,
`lastTrySecondsAgo`, `tailscaleStatus`) and the `error` field carries
the underlying error string.

### No redaction

The user explicitly chose to copy. Hostnames, IPs, identity names, SSID
names are theirs. No "anonymize before copy" toggle in v1 — adds UI for
a workflow that is itself opt-in.

### Feedback

On tap: light haptic + a tiny "Copied" toast that floats up from the
bottom of the expanded panel, auto-fades after ~1.2s. No banner-style
chrome for the toast.

## Live updating

Fields refresh once per second while the expanded view is open. The
header stamp and the body's `Last seen` row update from the same
observable so they never disagree. The RTT graph appends one sample per
second and drops the oldest beyond 60s; no animation between samples
(would visually overweight tiny fluctuations).

## Out of scope

- **Per-state custom layouts** beyond the two templates. Five custom
  layouts is over-design.
- **Editable thresholds** (when does "degraded" trip, etc.). Use the
  defaults from connection-status / mosh; expose later if power users
  ask.
- **Roam history view.** "Last roam" is one row. A full roam-events
  log is a v1.5+ candidate.
- **Inline action: switch network.** iOS does not let third-party apps
  pick a Wi-Fi network programmatically. The action would have to push
  the user to Settings, which is friction-y. Skipped.
- **Inline action: change identity.** The Edit host action is
  sufficient — pick a different identity there, then Retry.
- **Sharing diagnostics via ShareSheet.** Copy is enough for v1; if the
  user wants to send it somewhere, they can paste. Removes a button.
- **iPad / Stage Manager adaptation** — when iPad nav is brainstormed.
- **Localisation** — English only for v1.

## Related specs and mockups

- `docs/superpowers/specs/2026-06-14-degraded-mode-design.md` — tmux
  crashed banner remains its own thing; this spec does not touch it.
- `docs/superpowers/specs/2026-06-15-multi-connection-switching-design.md` —
  banner is single-subject (foreground); this spec inherits that.
- `docs/superpowers/specs/2026-06-15-host-config-model-design.md` —
  Tailscale `required` flag drives the inline Tailscale note in
  Template 2.
- `mockups/drafts/banner-expanded-layouts.html` — three layout options
  compared (A wins).
- `mockups/drafts/banner-expanded-templates.html` — both templates
  rendered with example states.
