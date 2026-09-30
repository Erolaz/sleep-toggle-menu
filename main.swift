import AppKit

enum SleepControl {
    enum ExitPlan { case exitNow, cancel, restore }

    static func exitPlan(smokeTest: Bool, busy: Bool, disabled: Bool?) -> ExitPlan {
        if smokeTest { return .exitNow }
        if busy { return .cancel }
        return disabled == false ? .exitNow : .restore
    }

    static func parse(_ text: String) -> Bool? {
        let pattern = #"(?m)^\s*(?:SleepDisabled|disablesleep)\s+([01])\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return text[range] == "1"
    }

    static func read() -> Bool? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return parse(String(decoding: data, as: UTF8.self))
        } catch { return nil }
    }

    static func arguments(disabled: Bool, checkOnly: Bool = false) -> [String] {
        return ["-n"] + (checkOnly ? ["-l"] : []) + ["/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"]
    }

    static func sudo(_ arguments: [String]) -> (status: Int32, message: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch { return (-1, error.localizedDescription) }
    }

    static func hasPermission() -> Bool {
        return sudo(arguments(disabled: false, checkOnly: true)).status == 0
            && sudo(arguments(disabled: true, checkOnly: true)).status == 0
    }

    static func shellQuote(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func setupScript(path: String, user: String) -> String {
        let command = "/bin/sh " + shellQuote(path) + " " + shellQuote(user)
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"" + escaped + "\" with administrator privileges"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let heading = NSMenuItem(title: "Проверка состояния…", action: nil, keyEquivalent: "")
    private let toggle = NSMenuItem(title: "Не давать Mac засыпать", action: #selector(toggleSleep), keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Обновить состояние", action: #selector(refresh), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Выйти и разрешить сон", action: #selector(quit), keyEquivalent: "q")
    private var disabled: Bool?
    private var busy = false
    private var timer: Timer?
    private let smokeTest = CommandLine.arguments.contains("--smoke-test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "SleepToggleMenuStatus"
        menu.autoenablesItems = false
        menu.delegate = self
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        toggle.target = self
        menu.addItem(toggle)
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "О приложении и правах…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        refresh()
        timer = Timer(timeInterval: 20, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)

        if smokeTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                guard NSApp.activationPolicy() == .accessory,
                      statusItem.button != nil, statusItem.button?.image != nil,
                      statusItem.menu === menu, menu.items.count == 7,
                      statusItem.button?.title == "", statusItem.length == NSStatusItem.squareLength,
                      disabled != nil, toggle.isEnabled else {
                    fputs("GUI smoke test failed\n", stderr)
                    exit(1)
                }
                print("GUI smoke test passed: icon-only square status item, menu, accessory policy, live pmset state. No settings changed.")
                NSApp.terminate(nil)
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc private func refresh() {
        guard !busy else { return }
        disabled = SleepControl.read()
        render()
    }

    private func render() {
        let title: String
        let symbol: String
        switch disabled {
        case true?:
            title = "Системный сон запрещён"
            symbol = "cup.and.saucer.fill"
        case false?:
            title = "Системный сон разрешён"
            symbol = "zzz"
        case nil:
            title = "Не удалось прочитать состояние сна"
            symbol = "exclamationmark.triangle"
        }
        heading.title = busy ? "Изменение настройки…" : title
        toggle.state = disabled == true ? .on : .off
        toggle.isEnabled = !busy && disabled != nil
        refreshItem.isEnabled = !busy
        quitItem.isEnabled = !busy
        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName: busy ? "hourglass" : symbol, accessibilityDescription: title)
            icon?.isTemplate = true
            icon?.size = NSSize(width: 18, height: 18)
            button.image = icon
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = "Сон Mac — \(title.lowercased())"
            button.setAccessibilityLabel("Сон Mac. \(title)")
        }
    }

    @objc private func toggleSleep() {
        guard !busy else { return }
        // Re-read before choosing the target: another utility can change pmset.
        guard let current = SleepControl.read() else {
            refresh()
            showError("Не удалось прочитать состояние через pmset. Настройки не изменены.")
            return
        }
        _ = setDisabled(!current)
    }

    @discardableResult private func setDisabled(_ value: Bool) -> Bool {
        busy = true
        render()
        defer {
            busy = false
            refresh()
        }
        // Reuse a narrow permission installed by the original utility, if present.
        // The normal path never uses administrator AppleScript or prompts for a password.
        var result = SleepControl.sudo(SleepControl.arguments(disabled: value))
        if result.status != 0 {
            guard installPermission() else { return false }
            result = SleepControl.sudo(SleepControl.arguments(disabled: value))
        }
        guard result.status == 0 else {
            showError("Не удалось выполнить команду сна без пароля.\n\n" + result.message)
            return false
        }
        guard SleepControl.read() == value else {
            showError("Команда выполнена, но новое состояние не подтверждено. Проверьте состояние ещё раз.")
            return false
        }
        return true
    }

    private func installPermission() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Однократная настройка"
        alert.informativeText = "macOS один раз попросит пароль администратора, чтобы разрешить этому пользователю две команды: включить и выключить запрет сна. После этого переключение и восстановление сна при выходе работают без пароля.\n\nРазрешение постоянно и доступно всем программам вашего пользователя, но только для этих двух точных команд pmset."
        alert.addButton(withTitle: "Настроить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        guard let path = Bundle.main.path(forResource: "install-permission", ofType: "sh"),
              let script = NSAppleScript(source: SleepControl.setupScript(path: path, user: NSUserName())) else {
            showError("Не найден скрипт первоначальной настройки. Установите приложение заново.")
            return false
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            if code != -128 {
                showError(error[NSAppleScript.errorMessage] as? String ?? "macOS не разрешила изменить настройку.")
            }
            return false
        }
        guard SleepControl.hasPermission() else {
            showError("Разрешение установлено, но sudo его не применил. Настройки сна не изменены.")
            return false
        }
        return true
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Сон Mac — строка меню"
        alert.informativeText = "Версия 1.4\n\nПереключает только pmset -a disablesleep 0/1. Настройки гашения экрана не меняются.\n\nПароль нужен только для однократной настройки sudoers, если подходящее разрешение ещё не установлено. Разрешены только две точные команды от имени root; правило доступно всем программам вашего пользователя. Пароль не хранится. Нет сетевого кода, служб и автозапуска.\n\nПри обычном выходе приложение автоматически разрешает системный сон. При ошибке выход отменяется. При сбое, принудительном завершении или отключении питания восстановление не гарантируется. Другие приложения тоже могут удерживать Mac от сна. Не кладите работающий Mac в сумку."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Не удалось изменить сон"
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        guard !busy else { return }
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Diagnostic GUI mode must never change power settings, even on exit.
        switch SleepControl.exitPlan(smokeTest: smokeTest, busy: busy, disabled: SleepControl.read()) {
        case .exitNow: return .terminateNow
        case .cancel: return .terminateCancel
        case .restore:
            // Unknown state also requires an explicit restore; never silently leave sleep blocked.
            return setDisabled(false) ? .terminateNow : .terminateCancel
        }
    }
}

if CommandLine.arguments.contains("--self-test") {
    let cases: [(String, Bool?)] = [
        ("System-wide power settings:\n SleepDisabled\t\t0\nCurrently in use:\n sleep 1", false),
        (" SleepDisabled 1\n", true),
        (" disablesleep 0\n", false),
        (" disablesleep 1\n", true),
        (" sleep 1\n", nil),
        ("SleepDisabled 10\n", nil),
        ("SleepDisabled 2\n", nil),
        ("", nil)
    ]
    for (input, expected) in cases {
        guard SleepControl.parse(input) == expected else { fatalError("Parser failed: \(input)") }
    }
    guard SleepControl.arguments(disabled: true) == ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"],
          SleepControl.arguments(disabled: false) == ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"],
          SleepControl.arguments(disabled: false, checkOnly: true) == ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"],
          SleepControl.shellQuote("a'b") == "'a'\\''b'" else {
        fatalError("Command allowlist test failed")
    }
    guard SleepControl.exitPlan(smokeTest: false, busy: false, disabled: true) == .restore,
          SleepControl.exitPlan(smokeTest: false, busy: false, disabled: nil) == .restore,
          SleepControl.exitPlan(smokeTest: false, busy: false, disabled: false) == .exitNow,
          SleepControl.exitPlan(smokeTest: false, busy: true, disabled: false) == .cancel,
          SleepControl.exitPlan(smokeTest: true, busy: false, disabled: true) == .exitNow else {
        fatalError("Exit restore policy failed")
    }
    print("Self-test passed: 8 parser cases, 4 command/quoting checks, 5 exit restore cases.")
} else if CommandLine.arguments.contains("--check-permissions") {
    guard SleepControl.hasPermission() else { fputs("One-time permission setup needed\n", stderr); exit(1) }
    print("sudo policy lists both exact pmset commands as allowed. No commands executed.")
} else if CommandLine.arguments.contains("--verify-current-state") {
    guard let original = SleepControl.read() else { fputs("Unknown state; no command attempted\n", stderr); exit(1) }
    let result = SleepControl.sudo(SleepControl.arguments(disabled: original))
    guard result.status == 0, SleepControl.read() == original else {
        fputs("Noninteractive verification failed: \(result.message)\n", stderr)
        exit(1)
    }
    print("Noninteractive sudo succeeded; reapplied existing SleepDisabled=\(original ? 1 : 0). State unchanged, no password prompt.")
} else if CommandLine.arguments.contains("--read-state") {
    guard let state = SleepControl.read() else { fputs("Unknown state\n", stderr); exit(1) }
    print("SleepDisabled=\(state ? 1 : 0)")
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
