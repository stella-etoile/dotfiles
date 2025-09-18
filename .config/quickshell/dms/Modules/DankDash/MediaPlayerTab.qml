import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property MprisPlayer activePlayer: MprisController.activePlayer
    property var allPlayers: MprisController.availablePlayers


    property var defaultSink: AudioService.sink

    // Palette that stays stable across track switches until new colors are ready
    property color dom: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 1.0)
    property color acc: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.25)
    property color _nextDom: dom
    property color _nextAcc: acc

    // Track-switch hold (prevents banner flicker only during switches)
    property bool isSwitching: false
    property bool paletteReady: false
    property string _lastArtUrl: ""
    property url _cqSource: ""

    // Derived "no players" state: always correct, no timers.
    readonly property int _playerCount: allPlayers ? allPlayers.length : 0
    readonly property bool _noneAvailable: _playerCount === 0
    readonly property bool _trulyIdle: activePlayer
          && activePlayer.playbackState === MprisPlaybackState.Stopped
          && !activePlayer.trackTitle && !activePlayer.trackArtist
    readonly property bool showNoPlayerNow: (!_switchHold) && (_noneAvailable || _trulyIdle)

    // Short hold only during track switches (not when players disappear)
    property bool _switchHold: false
    Timer {
      id: _switchHoldTimer
      interval: 650
      repeat: false
      onTriggered: _switchHold = false
    }

    onActivePlayerChanged: {
        isSwitching = true
        _switchHold = true
        paletteReady = false
        _switchHoldTimer.restart()
        if (activePlayer && activePlayer.trackArtUrl)
            _preloadImage.source = activePlayer.trackArtUrl
    }

    function maybeFinishSwitch() {
        if (activePlayer && activePlayer.trackTitle !== "" && paletteReady) {
            isSwitching = false
            _switchHold = false
        }
    }

    readonly property real ratio: {
        if (!activePlayer || !activePlayer.length || activePlayer.length <= 0) {
            return 0
        }
        const calculatedRatio = (activePlayer.position || 0) / activePlayer.length
        return Math.max(0, Math.min(1, calculatedRatio))
    }

    implicitWidth: 700
    implicitHeight: 410

    Connections {
        target: activePlayer
        function onTrackTitleChanged() {
            _switchHoldTimer.restart()
            maybeFinishSwitch()
        }
        function onTrackArtUrlChanged() {
            if (activePlayer?.trackArtUrl) {
                _lastArtUrl = activePlayer.trackArtUrl
                _preloadImage.source = activePlayer.trackArtUrl
            }
        }
    }

    Connections {
        target: MprisController
        function onAvailablePlayersChanged() {
            const count = (MprisController.availablePlayers?.length || 0)
            if (count === 0) {
                isSwitching = false
                _switchHold = false
            } else {
                _switchHold = true
                _switchHoldTimer.restart()
            }
        }
    }

    function getAudioDeviceIcon(device) {
        if (!device || !device.name) return "speaker"
        
        const name = device.name.toLowerCase()
        
        if (name.includes("bluez") || name.includes("bluetooth"))
            return "headset"
        if (name.includes("hdmi"))
            return "tv"
        if (name.includes("usb"))
            return "headset"
        if (name.includes("analog") || name.includes("built-in"))
            return "speaker"
        
        return "speaker"
    }
    
    function getVolumeIcon(sink) {
        if (!sink || !sink.audio) return "volume_off"

        const volume = sink.audio.volume
        const muted = sink.audio.muted

        if (muted || volume === 0.0) return "volume_off"
        if (volume <= 0.33) return "volume_down"
        if (volume <= 0.66) return "volume_up"
        return "volume_up"
    }

    function adjustVolume(step) {
        if (!defaultSink?.audio) return

        const currentVolume = Math.round(defaultSink.audio.volume * 100)
        const newVolume = Math.min(100, Math.max(0, currentVolume + step))

        defaultSink.audio.volume = newVolume / 100
        if (newVolume > 0 && defaultSink.audio.muted) {
            defaultSink.audio.muted = false
        }
    }

    Image {
        id: _preloadImage
        source: ""
        asynchronous: true
        cache: true
        visible: false
        onStatusChanged: {
            if (status === Image.Ready) {
                _cqSource = source
                colorQuantizer.source = _cqSource
            }
            else if (status === Image.Error) {
                _cqSource = ""
            }
        }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: _cqSource !== "" ? _cqSource : undefined
        depth: 8
        rescaleSize: 32
        onColorsChanged: {
            if (!colors || colors.length === 0) return

            function enhanceColor(color) {
                const satBoost = 1.4
                const valueBoost = 1.2
                return Qt.hsva(color.hsvHue, Math.min(1, color.hsvSaturation * satBoost), Math.min(1, color.hsvValue * valueBoost), color.a)
            }

            function getExtremeColor(startIdx, direction = 1) {
                let bestColor = colors[startIdx]
                let bestScore = 0

                for (let i = startIdx; i >= 0 && i < colors.length; i += direction) {
                    const c = colors[i]
                    const saturation = c.hsvSaturation
                    const brightness = c.hsvValue
                    const contrast = Math.abs(brightness - 0.5) * 2
                    const score = saturation * 0.7 + contrast * 0.3

                    if (score > bestScore) {
                        bestScore = score
                        bestColor = c
                    }
                }

                return enhanceColor(bestColor)
            }

            _pendingDom = getExtremeColor(Math.floor(colors.length * 0.2), 1)
            _pendingAcc = getExtremeColor(Math.floor(colors.length * 0.8), -1)
            paletteApplyDelay.restart()
        }
    }

    property color _pendingDom: dom
    property color _pendingAcc: acc
    Timer {
        id: paletteApplyDelay
        interval: 90
        repeat: false
        onTriggered: {
            const dist = (c1, c2) => {
                const dr = c1.r - c2.r, dg = c1.g - c2.g, db = c1.b - c2.b
                return Math.sqrt(dr*dr + dg*dg + db*db)
            }
            const domChanged = dist(_pendingDom, dom) > 0.02
            const accChanged = dist(_pendingAcc, acc) > 0.02
            if (domChanged || accChanged) {
                dom = _pendingDom
                acc = _pendingAcc
            }
            paletteReady = true
            maybeFinishSwitch()
        }
    }
    
    

    property bool isSeeking: false


    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        opacity: 1.0
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(dom.r, dom.g, dom.b, paletteReady ? 0.38 : 0.06)
            }
            GradientStop {
                position: 0.3
                color: Qt.rgba(acc.r, acc.g, acc.b, paletteReady ? 0.28 : 0.05)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, paletteReady ? 0.92 : 0.985)
            }
        }
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    Behavior on dom { ColorAnimation { duration: 220; easing.type: Easing.InOutQuad } }
    Behavior on acc { ColorAnimation { duration: 220; easing.type: Easing.InOutQuad } }

    Column {
        anchors.centerIn: parent
        spacing: Theme.spacingM
        visible: showNoPlayerNow

        DankIcon {
            name: "music_note"
            size: Theme.iconSize * 3
            color: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.5)
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text: "No Active Players"
            font.pixelSize: Theme.fontSizeLarge
            color: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.7)
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Item {
        anchors.fill: parent
        clip: false
        visible: !_noneAvailable && (!showNoPlayerNow)

        MouseArea {
            anchors.fill: parent
            enabled: audioDevicesButton.devicesExpanded || volumeButton.volumeExpanded || playerSelectorButton.playersExpanded
            onClicked: function(mouse) {
                const clickOutside = (item) => {
                    return mouse.x < item.x || mouse.x > item.x + item.width ||
                           mouse.y < item.y || mouse.y > item.y + item.height
                }
                
                if (playerSelectorButton.playersExpanded && clickOutside(playerSelectorDropdown)) {
                    playerSelectorButton.playersExpanded = false
                }
                if (audioDevicesButton.devicesExpanded && clickOutside(audioDevicesDropdown)) {
                    audioDevicesButton.devicesExpanded = false
                }
                if (volumeButton.volumeExpanded && clickOutside(volumeSliderPanel) && clickOutside(volumeButton)) {
                    volumeButton.volumeExpanded = false
                }
            }
        }

        Rectangle {
            id: audioDevicesDropdown
            width: 280 
            height: audioDevicesButton.devicesExpanded ? Math.max(200, Math.min(280, audioDevicesDropdown.availableDevices.length * 50 + 100)) : 0
            x: parent.width + Theme.spacingS 
            y: 180  
            visible: audioDevicesButton.devicesExpanded
            clip: true
            z: 150  
            
            property var availableDevices: Pipewire.nodes.values.filter(node => {
                return node.audio && node.isSink && !node.isStream
            })
            
            color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.98)
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.6)
            border.width: 2
            radius: Theme.cornerRadius * 2
            
            opacity: audioDevicesButton.devicesExpanded ? 1 : 0
            
            // Drop shadow effect
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 8
                shadowBlur: 1.0
                shadowColor: Qt.rgba(0, 0, 0, 0.4)
                shadowOpacity: 0.7
            }
            
            Behavior on height {
                NumberAnimation {
                    duration: Anims.durShort
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Anims.emphasizedDecel
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Anims.durShort
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Anims.standard
                }
            }
            
            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                
                StyledText {
                    text: "Audio Output Devices (" + audioDevicesDropdown.availableDevices.length + ")"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    bottomPadding: Theme.spacingM
                }
                
                DankFlickable {
                    width: parent.width
                    height: parent.height - 40 
                    contentHeight: deviceColumn.height
                    clip: true
                    
                    Column {
                        id: deviceColumn
                        width: parent.width
                        spacing: Theme.spacingS
                        
                        Repeater {
                            model: audioDevicesDropdown.availableDevices
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                
                                width: parent.width
                                height: 48
                                radius: Theme.cornerRadius
                                color: deviceMouseAreaLeft.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, index % 2 === 0 ? 0.3 : 0.2)
                                border.color: modelData === AudioService.sink ? Theme.primary : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.2)
                                border.width: modelData === AudioService.sink ? 2 : 1
                                
                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingM
                                    width: parent.width - Theme.spacingM * 2
                                    
                                    DankIcon {
                                        name: getAudioDeviceIcon(modelData)
                                        size: 20
                                        color: modelData === AudioService.sink ? Theme.primary : Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 20 - Theme.spacingM * 2
                                        
                                        StyledText {
                                            text: AudioService.displayName(modelData)
                                            font.pixelSize: Theme.fontSizeMedium
                                            color: Theme.surfaceText
                                            font.weight: modelData === AudioService.sink ? Font.Medium : Font.Normal
                                            elide: Text.ElideRight
                                            width: parent.width
                                            wrapMode: Text.NoWrap
                                        }
                                        
                                        StyledText {
                                            text: modelData === AudioService.sink ? "Active" : "Available"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            elide: Text.ElideRight
                                            width: parent.width
                                            wrapMode: Text.NoWrap
                                        }
                                    }
                                }
                                
                                MouseArea {
                                    id: deviceMouseAreaLeft
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData) {
                                            Pipewire.preferredDefaultAudioSink = modelData
                                            console.log("Current default sink after change:", AudioService.sink ? AudioService.sink.name : "null")
                                        }
                                        audioDevicesButton.devicesExpanded = false
                                    }
                                }
                                
                                Behavior on color { ColorAnimation { duration: Anims.durShort } }
                                Behavior on border.color { ColorAnimation { duration: Anims.durShort } }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: playerSelectorDropdown
            width: 240
            height: playerSelectorButton.playersExpanded ? Math.max(180, Math.min(240, (root.allPlayers?.length || 0) * 50 + 80)) : 0
            x: parent.width + Theme.spacingS
            y: 180
            visible: playerSelectorButton.playersExpanded
            clip: true
            z: 150

            color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.98)
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.6)
            border.width: 2
            radius: Theme.cornerRadius * 2

            opacity: playerSelectorButton.playersExpanded ? 1 : 0

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 8
                shadowBlur: 1.0
                shadowColor: Qt.rgba(0, 0, 0, 0.4)
                shadowOpacity: 0.7
            }

            Behavior on height {
                NumberAnimation { 
                    duration: Anims.durShort
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Anims.emphasizedDecel
                }
            }

            Behavior on opacity {
                NumberAnimation { 
                    duration: Anims.durShort
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Anims.standard
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingM

                StyledText {
                    text: "Media Players (" + (allPlayers?.length || 0) + ")"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    bottomPadding: Theme.spacingM
                }

                DankFlickable {
                    width: parent.width
                    height: parent.height - 40
                    contentHeight: playerColumn.height
                    clip: true

                    Column {
                        id: playerColumn
                        width: parent.width
                        spacing: Theme.spacingS

                        Repeater {
                            model: allPlayers || []
                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                width: parent.width
                                height: 48
                                radius: Theme.cornerRadius
                                color: playerMouseArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, index % 2 === 0 ? 0.3 : 0.2)
                                border.color: modelData === activePlayer ? Theme.primary : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.2)
                                border.width: modelData === activePlayer ? 2 : 1

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingM
                                    width: parent.width - Theme.spacingM * 2

                                    DankIcon {
                                        name: "music_note"
                                        size: 20
                                        color: modelData === activePlayer ? Theme.primary : Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 20 - Theme.spacingM * 2

                                        StyledText {
                                            text: modelData && modelData.identity ? modelData.identity : "Unknown Player"
                                            font.pixelSize: Theme.fontSizeMedium
                                            color: Theme.surfaceText
                                            font.weight: modelData === activePlayer ? Font.Medium : Font.Normal
                                            elide: Text.ElideRight
                                            width: parent.width
                                            wrapMode: Text.NoWrap
                                        }

                                        StyledText {
                                            text: modelData === activePlayer ? "Active" : "Available"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            elide: Text.ElideRight
                                            width: parent.width
                                            wrapMode: Text.NoWrap
                                        }
                                    }
                                }

                                MouseArea {
                                    id: playerMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData && modelData.identity) {
                                            if (activePlayer && activePlayer !== modelData && activePlayer.canPause) {
                                                activePlayer.pause()
                                            }

                                            MprisController.activePlayer = modelData
                                        }
                                        playerSelectorButton.playersExpanded = false
                                    }
                                }

                                Behavior on color {
                                    ColorAnimation { 
                                        duration: Anims.durShort
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Anims.standard
                                    }
                                }

                                Behavior on border.color {
                                    ColorAnimation { 
                                        duration: Anims.durShort
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Anims.standard
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }      
        // Center Column: Main Media Content
        ColumnLayout {
            x: 72  
            y: 20  
            width: 484  
            height: 370  
            spacing: Theme.spacingXS  

            Item {
                width: parent.width
                height: 200

                DankAlbumArt {
                    width: Math.min(parent.width * 0.8, parent.height * 0.9)
                    height: width
                    anchors.centerIn: parent
                    activePlayer: root.activePlayer
                }
            }

            // Song Info and Controls Section
            Item {
                width: parent.width
                Layout.fillHeight: true

                Column {
                    id: songInfo
                    width: parent.width
                    spacing: Theme.spacingXS
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter

                    StyledText {
                        text: activePlayer?.trackTitle || "Unknown Track"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                    }

                    StyledText {
                        text: activePlayer?.trackArtist || "Unknown Artist"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.8)
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        wrapMode: Text.WordWrap
                        maximumLineCount: 1
                    }

                    StyledText {
                        text: activePlayer?.trackAlbum || ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.6)
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        wrapMode: Text.WordWrap
                        maximumLineCount: 1
                        visible: text.length > 0
                    }
                }

                // Controls Group
                Column {
                    id: controlsGroup
                    width: parent.width
                    spacing: Theme.spacingXS
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 0

                    DankSeekbar {
                        width: parent.width * 0.8
                        height: 20
                        anchors.horizontalCenter: parent.horizontalCenter
                        activePlayer: root.activePlayer
                        isSeeking: root.isSeeking
                        onIsSeekingChanged: root.isSeeking = isSeeking
                    }

                    Item {
                        width: parent.width * 0.8
                        height: 20
                        anchors.horizontalCenter: parent.horizontalCenter

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (!activePlayer) return "0:00"
                                const pos = Math.max(0, activePlayer.position || 0)
                                const minutes = Math.floor(pos / 60)
                                const seconds = Math.floor(pos % 60)
                                const timeStr = minutes + ":" + (seconds < 10 ? "0" : "") + seconds
                                return timeStr
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                        
                        StyledText {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (!activePlayer || !activePlayer.length) return "0:00"
                                const dur = Math.max(0, activePlayer.length || 0)  // Length is already in seconds
                                const minutes = Math.floor(dur / 60)
                                const seconds = Math.floor(dur % 60)
                                return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Item {
                        width: parent.width
                        height: 50
                        
                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingM
                            height: parent.height

                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: shuffleArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : "transparent"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: activePlayer && activePlayer.shuffleSupported

                            DankIcon {
                                anchors.centerIn: parent
                                name: "shuffle"
                                size: 20
                                color: activePlayer && activePlayer.shuffle ? Theme.primary : Theme.surfaceText
                            }

                            MouseArea {
                                id: shuffleArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (activePlayer && activePlayer.canControl && activePlayer.shuffleSupported) {
                                        activePlayer.shuffle = !activePlayer.shuffle
                                    }
                                }
                            }

                            Behavior on color {
                                ColorAnimation { 
                                    duration: Anims.durShort
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Anims.standard
                                }
                            }
                        }

                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: prevBtnArea.containsMouse ? Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.12) : "transparent"
                            anchors.verticalCenter: parent.verticalCenter

                            DankIcon {
                                anchors.centerIn: parent
                                name: "skip_previous"
                                size: 24
                                color: Theme.surfaceText
                            }

                            MouseArea {
                                id: prevBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!activePlayer) {
                                        return
                                    }

                                    if (activePlayer.position > 8 && activePlayer.canSeek) {
                                        activePlayer.position = 0
                                    } else {
                                        activePlayer.previous()
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: 50
                            height: 50
                            radius: 25
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter

                            DankIcon {
                                anchors.centerIn: parent
                                name: activePlayer && activePlayer.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow"
                                size: 28
                                color: Theme.background
                                weight: 500
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: activePlayer && activePlayer.togglePlaying()
                            }

                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowHorizontalOffset: 0
                                shadowVerticalOffset: 6
                                shadowBlur: 1.0
                                shadowColor: Qt.rgba(0, 0, 0, 0.3)
                                shadowOpacity: 0.3
                            }
                        }

                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: nextBtnArea.containsMouse ? Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.12) : "transparent"
                            anchors.verticalCenter: parent.verticalCenter

                            DankIcon {
                                anchors.centerIn: parent
                                name: "skip_next"
                                size: 24
                                color: Theme.surfaceText
                            }

                            MouseArea {
                                id: nextBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: activePlayer && activePlayer.next()
                            }
                        }

                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: repeatArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : "transparent"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: activePlayer && activePlayer.loopSupported

                            DankIcon {
                                anchors.centerIn: parent
                                name: {
                                    if (!activePlayer) return "repeat"
                                    switch(activePlayer.loopState) {
                                        case MprisLoopState.Track: return "repeat_one"
                                        case MprisLoopState.Playlist: return "repeat"
                                        default: return "repeat"
                                    }
                                }
                                size: 20
                                color: activePlayer && activePlayer.loopState !== MprisLoopState.None ? Theme.primary : Theme.surfaceText
                            }

                            MouseArea {
                                id: repeatArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (activePlayer && activePlayer.canControl && activePlayer.loopSupported) {
                                        switch(activePlayer.loopState) {
                                            case MprisLoopState.None:
                                                activePlayer.loopState = MprisLoopState.Playlist
                                                break
                                            case MprisLoopState.Playlist:
                                                activePlayer.loopState = MprisLoopState.Track
                                                break
                                            case MprisLoopState.Track:
                                                activePlayer.loopState = MprisLoopState.None
                                                break
                                        }
                                    }
                                }
                            }

                            Behavior on color {
                                ColorAnimation { 
                                    duration: Anims.durShort
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Anims.standard
                                }
                            }
                        }
                        }  
                    }      
                }         
            }            
        }                  

        Rectangle {
            id: playerSelectorButton
            width: 40
            height: 40
            radius: 20
            x: parent.width - 40 - Theme.spacingM
            y: 235
            color: playerSelectorArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.8)
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
            border.width: 1
            z: 100
            visible: (allPlayers?.length || 0) >= 1

            property bool playersExpanded: false

            DankIcon {
                anchors.centerIn: parent
                name: "assistant_device"
                size: 18
                color: Theme.surfaceText
            }

            MouseArea {
                id: playerSelectorArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    parent.playersExpanded = !parent.playersExpanded
                }
            }

        }

        Rectangle {
            id: volumeButton
            width: 40
            height: 40
            radius: 20
            x: parent.width - 40 - Theme.spacingM
            y: 180  
            color: volumeButtonArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.8)
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
            border.width: 1
            z: 100

            property bool volumeExpanded: false

            Timer {
                id: volumeHideTimer
                interval: 500
                onTriggered: volumeButton.volumeExpanded = false
            }

            DankIcon {
                anchors.centerIn: parent
                name: getVolumeIcon(defaultSink)
                size: 18
                color: defaultSink && !defaultSink.audio.muted && defaultSink.audio.volume > 0 ? Theme.primary : Theme.surfaceText
            }

            MouseArea {
                id: volumeButtonArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    volumeButton.volumeExpanded = true
                    volumeHideTimer.stop()
                }
                onExited: {
                    volumeHideTimer.restart()
                }
                onClicked: {
                    if (defaultSink?.audio) {
                        defaultSink.audio.muted = !defaultSink.audio.muted
                    }
                }
                onWheel: wheelEvent => {
                    adjustVolume(wheelEvent.angleDelta.y > 0 ? 3 : -3)
                    volumeButton.volumeExpanded = true
                    wheelEvent.accepted = true
                }
            }

        }

        Rectangle {
            id: volumeSliderPanel
            width: 60
            height: 180
            radius: Theme.cornerRadius * 2
            x: parent.width + Theme.spacingS
            y: 130
            color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.95)
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
            border.width: 1
            visible: volumeButton.volumeExpanded
            clip: true
            z: 110

            opacity: volumeButton.volumeExpanded ? 1 : 0

            Behavior on opacity {
                NumberAnimation { 
                    duration: Anims.durShort
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Anims.standard
                }
            }

            Item {
                anchors.fill: parent
                anchors.margins: Theme.spacingS

                Item {
                    width: parent.width * 0.6
                    height: parent.height - Theme.spacingXL * 2  
                    anchors.top: parent.top
                    anchors.topMargin: Theme.spacingS
                    anchors.horizontalCenter: parent.horizontalCenter
                    
                    property bool dragging: false
                    property bool containsMouse: volumeSliderArea.containsMouse
                    
                    Rectangle {
                        width: parent.width
                        height: parent.height
                        anchors.centerIn: parent
                        color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.5)
                        radius: width / 2
                    }
                    
                    Rectangle {
                        width: parent.width
                        height: defaultSink ? (Math.min(1.0, defaultSink.audio.volume) * parent.height) : 0
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Theme.primary
                        radius: width / 2

                    }
                    
                    MouseArea {
                        id: volumeSliderArea
                        anchors.fill: parent
                        anchors.margins: -12
                        enabled: defaultSink !== null
                        hoverEnabled: true
                        preventStealing: true
                        
                        onEntered: {
                            volumeHideTimer.stop()
                        }
                        
                        onExited: {
                            volumeHideTimer.restart()
                        }
                        
                        onPressed: function(mouse) {
                            parent.dragging = true
                            updateVolume(mouse)
                        }
                        
                        onReleased: {
                            parent.dragging = false
                        }
                        
                        onPositionChanged: function(mouse) {
                            if (pressed) {
                                updateVolume(mouse)
                            }
                        }
                        
                        onClicked: function(mouse) {
                            updateVolume(mouse)
                        }
                        
                        onWheel: wheel => adjustVolume(wheel.angleDelta.y > 0 ? 3 : -3)
                        
                        function updateVolume(mouse) {
                            if (defaultSink) {
                                const ratio = 1.0 - (mouse.y / height)
                                const volume = Math.max(0, Math.min(1, ratio))
                                defaultSink.audio.volume = volume
                                if (volume > 0 && defaultSink.audio.muted) {
                                    defaultSink.audio.muted = false
                                }
                            }
                        }
                    }
                }

                StyledText {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: Theme.spacingL
                    text: defaultSink ? Math.round(defaultSink.audio.volume * 100) + "%" : "0%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    font.weight: Font.Medium
                }
            }
        }

        Rectangle {
            id: audioDevicesButton
            width: 40
            height: 40
            radius: 20
            x: parent.width - 40 - Theme.spacingM
            y: 290  
            color: audioDevicesArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.8)
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
            border.width: 1
            z: 100

            property bool devicesExpanded: false

            DankIcon {
                anchors.centerIn: parent
                name: parent.devicesExpanded ? "expand_less" : "speaker"
                size: 18
                color: Theme.surfaceText
            }

            MouseArea {
                id: audioDevicesArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    parent.devicesExpanded = !parent.devicesExpanded
                }
            }

        }

    }
}