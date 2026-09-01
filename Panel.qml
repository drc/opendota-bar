import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.drc.opendota"
  ipcTarget: "io.github.drc.opendota"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var record: usage.record
  readonly property var modes: record && record.modes ? record.modes : null
  readonly property var streak: record && record.streak ? record.streak : ({ current: 0, kind: "none" })
  readonly property string dataStatus: record ? String(record.dataStatus || "public") : "public"

  readonly property string primaryMode: modes ? usage.primaryMode(modes) : "turbo"
  readonly property var recentPrimary: usage.recentForMode(record, primaryMode)
  readonly property var topHeroesPrimary: usage.topHeroesForMode(record, primaryMode)

  property bool cursorActive: false
  property double nowMs: Date.now()

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refreshNow() { usage.refreshAll(true) }

  function formatWinRate(pct) {
    var n = Number(pct || 0)
    if (!(n >= 0)) n = 0
    return n.toFixed(1) + "%"
  }

  function logoSource() {
    var lum = 0.2126 * surface.r + 0.7152 * surface.g + 0.0722 * surface.b
    return Qt.resolvedUrl(lum > 0.5 ? "assets/opendota-light.svg" : "assets/opendota.svg")
  }

  function heroMeta() {
    if (!record) return ""
    var rank = record.rank ? String(record.rank.name || "") : ""
    var mmr = record.rank && record.rank.mmrEstimate ? "~" + record.rank.mmrEstimate + " MMR" : ""
    var primarySummary = ""
    if (modes) {
      var primary = primaryMode
      var pm = modes[primary]
      if (pm && pm.games > 0) {
        var label = usage.modeLabel(primary)
        primarySummary = pm.games + " " + label + " ("
          + formatWinRate(pm.winRate) + ")"
      }
    }
    var parts = []
    if (rank !== "") parts.push(rank)
    if (mmr !== "") parts.push(mmr)
    if (primarySummary !== "") parts.push(primarySummary)
    return parts.join(" · ")
  }

  function footerText() {
    if (!record) return ""
    if (record.updatedAtMs) {
      var msAge = Math.max(0, root.nowMs - Number(record.updatedAtMs))
      var mins = Math.round(msAge / 60000)
      return mins === 0 ? "Updated just now" : "Updated " + mins + " min ago"
    }
    if (!record.updatedAt) return ""
    var updated = new Date(String(record.updatedAt))
    if (isNaN(updated.getTime())) return ""
    var minutes = Math.max(0, Math.round((root.nowMs - updated.getTime()) / 60000))
    return minutes === 0 ? "Updated just now" : "Updated " + minutes + " min ago"
  }

  function modesHaveData() {
    if (!modes) return false
    var t = Number(modes.turbo && modes.turbo.games || 0)
    var r = Number(modes.ranked && modes.ranked.games || 0)
    var u = Number(modes.unranked && modes.unranked.games || 0)
    return (t + r + u) > 0
  }

  function modeMaxGames() {
    if (!modes) return 1
    var t = Number(modes.turbo && modes.turbo.games || 0)
    var r = Number(modes.ranked && modes.ranked.games || 0)
    var u = Number(modes.unranked && modes.unranked.games || 0)
    return Math.max(1, t, r, u)
  }

  function topHeroesPeak() {
    var peak = 0
    for (var i = 0; i < topHeroesPrimary.length; i++) {
      peak = Math.max(peak, Number(topHeroesPrimary[i].games || 0))
    }
    return Math.max(1, peak)
  }

  function matchTooltip(match) {
    if (!match) return ""
    var kda = usage.formatKda(match.kills, match.deaths, match.assists)
    var heroName = String(match.heroName || usage.friendlyHeroName(match.heroId) || "Hero")
    var result = match.won ? "Win" : "Loss"
    var ago = usage.relativeTime((Number(match.startedAt || 0)) * 1000)
    var line = heroName + " · " + result + " · " + kda + " KDA"
    if (ago !== "") line += " · " + ago
    return line
  }

  function heroTooltip(hero) {
    if (!hero) return ""
    var name = String(hero.name || "Hero")
    var games = Number(hero.games || 0)
    var wins = Number(hero.win || 0)
    var rate = games > 0 ? formatWinRate((wins / games) * 100) : "—"
    return name + " · " + games + " games · " + wins + " wins (" + rate + ")"
  }

  readonly property bool urgentActive: {
    if (streak && streak.kind === "lose"
        && streak.current >= Number(setting("urgentStreakMin", 3))) return true
    if (modes) {
      var pm = modes[primaryMode]
      if (pm && pm.games >= 20
          && Number(pm.winRate || 0) < Number(setting("urgentWinRatePct", 45))) return true
    }
    return false
  }

  readonly property int recentLimit: Math.max(1, Number(setting("recentMatchesCount", 10)))
  readonly property int topHeroesLimit: Math.max(1, Number(setting("topHeroesCount", 5)))
  readonly property int recentCount: Math.min(recentPrimary.length, recentLimit)
  readonly property int topHeroesCountShown: Math.min(topHeroesPrimary.length, topHeroesLimit)
  readonly property var recentSliced: recentPrimary.slice(0, recentCount)
  readonly property var topHeroesSliced: topHeroesPrimary.slice(0, topHeroesCountShown)

  visible: !!record && record.ready === true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshSummary()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰑴"
    active: root.urgentActive
    iconComponent: Component {
      Item {
        Image {
          id: barMark
          anchors.centerIn: parent
          width: parent.width
          height: parent.height
          source: root.logoSource()
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          fillMode: Image.PreserveAspectFit
          visible: false
          layer.enabled: true
        }

        MultiEffect {
          anchors.fill: barMark
          source: barMark
          visible: barMark.status === Image.Ready
          colorization: 1.0
          colorizationColor: root.urgentActive ? root.urgent : root.foreground
        }

        Text {
          anchors.centerIn: parent
          visible: barMark.status !== Image.Ready
          text: button.text
          color: root.urgentActive ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refreshNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            visible: !!root.record
            width: parent.width
            title: "OpenDota"
            meta: root.heroMeta()
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display

                Image {
                  id: heroMarkImage
                  anchors.fill: parent
                  source: root.logoSource()
                  sourceSize.width: Style.font.display * 2
                  sourceSize.height: Style.font.display * 2
                  fillMode: Image.PreserveAspectFit
                }

                Text {
                  anchors.centerIn: parent
                  visible: heroMarkImage.status !== Image.Ready
                  text: button.text
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }
          }

          Text {
            visible: text !== ""
            width: parent.width
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          BorderSurface {
            visible: root.dataStatus === "private"
            width: parent.width
            implicitHeight: privateText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: privateText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: "Steam match history is private. Enable 'Expose Public Match Data' in Dota 2 settings (under Social) and wait ~5 minutes for OpenDota to refresh."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator {
            visible: modesSection.visible
            foreground: root.foreground
          }

          Column {
            id: modesSection
            visible: root.modesHaveData()
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: "MODES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: [
                { id: "turbo",    data: root.modes ? root.modes.turbo    : null },
                { id: "ranked",   data: root.modes ? root.modes.ranked   : null },
                { id: "unranked", data: root.modes ? root.modes.unranked : null }
              ]

              ModeRow {
                required property var modelData
                width: modesSection.width
                modeId: modelData.id
                modeData: modelData.data
                ratio: modelData.data && modelData.data.games
                  ? modelData.data.games / root.modeMaxGames() : 0
              }
            }
          }

          PanelSeparator {
            visible: streakSection.visible
            foreground: root.foreground
          }

          Column {
            id: streakSection
            visible: root.streak && root.streak.kind !== "none"
              && Number(root.streak.current || 0) > 0
            width: parent.width
            spacing: Style.spacing.sm

            PanelSectionHeader {
              width: parent.width
              text: "STREAK"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            StreakRow {
              width: streakSection.width
              streak: root.streak
            }
          }

          PanelSeparator {
            visible: recentSection.visible
            foreground: root.foreground
          }

          Column {
            id: recentSection
            visible: root.recentSliced.length > 0
            width: parent.width
            spacing: Style.spacing.xs

            PanelSectionHeader {
              width: parent.width
              text: "RECENT TURBO"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.recentSliced

              MatchRow {
                required property var modelData
                width: recentSection.width
                match: modelData
                startedAtMs: Number(modelData.startedAt || 0) * 1000
              }
            }
          }

          PanelSeparator {
            visible: heroesSection.visible
            foreground: root.foreground
          }

          Column {
            id: heroesSection
            visible: root.topHeroesSliced.length > 0
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: "TOP TURBO HEROES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.topHeroesSliced

              HeroRow {
                required property var modelData
                width: heroesSection.width
                hero: modelData
                share: Number(modelData.games || 0) / root.topHeroesPeak()
              }
            }
          }

          Text {
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  component ModeRow: Item {
    id: modeRow
    property string modeId: ""
    property var modeData: null
    property real ratio: 0

    readonly property int games: modeData ? Number(modeData.games || 0) : 0
    readonly property int wins: modeData ? Number(modeData.win || 0) : 0
    readonly property int losses: modeData ? Number(modeData.lose || 0) : 0
    readonly property real winRate: modeData ? Number(modeData.winRate || 0) : 0
    readonly property bool isPrimary: modeId === "turbo"
    readonly property bool hasGames: games > 0

    implicitHeight: Math.max(modeName.implicitHeight, modeValue.implicitHeight) + Style.spacing.sm

    Text {
      id: modeName
      text: usage.modeLabel(modeRow.modeId)
      color: modeRow.isPrimary ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: modeRow.isPrimary
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(72)
    }

    Item {
      id: modeTrackHost
      anchors.left: modeName.right
      anchors.right: modeValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: modeRow.implicitHeight

      Rectangle {
        id: modeTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
        radius: height / 2
        color: root.track
      }

      Rectangle {
        anchors.left: modeTrack.left
        anchors.verticalCenter: modeTrack.verticalCenter
        height: modeTrack.height
        radius: modeTrack.radius
        width: modeTrack.width * root.clamp(modeRow.ratio, 0, 1)
        color: modeRow.isPrimary ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: modeValue
      text: modeRow.hasGames
        ? modeRow.wins + "W-" + modeRow.losses + "L  " + root.formatWinRate(modeRow.winRate)
        : "—"
      color: modeRow.isPrimary ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(110)
    }
  }

  component StreakRow: Item {
    id: streakRow
    property var streak: ({ current: 0, kind: "none" })

    readonly property int current: Number(streak ? streak.current || 0 : 0)
    readonly property string kind: streak ? String(streak.kind || "none") : "none"
    readonly property bool isWin: kind === "win"
    readonly property bool isLose: kind === "lose"
    readonly property color accent: isWin ? root.foreground : (isLose ? root.urgent : root.dim)

    implicitHeight: streakText.implicitHeight + Style.spacing.md

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(streakRow.accent, 0.10)
    }

    Text {
      id: streakText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      text: streakRow.isWin
        ? streakRow.current + "-win streak"
        : (streakRow.isLose ? streakRow.current + "-loss streak" : "")
      color: streakRow.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
    }
  }

  component MatchRow: Item {
    id: matchRow
    property var match: null
    property double startedAtMs: 0

    readonly property bool won: match && match.won === true
    readonly property string heroName: match
      ? String(match.heroName || usage.friendlyHeroName(match.heroId) || "Hero")
      : "Hero"
    readonly property string kda: match
      ? usage.formatKda(match.kills, match.deaths, match.assists)
      : "0"
    readonly property string duration: match
      ? usage.formatDuration(match.duration)
      : "00:00"
    readonly property string ago: startedAtMs > 0 ? usage.relativeTime(startedAtMs) : ""

    implicitHeight: Math.max(heroText.implicitHeight, kdaText.implicitHeight, resultText.implicitHeight)
      + Style.spacing.sm

    Rectangle {
      id: resultPill
      width: Style.space(28)
      height: Style.space(18)
      radius: height / 2
      color: matchRow.won
        ? root.alpha(root.foreground, 0.18)
        : root.alpha(root.urgent, 0.18)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter

      Text {
        id: resultText
        anchors.centerIn: parent
        text: matchRow.won ? "W" : "L"
        color: matchRow.won ? root.foreground : root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Text {
      id: heroText
      anchors.left: resultPill.right
      anchors.leftMargin: Style.space(8)
      anchors.right: kdaText.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: matchRow.heroName
      color: matchRow.won ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Text {
      id: kdaText
      anchors.right: durationText.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: matchRow.kda
      color: matchRow.won ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      width: Style.space(36)
      horizontalAlignment: Text.AlignRight
    }

    Text {
      id: durationText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: matchRow.duration + (matchRow.ago !== "" ? "  " + matchRow.ago : "")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: matchHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: matchHover.containsMouse
      text: root.matchTooltip(matchRow.match)
      fontFamily: root.fontFamily
    }
  }

  component HeroRow: Item {
    id: heroRow
    property var hero: null
    property real share: 0

    readonly property string name: hero ? String(hero.name || "Hero") : ""
    readonly property int games: hero ? Number(hero.games || 0) : 0
    readonly property int wins: hero ? Number(hero.win || 0) : 0

    implicitHeight: heroNameText.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(heroRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: heroNameText
      text: heroRow.name
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: heroGamesText.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: heroGamesText
      text: heroRow.games > 0
        ? heroRow.games + " games  ·  " + heroRow.wins + "W"
        : "—"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: heroHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: heroHover.containsMouse
      text: root.heroTooltip(heroRow.hero)
      fontFamily: root.fontFamily
    }
  }
}
