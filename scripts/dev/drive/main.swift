// Drives one isolated instance of Native through Accessibility, for playtesting and checking changes
// in the running app (docs/playtesting.md). `scripts/dev/drive.sh` compiles and runs it.
//
// Every command acts on the one process `run-isolated.sh <name>` started, found by that name: there is
// no pid argument. Presses and values go through Accessibility, keys through `CGEvent.postToPid`, and
// screenshots through `screencapture -l` of that process's windows. Nothing is brought to the front,
// nothing is clicked at a position, and no keystroke goes to whatever app has focus.
import ApplicationServices
import Foundation

let help = """
    usage: drive.sh <name> <command> [arguments]

    Reading
      tree [--depth N] [--raw] [--frames] [--menus]   the accessibility tree, one element a line
      find <text> [--role R]                          every match, numbered for --nth, with where it is
      text [<text>] [--nth N]                         the text a person would read, under a match or everywhere
      focused                                         the element with keyboard focus
      wait <text> [--gone] [--timeout S] [--role R]   until something matches (or stops matching); 30 s
      windows                                         the instance's windows: id, size, whether covered
      menu <Menu> [<Item> ...]                        list a menu's items and shortcuts
      actions <text> [--nth N]                        an element's accessibility actions
      pid                                             the instance's process id
      screen                                          `locked` or `unlocked`; nothing seen while locked counts

    Acting
      press <text> [--nth N] [--role R]               AXPress a button, menu item, row or toggle
      press <menu button> [--item <text>]             list a pop-up menu's items, or pick one; never left open
      set <text> <value> [--nth N] [--role R]         write a text field, the composer or a switch; - reads stdin
      type <text>                                     type characters into the focused element (\\n is Shift-Return)
      key <combo> [<combo> ...]                       e.g. cmd+n, return, escape, shift+cmd+a, opt+cmd+up
      key <combo> --hold <seconds>                   hold before release, from 0 to 3 seconds
      drop <composer|transcript> <file>... [--phase hover|drop|exit]   fixture drag, isolated Debug only
      paste-files <file>...                           fixture paste, private test pasteboard only
      menu <Menu> <Item> [<Item> ...]                 press a menu bar item (a submenu path goes deeper)
      action <text> <name> [--nth N] [--item <text>]  perform an action; AXShowMenu lists or picks from a context menu
      scroll <text> <up|down|top|bottom|reveal>       page the scroll area at or around a match, or reveal it
      shot <file.png> [--window ID]                   screenshot the main window (or one from `windows`)
      frame [<x> <y> <width> <height>]                read or set the main window's frame (top left, points)

    Around it (drive.sh itself)
      seed [<folder> ...] | seed --remove             projects, a sample repo and the Fake Agent; run while quit
      logs [--last 10m | --stream]                    this instance's log lines, app and host
      crashes                                         this instance's crash and hang reports, newest first
      processes                                       its app, host and every process under them

    <text> matches an accessibility identifier, else a title or label exactly, else ignoring case,
    else as part of any label, value or help text. Ties go to reading order; `find` shows the order.
    --role narrows to a role: button, textarea, textfield, checkbox, row, menuitem, statictext...

    Background instances may not expose a menu bar. Stop an instance and its host with
    scripts/dev/run-isolated.sh <name> --quit. To test app-only quitting, use key cmd+q.
    """

/// A command's arguments, its options and its flags, as `Arguments` takes them.
let specs: [String: (options: Set<String>, flags: Set<String>)] = [
    "tree": (["depth"], ["raw", "frames", "menus"]),
    "find": (["role"], []), "text": (["nth", "role"], []), "focused": ([], []),
    "wait": (["timeout", "role"], ["gone"]), "windows": ([], []), "menu": ([], []),
    "actions": (["nth", "role"], []), "pid": ([], []), "press": (["nth", "role", "item"], []),
    "set": (["nth", "role"], []), "type": ([], []), "key": (["hold"], []), "action": (["nth", "role", "item"], []),
    "scroll": (["nth", "role"], []), "shot": (["window"], []), "frame": ([], []), "screen": ([], []),
    "drop": (["phase", "text"], []), "paste-files": ([], []),
]

@MainActor func run(_ raw: [String]) throws(DriveError) {
    guard raw.count >= 2, let spec = specs[raw[1]] else {
        if raw.count >= 2, ["help", "-h", "--help"].contains(raw[1]) {
            print(help)
            return
        }
        throw DriveError(help, code: 2)
    }
    let command = raw[1]
    let arguments = try Arguments(Array(raw.dropFirst(2)), options: spec.options, flags: spec.flags)
    if command == "screen" {
        print(Screen.isLocked ? "locked" : "unlocked")
        return
    }
    let instance = try Instance.resolve(name: raw[0])
    if Screen.isLocked {
        guard command != "shot" else {
            throw DriveError("the screen is locked, so the window isn't drawn; no screenshots until it's unlocked")
        }
        FileHandle.standardError.write(Data("drive: \(Screen.lockedWarning)\n".utf8))
    }
    guard AXIsProcessTrusted() || ["pid", "windows", "shot", "key", "type"].contains(command) else {
        throw DriveError(
            "this shell has no Accessibility permission (System Settings ▸ Privacy & Security ▸ Accessibility); ask Brayden, don't work around it"
        )
    }
    let driver = Driver(instance: instance)
    let positional = arguments.positional
    let nth = try Int(arguments.number("nth") ?? 0)
    let query = { (text: String) in Query(text: text, role: arguments.string("role")) }

    switch command {
    case "tree":
        try arguments.expect(0...0, "tree [--depth N] [--raw] [--frames] [--menus]")
        let depth = try Int(arguments.number("depth") ?? 1_000)
        driver.tree(
            depth: depth, raw: arguments.has("raw"), frames: arguments.has("frames"), menus: arguments.has("menus")
        )
        .forEach { print($0) }
    case "find":
        try arguments.expect(1...1, "find <text> [--role R]")
        let lines = driver.find(query(positional[0]))
        guard !lines.isEmpty else { throw DriveError("nothing matches \(Node.quoted(positional[0]))") }
        lines.forEach { print($0) }
    case "text":
        try arguments.expect(0...1, "text [<text>] [--nth N]")
        try driver.text(positional.first.map(query), nth: nth).forEach { print($0) }
    case "focused":
        print(try driver.focused())
    case "wait":
        try arguments.expect(1...1, "wait <text> [--gone] [--timeout S]")
        print(
            try driver.wait(
                query(positional[0]), timeout: try arguments.number("timeout") ?? 30, gone: arguments.has("gone")))
    case "windows":
        let windows = Windows(pid: instance.pid)
        windows.all().forEach { print(windows.describe($0)) }
    case "menu":
        try arguments.expect(1...8, "menu <Menu> [<Item> ...]")
        let menus = Menus(app: driver.app)
        let item = try menus.item(positional)
        // A menu, or an item that opens a submenu, lists its items; any other item is pressed.
        let items = try menus.list(positional)
        if positional.count == 1 || !items.isEmpty {
            items.forEach { print($0) }
        } else {
            guard (Accessibility.attribute(item, kAXEnabledAttribute) as? NSNumber)?.boolValue != false else {
                throw DriveError("\(positional.joined(separator: " ▸ ")) is disabled")
            }
            print("pressed \(positional.joined(separator: " ▸ "))" + driver.perform(kAXPressAction, on: item))
        }
    case "actions":
        try arguments.expect(1...1, "actions <text> [--nth N]")
        try driver.actions(query(positional[0]), nth: nth).forEach { print($0) }
    case "pid":
        print(instance.pid)
    case "drop":
        try arguments.expect(1...32, "drop <composer|transcript> <file>... [--phase hover|drop|exit]")
        try AttachmentInput(instance: instance).drop(
            target: positional[0], paths: Array(positional.dropFirst()), phase: arguments.string("phase") ?? "drop",
            text: arguments.string("text"))
    case "paste-files":
        try arguments.expect(1...32, "paste-files <file>...")
        try AttachmentInput(instance: instance).paste(paths: positional)
    case "press":
        try arguments.expect(1...1, "press <text> [--nth N] [--role R]")
        print(try driver.press(query(positional[0]), nth: nth, item: arguments.string("item")))
    case "set":
        try arguments.expect(2...2, "set <text> <value> [--nth N] [--role R]")
        let value =
            positional[1] == "-"
            ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) : positional[1]
        print(try driver.set(query(positional[0]), nth: nth, to: value))
    case "type":
        try arguments.expect(1...1, "type <text>")
        try Keyboard(pid: instance.pid).type(positional[0])
    case "key":
        try arguments.expect(1...32, "key <combo> [<combo> ...] [--hold seconds]")
        let keyboard = Keyboard(pid: instance.pid)
        for combo in positional {
            try keyboard.press(combo, hold: arguments.number("hold") ?? 0.012)
        }
    case "action":
        try arguments.expect(2...2, "action <text> <name> [--nth N]")
        print(try driver.action(query(positional[0]), nth: nth, positional[1], item: arguments.string("item")))
    case "scroll":
        try arguments.expect(2...2, "scroll <text> <up|down|top|bottom|reveal> [--nth N]")
        guard let direction = Driver.ScrollDirection(rawValue: positional[1]) else {
            throw DriveError("scroll: up, down, top, bottom or reveal", code: 2)
        }
        print(try driver.scroll(query(positional[0]), nth: nth, direction))
    case "shot":
        try arguments.expect(1...1, "shot <file.png> [--window ID]")
        let windows = Windows(pid: instance.pid)
        let window = try windows.pick(try arguments.number("window").map { Int($0) })
        let url = URL(filePath: positional[0], relativeTo: URL(filePath: FileManager.default.currentDirectoryPath))
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try windows.capture(window, to: url.path)
        print(url.path)
        let covering = windows.covering(window)
        if !covering.isEmpty {
            FileHandle.standardError.write(
                Data(
                    "drive: covered by \(covering.joined(separator: ", ")); the covered part may be stale (docs/playtesting.md)\n"
                        .utf8))
        }
    case "frame":
        try arguments.expect(0...4, "frame [<x> <y> <width> <height>]")
        if positional.isEmpty {
            let window = try Windows(pid: instance.pid).pick(nil)
            let bounds = window.bounds
            print("\(Int(bounds.minX)) \(Int(bounds.minY)) \(Int(bounds.width)) \(Int(bounds.height))")
        } else {
            let numbers = positional.compactMap(Double.init)
            guard numbers.count == 4 else { throw DriveError("frame takes x y width height, in points", code: 2) }
            try Windows.setFrame(
                of: driver.app, to: CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
        }
    default:
        throw DriveError(help, code: 2)
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("drive: \(error.message)\n".utf8))
    exit(error.code)
}
