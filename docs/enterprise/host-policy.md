# Host policy: the host enforces its own

Native's host runs agents, commands and updates whether or not the app is open, for the Mac's own
app and for paired devices. So the organization's policy has to hold on the host itself, not only
in the app that shows it. This is Phase A's A2-A4 in the
[regulated environments plan](../plans/regulated-environments.md): the host loads its policy before
it does anything, checks it again where each side effect happens, and ends what a revoked policy no
longer allows. It does not make the restricted profile usable yet: most capabilities stay off in
restricted mode until their own work lands (below).

## Where the host reads its policy

The host reads the policy itself, from the machine. Nothing a client sends is policy: not an agent
spec, an environment variable, a request's params or a client's name.

| Host | Source |
| --- | --- |
| Mac helper inside Native.app (bundle id `<app id>.Host`) | The managed preferences of Native.app's domain (`<app id>`), the same configuration profile the app reads. A development build's host reads its own build's domain (`dev.binbandit.native.dev.<name>`), never the installed app's. |
| Standalone `native-host` release on a Mac | The release app's domain for its channel: `dev.binbandit.native`, or `dev.binbandit.native.nightly` on nightly. |
| `native-host` built locally (`swift build`, tests) | None: it has no bundle identifier, so no organization manages it. |
| Linux | No managed source is supported yet. A file at `/etc/native/host-policy` asks for one, so the host blocks everything with side effects rather than run unrestricted. Without the file, the host is unmanaged, as before. |

`MacHostPolicySource` (`Packages/NativeHost/Sources/NativeHostMac/`) reads the domain through
cfprefsd: a value a profile forces is the organization's, any other the user's, and launch arguments
never reach it. `NativePolicy` resolves it, so the host and the app agree on every key, on malformed
input and on [restricted enrollment](../enterprise.md#restricted-deployment): the host keeps its own
enrollment record in `policy-enrollment.json` beside its store, so removing a restricted profile
while no app runs keeps the host blocked until the organization deploys ordinary mode. The host
reads the policy again every 10 seconds, so a profile installed or removed while no app runs takes
effect. A source that can't read or validate the policy returns a blocked policy, never the last
good one.

## Modes and capabilities

`HostPolicy` (`Packages/NativeHost/Sources/NativeHost/HostPolicy.swift`) is one of three modes with
a closed set of capabilities:

- **Ordinary**: everything the host has always done, minus what the app's own decision for the same
  feature denies (`NativePolicy.decision(for:)`, [policy coverage](policy-coverage.md)), including
  when a managed value it depends on is malformed: `agents` follows `agents.execution` and covers
  only the ids in `policy.agents.allowed`, `agentTools` follows `orchestration`, `companion`
  `hosts.pairing`, and `updates` `updates.host`, the host's channel in `policy.updates.channels`
  and a valid `policy.updates.feedURL`.
- **Restricted** (`policy.deployment.mode` is `internalOnly` or `airGapped`): only the capabilities
  qualified for restricted mode, and only where the app's decision permits them too.
- **Blocked**: the managed policy is malformed, can't be read, names a mode Native doesn't know,
  sets keys it doesn't know in restricted mode, or was removed after a restricted enrollment.
  Nothing with side effects.

| Capability | What it covers | Restricted mode |
| --- | --- | --- |
| `agents` | Agent processes: sessions, prompts, recovery, sign-in, queued messages, tasks agents start for each other | Not available |
| `loginShell` | Reading the user's login-shell environment, which runs their shell's startup files | Not available |
| `commands` | Clients' commands (`_native/exec/*`) | Not available |
| `files` | Clients reading files and projects (`_native/fs/*`, `_native/projects/*`) | Not available |
| `plugins` | Turning the host's plugins on or off | Not available |
| `agentTools` | Native's tools for agents on a loopback port | Not available |
| `companion` | The paired-device gateway: listening, Bonjour, pairing windows, paired connections | When `hosts.pairing` is permitted, which needs its app side converted first |
| `updates` | Checking, downloading and installing updates of this host | Not available |
| `diagnostics` | The doctor's platform checks, which run `gh` and tools' `--version` | Not available |

## Admission

Every request is admitted before its params are read (`HostMethodAdmission`). The policy comes first
for every client, the Mac app included; a client's grants then narrow what's left, never widen it.
Outside ordinary mode, a method the host doesn't know is refused whatever it is.

These stay available whatever the policy, so a denied host can say why and wind down: status
(`initialize`, host status, update status, the doctor's own checks), listing what the host has
(agents, sessions, activity, notifications, plugins, tasks), following sessions, stopping things
(cancel, stop agent, cancel sign-in, cancel a command, unwatch, close, shut down), and bookkeeping
that only edits the host's own records (queue edits, titles, keeping awake, the agent catalog, who
serves Native's tools). Storing an agent spec never makes it launchable: the launch decides that.

A refusal is `notAuthorized` with the reason, for example: "Your organization's policy doesn't allow
this host to start agents. Its managed policy couldn't be read." It never contains policy values.

## Checked again where it happens

A request that was allowed can still be stopped later, and much of what a host does starts without a
request. So each side effect checks the policy where it happens:

- **Agents**: `HostCore.readyAgent`, which every launch goes through (clients, recovery, queues,
  tasks, titles, sign-in), checks before launching, again right before the process spawns in the
  same actor turn, and once the agent is ready. A launch revoked while its environment was read
  never spawns.
- **Login shell**: the environment provider isn't called while the policy denies it.
- **Commands**: before the environment is read and again after it, before the command starts.
- **Updates**: the background timer isn't scheduled, each check and install checks again, and a
  check that finishes after a revocation offers and installs nothing.
- **Native's tools for agents**: the loopback listener starts only when allowed, whatever a client
  configured; sessions get its address, and a call with a session's token gets in, only while it
  is.
- **Gateway**: the helper creates `LinkGateway` with the host's policy, so a denied host never
  listens, advertises or opens a window, not even for devices paired before or for
  `Native Host pair`. Later changes reach it in order through `HostCore.observePolicy`.

## Revocation and restarts

When a refresh takes a capability away, the host ends what uses it:

- **Agents**, all of them or those taken off `policy.agents.allowed`: each running turn ends with
  the reason (`turnFailed`, and a journal entry), each queue is paused with its messages kept,
  recoveries and retries stop, a Stop in progress finishes ending its processes at once, and each
  agent's process tree is ended. Agents still allowed keep running. A turn committed afterwards (a
  task handing another a message) ends the same way as soon as its launch is refused. Nothing is
  sent again without the user, here or after a restart.
- **Commands** are cancelled; **file watches** stop.
- **Native's tools**: the listener stops, sessions stop getting its address and existing tokens are
  turned away, while agents may keep running.
- **Updates**: the timer and any check stop, a pending install is dropped, and a staged build isn't
  activated.
- **Gateway**: a device waiting to pair is turned away, the window closes and paired connections
  close. Pairings and the host's key stay for when it's allowed again.

A host that starts under a policy denying an agent, restricted, blocked or off the allowed list,
doesn't recover that agent's work: each turn the previous run left unfinished ends with a recovery
note giving the reason, and its queue stays paused. Transcripts, queues and sessions are never
deleted. When agents are allowed again, the user continues each task.

`_native/host/doctor` on a host that may not start agents runs none of its platform checks (they run
`gh` and every agent's CLI) and reports the policy instead. A check revoked while it runs asks the
policy again before each command or connection it makes.

## Self-update

A standalone host checks for updates only while `updates` is allowed. A managed
`policy.updates.feedURL` (the organization's appcast) moves its checks to the host feed beside it,
with the same signing key and no fallback to the built-in feed. In restricted mode self-update stays
off: `HostUpdater` fetches over `URLSession`, which follows redirects without network admission, so
it can't yet obey `policy.network` for the feed, signature and asset downloads. It becomes available
once its transport goes through `NativeNetwork` (A8).

## Not available in restricted mode yet

Each needs its own qualified path first; until then it stays off in restricted mode:

| Capability | Waiting on |
| --- | --- |
| `agents`, `loginShell` | A trusted launch and environment declaration (B1), qualified adapters (B3, B4) and providers (B9). Client agent specs are never approved executables. |
| `commands` | Host executable admission (B1). |
| `files` | A policy for what paired devices may read. |
| `plugins` | Host-side plugin admission matching the app's (A5). |
| `agentTools` | The orchestration capability for the loopback listener. |
| `updates` | `HostUpdater` over `NativeNetwork` (A8). |
| `diagnostics` | Doctor checks that run nothing unqualified. |

## Known limits

- `Native Host doctor` run from a shell while no host runs makes its checks itself, login shell
  included; it's the user's command, not the host's.
- Policy is not a sandbox. Agents and commands the host does start run as the user; restricted
  deployments still need the OS and network controls in the plan.
