<h1 align="center">
  <img src="docs/images/ai-helper-icon.svg" width="64" height="64" alt="ai-helper app icon" valign="middle">&nbsp;
  ai-helper
</h1>
<p align="center">
  <b>AI coding session monitor for the macOS menu bar</b><br>
  <a href="https://github.com/Miofly/vft-kit">Repository</a> •
  <a href="#lets-try-it">Try it</a> •
  <a href="#installation">Install</a> •
  <a href="#features">Features</a> •
  <a href="#supported-clients">Supported Clients</a> •
  <a href="#build-from-source">Build</a> •
  <a href="#contributors">Contributors</a> •
  <a href="docs/privacy-policy.md">Privacy</a><br>
  English | <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/Miofly/vft-kit/releases">
    <img src="https://img.shields.io/badge/Release-ai--helper--v*-111827?style=flat-square&logo=github" alt="ai-helper Releases">
  </a>
  <img src="https://img.shields.io/badge/macOS-14%2B-0A84FF?style=flat-square&logo=apple&logoColor=white" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6.1-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.1">
  <img src="https://img.shields.io/badge/Clients-12%2B-111827?style=flat-square" alt="Supports 12 plus client families">
  <img src="https://img.shields.io/badge/License-Apache%202.0-4F46E5?style=flat-square" alt="Apache 2.0 license">
</p>

<p align="center">
  <img src="docs/images/notch-panel.png" width="480" alt="ai-helper preview">
</p>


<p align="center">
  <sub>Watch active coding sessions, answer follow-up questions, and jump back to the right terminal or IDE window.</sub>
</p>

<p align="center">
  <sub>Source: <a href="https://github.com/Miofly/vft-kit/tree/main/apps/ai-helper">Miofly/vft-kit/apps/ai-helper</a></sub>
</p>

<p align="center">
  <img src="docs/images/mascots/claude.gif" width="36" alt="Claude mascot" title="Claude Code">&nbsp;
  <img src="docs/images/mascots/codex.gif" width="36" alt="Codex mascot" title="Codex">&nbsp;
  <img src="docs/images/mascots/gemini.gif" width="36" alt="Gemini CLI mascot" title="Gemini CLI">&nbsp;
  <img src="docs/images/mascots/hermes.gif" width="36" alt="Hermes Agent mascot" title="Hermes Agent">&nbsp;
  <img src="docs/images/mascots/pi.gif" width="36" alt="Pi Agent mascot" title="Pi Agent">&nbsp;
  <img src="docs/images/mascots/qwen.gif" width="36" alt="Qwen Code mascot" title="Qwen Code">&nbsp;
  <img src="docs/images/mascots/kimi.gif" width="36" alt="Kimi CLI mascot" title="Kimi CLI">&nbsp;
  <img src="docs/images/mascots/openclaw.gif" width="36" alt="OpenClaw mascot" title="OpenClaw">&nbsp;
  <img src="docs/images/mascots/opencode.gif" width="36" alt="OpenCode mascot" title="OpenCode">&nbsp;
  <img src="docs/images/mascots/cursor.gif" width="36" alt="Cursor mascot" title="Cursor">&nbsp;
  <img src="docs/images/mascots/qoder.gif" width="36" alt="Qoder mascot" title="Qoder">&nbsp;
  <img src="docs/images/mascots/codebuddy.gif" width="36" alt="CodeBuddy mascot" title="CodeBuddy">&nbsp;
  <img src="docs/images/mascots/copilot.gif" width="36" alt="GitHub Copilot mascot" title="GitHub Copilot">
</p>
<p align="center">
  <sub>Claude Code · Codex · Gemini CLI · Hermes Agent · Pi Agent · Qwen Code · Kimi CLI · OpenClaw · OpenCode · Cursor · Qoder · CodeBuddy · GitHub Copilot</sub>
</p>

<a id="lets-try-it"></a>
## Let’s try it!

Detach the active pet from the notch and keep session status nearby while you work across other windows.

<p align="center">
  <img src="docs/images/demos/ai-helper-ask-tool-demo.gif" width="800" alt="ai-helper detached pet interaction demo">
</p>

On notch-screen Macs, ai-helper expands from the notch with session context and action controls when an agent needs attention.

<p align="center">
  <img src="docs/images/demos/ai-helper-question-demo.gif" width="800" alt="ai-helper notch interaction demo">
</p>

<a id="installation"></a>
## Installation

### Install through the vft-kit plugin (recommended)

```bash
# Claude Code
claude plugin marketplace add Miofly/vft-kit
claude plugin install vft-kit@vft-kit

# Codex
codex plugin marketplace add Miofly/vft-kit
codex plugin add vft-kit@vft-kit
```

Then ask Claude Code or Codex to “install ai-helper”. The bundled `install-ai-helper` skill downloads the release DMG and verifies its SHA-256, bundle ID, Developer ID signature, and Gatekeeper assessment. No source checkout or Xcode installation is required.

### Download a Release

1. Open [vft-kit Releases](https://github.com/Miofly/vft-kit/releases) and select an `ai-helper-v*` tag.
2. Download `AIHelper-<version>.dmg`.
3. Move `ai-helper.app` into your Applications folder.
4. Launch the app and start the clients you want ai-helper to monitor.

> On first launch, macOS may ask you to confirm the app or grant Accessibility / Apple Events permissions for focus features.

<a id="build-from-source"></a>
### Build from Source

Requires macOS 14+ and an Xcode toolchain that can build the Xcode project and the Swift 6.1 `Prototype` package tests.

```bash
git clone https://github.com/Miofly/vft-kit.git
cd vft-kit/apps/ai-helper

# Debug build
xcodebuild -project AIHelper.xcodeproj -scheme AIHelper -configuration Debug build

# Release build
xcodebuild -project AIHelper.xcodeproj -scheme AIHelper -configuration Release build
```

To create a locally shareable unsigned package for local testing:

```bash
./scripts/package-unsigned.sh
```

The script re-signs the built app bundle with a consistent ad-hoc signature before creating the `.dmg` and `.zip`, which helps embedded frameworks launch more reliably on another machine. The package is still unsigned for distribution and not notarized, so first launch may still require `Open` from Finder's context menu or manual quarantine removal.
The generated files land in `releases/unsigned/` as `AIHelper-<version>.dmg` and `AIHelper-<version>.zip`.
The DMG uses the repo-tracked installer artwork at `docs/images/ai-helper-dmg-installer-background.png` by default; set `PING_ISLAND_DMG_BACKGROUND_SOURCE` if you want to preview a different background locally.

Maintainers can run `./scripts/create-release.sh` to produce Developer ID signed, notarized packages and a SHA-256 checksum, then publish them under an `ai-helper-v<version>` tag.

## What is ai-helper?

ai-helper is a macOS menu bar app that expands into a compact session surface when your coding agents need attention. It listens to Claude-style hooks, Codex hooks, Gemini CLI hooks, Hermes Agent plugin hooks, Pi Agent extension hooks, Qwen Code hooks, Kimi CLI hooks, OpenClaw internal hooks plus session transcripts, the Codex app-server, OpenCode plugins, and compatible IDE integrations so approvals, input requests, completions, and session summaries show up without babysitting terminal tabs.

If you have seen [Vibe Island](https://vibeisland.app/), ai-helper is positioned as an independent open-source alternative in the same category: a native macOS notch/menu bar surface for monitoring and controlling AI coding sessions.

## Features

ai-helper focuses on the moments that actually interrupt coding flow, then keeps them visible and actionable from a native macOS notch surface.

- **Attention-first UI** - Stay compact until a session needs approval, input, review, or intervention.
- **Act from the notch** - Approve tools, deny requests, and answer follow-up prompts without hunting through tabs.
- **Claude Code auto-approve** - Turn on per-session auto-approval when you want Claude Code to stop pausing on every permission request.
- **One-click return** - Jump back to the right iTerm2, Ghostty, Terminal.app, tmux pane, or IDE window.
- **SSH terminal support** - Bootstrap a remote AIHelperBridge over SSH, rewrite remote hooks to point back at your Mac, forward remote Codex app-server activity, and keep remote terminal activity visible in the same local Island UI.
- **Multi-agent coverage** - Track Claude Code, Codex, Gemini CLI, Hermes Agent, Pi Agent, Qwen Code, Kimi CLI, OpenClaw, OpenCode, Cursor, Qoder, CodeBuddy, WorkBuddy, GitHub Copilot, and other compatible sessions in one place.
- **Quota at a glance** - The menu bar summarizes Claude and Codex usage together. Subscription logins show Codex 5h / 7d quota and reset countdowns, while API-key sessions fall back to the latest local session token total.
- **OpenClaw gateway support** - Follow OpenClaw sessions from managed internal hooks, then refill the conversation from OpenClaw's local session transcripts so the Island UI can show the actual back-and-forth instead of a single inbound message.
- **Codex hook + app-server sync** - Support Codex CLI hooks, live app-server threads, and rollout parsing fallback when needed.
- **Custom sounds** - Pick per-event macOS sounds or import local sound packs for your own notification style.
- **Custom agent mascots** - Give each client its own animated mascot override across the notch, session list, and hover UI.
- **Buddy detach in v0.5.0+** - Drag the active Buddy out of the notch so it can stay nearby as an independent floating companion.
- **Hermes courier-fox mascot** - Hermes Agent uses a gold courier fox with a winged helmet and satchel so plugin-hook sessions stay visually distinct from the Claude/Qwen family.
- **Pi terminal-cloud mascot** - Pi Agent uses its own terminal-cloud mascot so extension-hook sessions are easy to spot in the Island UI.
- **Qwen capybara mascot** - Qwen Code now ships with a mint-scarf capybara mascot tuned for prompt, reply, and notification-heavy flows.
- **Kimi keyboard-orb mascot** - Kimi CLI keeps its original blue keyboard-orb mascot so its hook sessions stay visually distinct in the README strip and app UI.

<a id="supported-clients"></a>
## Supported Clients

| Client | Ingress | Focus / return path | Island capabilities |
| --- | --- | --- | --- |
| Claude Code | Claude-compatible hooks through `AIHelperBridge` | Terminal.app, iTerm2, Ghostty, tmux, and IDE terminals | Tool approvals, AskUserQuestion replies, compaction alerts, completion popups, auto-approve |
| Codex App + Codex CLI | Codex CLI hooks, live `codex app-server`, rollout parsing fallback | Codex app, terminal, tmux, and IDE terminals | Approval/input requests, live thread sync, usage snapshots, remote app-server forwarding |
| Gemini CLI | Gemini CLI hooks in `~/.gemini/settings.json` | Compatible terminal hosts | Session lifecycle, tool activity, notifications, pre-compaction events |
| Hermes Agent | Official plugin hooks in `~/.hermes/plugins/ping_island/` | Hermes CLI terminal host | User prompts, tool activity, assistant replies, session-end notifications |
| Pi Agent | Official extension under `~/.pi/agent/extensions/ping_island/` | Pi Agent terminal host | Extension event forwarding, client-aware session tracking, terminal-cloud mascot |
| Qwen Code | Official hooks in `~/.qwen/settings.json` | Compatible terminal hosts and remote SSH sessions | Permission prompts, notification popups, stop/session-end handling, remote hook forwarding |
| Kimi CLI | Official `[[hooks]]` entries in `~/.kimi/config.toml` | Compatible terminal hosts | Tool activity, notifications, turn completion, session-end handling |
| OpenClaw | Managed internal hooks plus local transcript refresh | OpenClaw terminal host | Fast hook status, transcript backfill, message/session state |
| OpenCode | Generated plugin file under `~/.config/opencode/plugins/` | OpenCode app and terminal host | Plugin event forwarding into the shared Island UI |
| Cursor | Claude-compatible hooks plus optional VS Code-compatible focus extension | Cursor project window and active terminal | IDE routing, terminal focus, Claude-family session tracking |
| Qoder / Qoder CLI / QoderWork | Managed hook profiles in `~/.qoder/settings.json` and `~/.qoderwork/settings.json` | Qoder windows, terminal, and supported IDE extension paths | Separate IDE/CLI semantics, approvals where supported, notify-only handling for QoderWork |
| CodeBuddy / WorkBuddy | Managed hook profiles plus optional VS Code-compatible focus extension | App windows, terminal, and supported IDE extension paths | Claude-family session tracking, client-aware jump-back, follow-up visibility |
| GitHub Copilot | Copilot hook protocol | Compatible terminal hosts | Copilot CLI / agent hook event status |

## Testing

The fastest full-repo regression path is:

```bash
./scripts/test.sh
```

That covers:

```bash
swift test --package-path Prototype
xcodebuild -project AIHelper.xcodeproj -scheme AIHelper -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:AIHelperTests
xcodebuild -project AIHelper.xcodeproj -scheme AIHelper -configuration Debug CODE_SIGN_IDENTITY=- test
```

Useful targeted slices:

```bash
swift test --package-path Prototype --filter IslandBridgeE2ETests
xcodebuild -project AIHelper.xcodeproj -scheme AIHelper -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:AIHelperTests
xcodebuild -project AIHelper.xcodeproj -scheme AIHelper -configuration Debug CODE_SIGN_IDENTITY=- test -only-testing:AIHelperUITests
```

If `AIHelperUITests-Runner` stays suspended on macOS, run the UI tests from Xcode with a valid local signing identity and check `amfid` / `AppleSystemPolicy` logs before treating it as an app regression.

## Settings

ai-helper currently ships a 4-category settings panel:

- **General** - launch at login and baseline app behavior
- **Display** - notch display target and placement behavior
- **Mascot** - client mascot previews, per-client overrides, animation states
- **Sound** - event-specific sounds, sound pack mode, sound pack import

## Custom Sounds

ai-helper currently supports three sound modes under `Settings -> Sound`:

- **System sounds** - choose a macOS sound for each event.
- **Built-in 8-bit** - use Island's bundled retro sound set, including the fixed client startup sound.
- **Sound pack** - load a local OpenPeon / CESP-compatible pack from disk.

### Quick setup

1. Open `Settings -> Sound`.
2. Turn on `Enable sounds`.
3. Pick the mode you want:
   - `System sounds` if you just want a different macOS sound per event.
   - `Sound pack` if you want fully custom audio files.
4. Preview each event with the play button and leave only the event toggles you want enabled.

### Import a local sound pack

1. Switch `Sound mode` to `Sound pack`.
2. Click `Import local sound pack`.
3. Choose a folder that contains `openpeon.json`.
4. Pick the imported pack from the `Sound pack` dropdown.

ai-helper also auto-discovers packs placed under `~/.openpeon/packs` and `~/.claude/hooks/peon-ping/packs`.

### Minimal sound pack layout

```text
my-pack/
  openpeon.json
  session-start.wav
  attention.ogg
  complete.mp3
  error.wav
  limit.wav
```

```json
{
  "cesp_version": "1.0",
  "name": "my-pack",
  "display_name": "My Pack",
  "categories": {
    "task.acknowledge": {
      "sounds": [{ "file": "session-start.wav", "label": "Session Start" }]
    },
    "input.required": {
      "sounds": [{ "file": "attention.ogg", "label": "Attention" }]
    },
    "task.complete": {
      "sounds": [{ "file": "complete.mp3", "label": "Complete" }]
    },
    "task.error": {
      "sounds": [{ "file": "error.wav", "label": "Error" }]
    },
    "resource.limit": {
      "sounds": [{ "file": "limit.wav", "label": "Limit" }]
    }
  }
}
```

### Event mapping

- `Processing started` checks `task.acknowledge`, then `session.start`.
- `Attention required` checks `input.required`.
- `Task completed` checks `task.complete`.
- `Task error` checks `task.error`.
- `Resource limit` checks `resource.limit`.

Release builds can also publish a Linux `AIHelperBridge` artifact alongside the macOS app packages, which ai-helper uses when bootstrapping remote SSH hosts that are not running macOS.

Sound packs can use `.wav`, `.mp3`, or `.ogg` files. If a selected pack does not provide a matching category for an event, ai-helper falls back to the macOS system sound selected for that event.

## How It Works

```text
Claude / Codex / Gemini CLI / Hermes Agent / Pi Agent / Qwen Code / Kimi CLI / OpenCode / Cursor / Qoder / CodeBuddy / WorkBuddy / Copilot / ...
  -> hook or app-server event
    -> ai-helper monitor + normalization layer
      -> SessionStore
        -> SessionMonitor / NotchViewModel
          -> notch, list, hover preview, completion popup
```

Implementation details worth knowing:

- Claude-family tools enter through managed hook files plus the embedded `AIHelperBridge` launcher.
- Codex sessions can come from hook events or the live `codex app-server` websocket monitor.
- Gemini CLI hooks are installed into `~/.gemini/settings.json`; tool matchers use Gemini's regex-based hook matcher syntax.
- Pi Agent is wired through a generated TypeScript extension under `~/.pi/agent/extensions/ping_island/` and forwards events through the Claude-compatible bridge with Pi-specific client metadata.
- Qwen Code hooks are installed into `~/.qwen/settings.json`; the bridge follows the official event names and uses `Stop` / `SessionEnd` / `Notification` messages to surface popup-ready summaries in Island.
- Kimi CLI hooks are installed into `~/.kimi/config.toml`; ai-helper preserves unrelated TOML content and maps Kimi `Stop` to turn completion while `SessionEnd` closes the session.
- OpenCode is wired through a generated plugin file under `~/.config/opencode/plugins/` and enabled from the documented global config at `~/.config/opencode/opencode.json`; legacy `config.json` entries are still recognized for cleanup.
- Remote SSH hosts can bootstrap `AIHelperBridge`, rewrite remote Claude-compatible hooks to target that bridge, and forward remote events back into the local ai-helper UI.
- Focus routing spans iTerm2, Ghostty, Terminal.app, tmux, and VS Code-compatible IDE extensions.

## Requirements

- macOS 14.0 or later
- Best experience on MacBooks with a notch, but external displays are supported too
- Install whichever CLI or desktop clients you want ai-helper to monitor

## Contributors

Thanks to everyone who has helped shape ai-helper through code, issues, ideas, testing, docs, design feedback, and release validation.

See the full contributor history on the [GitHub contributors graph](https://github.com/Miofly/vft-kit/graphs/contributors).

## Acknowledgments

ai-helper follows the lineage of notch-first agent monitors such as [claude-island](https://github.com/farouqaldori/claude-island), and adapts that idea into a broader multi-client session surface with hooks, app-server sync, and IDE routing.

## License

Apache 2.0 - see [LICENSE.md](LICENSE.md).
