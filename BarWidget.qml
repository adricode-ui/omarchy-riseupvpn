import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon for Riseup OpenVPN plus its nftables kill switch.
// Polls a user helper. Privileged reads go through the root-owned
// /usr/local/bin/riseup-ctl once setup has installed polkit; until then the
// VPN state still comes from systemctl, which needs no root.
BarWidget {
  id: root
  moduleName: "adri.vpn-killswitch"

  readonly property string pluginVersion: "1.0.0"
  readonly property string helper: Qt.resolvedUrl("bin/riseup-ctl").toString().replace(/^file:\/\//, "")

  property string vpn: "unknown"
  property string killswitch: "unknown"
  property bool boot: false
  property bool tun: false
  property string address: ""
  property string statusText: ""
  property bool privileged: false
  property bool helperInstalled: false
  property string helperVersion: ""
  property string lastError: ""
  property bool busy: false
  property string publicIp: ""
  property string publicIpState: "idle"
  // Bumped on every toggle so a status read that started earlier is discarded.
  property int actionEpoch: 0
  property int statusEpoch: 0

  readonly property bool vpnUp: vpn === "active"
  readonly property bool ksOn: killswitch === "on"
  readonly property bool blocked: ksOn && vpn !== "active" && vpn !== "activating"
  readonly property bool helperStale: helperVersion !== "" && helperVersion !== pluginVersion
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function cleanToken(value, allowed, fallback) {
    var v = String(value == null ? "" : value)
    return allowed.indexOf(v) >= 0 ? v : fallback
  }

  function cleanAddress(value) {
    var v = String(value == null ? "" : value)
    return /^[0-9a-fA-F.:/]{1,64}$/.test(v) ? v : ""
  }

  function cleanText(value) {
    return String(value == null ? "" : value).replace(/[<>&]/g, "").slice(0, 160)
  }

  function parsePayload(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = lines[i].trim()
      if (line.charAt(0) !== "{") continue
      try { return JSON.parse(line) } catch (error) { return null }
    }
    return null
  }

  function applyStatus(data) {
    if (!data) return
    vpn = cleanToken(data.vpn, ["active", "inactive", "activating", "deactivating", "failed", "unknown"], "unknown")
    killswitch = cleanToken(data.killswitch, ["on", "off", "unknown"], "unknown")
    boot = data.boot === true
    tun = data.tun === true
    address = cleanAddress(data.address)
    statusText = cleanText(data.statusText)
    privileged = data.privileged === true
    helperInstalled = data.helperInstalled === true
    helperVersion = cleanText(data.version)
  }

  function stateWord(group, token) {
    var key = "state." + group + "." + token
    var word = strings.t(key)
    return word === key ? strings.t("state." + group + ".unknown") : word
  }

  function refresh() {
    if (busy || statusProcess.running) return
    statusEpoch = actionEpoch
    statusProcess.command = [helper, "status"]
    statusProcess.running = true
  }

  function runAction(cmd) {
    if (busy || actionProcess.running) return
    actionEpoch += 1
    busy = true
    lastError = ""
    if (cmd === "vpn-on") vpn = "activating"
    else if (cmd === "vpn-off") vpn = "deactivating"
    actionProcess.command = [helper, cmd]
    actionProcess.running = true
  }

  // One lookup when the panel opens, plus the refresh button. Not polled.
  function fetchIp() {
    if (ipProcess.running) return
    publicIpState = "loading"
    ipProcess.command = [helper, "public-ip"]
    ipProcess.running = true
  }

  function openSetup() {
    if (!bar) return
    if (panelLoader.item) panelLoader.item.close()
    bar.run("omarchy-launch-floating-terminal-with-presentation "
      + Util.shellQuote("sudo " + helper + " setup"))
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  Component.onCompleted: refresh()

  // Plugin catalogs in i18n/. English is the fallback.
  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  Timer {
    interval: Math.max(2, Math.min(30, Number(root.setting("refreshIntervalSec", 3)))) * 1000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  Process {
    id: statusProcess
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.busy || root.statusEpoch !== root.actionEpoch) return
      var data = root.parsePayload(statusStdout.text)
      if (exitCode === 0 && data) root.applyStatus(data)
    }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var data = root.parsePayload(actionStdout.text)
      if (data) root.applyStatus(data)
      if (data && data.ok === false && data.error)
        root.lastError = root.cleanToken(data.error, ["helper-not-installed", "cancelled", "start-failed", "stop-failed", "ks-failed", "generic"], "generic")
      else if (!data || exitCode !== 0)
        root.lastError = (exitCode === 126 || exitCode === 127) ? "cancelled" : "generic"
      else
        root.lastError = ""
      root.busy = false
      Qt.callLater(root.refresh)
    }
  }

  Process {
    id: ipProcess
    stdout: StdioCollector { id: ipStdout; waitForEnd: true }
    onExited: function(exitCode) {
      var data = root.parsePayload(ipStdout.text)
      var ip = data ? root.cleanAddress(data.ip) : ""
      if (exitCode === 0 && data && data.ok === true && ip !== "") {
        root.publicIp = ip
        root.publicIpState = "ok"
      } else {
        root.publicIp = ""
        root.publicIpState = "error"
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰖂"
    // Lock beside the tunnel icon so both states are visible without opening.
    labelText: root.killswitch === "on" ? "󰌾" : (root.killswitch === "off" ? "󰌋" : "")
    active: root.blocked || root.vpn === "failed"
    opacity: (root.vpnUp || root.vpn === "activating" || root.vpn === "failed" || root.ksOn) ? 1 : 0.45
    tooltipText: strings.t("bar.tooltip").arg(root.stateWord("vpn", root.vpn)).arg(root.stateWord("ks", root.killswitch))
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }
  }
}
