// Standalone Quickshell carousel picker (omarchy image-picker style).
// Driven by a JSON file (env PICKER_JSON) with { items:[{path,thumb,label}], selected:<path> }.
// On Enter the selected path is written to PICKER_SEL and PICKER_DONE is touched, then the
// process quits. On Esc/cancel only PICKER_DONE is touched. The calling script applies the result.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

PanelWindow {
  id: root

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "qs-picker"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: root.opened && root.imagesLoaded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore

  readonly property string home: Quickshell.env("HOME")
  readonly property string jsonFile: Quickshell.env("PICKER_JSON")
  readonly property string selectionFile: Quickshell.env("PICKER_SEL")
  readonly property string doneFile: Quickshell.env("PICKER_DONE")

  property var imageArray: []
  property int selectedIndex: 0
  property bool imagesLoaded: false
  property bool opened: false
  property bool layoutSettled: false

  readonly property color dimColor: "#000000"
  readonly property color foreground: "#c0caf5"
  readonly property color scrim: Qt.rgba(0.06, 0.06, 0.09, 0.72)
  readonly property color selectedBorder: "#7aa2f7"
  readonly property color unselectedBorder: "#3b4261"

  readonly property int expandedWidth: 768
  readonly property int expandedHeight: 432
  readonly property int sliceWidth: 108
  readonly property int sliceHeight: 400
  readonly property int sliceSpacing: -30
  readonly property int skewOffset: 28
  readonly property int bottomChromeHeight: 74

  function fileUrl(path) {
    return "file://" + path
  }

  function alpha(color, value) {
    return Qt.rgba(color.r, color.g, color.b, color.a * value)
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function parseRows(text) {
    var data = {}
    try { data = JSON.parse(text) || {} } catch (e) { data = {} }
    var items = data.items || []
    var out = []
    for (var i = 0; i < items.length; i++) {
      out.push({
        filePath: String(items[i].path || ""),
        thumbnailPath: String(items[i].thumb || items[i].path || ""),
        label: String(items[i].label || "")
      })
    }
    return out
  }

  function currentPath() {
    if (imageArray.length === 0) return ""
    return imageArray[selectedIndex].filePath
  }

  function currentLabel() {
    if (imageArray.length === 0) return ""
    return imageArray[selectedIndex].label
  }

  function select(index, immediate) {
    if (imageArray.length === 0) return
    if (index < 0) index = 0
    else if (index >= imageArray.length) index = imageArray.length - 1
    if (index === selectedIndex && immediate !== true) return
    selectedIndex = index
  }

  function selectAdjacent(direction) {
    var count = imageArray.length
    if (count === 0) return
    selectedIndex = (selectedIndex + direction + count) % count
    select(selectedIndex, true)
  }

  function indexForSelected(images, want) {
    if (!want) return 0
    for (var i = 0; i < images.length; i++) {
      if (images[i].filePath === want) return i
    }
    return 0
  }

  function applySelected() {
    var path = currentPath()
    if (!path || !selectionFile) {
      cancel()
      return
    }
    runWriter("printf '%s\\n' " + shellQuote(path) + " > " + shellQuote(selectionFile) + "; : > " + shellQuote(doneFile))
  }

  function cancel() {
    runWriter(": > " + shellQuote(doneFile))
  }

  function runWriter(script) {
    applyProc.script = script
    applyProc.running = true
  }

  Process {
    id: applyProc
    property string script: ""
    command: ["sh", "-c", script]
    onExited: Qt.quit()
  }

  Process {
    id: loadProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var images = root.parseRows(String(text || ""))
        root.imageArray = images
        root.selectedIndex = root.indexForSelected(images, root.desiredSelected)
        root.imagesLoaded = images.length > 0
        root.opened = true
        root.layoutSettled = true
      }
    }
    onExited: {
      if (!root.imagesLoaded) {
        root.opened = true
        Qt.quit()
      }
    }
  }

  property string desiredSelected: ""

  function start() {
    root.opened = true
    loadProc.command = ["sh", "-c", "cat " + shellQuote(root.jsonFile)]
    loadProc.running = true
  }

  Timer {
    id: startTimer
    interval: 50
    repeat: false
    onTriggered: root.start()
  }

Component.onCompleted: startTimer.running = true

  Rectangle {
        anchors.fill: parent
        visible: root.opened && root.imagesLoaded
        color: root.scrim
      }

      MouseArea {
        anchors.fill: parent
        enabled: root.opened && root.imagesLoaded
        onClicked: root.cancel()
      }

      Item {
        id: card
        visible: root.opened && root.imagesLoaded && root.layoutSettled && root.imageArray.length > 0
        width: Math.min(parent.width - 80, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 40)
        height: root.expandedHeight + root.bottomChromeHeight
        anchors.centerIn: parent

        MouseArea { anchors.fill: parent; onClicked: {} }

        Item {
          id: carousel
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.bottomChromeHeight
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
          clip: false
          focus: true

          readonly property real itemStep: root.sliceWidth + root.sliceSpacing
          readonly property real previewX: (width - root.expandedWidth) / 2

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.cancel()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.applySelected()
              event.accepted = true
            } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) {
              root.selectAdjacent(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
              root.selectAdjacent(1)
              event.accepted = true
            }
          }

          Component.onCompleted: forceActiveFocus()

          readonly property bool readyToFocus: root.layoutSettled
          onReadyToFocusChanged: if (readyToFocus) Qt.callLater(() => carousel.forceActiveFocus())

          Repeater {
            model: root.imageArray.length

            delegate: Item {
              id: item
              required property int index

              readonly property var entry: root.imageArray[index]
              readonly property string filePath: entry ? entry.filePath : ""
              readonly property string thumbnailPath: entry ? entry.thumbnailPath : ""
              readonly property int relativeIndex: index - root.selectedIndex
              readonly property bool selected: index === root.selectedIndex

              readonly property bool nearby: Math.abs(relativeIndex) <= 12
              property bool sourceActivated: nearby
              onNearbyChanged: if (nearby) sourceActivated = true

              visible: nearby
              x: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
              width: selected ? root.expandedWidth : root.sliceWidth
              height: selected ? root.expandedHeight : root.sliceHeight
              y: selected ? 0 : (root.expandedHeight - root.sliceHeight) / 2
              z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)

              readonly property real sAbs: Math.abs(root.skewOffset)
              readonly property real topLeft: root.skewOffset >= 0 ? sAbs : 0
              readonly property real topRight: root.skewOffset >= 0 ? width : width - sAbs
              readonly property real bottomRight: root.skewOffset >= 0 ? width - sAbs : width
              readonly property real bottomLeft: root.skewOffset >= 0 ? 0 : sAbs

              Item {
                id: maskShape
                anchors.fill: parent
                visible: false
                layer.enabled: true

                Shape {
                  anchors.fill: parent
                  antialiasing: true
                  preferredRendererType: Shape.CurveRenderer
                  ShapePath {
                    fillColor: "white"
                    strokeColor: "transparent"
                    startX: item.topLeft; startY: 0
                    PathLine { x: item.topRight; y: 0 }
                    PathLine { x: item.bottomRight; y: item.height }
                    PathLine { x: item.bottomLeft; y: item.height }
                    PathLine { x: item.topLeft; y: 0 }
                  }
                }
              }

              Item {
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                  maskEnabled: true
                  maskSource: maskShape
                  maskThresholdMin: 0.3
                  maskSpreadAtMin: 0.3
                }

                Image {
                  id: image
                  anchors.fill: parent
                  source: item.sourceActivated && item.thumbnailPath ? root.fileUrl(item.thumbnailPath) : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: false
                  cache: true
                  smooth: true
                }

                Rectangle {
                  anchors.fill: parent
                  color: root.alpha(root.dimColor, item.selected ? 0 : 0.42)
                }
              }

              Shape {
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                  fillColor: "transparent"
                  strokeColor: item.selected ? root.selectedBorder : root.unselectedBorder
                  strokeWidth: item.selected ? 3 : 1
                  startX: item.topLeft; startY: 0
                  PathLine { x: item.topRight; y: 0 }
                  PathLine { x: item.bottomRight; y: item.height }
                  PathLine { x: item.bottomLeft; y: item.height }
                  PathLine { x: item.topLeft; y: 0 }
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: item.selected ? root.applySelected() : root.select(index)
              }
            }
          }
        }

        Text {
          id: selectedLabel
          visible: root.imagesLoaded && root.imageArray.length > 0
          textFormat: Text.PlainText
          anchors.top: carousel.bottom
          anchors.topMargin: 16
          anchors.horizontalCenter: carousel.horizontalCenter
          width: root.expandedWidth
          text: root.currentLabel()
          color: root.foreground
          style: Text.Outline
          styleColor: root.alpha(root.dimColor, 0.7)
          font.pixelSize: 32
          font.weight: Font.DemiBold
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
}