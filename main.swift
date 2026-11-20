// LidAwake: menu bar toggle for `pmset -a disablesleep`.
// On = the Mac stays awake with the lid closed, so other devices can ssh in.
import AppKit
import ServiceManagement

let sudoersPath = "/etc/sudoers.d/lidawake"  // no dot in the name: sudoers.d skips dotted files

@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

/// Runs a shell command as root through the standard macOS password dialog.
func runAsAdmin(_ shell: String, prompt: String) -> Bool {
    let esc = { (s: String) in
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    let script = "do shell script \"\(esc(shell))\" with prompt \"\(esc(prompt))\" with administrator privileges"
    return run("/usr/bin/osascript", ["-e", script]).status == 0
}

/// Real system state, read from pmset every time (never cached).
func sleepDisabled() -> Bool {
    for line in run("/usr/bin/pmset", ["-g"]).out.split(separator: "\n") {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        if parts.first == "SleepDisabled" { return parts.count > 1 && parts[1] == "1" }
    }
    return false
}

func setSleepDisabled(_ on: Bool) -> Bool {
    let n = on ? "1" : "0"
    // Passwordless path, works only after "Skip password prompts" was set up.
    if run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", n]).status == 0 { return true }
    return runAsAdmin("/usr/bin/pmset -a disablesleep \(n)",
                      prompt: on ? "LidAwake wants to keep this Mac awake with the lid closed."
                                 : "LidAwake wants to let this Mac sleep normally again.")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let stateLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let toggleItem = NSMenuItem(title: "", action: #selector(toggle), keyEquivalent: "t")
    let sshLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let sudoItem = NSMenuItem(title: "", action: #selector(toggleSudoers), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    var busy = false

    func applicationDidFinishLaunching(_ note: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        stateLine.isEnabled = false
        sshLine.isEnabled = false
        for i in [toggleItem, sudoItem, loginItem] { i.target = self }
        menu.addItem(stateLine)
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(sshLine)
        menu.addItem(.separator())
        menu.addItem(sudoItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit LidAwake", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        refresh()
        // The setting can change outside the app (terminal, reboot), so keep the icon honest.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    /// Logout, restart, or kill: turn off silently if the passwordless rule exists (no prompt here).
    func applicationWillTerminate(_ note: Notification) {
        if sleepDisabled() { run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]) }
    }

    func refresh() {
        let on = sleepDisabled()
        let name = on ? "bolt.fill" : "moon.zzz"
        var img = NSImage(systemSymbolName: name, accessibilityDescription: on ? "Staying awake" : "Normal sleep")
        if on {
            img = img?.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            img?.isTemplate = false
        } else {
            img?.isTemplate = true
        }
        item.button?.image = img
        item.button?.toolTip = on ? "LidAwake: awake with lid closed" : "LidAwake: normal sleep"
        stateLine.title = on ? "ON: stays awake with lid closed" : "OFF: sleeps normally"
        toggleItem.title = on ? "Turn Off" : "Keep Awake (Lid Closed)"
        toggleItem.isEnabled = !busy
        let ssh = run("/usr/bin/nc", ["-z", "-G", "1", "127.0.0.1", "22"]).status == 0
        sshLine.title = ssh ? "SSH (Remote Login): on" : "SSH (Remote Login): OFF, enable in Settings > Sharing"
        sudoItem.title = "Skip Password Prompts"
        sudoItem.state = FileManager.default.fileExists(atPath: sudoersPath) ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func toggle() {
        guard !busy else { return }
        busy = true
        let target = !sleepDisabled()
        DispatchQueue.global().async {
            _ = setSleepDisabled(target)
            DispatchQueue.main.async { self.busy = false; self.refresh() }
        }
    }

    /// Adds or removes a sudoers rule that allows exactly the two pmset commands without a password.
    @objc func toggleSudoers() {
        let installed = FileManager.default.fileExists(atPath: sudoersPath)
        DispatchQueue.global().async {
            if installed {
                _ = runAsAdmin("/bin/rm -f \(sudoersPath)", prompt: "LidAwake wants to remove its passwordless rule.")
            } else {
                let rule = "\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
                // Validate with visudo before installing: a broken sudoers file locks out sudo.
                let sh = "f=$(/usr/bin/mktemp) && /usr/bin/printf '%s\\n' '\(rule)' > \"$f\" && /usr/sbin/visudo -cf \"$f\" && /usr/bin/install -o root -g wheel -m 0440 \"$f\" \(sudoersPath); r=$?; /bin/rm -f \"$f\"; exit $r"
                _ = runAsAdmin(sh, prompt: "LidAwake wants to allow its on/off switch to work without a password.")
            }
            DispatchQueue.main.async { self.refresh() }
        }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Could not change Launch at Login"
            a.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
        refresh()
    }

    @objc func quit() {
        // Never leave the Mac stuck awake with no indicator in the menu bar.
        if sleepDisabled() && !setSleepDisabled(false) {
            let a = NSAlert()
            a.messageText = "Keep-awake is still ON"
            a.informativeText = "LidAwake could not turn it off. Quit anyway? To turn it off later, run: sudo pmset -a disablesleep 0"
            a.addButton(withTitle: "Stay Open")
            a.addButton(withTitle: "Quit Anyway")
            NSApp.activate(ignoringOtherApps: true)
            if a.runModal() == .alertFirstButtonReturn { refresh(); return }
        }
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
