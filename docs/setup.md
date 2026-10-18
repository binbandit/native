# Set up Native

How to set Native up for an engineer, on one Mac or across their devices, and fix what isn't
working. It covers installing, agents and signing in, projects, MCP servers, skills, the terminal,
appearance, notifications, shortcuts, the iPhone companion, organization policy and
troubleshooting, starting from the `setup_status` tool.

This file is the canonical setup guide. Native serves it to agents as the `set-up-native` skill (the
`get_skill` tool of its `native` MCP server), so it's written for an agent doing the setup with a
person as much as for the person. Where it says "not available yet", the piece is designed (the
linked doc says how) but not built: say so, and don't invent a way around it.

## If you're an agent

**Start with `setup_status`** on the `native` MCP server. It's read-only and reports, for the Mac
your session runs on, six checks in this order:

1. **Native**: version, build and channel (`stable`, `beta`, `nightly`, or `dev` for a build run from
   source).
2. **Agents**: every agent a plugin provides: `state` (`ready`, `starting`, `stopped`,
   `not_installed`, `turned_off`, `not_allowed`), `sign_in` (`signed_in`, `needs_sign_in`,
   `signing_in`, `unknown`), the version it reported, how Native launches it, the command missing from
   the PATH, and its plugin's install and sign-in commands. `is_caller` marks the agent you are.
   Native only learns an agent is signed out when it turns a session away, so `unknown` is normal
   for an agent with no session open yet.
3. **Durable host**: the background host that keeps agents running after Native quits, and that
   paired devices connect through: `off`, `starting`, `connected`, `reconnecting`, `unreachable`,
   `incompatible`, `needs_approval` or `failed`, with its version.
4. **Paired devices**: how many are paired and connected, whether connections are allowed, whether
   the gateway is listening on the network, and whether a pairing code is showing.
5. **Organization**: which `policy.*` keys a configuration profile manages (keys only), and keys
   whose values were ignored as invalid.
6. **Updates**: state, channel, an available version, automatic checks and downloads, and why
   updates are off when they are.

Its text answer is that checklist, each problem with where to fix it; its structured answer has the
same fields. Call it again after the user changes something, rather than assuming it worked.

**What you can do yourself**, in your own shell, after asking the user:

- Check what Native sees: agents run through the user's login shell, so test commands the same way:
  `"$SHELL" -lc 'command -v claude codex cursor-agent opencode pi copilot npx gh git'`.
- Install an agent's CLI with the command `setup_status` lists (`install_command`), or into a
  location the user picks (an npm `--prefix`, a Homebrew prefix), as long as that folder ends up on
  the login shell's PATH. Ask before editing shell startup files (`~/.zprofile`, `~/.zshrc`).
- Download a release with `gh release download` or `curl`, when the user wants you to.
- Write a `plugin.json` into Native's plugins folder, for an agent Native doesn't know or an MCP
  server every session should get. Read the `build-a-native-plugin` skill first; this skill's
  "On this Mac" section names the folder Native reads.
- Draft a project's setup script, a Ghostty config, or a configuration profile from the sample, and
  write it where the user says.
- Read Native's logs: `log show --last 15m --style compact --predicate 'subsystem == "Native"'`.

**Leave Native's window to the user.** You can't click its UI, and its settings aren't files to
edit: don't write its preferences (`defaults write`) or its Application Support folder. Give the user
the exact place, as Settings labels it ("Settings ▸ Agents ▸ Add an Agent ▸ Check Again"), without
explaining why you can't do it yourself. Settings opens with ⌘, in the main window, and ⌘F there
searches every row by name. Sign-in commands open a browser and wait, so the user runs them (in
Native's terminal, ⌃`, or any terminal) rather than you.

Don't change agents' own configuration (`~/.claude`, `~/.codex`, …) or shell files without asking,
never ask for API keys or tokens in the conversation, and don't install anything globally the user
didn't agree to.

**A setup session.** When the user asks you to set Native up:

1. Call `setup_status`, and open with a short summary: what already works, what's missing, and the
   plan.
2. Agents: offer to install the ones that are `not_installed` (the user may not want them all), fix
   any that are `stopped` or `needs_sign_in`, and for `unknown` sign-ins say that starting a task on
   the agent shows whether it's signed in.
3. Projects: ask which folders they work in and how they like branches, then the Settings ▸ Git
   choices below, drafting a setup script if a project needs one.
4. Every device they mention, in this order: the durable host, then pairing. Say plainly what isn't
   available yet and what they can do now, and get the Mac side ready anyway.
5. Offer the rest (MCP servers, skills, terminal, appearance, notifications, keeping awake,
   shortcuts) as options rather than walking through all of it.
6. Finish with `setup_status` again and a short list of what's done and what's left.

Give the user one group of steps at a time, each with its Settings path, and check with
`setup_status` when they say it's done.

## Installing Native

Native needs macOS 27. It ships through
[GitHub Releases](https://github.com/binbandit/native/releases) and updates itself after that
([docs/releasing.md](https://github.com/binbandit/native/blob/main/docs/releasing.md)).

| Channel | What it is | Get it |
| --- | --- | --- |
| Stable | tested releases | the latest release (`v1.4.0`), `Native-<version>.dmg` |
| Beta | upcoming features a few weeks early | a prerelease (`v1.5.0-beta.1`); or, in a stable install, Settings ▸ Updates ▸ Update channel ▸ Beta |
| Nightly | built from `main` every night | the rolling `nightly` prerelease, `Native-Nightly.dmg` |

Open the DMG and drag the app to Applications. Builds are signed and notarized. Native Nightly is a
separate app (Native Nightly.app) with its own settings, data and background host, so it installs
beside Native and the two never share anything. A beta user still gets stable releases; switching
back to Stable keeps the beta until a newer stable release arrives.

Check what's published with `gh release list -R binbandit/native`. If nothing is, there's no
download yet: build from source instead (macOS 27 and Xcode 27.1, see the
[README](https://github.com/binbandit/native#build-and-run)). A build run from source is the `dev`
channel and never updates itself.

**Updates** are in Settings ▸ Updates: Version, Update channel, Check for updates automatically and
Download updates automatically (both on by default), and Show What's New. Native ▸ Check for
Updates… checks now. A downloaded update installs when Native quits, or with Restart to Update.

## Agents

Every agent is a plugin that speaks the [Agent Client Protocol](https://agentclientprotocol.com).
Native runs the user's own CLI for each one, found on their login shell's PATH; agents that don't
speak ACP themselves go through an adapter that Native runs with `npx`, pinned to a version, so
those need Node.js. Details per agent: [docs/agents.md](https://github.com/binbandit/native/blob/main/docs/agents.md).

| Agent | Needs on the PATH | Install (from its plugin) | Sign in |
| --- | --- | --- | --- |
| Claude Code | `claude`, `npx` | `npm install -g @anthropic-ai/claude-code` | in a terminal: `claude`, then `/login` |
| Codex | `codex`, `npx` | `npm install -g @openai/codex` | Sign In… in Native, or `codex login` |
| Cursor | `cursor-agent` | `brew install --cask cursor-cli` | Sign In… in Native, or `cursor-agent login` |
| OpenCode | `opencode` | `brew install anomalyco/tap/opencode` | none for its free models; `opencode auth login` for others |
| Pi | `pi`, `npx` (Node 22 or later) | `npm install -g --ignore-scripts @earendil-works/pi-coding-agent` | `pi`, then `/login`; or provider API keys in the login shell's environment |
| Copilot | `copilot` | `brew install --cask copilot-cli` | `copilot login`, or an existing `gh` login or `GH_TOKEN` |

`setup_status` gives the exact launch command and install command this copy of Native uses; prefer
those over this table.

**Finding an agent.** Installed agents are listed in Settings ▸ Agents, each with a switch, its
launch command, and a ⋯ menu with Restart and, when the agent asks for it, Sign In…. Agents Native
knows but can't find are under Settings ▸ Agents ▸ Add an Agent, with their install command and docs
(Native never runs them). After installing one, the user chooses Check Again there; Native reads the
login shell's PATH again, no relaunch needed. "Nothing new on your PATH" means the new command isn't
visible to a login shell: check with `"$SHELL" -lc 'command -v <command>'` in a new terminal.

**Signing in.** OpenCode, Pi and Copilot sign in only in a terminal: Sign In… opens a sheet running
the agent's own sign-in command, and closes it once that succeeds. Codex and Cursor sign in over ACP
from Sign In…. Claude Code's adapter offers no sign-in, so the user runs `claude` and `/login` in a
terminal, then Restart Claude Code from its ⋯ menu.

**Defaults.** Under each agent in Settings ▸ Agents, "Defaults for new tasks" sets its default model
and effort, once a task has run on it. Settings ▸ General ▸ Follow-up behavior chooses whether
Return queues a message for after the turn (Queue) or adds it to the turn in progress (Steer).

An agent Native doesn't know is a plugin: see the `build-a-native-plugin` skill.

## Projects

The user adds a project with Add Project in the sidebar or File ▸ Open Folder… (⌘O); tasks start
in it. Settings ▸ Git sets how
new tasks get their branch and worktree, with the user's own git:

- **New tasks get**: Its own worktree (the default; worktrees live in `~/.native/worktrees`, so
  parallel tasks never edit the same files) or A branch in the project folder.
- **Branch prefix**: GitHub login (the default, `<login>/`), Custom, or None. **Rename branches from
  the task** renames a new branch after the task's title until it's pushed.
- **Files to copy into new worktrees**: ignored files a task needs, as gitignore patterns (`.env*`
  by default).
- **Delete the branch when archiving** (off by default; the commits stay reachable).
- **Setup scripts**, per project: Add Script…, pick the project's folder, write the script, ⌘Return
  saves. It runs in each new worktree after the env files are copied, to install dependencies or
  start services. You can draft the script; the user pastes it in.

Pull requests go through the user's GitHub CLI: Settings ▸ GitHub needs `gh` (`brew install gh`)
signed in (`gh auth login`), and sets whether pull requests open in Native or the browser.

## MCP servers

Settings ▸ MCP Servers has two lists:

- **Set up in Native**: servers Native hands to the agents and projects chosen for each (all of
  them by default), in every session they start. Add Server takes a name and a local command (run
  with the user's shell environment, so `npx` and `uvx` work) with environment variables, or a
  remote URL with headers. Import into Native, on a row in the other list, copies an agent's own
  server here.
- **Loaded by your agents**: what each agent's own configuration loads (Claude Code, Codex and
  Cursor). Changes there go through the agent's own CLI, never by editing its files, and Native
  doesn't hand an agent a second copy.

Check All starts or reaches every server, lists its tools and disconnects, without calling any; a
row's details show its tools and how much context their definitions take. Each row's switch turns a
server off for new sessions, and its ⋯ menu sets how agents reach it (Agents Reach It):

- **Loaded into Each Session**, the default.
- **Through Native's Scripts**: agents don't load the server; they call its tools from Native's
  `run_script` instead, so a heavy server (one with a hundred tools can take most of a session's
  context) costs nothing until it's used. Needs a build with the script runtime, and the
  organization can turn scripts off.

Changes apply to sessions started afterwards. Claude Code gets them per session; Codex reads them
when it restarts (Native restarts it once idle, or right away with Apply to Running Sessions), and
for Codex switching a server off is best effort. Cursor's own servers can't be switched off from
Native. ⌃⌘M shows the current session's servers. Why each agent behaves this way:
[docs/agent-session-overrides.md](https://github.com/binbandit/native/blob/main/docs/agent-session-overrides.md).

A server that should come with Native everywhere can also be a plugin (`build-a-native-plugin`).

## Skills

Settings ▸ Skills lists every skill the user's agents load (from user, project and agent folders),
grouped by name, with one switch per skill that applies across agents, globally or per project.
Install Skill takes a git URL, `owner/repo`, a folder or a skill from skills.sh, shows every file
before writing anything, and can be undone. Switches reach Claude Code per session and Codex at
launch; Cursor, OpenCode, Pi and Copilot can't be switched from Native, and their rows say so.
Details: [docs/skills.md](https://github.com/binbandit/native/blob/main/docs/skills.md).

Native's own skills (`build-a-native-plugin` and this one) are listed under Native's skills, served
to every agent through the `native` MCP server, each with its own switch.

## Terminal

Every task has a terminal panel under its composer, drawn by libghostty (the library inside
[Ghostty](https://ghostty.org)): ⌃` shows and hides it, ⌃⇧` adds a tab. Settings ▸ Terminal:

- **Use my Ghostty settings** loads the user's own Ghostty config live (theme, font, cursor,
  padding, key bindings), from `~/.config/ghostty/config` and Ghostty's other locations. Ghostty.app
  isn't required, but its bundled themes are only found when it's installed. Problems in the config
  are listed with their file and line, and Native's settings apply until it loads.
- **Import from Ghostty** copies the font, size, theme or palette, cursor and scrollback into
  Native's settings once, showing each change, with Undo.
- Otherwise: Shell (the login shell by default), Font, Font size, Cursor, Scrollback and Terminal
  colors.

A build without libghostty says "Terminal isn't available in this build". More:
[docs/terminal.md](https://github.com/binbandit/native/blob/main/docs/terminal.md).

## Appearance

Light and dark follow macOS. Settings ▸ Appearance: App icon and Icon appearance (Mac only), Light
mode (Paper, crisp white, or Wool, a warm off-white), Transparency (Reduce Transparency in macOS
keeps it solid), Accent (Match app icon, or a plugin's accent), Code font (family, size, line height,
ligatures) and Code theme (one for light mode and one for dark). Plugins can add code themes,
accents and icon sets.

## Notifications, sounds and keeping awake

- **Settings ▸ Notifications**: When long work finishes, and Long means (shorter turns finish
  quietly); When a task needs you (permission requests and questions, answerable from the
  notification); Usage limits; Dock badge. Native notifies only when the user is in another app or
  task. If nothing ever arrives, macOS notifications for Native are off: System Settings ▸
  Notifications ▸ Native.
- **Settings ▸ Sounds**: Play sounds, Volume, When to play, and a sound per event under "Play a
  sound when" (Native's, the user's own with Add Sound…, or the reference app's when it's installed). Stay
  quiet during Focus works only in builds that can read Focus status; the row says when it can't.
- **Settings ▸ Keep Awake**: Keep Mac awake (Off, While Agents Work, On), Stay awake for a while (a
  timer), Keep display on, and On battery (Keep awake, Stop below 10%, Don't keep awake). Closing the
  lid still sleeps the Mac. ⌃⌘A cycles the mode.

## Shortcuts

Settings ▸ Keyboard shortcuts lists every command: click a shortcut to record a new one,
right-click for more, and the ⋯ menu has Import…, Export… and Reset All…. Exporting is how to carry
shortcuts to another Mac. ⌘K opens the command palette, which runs any command and jumps to any
task, project or Settings page. Defaults:
[docs/keyboard.md](https://github.com/binbandit/native/blob/main/docs/keyboard.md).

## Several devices

### More than one Mac

Install Native on each Mac; nothing syncs between them. To match a setup, run this skill on each
one, copy the plugins folder (`~/.native/plugins`), export and import shortcuts, and redo the
choices in Settings ▸ Git (setup scripts are stored per Mac). Agents keep their own sign-ins and
configuration on each machine.

### The durable host

Native's background host runs agents outside the app, so its sessions keep going when the window
closes, Native quits or it updates, and it resumes interrupted turns after a crash or a restart. The user turns it on in Window ▸ Durable
Sessions ▸ Turn On. On a release build it registers as a login item named Native; if macOS's
"Allow in the Background" switch for Native is off, `setup_status` says `needs_approval` and the
window offers Allow in Login Items… (System Settings ▸ General ▸ Login Items & Extensions).

What runs there today: sessions started from the Durable Sessions window, and everything paired
devices do. Tasks in the main window still run inside the app and stop when it quits; moving them
into the host is designed but not available yet
([docs/durability.md](https://github.com/binbandit/native/blob/main/docs/durability.md),
"Migration").

### The iPhone companion

The companion follows tasks, answers approvals and questions, sends follow-ups and starts tasks
from the iPhone, over an end-to-end encrypted connection to the Mac's durable host
([docs/companion.md](https://github.com/binbandit/native/blob/main/docs/companion.md)).

On the Mac:

1. Turn on the durable host (above). Settings ▸ Paired Devices offers Turn On too.
2. Settings ▸ Paired Devices ▸ Pair iPhone… shows a QR code and a six-character code, valid for five
   minutes and one use. Nothing listens on the network before this.
3. On the phone, in Native, tap Pair with Your Mac (or Add Host in its Settings) and scan the code;
   the iPhone's Camera works too, since the code is a link that opens the app. Without a camera,
   pick the Mac the phone found and type the code shown under "No camera? Enter this code instead".
   With a typed code, both screens show a verification code: pair only if they match.
4. The Mac asks Pair "<device>"?, with Allow installing updates for this Mac's Native and Allow
   turning plugins on and off. Both can change later in the device's ⋯ menu (Can Install Updates,
   Can Turn Plugins On and Off), beside Rename… and Remove.

Allow paired devices to connect turns every pairing off without forgetting it. The phone finds the
Mac over Bonjour on the same network; away from it, the QR code carries the Mac's Tailscale address
when it has one, so with Tailscale on both devices the phone reaches it anywhere.

Not available yet (get the Mac side ready anyway, so pairing is one step once it is):

- **The companion on a real iPhone.** There's no App Store or TestFlight build, and device signing
  isn't set up. Engineers can run it in the iOS Simulator from source
  (`Companion/NativeCompanion.xcodeproj`), choosing the Mac in Add Host or pasting the pairing link,
  since the Simulator can't scan.
- **Push notifications and Live Activities**: the companion notifies only while it's open.
- **A relay** for reaching the Mac without Tailscale.
- **The iPad app.** The iPad is designed to run the full app as a client of a host.

### Several Natives on one phone

The companion pairs with each host separately and keeps them apart: its own key, connection, name,
color and notifications per host, with tasks grouped by host. Each Mac is a host, and so is Native
Nightly beside Native on the same Mac (a second Native takes another port). Pair each one from its
own Settings ▸ Paired Devices; removing one never touches the others.

### Remote hosts and Linux run boxes

Not available yet. The design: a Mac pointed at a Mac mini or a Linux server, connected over the
user's SSH (`ssh <machine> native-host attach`), with Add Host… provisioning the `native-host`
binary and a user service there and listing missing agent CLIs
([docs/durability.md](https://github.com/binbandit/native/blob/main/docs/durability.md),
"Provisioning a remote host"). Built so far: the standalone `native-host` (`serve` and `attach`) for
macOS, published with each release; the app's side of the SSH connection and Linux builds aren't.
`policy.remoteHosts.enabled` exists for when they are.

## Organizations

An organization deploys settings as a configuration profile for Native's bundle id with its device
management (Jamf, Kandji, Intune). macOS applies them as forced preferences; each managed setting
shows "Managed by your organization" and is locked in Settings, and a value Native can't use is
ignored and logged, never a lockout. Full reference:
[docs/enterprise.md](https://github.com/binbandit/native/blob/main/docs/enterprise.md).

Start from the sample profile,
[docs/enterprise/native-policy.mobileconfig](https://github.com/binbandit/native/blob/main/docs/enterprise/native-policy.mobileconfig),
which has every key: replace `NATIVE_BUNDLE_ID` (read it from the installed app with
`defaults read /Applications/Native.app/Contents/Info.plist CFBundleIdentifier`; Nightly has its
own), give every `PayloadUUID` a fresh `uuidgen`, and delete the keys the organization doesn't
manage. The keys:

| Key | Manages |
| --- | --- |
| `policy.agents.allowed`, `policy.agents.environment` | which agents may run; extra environment per agent, such as routing Claude Code through Bedrock or Vertex |
| `policy.mcp.allowed`, `policy.mcp.blocked`, `policy.mcp.required` | MCP servers by name or `command:` pattern; servers every session gets |
| `policy.plugins.allowed` | which plugins may load |
| `policy.skills.blocked` | skills turned off for every session |
| `policy.permissions.forbiddenModes` | permission modes users can't pick |
| `policy.scripts.enabled`, `policy.labs.enabled` | the script runtime and `run_script`; Labs and experiments |
| `policy.companion.enabled` | pairing devices |
| `policy.remoteHosts.enabled` | remote hosts, which aren't available yet |
| `policy.updates.feedURL`, `policy.updates.enabled`, `policy.updates.channels` | an internal update feed, updates off, allowed channels |
| `policy.search.retentionDays` | how long search keeps sessions |
| `policy.shortcuts.bindings` | shortcuts, in the format Settings ▸ Keyboard shortcuts exports |
| `policy.telemetry.native`, `policy.telemetry.endpoints` | Native's own telemetry (`on`, `off`, or `user`); the organization's OpenTelemetry collectors |

Native's own telemetry is off until the user opts in (Settings ▸ Privacy ▸ Share anonymous usage
with Native, with Show what Native sends), and never carries prompts, code, paths or commands. After
deploying, `setup_status` lists the managed keys and any it ignored. Not available yet: requiring
plugin signers, an organization plugin catalog, shared team hosts, and an admin view of the policy.

On a build run from source, which can't take a profile without enrolling the Mac, keys can be marked
managed for testing with `defaults write <bundle id> policy.debug.managedKeys -array <keys…>`.

## Troubleshooting

Go through `setup_status` in its order, fixing the first problem before the next:

1. **No `native` tools in your session.** The Orchestration extension is off (Settings ▸
   Extensions), or the agent doesn't pass Native's MCP servers on: Pi's adapter doesn't yet, so Pi
   sessions never see them. Use another agent for setup.
2. **An agent is `not_installed`.** Install the missing command, make sure a login shell finds it,
   then Settings ▸ Agents ▸ Add an Agent ▸ Check Again. For adapters, `npx` (Node.js) must be on the
   PATH too.
3. **An agent is `stopped`.** `problem` is the first line of the failure. The full output, with what
   the agent logged, shows when the user opens a task on it ("Couldn't Start <agent>", with
   Restart). Fix the cause (often an outdated CLI or Node), then Restart from its ⋯ menu in
   Settings ▸ Agents.
4. **`needs_sign_in`**, or a task that fails asking for a sign-in. Sign In… from the agent's ⋯ menu,
   or the agent's own command in a terminal followed by Restart. An expired login can look like an
   error rather than a sign-in (OpenCode's "Token refresh failed: 401") or, for Pi, a turn with no
   reply: sign in again.
5. **`turned_off` or `not_allowed`.** The switch on its row in Settings ▸ Agents, or the
   organization's policy, which the user can't change.
6. **The durable host** is `needs_approval` (Allow in the Background is off for Native), `failed`,
   or `unreachable`: the Durable Sessions window shows the reason, with Turn Off and Stop Host and
   Agents to start over. After an update, a host running the older build switches over once its
   tasks finish, or at once with Restart Host Now.
7. **The phone can't pair or connect.** The durable host must be on, Allow paired devices to connect
   on, and the gateway listening; the phone and Mac on the same network (or both on Tailscale); a
   code is single use and lasts five minutes, so open Pair iPhone… again for a fresh one. "Removed on
   the Mac" on the phone means the device was removed: pair it again.
8. **Updates are `unavailable`.** Builds run from source never update; the organization may manage
   updates. A `failed` check says what happened, and Native stays on its version.
9. **Settings are locked** ("Managed by your organization"): the organization manages that key.

If none of that explains it, read the logs (above) and tell the user what you found, with the
exact message, rather than guessing.
