import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  property var settings: ({})

  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    return url.replace(/^file:\/\//, "").replace(/\/$/, "")
  }

  readonly property string cachePath: {
    var home = Quickshell.env("HOME") || "/root"
    var xdg = Quickshell.env("XDG_CACHE_HOME") || (home + "/.cache")
    return xdg + "/omarchy/opendota/record.json"
  }

  property var record: null
  property bool loading: false
  property string collectError: ""

  readonly property bool ready: !!record && record.ready === true

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  property int refreshIntervalSec: Math.max(3600, Number(setting("refreshIntervalSec", 21600)))
  property bool demoMode: setting("demo", false) === true
  property string pendingKind: ""

  FileView {
    id: cacheView
    path: root.cachePath
    onLoaded: {
      try {
        var parsed = JSON.parse(String(text || ""))
        if (parsed && typeof parsed === "object" && parsed.ready === true) {
          root.record = parsed
        }
      } catch (e) {
        console.warn("opendota", "Ignoring cached record", e)
      }
    }
  }

  Process {
    id: collectProcess
    running: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRecord(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("opendota", text.trim())
    }

    onExited: {
      root.loading = false
      if (root.pendingKind !== "") {
        var kind = root.pendingKind
        root.pendingKind = ""
        root.collect(kind)
      }
    }
  }

  function collect(kind) {
    if (collectProcess.running) {
      if (kind === "force" || pendingKind === "") pendingKind = kind
      return
    }
    var command = [pluginDir + "/bin/collect"]
    if (kind === "force") command.push("--force")
    if (kind === "summary") command.push("--summary-only")
    if (root.demoMode) command.push("--demo")
    var overrideId = String(setting("accountId", "") || "").trim()
    if (overrideId !== "") command.push("--account-id", overrideId)
    loading = true
    collectProcess.command = command
    collectProcess.running = true
  }

  function applyRecord(output) {
    try {
      var parsed = JSON.parse(String(output || ""))
      if (parsed && typeof parsed === "object") {
        record = parsed
        collectError = ""
        return
      }
    } catch (e) {
      console.warn("opendota", "Ignoring bad record", e)
    }
    collectError = "Collector produced no usable record."
  }

  function refreshAll(force) { collect(force === true ? "force" : "normal") }

  function refreshSummary() { collect("summary") }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.collect("normal")
  }

  function modeLabel(mode) {
    if (mode === "turbo") return "Turbo"
    if (mode === "ranked") return "Ranked"
    if (mode === "unranked") return "Unranked"
    if (mode === "all") return "All modes"
    return String(mode || "")
  }

  function primaryMode(modes) {
    if (!modes) return "turbo"
    var candidates = [
      { id: "turbo", n: Number(modes.turbo && modes.turbo.games || 0) },
      { id: "ranked", n: Number(modes.ranked && modes.ranked.games || 0) },
      { id: "unranked", n: Number(modes.unranked && modes.unranked.games || 0) }
    ]
    candidates.sort(function(a, b) { return b.n - a.n })
    return candidates[0].n > 0 ? candidates[0].id : "turbo"
  }

  function recentForMode(record, modeId) {
    if (!record) return []
    var byMode = record.recentByMode
    if (byMode && Array.isArray(byMode[modeId])) return byMode[modeId]
    if (modeId === "turbo" && Array.isArray(record.recentTurbo)) return record.recentTurbo
    return []
  }

  function topHeroesForMode(record, modeId) {
    if (!record) return []
    var byMode = record.topHeroesByMode
    if (byMode && Array.isArray(byMode[modeId])) return byMode[modeId]
    if (modeId === "turbo" && Array.isArray(record.topHeroesTurbo)) return record.topHeroesTurbo
    return []
  }

  function formatKda(k, d, a) {
    var kills = Number(k || 0)
    var deaths = Number(d || 0)
    var assists = Number(a || 0)
    if (!(deaths > 0)) return String(kills + assists)
    return ((kills + assists) / deaths).toFixed(1)
  }

  function formatDuration(sec) {
    var total = Math.max(0, Math.floor(Number(sec || 0)))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var seconds = total % 60
    var mm = String(minutes).padStart(2, "0")
    var ss = String(seconds).padStart(2, "0")
    if (hours > 0) {
      return String(hours) + ":" + mm + ":" + ss
    }
    return mm + ":" + ss
  }

  function relativeTime(unixMs) {
    var stamp = Number(unixMs || 0)
    if (!(stamp > 0)) return ""
    var now = Date.now()
    var deltaMs = Math.max(0, now - stamp)
    var minutes = Math.floor(deltaMs / 60000)
    if (minutes < 1) return "now"
    if (minutes < 60) return minutes + "m"
    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h"
    var days = Math.floor(hours / 24)
    if (days < 30) return days + "d"
    var months = Math.floor(days / 30)
    if (months < 12) return months + "mo"
    var years = Math.floor(days / 365)
    return years + "y"
  }

  function rankName(tier) {
    var names = {
      1: "Herald",
      2: "Guardian",
      3: "Crusader",
      4: "Archon",
      5: "Legend",
      6: "Ancient",
      7: "Divine",
      8: "Immortal"
    }
    var key = Number(tier)
    return names[key] || "Unranked"
  }

  function friendlyHeroName(id) {
    if (!record || !record.heroNames) return ""
    var name = record.heroNames[String(id)]
    return name ? String(name) : ""
  }
}
