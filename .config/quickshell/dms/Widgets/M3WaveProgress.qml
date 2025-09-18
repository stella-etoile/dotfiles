import QtQuick
import QtQuick.Shapes
import qs.Common

Item {
    id: root

    property real value: 0
    property real lineWidth: 2
    property real wavelength: 20
    property real amp: 1.6
    property real phase: 0.0
    property bool isPlaying: false
    property real currentAmp: 1.6
    property int samples: Math.max(48, Math.round(width / 3))
    property color trackColor: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.40)
    property color fillColor: Theme.primary
    property color playheadColor: Theme.primary

    property real dpr: (root.window ? root.window.devicePixelRatio : 1)
    function snap(v) { return Math.round(v * dpr) / dpr }

    readonly property real playX: snap(root.width * root.value)
    readonly property real midY: snap(height / 2)
    readonly property real capPad: Math.ceil(lineWidth / 2)

    function yWave(x) {
        return midY + currentAmp * Math.sin((x / wavelength) * 2 * Math.PI + phase)
    }

    Behavior on currentAmp {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    onIsPlayingChanged: {
        currentAmp = isPlaying ? amp : 0
    }

    Shape {
        id: flatTrack
        anchors.fill: parent
        antialiasing: true
        asynchronous: false
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: true
        layer.smooth: true
        layer.samples: 8
        layer.textureSize: Qt.size(Math.ceil(width * dpr * 2), Math.ceil(height * dpr * 2))

        ShapePath {
            id: flatPath
            strokeColor: root.trackColor
            strokeWidth: snap(root.lineWidth)
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            fillColor: "transparent"

            PathMove {
                id: flatStart
                x: 0
                y: root.midY
            }

            PathLine {
                id: flatEnd
                x: root.width
                y: root.midY
            }
        }
    }

    Item {
        id: waveContainer
        anchors.fill: parent
        clip: true
        width: Math.max(0, Math.min(parent.width, root.playX))

        Shape {
            id: waveShape
            anchors.fill: parent
            antialiasing: true
            asynchronous: false
            preferredRendererType: Shape.CurveRenderer
            layer.enabled: true
            layer.smooth: true
            layer.samples: 8
            layer.textureSize: Qt.size(Math.ceil(width * dpr * 2), Math.ceil(height * dpr * 2))

        ShapePath {
            id: wavePath
            strokeColor: root.fillColor
            strokeWidth: snap(root.lineWidth)
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            fillColor: "transparent"
        }
        }
    }

    property var cubics: []
    property real startY: root.midY + root.currentAmp * Math.sin(root.phase)
    property real endY: root.midY + root.currentAmp * Math.sin((root.playX / root.wavelength) * 2 * Math.PI + root.phase)

    Component {
        id: moveComp
        PathMove {}
    }

    Component {
        id: cubicComp
        PathCubic {}
    }

    function buildWave() {
        wavePath.pathElements = []
        cubics = []
        wavePath.pathElements.push(moveComp.createObject(wavePath))
        for (let i = 0; i < samples - 1; ++i) {
            const cubic = cubicComp.createObject(wavePath)
            wavePath.pathElements.push(cubic)
            cubics.push(cubic)
        }
        updateWave()
    }

    function updateWave() {
        if (cubics.length === 0) return
        const step = root.width / (samples - 1)
        const startX = snap(root.lineWidth / 2)
        const r = root.lineWidth / 2
        const aaBias = 0.25 / dpr

        function y(x) { return yWave(x) }
        function dy(x) {
            return currentAmp * (2 * Math.PI / wavelength) * Math.cos((x / wavelength) * 2 * Math.PI + phase)
        }

        const m = wavePath.pathElements[0]
        m.x = startX
        m.y = y(startX)

        for (let i = 0; i < cubics.length; ++i) {
            const x0 = startX + i * step
            const x1 = startX + (i + 1) * step
            
            // Stop exactly at playX
            if (x0 >= root.playX) {
                // This segment is entirely past the playhead - collapse it
                const seg = cubics[i]
                seg.control1X = seg.control2X = seg.x = root.playX
                const py = y(root.playX)
                seg.control1Y = seg.control2Y = seg.y = py
                continue
            }
            
            const xe = Math.min(x1, root.playX - r - aaBias)
            const p0x = x0, p0y = y(x0)
            const p1x = xe, p1y = y(xe)
            const dx = xe - x0
            
            if (dx <= 0) {
                // Zero-length segment
                const seg = cubics[i]
                seg.control1X = seg.control2X = seg.x = root.playX
                const py = y(root.playX)
                seg.control1Y = seg.control2Y = seg.y = py
                continue
            }

            const c1x = p0x + dx / 4
            const c1y = p0y + (dx * dy(x0)) / 4
            const c2x = p1x - dx / 4
            const c2y = p1y - (dx * dy(xe)) / 4

            const seg = cubics[i]
            seg.control1X = c1x
            seg.control1Y = c1y
            seg.control2X = c2x
            seg.control2Y = c2y
            seg.x = p1x
            seg.y = p1y
        }

        flatStart.x = 0
        flatStart.y = midY
        flatEnd.x = width
        flatEnd.y = midY
    }


    Rectangle {
        id: playhead
        width: 3.5
        height: Math.max(root.lineWidth + 12, 16)
        radius: width / 2
        color: root.playheadColor
        x: root.playX - width / 2
        y: root.midY - height / 2
        z: 3

        Behavior on x {
            NumberAnimation {
                duration: 80
            }
        }
    }

    FrameAnimation {
        running: root.visible && (root.isPlaying || root.currentAmp > 0)
        onTriggered: {
            if (root.isPlaying) {
                root.phase += 0.03 * frameTime * 60
            }
            root.updateWave()
        }
    }

    Component.onCompleted: {
        currentAmp = isPlaying ? amp : 0
        buildWave()
    }
    onWidthChanged: buildWave()
    onSamplesChanged: buildWave()
    onCurrentAmpChanged: updateWave()
}