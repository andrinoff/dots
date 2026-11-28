import QtQuick
import qs.Commons
import qs.Ui

// The space invader from branding/about.txt, drawn pixel by pixel in the bar's
// ink. Left click opens the Omarchy menu, right click a terminal. While the
// pointer rests on it, it marches between its two classic frames.
BarWidget {
  id: root
  moduleName: "andrinoff.mark"

  readonly property var frames: [
    ["..X.....X..",
     "...X...X...",
     "..XXXXXXX..",
     ".XX.XXX.XX.",
     "XXXXXXXXXXX",
     "X.XXXXXXX.X",
     "X.X.....X.X",
     "...XX.XX..."],
    ["..X.....X..",
     "X..X...X..X",
     "X.XXXXXXX.X",
     "XXX.XXX.XXX",
     "XXXXXXXXXXX",
     ".XXXXXXXXX.",
     "..X.....X..",
     ".X.......X."]
  ]
  property int frame: 0
  property bool hovered: false

  readonly property color ink: root.bar ? root.bar.barForeground : Color.foreground
  // Whole device pixels per invader pixel keep the edges crisp.
  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  readonly property real cell: Math.max(1, Math.round(Style.bar.iconSize / 7 * dpr)) / dpr

  implicitWidth: root.vertical ? root.barSize : art.width + Style.space(16)
  implicitHeight: root.vertical ? art.height + Style.space(16) : root.barSize

  Timer {
    interval: 420
    repeat: true
    running: root.hovered
    onTriggered: root.frame = 1 - root.frame
    onRunningChanged: if (!running) root.frame = 0
  }

  Grid {
    id: art
    anchors.centerIn: parent
    columns: 11
    opacity: root.hovered ? 1 : 0.9

    Repeater {
      model: 88

      Rectangle {
        required property int index
        width: root.cell
        height: root.cell
        color: root.frames[root.frame][Math.floor(index / 11)][index % 11] === "X" ? root.ink : "transparent"
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hovered = true
    onExited: root.hovered = false
    onClicked: function(mouse) {
      if (!root.bar) return
      if (mouse.button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
