import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  // Injected by omarchy-shell
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "culcat.cursor-finder"
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : (home + "/.config/omarchy/plugins/culcat.cursor-finder")
  readonly property string trackerScript: sourceDir + "/tracker.py"
  readonly property string configPath: home + "/.config/omarchy/cursor-finder.json"

  // Live configuration state
  property bool enabled: true
  property real sensitivity: 1.0
  property real maxScale: 4.2
  property int baseSize: 24
  property int holdMs: 480
  property string cursorStyle: "macos" // "macos" | "theme" | "inverted"
  property bool showHalo: false
  property bool hideNativeCursor: true

  // Live cursor overlay state (updated at ~125 FPS only while active)
  property bool overlayVisible: false
  property int cursorX: 0
  property int cursorY: 0
  property real cursorScale: 1.0
  property int trackerPid: 0
  property bool configLoaded: false
  property bool restartingTracker: false

  function clamp(val, minVal, maxVal) {
    return Math.max(minVal, Math.min(maxVal, val))
  }

  function currentSettingsObject() {
    return {
      enabled: root.enabled,
      sensitivity: Math.round(root.sensitivity * 100) / 100,
      maxScale: Math.round(root.maxScale * 100) / 100,
      baseSize: root.baseSize,
      holdMs: root.holdMs,
      cursorStyle: root.cursorStyle,
      showHalo: root.showHalo,
      hideNativeCursor: root.hideNativeCursor
    }
  }

  function applySettingsObject(obj, persist) {
    if (!obj || typeof obj !== "object") return
    var needTrackerRestart = false

    if (obj.enabled !== undefined) {
      var nextEnabled = Boolean(obj.enabled)
      if (root.enabled !== nextEnabled) {
        root.enabled = nextEnabled
        needTrackerRestart = true
      }
    }
    if (obj.sensitivity !== undefined && isFinite(Number(obj.sensitivity))) {
      var nextSens = clamp(Number(obj.sensitivity), 0.3, 3.0)
      if (Math.abs(root.sensitivity - nextSens) > 0.001) {
        root.sensitivity = nextSens
        needTrackerRestart = true
      }
    }
    if (obj.maxScale !== undefined && isFinite(Number(obj.maxScale))) {
      var nextScale = clamp(Number(obj.maxScale), 2.0, 8.0)
      if (Math.abs(root.maxScale - nextScale) > 0.001) {
        root.maxScale = nextScale
        needTrackerRestart = true
      }
    }
    if (obj.baseSize !== undefined && isFinite(Number(obj.baseSize))) {
      root.baseSize = Math.round(clamp(Number(obj.baseSize), 16, 64))
    }
    if (obj.holdMs !== undefined && isFinite(Number(obj.holdMs))) {
      var nextHold = Math.round(clamp(Number(obj.holdMs), 150, 3000))
      if (root.holdMs !== nextHold) {
        root.holdMs = nextHold
        needTrackerRestart = true
      }
    }
    if (obj.cursorStyle !== undefined) {
      var st = String(obj.cursorStyle)
      if (["macos", "theme", "inverted"].indexOf(st) !== -1) {
        root.cursorStyle = st
      }
    }
    if (obj.showHalo !== undefined) {
      root.showHalo = Boolean(obj.showHalo)
    }
    if (obj.hideNativeCursor !== undefined) {
      var nextHide = Boolean(obj.hideNativeCursor)
      if (root.hideNativeCursor !== nextHide) {
        root.hideNativeCursor = nextHide
        needTrackerRestart = true
      }
    }

    if (persist) {
      saveConfig()
    }
    if (needTrackerRestart && root.configLoaded) {
      restartTracker()
    }
  }

  function saveConfig() {
    var data = currentSettingsObject()
    configFile.setText(JSON.stringify(data, null, 2) + "\n")
    if (root.shell && typeof root.shell.updateEntryInline === "function") {
      root.shell.updateEntryInline(root.pluginId, data)
    }
  }

  function loadConfigText(raw) {
    var text = String(raw || "").trim()
    if (text) {
      try {
        var parsed = JSON.parse(text)
        applySettingsObject(parsed, false)
      } catch (e) {
        console.warn("cursor-finder: failed to parse config:", e)
      }
    }
    root.configLoaded = true
    restartTracker()
  }

  function handleTrackerLine(line) {
    var trimmed = String(line || "").trim()
    if (!trimmed) return

    if (trimmed.indexOf("FRAME ") === 0) {
      var parts = trimmed.split(" ")
      if (parts.length >= 4) {
        var nx = parseInt(parts[1], 10)
        var ny = parseInt(parts[2], 10)
        var ns = parseFloat(parts[3])
        if (isFinite(nx) && isFinite(ny) && isFinite(ns)) {
          root.cursorX = nx
          root.cursorY = ny
          root.cursorScale = ns
          root.overlayVisible = true
        }
      }
    } else if (trimmed === "HIDE") {
      root.overlayVisible = false
      root.cursorScale = 1.0
    } else if (trimmed.indexOf("READY ") === 0) {
      var pid = parseInt(trimmed.slice(6).trim(), 10)
      if (isFinite(pid) && pid > 0) {
        root.trackerPid = pid
      }
    }
  }

  function startTracker() {
    if (!root.enabled) {
      stopTracker()
      return
    }
    if (trackerProcess.running) return

    trackerProcess.command = [
      "python3",
      root.trackerScript,
      "--sensitivity", String(root.sensitivity),
      "--max-scale", String(root.maxScale),
      "--hold-ms", String(root.holdMs),
      "--hide-native", root.hideNativeCursor ? "1" : "0"
    ]
    trackerProcess.running = true
  }

  function stopTracker() {
    root.overlayVisible = false
    root.cursorScale = 1.0
    root.trackerPid = 0
    if (trackerProcess.running) {
      trackerProcess.running = false
    }
  }

  function restartTracker() {
    trackerRestartTimer.stop()
    if (trackerProcess.running) {
      root.restartingTracker = true
      stopTracker()
    } else {
      root.restartingTracker = false
      startTracker()
    }
  }

  function locate() {
    if (!root.enabled) {
      applySettingsObject({ enabled: true }, true)
    }
    if (root.trackerPid > 0 && !signalProcess.running) {
      signalProcess.command = ["kill", "-USR1", String(root.trackerPid)]
      signalProcess.running = true
      return "ok"
    }
    return "starting"
  }

  function updateSetting(key, value) {
    var patch = ({})
    if (key === "enabled" || key === "showHalo" || key === "hideNativeCursor") {
      var s = String(value).toLowerCase()
      patch[key] = (s === "true" || s === "1" || s === "yes" || s === "on")
    } else if (key === "sensitivity" || key === "maxScale" || key === "baseSize" || key === "holdMs") {
      patch[key] = Number(value)
    } else if (key === "cursorStyle") {
      patch[key] = String(value)
    } else {
      return "unknown_key"
    }
    applySettingsObject(patch, true)
    return "ok"
  }

  function statusJson() {
    return JSON.stringify({
      id: root.pluginId,
      enabled: root.enabled,
      running: trackerProcess.running,
      trackerPid: root.trackerPid,
      overlayVisible: root.overlayVisible,
      cursorX: root.cursorX,
      cursorY: root.cursorY,
      cursorScale: root.cursorScale,
      settings: currentSettingsObject()
    })
  }

  FileView {
    id: configFile
    path: root.configPath
    atomicWrites: true
    printErrors: false
    onLoaded: if (!root.configLoaded) root.loadConfigText(text())
    onLoadFailed: if (!root.configLoaded) root.loadConfigText("")
  }

  Process {
    id: trackerProcess
    stdout: SplitParser {
      onRead: function(line) { root.handleTrackerLine(line) }
    }
    onExited: function(exitCode, exitStatus) {
      root.overlayVisible = false
      root.cursorScale = 1.0
      root.trackerPid = 0
      if (root.restartingTracker) {
        root.restartingTracker = false
        Qt.callLater(root.startTracker)
      } else if (root.enabled) {
        trackerRestartTimer.restart()
      }
    }
  }

  Process {
    id: signalProcess
  }

  Timer {
    id: trackerRestartTimer
    interval: 1000
    repeat: false
    onTriggered: if (root.enabled && !trackerProcess.running) root.startTracker()
  }

  onManifestChanged: {
    if (root.configLoaded && !trackerProcess.running && root.enabled) {
      Qt.callLater(root.startTracker)
    }
  }

  Component.onCompleted: {
    Qt.callLater(function() {
      configFile.reload()
    })
  }

  Component.onDestruction: {
    stopTracker()
  }

  // Click-through overlay window per monitor
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: root.enabled && !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }

      WlrLayershell.namespace: "omarchy-cursor-finder"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // Empty input region so clicks, drags, and scroll pass straight through
      mask: Region {}

      readonly property int screenX: panel.screen ? panel.screen.x : 0
      readonly property int screenY: panel.screen ? panel.screen.y : 0
      readonly property int localCursorX: root.cursorX - screenX
      readonly property int localCursorY: root.cursorY - screenY
      readonly property int marginAllowance: Math.ceil(root.baseSize * root.maxScale) + 32
      readonly property bool onThisScreen: root.overlayVisible
        && localCursorX >= -marginAllowance
        && localCursorY >= -marginAllowance
        && localCursorX <= panel.width + marginAllowance
        && localCursorY <= panel.height + marginAllowance

      CursorShape {
        visible: panel.onThisScreen
        x: panel.localCursorX
        y: panel.localCursorY
        baseSize: root.baseSize
        cursorScale: root.cursorScale
        cursorStyle: root.cursorStyle
        showHalo: root.showHalo
      }
    }
  }

  IpcHandler {
    target: "cursor-finder"

    function status(): string {
      return root.statusJson()
    }

    function locate(): string {
      return root.locate()
    }

    function enable(): string {
      root.applySettingsObject({ enabled: true }, true)
      return "enabled"
    }

    function disable(): string {
      root.applySettingsObject({ enabled: false }, true)
      return "disabled"
    }

    function toggle(): string {
      var next = !root.enabled
      root.applySettingsObject({ enabled: next }, true)
      return next ? "enabled" : "disabled"
    }

    function settings(): string {
      if (root.shell && typeof root.shell.toggle === "function") {
        root.shell.toggle(root.pluginId, "{}")
        return "ok"
      }
      return "unavailable"
    }

    function set(key: string, value: string): string {
      return root.updateSetting(key, value)
    }

    function ping(): string {
      return "ok"
    }
  }
}
