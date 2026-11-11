import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "adri.vpn-killswitch"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var host: hostWidget
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property color warn: bar ? bar.urgent : Color.urgent

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function vpnMeta() {
    if (!host) return ""
    if (host.vpn === "activating") return strings.t("panel.metaConnecting")
    if (host.vpn === "deactivating") return strings.t("panel.metaDisconnecting")
    if (host.vpn === "failed") return strings.t("panel.metaFailed")
    if (host.vpnUp && host.address) return strings.t("panel.metaAddress").arg(host.address)
    if (host.vpnUp) return strings.t("panel.metaUp")
    if (host.vpn === "inactive") return strings.t("panel.metaDown")
    return strings.t("panel.metaUnknown")
  }

  function errorLine() {
    if (!host || !host.lastError) return ""
    if (host.lastError === "helper-not-installed") return strings.t("error.notInstalled")
    if (host.lastError === "cancelled") return strings.t("error.cancelled")
    if (host.lastError === "start-failed") return strings.t("error.startFailed")
    if (host.lastError === "stop-failed") return strings.t("error.stopFailed")
    if (host.lastError === "ks-failed") return strings.t("error.ksFailed")
    return strings.t("error.generic")
  }

  function toggleVpn() {
    if (!host || host.busy) return
    var up = host.vpnUp || host.vpn === "activating"
    host.runAction(up ? "vpn-off" : "vpn-on")
  }

  function toggleKs() {
    if (!host || host.busy) return
    host.runAction(host.ksOn ? "ks-off" : "ks-on")
  }

  onOpenedChanged: {
    if (opened && hostWidget) {
      hostWidget.refresh()
      hostWidget.fetchIp()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    Flickable {
      id: flick
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: Math.min(column.implicitHeight, panel.contentHeight)
      implicitHeight: column.implicitHeight
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height + 1

      Column {
        id: column
        width: flick.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: strings.t("panel.title")
          meta: root.vpnMeta()
          foreground: root.fg
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          iconOpacity: host && host.vpnUp ? 1 : 0.45
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: "󰖂"
              color: root.fg
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.display
              width: font.pixelSize
              height: font.pixelSize
            }
          }
        }

        Toggle {
          width: parent.width
          label: strings.t("panel.vpn")
          description: !host ? "" : (host.busy && (host.vpn === "activating" || host.vpn === "deactivating")
            ? strings.t("panel.vpnBusy")
            : (host.vpnUp ? strings.t("panel.vpnOn") : strings.t("panel.vpnOff")))
          checked: host ? (host.vpnUp || host.vpn === "activating") : false
          foreground: root.fg
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: root.toggleVpn()
        }

        Toggle {
          width: parent.width
          label: strings.t("panel.ks")
          description: !host ? ""
            : (host.killswitch === "on" ? strings.t("panel.ksOn")
            : (host.killswitch === "off" ? strings.t("panel.ksOff") : strings.t("panel.ksUnknown")))
          checked: host ? host.ksOn : false
          foreground: root.fg
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: root.toggleKs()
        }

        Text {
          width: parent.width
          visible: host && host.blocked
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: strings.t("panel.blocked")
          color: root.warn
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: host && host.vpnUp && host.killswitch === "off"
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: strings.t("panel.leak")
          color: root.warn
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: root.errorLine() !== ""
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.errorLine()
          color: root.warn
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { foreground: root.fg }
        PanelSectionHeader {
          text: strings.t("panel.details")
          foreground: root.fg
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        Kv {
          k: strings.t("panel.service")
          v: host ? root.stringsWord("vpn", host.vpn) : ""
        }
        Kv {
          k: strings.t("panel.boot")
          v: host && host.boot ? strings.t("panel.bootOn") : strings.t("panel.bootOff")
        }
        Kv {
          k: strings.t("panel.tunnel")
          v: host && host.address ? host.address : strings.t("panel.noTunnel")
        }
        Kv {
          k: strings.t("panel.openvpn")
          v: host && (host.vpnUp || host.vpn === "activating" || host.vpn === "failed") && host.statusText
             ? host.statusText : "—"
        }
        Kv {
          k: strings.t("panel.publicIp")
          v: !host || host.publicIpState === "idle" ? "—"
            : (host.publicIpState === "loading" ? strings.t("panel.publicIpLoading")
            : (host.publicIpState === "ok" ? host.publicIp : strings.t("panel.publicIpNone")))
        }

        Button {
          width: parent.width
          text: strings.t("panel.refreshIp")
          foreground: root.fg
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.bodySmall
          bordered: true
          onClicked: if (host) host.fetchIp()
        }

        Text {
          width: parent.width
          visible: host && (!host.privileged || !host.helperInstalled)
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: strings.t("panel.setupHint")
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        Button {
          width: parent.width
          visible: host && (!host.privileged || !host.helperInstalled || host.helperStale)
          text: strings.t("panel.setup")
          foreground: root.fg
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.bodySmall
          bordered: true
          onClicked: if (host) host.openSetup()
        }

        Text {
          width: parent.width
          visible: host && host.helperStale
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: strings.t("panel.stale")
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: strings.t("panel.coupling")
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  function stringsWord(group, token) {
    var key = "state." + group + "." + token
    var word = strings.t(key)
    return word === key ? strings.t("state." + group + ".unknown") : word
  }

  component Kv: Row {
    property string k: ""
    property string v: ""
    width: parent.width
    spacing: Style.space(8)
    Text {
      width: Style.space(88)
      textFormat: Text.PlainText
      text: k
      color: root.dim
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    Text {
      width: parent.width - Style.space(88) - parent.spacing
      textFormat: Text.PlainText
      text: v
      color: root.fg
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
