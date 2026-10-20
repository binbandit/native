# Droids

A droid is a Mac that runs your agents with nobody at it: a Mac mini on a shelf. You start a task
from your laptop, close the lid, and the droid keeps working; open the laptop again and the task is
where the droid got to. This guide sets one up once and keeps it healthy.

## How it fits together

The droid runs Native's background host (`Packages/NativeHost`), the process that owns agents,
sessions and their turns (docs/durability.md). It ships inside Native.app as `Native Host.app`, and
Native registers it as a login item, so it starts whenever the droid's user logs in and keeps running
whether or not a Native window is open. Your laptop's Native pairs with it (Settings ▸ Hosts ▸ Add
Host) and runs tasks there. While any task works, the host keeps the droid awake.

So the droid needs four things to hold: Native installed and opened once, the user logged in, the
Mac awake and powered, and a network your laptop can reach it on.

You need a Mac on macOS 27, on power and on a network (Ethernet is steadiest), an administrator
account for the one-time settings, and SSH from your laptop to it.

## 1. Install Native

- **A release:** download the latest from [GitHub Releases](https://github.com/binbandit/native/releases)
  and drag Native to Applications. Over SSH:

  ```sh
  gh release download -R binbandit/native --pattern 'Native-*.dmg' --dir /tmp/native
  hdiutil attach /tmp/native/Native-*.dmg -nobrowse -mountpoint /Volumes/Native
  cp -R /Volumes/Native/Native.app /Applications/
  hdiutil detach /Volumes/Native
  ```

  Releases are signed and notarized, and update themselves (Running it, below).
- **For builders:** `just dev` in a clone of the repository builds the latest published `main` as a
  Release build into `~/Applications`. Run it again to move to a newer `main`.

Use a Release build. A Debug build (`just run`, `scripts/dev/run-isolated.sh`) runs its host as a
launchd job for the current login session only: it's gone after a restart, and it stops after 15
idle minutes unless a device is paired with it (docs/durability.md, "Development builds").

## 2. Open it once

Open Native once in the droid's desktop session, with a display or Screen Sharing (System Settings
▸ General ▸ Sharing ▸ Screen Sharing). That registers the background host as a login item: macOS
posts "Background Items Added", naming Native, and Settings ▸ Background says agents run in the
background host. If it says Native isn't allowed in the background, turn Native on under System
Settings ▸ General ▸ Login Items & Extensions ▸ Allow in the Background, then relaunch Native.

While it's open:

- **Settings ▸ Keep Awake ▸ Keep Mac awake: While Agents Work.** The host then keeps the droid awake
  while any task works, and goes on doing so with Native closed (step 4).
- **Settings ▸ Background ▸ Check This Mac…** runs the doctor (Running it, below): it lists what the
  rest of this guide sets up, with the fix for each.

Then you can quit Native (⌘Q): the host keeps running. Native ▸ Quit Native and Stop Agents would
stop the host too, until Native opens again.

## 3. Staying logged in

The host runs in its user's login session, as login items do. After a restart nothing runs until
that user logs in, so a droid has to log in by itself: System Settings ▸ Users & Groups ▸
Automatically log in as ▸ your account.

macOS doesn't log in automatically while FileVault is on, so you choose:

- **FileVault off, automatic login on.** The droid comes back by itself after a power cut, a macOS
  update or a restart, and resumes its tasks. The cost: its disk isn't encrypted at rest, so anyone
  who takes the Mac can read what's on it, including your code and what agents keep signed in
  (`~/.claude`, `~/.codex`, `gh`'s token, SSH keys). Choose this where the Mac is physically safe,
  and sign its agents and `gh` in with accounts or tokens scoped to what the droid works on.
- **FileVault on.** The disk stays encrypted, and after every restart the droid waits at the unlock
  screen, its host and agents down, until someone types the password. For a restart you plan,
  `sudo fdesetup authrestart` skips the unlock screen once. Choose this where the Mac could walk
  away, and expect to unlock it after power cuts.

Check what the droid does with `fdesetup status` and
`defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser`, or with the doctor.

## 4. Power

In System Settings ▸ Energy:

- **Prevent automatic sleeping when the display is off:** on. The display can sleep; the Mac doesn't.
- **Wake for network access:** on, so a droid that does sleep can be reached.
- **Start up automatically after a power failure:** on.

Or over SSH: `sudo pmset -a sleep 0 womp 1 autorestart 1`, and `pmset -g` to check.

Keep awake (step 2) works on top of that: while any task works, the host holds a power assertion
that prevents idle system sleep (not display sleep), and releases it when nothing works. With the
setting On, or a "Stay awake for" timer, it holds regardless. `pmset -g assertions` lists it as
"Native is keeping this machine awake while agents work". The setting belongs to the Mac: Native
hands it to its host, which remembers it, so it holds across restarts with no window open.

## 5. Network

- **SSH.** System Settings ▸ General ▸ Sharing ▸ Remote Login: on (or
  `sudo systemsetup -setremotelogin on`), and copy your laptop's key over (`ssh-copy-id me@mac-mini.local`):
  pairing over SSH never prompts for a password.
- **The same network.** Your laptop finds the droid over Bonjour. Give it a fixed address (a DHCP
  reservation on your router) so a saved address keeps working too.
- **Anywhere: Tailscale** on both machines. The pairing link carries the droid's Tailscale address
  and MagicDNS name, so your laptop reaches it from any network. Make sure Tailscale starts at login
  on the droid.

Paired devices connect to the host's own port (47118 unless it was taken); nothing listens on the
network until the first device pairs.

## 6. Agents

Agents run as the droid's user, with its login shell's environment, so install them where a login
shell finds them and sign them in on the droid. Over SSH:

1. **Node.js**, for the adapters Native starts agents through: `brew install node` (install
   [Homebrew](https://brew.sh) first), or your version manager (mise, asdf, nvm) set up in the
   login shell's startup files.
2. **The agents' CLIs**, as docs/setup.md ("Agents") lists them: for example
   `npm install -g @anthropic-ai/claude-code @openai/codex`. Git comes with the Command Line Tools
   (`xcode-select --install`); add `brew install gh` for pull requests.
3. **Sign in,** with each CLI's own sign-in over SSH: `claude` then `/login`, `codex login`,
   `gh auth login`, and so on. Ones that print a link and a code work as is; ones that wait for a
   browser on the droid's `localhost` need that port forwarded to your laptop
   (`ssh -L <port>:localhost:<port> me@mac-mini.local`). Once it's paired, your laptop can also sign
   an agent in on the droid: Settings ▸ Hosts ▸ the droid ▸ the agent's Sign In….
4. **Check** with `"$SHELL" -lc 'command -v node npx claude codex git gh'`, or the doctor, which
   checks each agent the host runs and gives the install command for a missing one.

The host reads the login shell's environment when it starts, and learns which agents to run from
Native on the droid. After installing agents or plugins, open Native on the droid once (Settings ▸
Agents ▸ Add an Agent ▸ Check Again if one is still missing), or restart the host over SSH with
`launchctl kickstart -k gui/$(id -u)/dev.binbandit.native.host` (Native Nightly's ends in
`.host.nightly`); tasks it was running resume after it.

## 7. Pair it with your laptop

On your laptop: Settings ▸ Hosts ▸ Add Host…, enter the droid's SSH destination
(`me@mac-mini.local`, or its Tailscale name) and Continue. Native runs the droid's
`Native Host pair` over your SSH, shows what the droid will let your laptop do (run commands and
work with files in its projects, install updates; turning plugins on and off stays off), and pairs
when you choose Pair.

Without SSH from the laptop, run this on the droid and paste the link it prints into Add Host
(single use, valid five minutes):

```sh
"/Applications/Native.app/Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host" pair --run-commands --install-updates
```

Every pairing is recorded in the host's activity, and can be removed from either side. How pairing
works: docs/durability.md ("Pairing a host without a screen") and docs/companion.md.

## Running it

### Checking it: the host doctor

The doctor checks what the droid needs, read-only, each check with the exact command or setting
that fixes it. It never installs or changes anything.

- **In Native:** Settings ▸ Background ▸ Check This Mac…, on the droid. Copy as Text copies the
  report.
- **Over SSH:**

  ```sh
  "/Applications/Native.app/Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host" doctor
  ```

  It asks the running host, so it sees what the host sees, and checks the Mac without it when the
  host isn't running (then saying whether anyone is logged in and whether the login item is
  registered). It exits 1 when a check failed. The standalone host has the same:
  `native-host doctor`.

| Group | Checks |
| --- | --- |
| Background host | starts at login (a login item, the app running it itself because Allow in the Background is off, or started by hand); keep awake: the policy, what it's doing, and whether macOS let it |
| Agents | `node` and `npx`, and every command each agent needs, on the login shell's PATH, with versions |
| Git and GitHub | `git`, `gh`, and whether `gh` is signed in |
| Disk and network | free space (a warning under 20 GB, a failure under 5 GB); the addresses it's reachable on, Tailscale's labelled, and the port paired devices use; Remote Login |
| Running unattended | automatic login (and FileVault); sleep, wake for network access, and starting after a power failure, from `pmset -g` |

A laptop shows warnings under Running unattended; they matter only for a droid. For other clients
the same report is `_native/host/doctor`, and `_native/host/status` says what the droid runs on,
since when, how loaded it is and how it's kept awake.

### Updating

A release updates itself, as on any Mac (docs/releasing.md): leave Native open on the droid (its
window can stay closed) so it checks and downloads, and the update installs when Native quits or
with Restart to Update. With Native closed,
`open -g -j -a Native --args -NativeInstallUpdateAndQuit YES` checks, installs and quits again.
Either way the host switches to the new version once its tasks finish. A paired iPhone or iPad can
install the droid's update too, if its pairing allows installing updates. For a `just dev` droid,
run `just dev` again.

### After a restart or a power cut

With automatic login, the droid boots (by itself after a power cut, with autorestart on), logs in,
and launchd starts the host. The host keeps the Mac awake by the policy it remembers, and resumes
every task that was working when it went down: each transcript says "Your Mac restarted at 2:14 PM
while Codex was working…" and the agent picks up after checking its work (docs/durability.md,
"Recovery"). Paired devices reconnect on their own. With FileVault on, all of that waits until
someone unlocks the Mac. A Debug build's host doesn't come back at all.

## Other operating systems (later)

The host's core is portable (Foundation only), and `native-host` builds for Linux, so a Linux box
can be a droid once the rest lands: provisioning over SSH from Add Host with a `systemd --user`
service (with `loginctl enable-linger`, so it runs without anyone logged in), the paired-device
gateway in `native-host`, keep-awake through `systemd-inhibit`, and the doctor's platform checks
(the service, lingering, sleep targets). Its portable checks (agents, tools, disk, network, keep
awake) already work wherever the host runs. Windows isn't planned.
