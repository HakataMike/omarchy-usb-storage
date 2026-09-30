import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "hakatamike.usb-storage"
  ipcTarget: "hakatamike.usb-storage"

  readonly property string helper: String(Qt.resolvedUrl("usb-storage")).replace(/^file:\/\//, "")
  readonly property string driveIcon: "󱊞"
  readonly property string ejectIcon: "󰇪"
  readonly property string openIcon: "󰝰"

  property var drives: []
  // Disk path -> true while its eject is in flight.
  property var ejecting: ({})
  property string ejectingPath: ""
  readonly property bool hasDrives: drives.length > 0

  function refresh() {
    if (!listProc.running) listProc.running = true
  }

  function openDrive(drive) {
    var part = Model.primaryPartition(drive)
    if (part && part.mountpoint) Util.execArgv(["xdg-open", part.mountpoint])
    root.close()
  }

  function ejectDrive(drive) {
    if (ejectProc.running || !drive) return
    root.ejectingPath = drive.path
    var next = Object.assign({}, root.ejecting)
    next[drive.path] = true
    root.ejecting = next
    ejectProc.ejectedTitle = Model.driveTitle(drive)
    ejectProc.command = [root.helper, "eject", drive.path]
    ejectProc.running = true
  }

  function finishEject(exitCode, errorText) {
    var next = Object.assign({}, root.ejecting)
    delete next[root.ejectingPath]
    root.ejecting = next
    root.ejectingPath = ""

    if (exitCode === 0) {
      Util.execArgv(["notify-send", "-a", "USB Storage", "-i", "media-eject",
        ejectProc.ejectedTitle + " ejected", "Safe to remove"])
    } else {
      var reason = String(errorText || "").trim().split("\n").pop() || "Unknown error"
      Util.execArgv(["notify-send", "-a", "USB Storage", "-u", "critical", "-i", "dialog-error",
        "Couldn't eject " + ejectProc.ejectedTitle,
        reason + "\nClose any files or terminals using the drive and try again."])
    }
    refresh()
  }

  onOpenedChanged: if (opened) refresh()
  onHasDrivesChanged: if (!hasDrives) close()
  Component.onCompleted: refresh()

  visible: hasDrives
  implicitWidth: hasDrives ? button.implicitWidth : 0
  implicitHeight: hasDrives ? button.implicitHeight : 0

  Process {
    id: listProc
    command: [root.helper, "list"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.drives = Model.parseDrives(text) }
  }

  Process {
    id: ejectProc
    property string ejectedTitle: ""
    stderr: StdioCollector { id: ejectErr; waitForEnd: true }
    onExited: function(exitCode) { root.finishEject(exitCode, ejectErr.text) }
  }

  // Block-device hotplug events drive the refresh; the follow-up refresh
  // catches udiskie's automount, which lands a moment after the add event.
  Process {
    id: udevMonitor
    running: true
    command: ["udevadm", "monitor", "--udev", "--subsystem-match=block"]
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).indexOf("UDEV") === 0) {
          debounce.restart()
          settle.restart()
        }
      }
    }
    onExited: restartMonitor.start()
  }

  Timer { id: restartMonitor; interval: 5000; onTriggered: udevMonitor.running = true }
  Timer { id: debounce; interval: 400; onTriggered: root.refresh() }
  Timer { id: settle; interval: 2500; onTriggered: root.refresh() }
  // Usage figures change while files are copied; keep them fresh while open,
  // and poll slowly otherwise as a backstop for missed udev events.
  Timer { interval: root.opened ? 3000 : 30000; running: true; repeat: true; onTriggered: root.refresh() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.driveIcon
    tooltipText: ""
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.hasDrives
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.driveIcon
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "USB Storage"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: (root.drives.length === 1 ? "1 drive connected" : root.drives.length + " drives connected").toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        // ---------- One section per drive ----------
        Repeater {
          model: root.drives

          Column {
            id: driveColumn
            required property var modelData
            readonly property var part: Model.primaryPartition(modelData)
            readonly property bool mounted: !!(part && part.mountpoint)
            readonly property bool busy: root.ejecting[modelData.path] === true

            width: column.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.bar.foreground }

            Column {
              width: parent.width
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: Model.driveTitle(driveColumn.modelData)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                visible: text !== ""
                text: Model.driveSubtitle(driveColumn.modelData)
                color: root.bar.foreground
                opacity: 0.6
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: parent.width
              }
            }

            // Usage bar, only meaningful once the filesystem is mounted.
            Item {
              visible: driveColumn.mounted
              width: parent.width
              implicitHeight: Style.space(8)

              Rectangle {
                id: track
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
              }

              Rectangle {
                anchors.left: track.left
                anchors.verticalCenter: track.verticalCenter
                height: track.height
                radius: track.radius
                color: root.bar.foreground
                width: Math.max(track.height, track.width * Model.usedFraction(driveColumn.part))
                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              InfoPair { label: "Device"; value: driveColumn.modelData.path }
              InfoPair { label: "Capacity"; value: Model.formatBytes(driveColumn.modelData.size) }
              InfoPair {
                visible: driveColumn.mounted
                label: "Used / Free"
                value: driveColumn.mounted
                  ? Model.formatBytes(driveColumn.part.used) + " / " + Model.formatBytes(driveColumn.part.avail)
                  : ""
              }
              InfoPair {
                label: "Filesystem"
                value: driveColumn.part ? Model.fsLabel(driveColumn.part.fstype) : "None"
              }
              InfoPair {
                label: "Connection"
                value: Model.speedLabel((driveColumn.modelData.usb || {}).speed)
              }
              InfoPair { label: "Serial"; value: driveColumn.modelData.serial || "—" }
              InfoPair {
                label: "Mounted at"
                value: driveColumn.mounted ? driveColumn.part.mountpoint : "Not mounted"
              }
            }

            Text {
              visible: Model.runningSlow(driveColumn.modelData)
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "This USB 3 drive is running at USB 2 speed. Reseat it firmly or plug it straight into a rear motherboard port."
              color: Color.urgent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              id: actionRow
              width: parent.width
              spacing: Style.space(6)
              readonly property int buttonCount: driveColumn.mounted ? 2 : 1
              readonly property real cellWidth: (width - spacing * (buttonCount - 1)) / buttonCount

              Button {
                visible: driveColumn.mounted
                width: actionRow.cellWidth
                iconText: root.openIcon
                iconSize: Style.font.title
                text: "Open"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                onClicked: root.openDrive(driveColumn.modelData)
              }

              Button {
                width: actionRow.cellWidth
                iconText: root.ejectIcon
                iconSize: Style.font.title
                text: driveColumn.busy ? "Ejecting…" : "Eject"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: driveColumn.busy
                onClicked: root.ejectDrive(driveColumn.modelData)
              }
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideMiddle
  }
}
