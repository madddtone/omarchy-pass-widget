import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "lib/Parse.js" as Parse

Item {
  id: root

  readonly property string pluginDir: {
    var dir = decodeURIComponent(Qt.resolvedUrl(".").toString())
    if (dir.indexOf("file://") === 0) dir = dir.substring(7)
    return dir.replace(/\/$/, "")
  }

  property var shell: null

  property string passCliBin: ""
  property string vaultConfig: ""
  property string defaultCopyField: "password"
  property int lockMinutes: 5
  property string gitRemote: ""
  property string gitAuto: "On"

  property var credentials: []
  property var categories: []
  property string state: "unknown"
  property string lastError: ""
  property bool busy: false
  property bool loaded: false
  property double lastActivity: Date.now()

  signal feedback(string text, bool error)
  signal lockRequested()
  signal passwordRevealed(string service, string password)
  signal importFinished(var summary)
  signal importProgress(int done, int total)
  signal importDirLoaded(string dir, string parent, string home, var entries)
  signal gitStatusLoaded(var status)
  signal gitResult(var result)

  function _notify(text, error) {
    root.feedback(String(text), error === true)
  }

  function touch() {
    root.lastActivity = Date.now()
  }

  function _base(discard, clipClear) {
    var a = [root.pluginDir + "/scripts/pass-run.sh"]
    if (root.passCliBin) a.push("--bin", root.passCliBin)
    if (root.vaultConfig) a.push("--config", root.vaultConfig)
    if (discard === true) a.push("--discard")
    if (Number(clipClear) > 0) a.push("--clip-clear", String(clipClear))
    a.push("--")
    return a
  }

  function _classifyError(text) {
    var t = String(text || "").toLowerCase()
    if (t.indexOf("failed to lookup") !== -1 || t.indexOf("executable file not found") !== -1)
      return "nobinary"
    if (t.indexOf("pass-cli binary not found") !== -1)
      return "nobinary"
    if (t.indexOf("does not exist") !== -1 || t.indexOf("no vault") !== -1
        || t.indexOf("not initialized") !== -1 || t.indexOf("vault not found") !== -1
        || t.indexOf("guided initialization") !== -1 || t.indexOf("initialize vault") !== -1
        || t.indexOf("pass-cli init") !== -1 || t.indexOf("initialization") !== -1)
      return "missing"
    if (t.indexOf("password") !== -1 || t.indexOf("keychain") !== -1 || t.indexOf("unlock") !== -1
        || t.indexOf("terminal") !== -1 || t.indexOf("ioctl") !== -1 || t.indexOf("eof") !== -1
        || t.indexOf("decrypt") !== -1 || t.indexOf("authentication") !== -1)
      return "locked"
    return "error"
  }

  function refresh() {
    touch()
    if (listProc.running) return
    root.busy = true
    listProc.command = root._base(false).concat(["list", "--format", "json"])
    listProc.running = true
  }

  function _runAction(args, meta) {
    touch()
    if (actionProc.running) return
    actionProc.pending = meta
    actionProc.command = root._base(meta && meta.discard === true, meta ? meta.clipClear : 0).concat(args)
    actionProc.running = true
  }

  function copyPassword(service) {
    _runAction(["get", String(service), "--field", "password", "--quiet", "--no-clipboard"],
               { kind: "copyPassword", service: String(service), clipClear: 5 })
  }

  function copyTotp(service) {
    _runAction(["get", String(service), "--totp", "--quiet", "--no-clipboard"],
               { kind: "copyTotp", service: String(service), clipClear: 5 })
  }

  function copyField(service, field) {
    _runAction(["get", String(service), "--field", String(field), "--quiet", "--no-clipboard"],
               { kind: "copyField", service: String(service), field: String(field) })
  }

  // Read the password back for on-screen reveal. The value stays in QML only
  // while the user is looking at it; the view clears it on selection change.
  function revealPassword(service) {
    _runAction(["get", String(service), "--field", "password", "--quiet", "--no-clipboard"],
               { kind: "reveal", service: String(service) })
  }

  function generatePassword(length) {
    var n = Number(length) || 20
    if (n < 8) n = 8
    if (n > 128) n = 128
    _runAction(["generate", "--length", String(n), "--no-clipboard"], { kind: "generate", clipClear: 5 })
  }

  function deleteCredential(service) {
    _runAction(["delete", String(service), "--force"], { kind: "delete", service: String(service) })
  }

  function openUrl(url) {
    touch()
    if (url) Quickshell.execDetached(["xdg-open", String(url)])
  }

  function openTerminal(args) {
    touch()
    var bin = root.passCliBin || "pass-cli"
    Quickshell.execDetached(["omarchy-launch-terminal", bin].concat(args || []))
  }

  function _metadataFlags(url, category, notes, totp) {
    var a = []
    if (url) a.push("--url", String(url))
    if (category) a.push("--category", String(category))
    if (notes) a.push("--notes", String(notes))
    if (totp && String(totp).indexOf("otpauth://") === 0) a.push("--totp-uri", String(totp))
    return a
  }

  // Add a credential. autoGenerate asks pass-cli to make the password;
  // otherwise password must be supplied. pass-cli requires a username, so an
  // empty one falls back to the service name rather than letting add() hang
  // on a TTY prompt it cannot satisfy.
  function addCredential(service, username, url, category, notes, password, autoGenerate) {
    var user = String(username || "")
    var args = ["add", String(service), "--username", user ? user : String(service)]
    if (autoGenerate === true) args.push("--generate", "--gen-length", "20")
    else args.push("--password", String(password || ""))
    args = args.concat(_metadataFlags(url, category, notes, ""))
    _runAction(args, { kind: "added", service: String(service) })
  }

  // Add where the user types the password in a terminal instead.
  function addCredentialInteractive(service, username, url, category, notes) {
    var user = String(username || "")
    var args = ["add", String(service), "--username", user ? user : String(service)]
      .concat(_metadataFlags(url, category, notes, ""))
    openTerminal(args)
  }

  // Update metadata. autoGenerate adds --generate so pass-cli replaces the
  // password with a fresh one; otherwise a non-empty password replaces it with
  // the typed value. Empty means keep the current password.
  function updateCredential(service, username, url, category, notes, autoGenerate, password) {
    var args = ["update", String(service), "--force"]
    var flags = []
    if (username) flags.push("--username", String(username))
    flags = flags.concat(_metadataFlags(url, category, notes, ""))
    if (autoGenerate === true) flags.push("--generate", "--gen-length", "20")
    else if (String(password || "") !== "") flags.push("--password", String(password))
    if (flags.length === 0) {
      // Nothing changed; open the interactive update so the user can still act.
      openTerminal(["update", String(service)])
      return
    }
    _runAction(args.concat(flags), { kind: "updated", service: String(service) })
  }

  function updateWithTerminal(service) {
    openTerminal(["update", String(service)])
  }

  function _python() {
    return "python3"
  }

  property bool _gitStatusQueued: false

  function _runGit(args, meta) {
    if (gitProc.running) {
      if (meta && meta.kind === "status") root._gitStatusQueued = true
      return
    }
    gitProc.pending = meta
    gitProc.command = ["bash", root.pluginDir + "/scripts/git-sync.sh"].concat(args)
    gitProc.running = true
  }

  function gitStatus() { _runGit(["status"], { kind: "status" }) }
  function gitPush() { touch(); _runGit(["push"], { kind: "push" }) }
  function gitPull() { touch(); _runGit(["pull"], { kind: "pull" }) }
  function gitInit(remote) {
    var a = ["init"]
    if (remote) a.push(String(remote))
    _runGit(a, { kind: "init" })
  }
  function gitSetRemote(url) {
    if (url) _runGit(["remote", String(url)], { kind: "remote" })
  }

  function _maybeAutoPush() {
    if (String(root.gitAuto) === "On") autoPushTimer.restart()
  }

  function loadImportDir(dir) {
    if (candProc.running) return
    var a = [root._python(), root.pluginDir + "/scripts/import.py", "--browse"]
    if (dir) a.push(String(dir))
    candProc.command = a
    candProc.running = true
  }

  function runImport(path, overwrite, dryRun) {
    touch()
    if (importProc.running || !path) return
    var a = [root._python(), root.pluginDir + "/scripts/import.py", String(path), "--json"]
    if (overwrite === true) a.push("--overwrite")
    if (dryRun === true) a.push("--dry-run")
    if (root.passCliBin) a.push("--pass-cli", root.passCliBin)
    if (root.vaultConfig) a.push("--config", root.vaultConfig)
    importProc.pendingDryRun = dryRun === true
    importProc.command = a
    importProc.running = true
  }

  Process {
    id: candProc
    stdout: StdioCollector { id: candOut; waitForEnd: true }
    stderr: StdioCollector { id: candErr; waitForEnd: true }
    onExited: function (exitCode) {
      var dir = "", parent = "", home = "", entries = []
      if (exitCode === 0) {
        try {
          var parsed = JSON.parse(String(candOut.text || ""))
          if (parsed && parsed.ok === true) {
            dir = String(parsed.dir || "")
            parent = String(parsed.parent || "")
            home = String(parsed.home || "")
            if (Array.isArray(parsed.entries)) entries = parsed.entries
          }
        } catch (e) {
          console.warn("kalel.pass: browse parse failed:", e)
        }
      }
      root.importDirLoaded(dir, parent, home, entries)
    }
  }

  Process {
    id: importProc
    property bool pendingDryRun: false
    property string errTail: ""
    stdout: StdioCollector { id: impOut; waitForEnd: true }
    stderr: SplitParser {
      onRead: function (line) {
        var s = String(line || "").trim()
        if (s.indexOf("PROGRESS ") === 0) {
          var parts = s.split(/\s+/)
          root.importProgress(Number(parts[1]) || 0, Number(parts[2]) || 0)
        } else if (s !== "") {
          importProc.errTail = s
        }
      }
    }
    onExited: function (exitCode) {
      var summary = null
      try {
        summary = JSON.parse(String(impOut.text || ""))
      } catch (e) {
        summary = null
      }
      if (!summary) {
        summary = { ok: false, error: Parse.shortError(importProc.errTail) || "import failed" }
      }
      importProc.errTail = ""
      root.importFinished(summary)
      if (summary.ok === true && importProc.pendingDryRun !== true) {
        root.refresh()
        root._maybeAutoPush()
      }
    }
  }

  Process {
    id: gitProc
    property var pending: null
    stdout: StdioCollector { id: gitOut; waitForEnd: true }
    stderr: StdioCollector { id: gitErr; waitForEnd: true }
    onExited: function (exitCode) {
      var meta = gitProc.pending || ({})
      gitProc.pending = null
      var result = null
      try { result = JSON.parse(String(gitOut.text || "")) } catch (e) { result = null }
      if (!result) result = { ok: false, error: Parse.shortError(String(gitErr.text || "")) || "git command failed" }
      if (meta.kind === "status") root.gitStatusLoaded(result)
      else {
        root.gitResult(result)
        if (meta.kind === "push") root._notify(result.ok ? "Pushed to GitHub" : ("Push failed: " + (result.error || "")), result.ok !== true)
        else if (meta.kind === "pull") root._notify(result.ok ? "Pulled from GitHub" : ("Pull failed: " + (result.error || "")), result.ok !== true)
        else if (meta.kind === "init") root._notify(result.ok ? "Git sync initialized" : ("Init failed: " + (result.error || "")), result.ok !== true)
        else if (meta.kind === "remote") root._notify(result.ok ? "Remote set" : ("Remote failed: " + (result.error || "")), result.ok !== true)
      }
      if (root._gitStatusQueued) { root._gitStatusQueued = false; root.gitStatus() }
    }
  }

  Timer {
    id: autoPushTimer
    interval: 3000
    onTriggered: root.gitPush()
  }

  Process {
    id: listProc
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    stderr: StdioCollector { id: listErr; waitForEnd: true }
    onExited: function (exitCode) {
      root.busy = false
      root.loaded = true
      if (exitCode === 0) {
        var entries = Parse.listFromJson(listOut.text)
        root.credentials = entries
        root.categories = Parse.categories(entries)
        root.state = "ready"
        root.lastError = ""
      } else {
        var msg = String(listErr.text || "").trim()
        root.state = root._classifyError(msg)
        root.lastError = Parse.shortError(msg)
        root.credentials = []
        root.categories = []
      }
    }
  }

  Process {
    id: actionProc
    property var pending: null
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function (exitCode) {
      var meta = actionProc.pending || ({})
      actionProc.pending = null
      var out = String(actionOut.text || "")
      if (exitCode === 0) {
        if (meta.kind === "copyPassword") {
          root._notify("Password copied — clears in 5s", false)
        } else if (meta.kind === "copyTotp") {
          root._notify("TOTP code copied", false)
        } else if (meta.kind === "copyField") {
          var value = out.replace(/\r?\n+$/, "")
          if (value) {
            Quickshell.execDetached(["wl-copy", "--", value])
            var label = meta.field ? (meta.field.charAt(0).toUpperCase() + meta.field.slice(1)) : "Value"
            root._notify(label + " copied", false)
          } else {
            root._notify("Nothing to copy for " + (meta.field || "value"), true)
          }
        } else if (meta.kind === "reveal") {
          root.passwordRevealed(meta.service, out.replace(/\r?\n+$/, ""))
        } else if (meta.kind === "generate") {
          root._notify("Password generated and copied", false)
        } else if (meta.kind === "delete") {
          root._notify("Deleted " + meta.service, false)
          root.refresh()
          root._maybeAutoPush()
        } else if (meta.kind === "added") {
          root._notify("Added " + meta.service, false)
          root.refresh()
          root._maybeAutoPush()
        } else if (meta.kind === "updated") {
          root._notify("Updated " + meta.service, false)
          root.refresh()
          root._maybeAutoPush()
        }
      } else {
        var detail = Parse.shortError(String(actionErr.text || ""))
        root._notify(detail || "Action failed", true)
      }
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.lockMinutes > 0
    onTriggered: {
      if (root.lockMinutes <= 0) return
      if (Date.now() - root.lastActivity < root.lockMinutes * 60000) return
      root.credentials = []
      root.categories = []
      root.state = "locked"
      root.lockRequested()
    }
  }

  IpcHandler {
    target: "kalel.pass"

    function refresh(): void { root.refresh() }
    function copyPassword(service: string): void { root.copyPassword(service) }
    function copyField(service: string, field: string): void { root.copyField(service, field) }
    function copyTotp(service: string): void { root.copyTotp(service) }
    function generate(): void { root.generatePassword(20) }
    function remove(service: string): void { root.deleteCredential(service) }
  }
}
