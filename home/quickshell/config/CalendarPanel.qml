import Quickshell
import QtQuick

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null

    readonly property color panelColor: "#000000"
    readonly property color foregroundColor: "#ffffff"
    readonly property color mutedColor: "#b8b8b8"
    readonly property color borderColor: "#ffffff"
    readonly property color separatorColor: "#303030"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    readonly property var weekdayNames: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    readonly property var weekdayNamesLong: [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
    ]

    property int displayedYear: calendarClock.date.getFullYear()
    property int displayedMonth: calendarClock.date.getMonth()
    property var selectedDate: new Date(
        calendarClock.date.getFullYear(),
        calendarClock.date.getMonth(),
        calendarClock.date.getDate()
    )

    readonly property string todayKey: dateKey(
        calendarClock.date.getFullYear(),
        calendarClock.date.getMonth(),
        calendarClock.date.getDate()
    )
    readonly property string selectedDateKey: dateKey(
        selectedDate.getFullYear(),
        selectedDate.getMonth(),
        selectedDate.getDate()
    )
    readonly property var calendarDays: buildCalendarDays(displayedYear, displayedMonth)

    width: 310
    height: 310
    color: "transparent"
    visible: false

    // Native popup grab: dismiss automatically on outside click and release focus on close.
    anchor.window: root.anchorWindow
    anchor.rect.x: root.panelLeft
    anchor.rect.y: root.anchorWindow ? root.anchorWindow.height + 8 : 34
    grabFocus: true

    readonly property int panelLeft: {
        if (!root.anchorItem || !root.anchorWindow)
            return 8;

        const point = root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0);
        const minimumX = root.anchorWindow.width >= root.width + 16 ? 8 : 0;
        const maximumX = Math.max(minimumX, root.anchorWindow.width - root.width - minimumX);
        return Math.max(minimumX, Math.min(
            point.x + root.anchorItem.width / 2 - root.width / 2,
            maximumX
        ));
    }

    SystemClock {
        id: calendarClock
        precision: SystemClock.Minutes
    }

    function twoDigits(value) {
        return value < 10 ? "0" + value : String(value);
    }

    function dateKey(year, month, day) {
        return String(year) + "-" + twoDigits(month + 1) + "-" + twoDigits(day);
    }

    function formatTime(date) {
        return twoDigits(date.getHours()) + ":" + twoDigits(date.getMinutes());
    }

    function formatFullDate(date) {
        return weekdayNamesLong[date.getDay()] + ", "
            + monthNames[date.getMonth()] + " "
            + date.getDate() + ", " + date.getFullYear();
    }

    function buildCalendarDays(year, month) {
        const firstOfMonth = new Date(year, month, 1);
        const mondayFirstOffset = (firstOfMonth.getDay() + 6) % 7;
        const days = [];

        // A fixed six-week grid keeps the panel height stable for every month.
        for (let index = 0; index < 42; index++) {
            const date = new Date(year, month, 1 - mondayFirstOffset + index);
            days.push({
                year: date.getFullYear(),
                month: date.getMonth(),
                day: date.getDate(),
                key: dateKey(date.getFullYear(), date.getMonth(), date.getDate()),
                currentMonth: date.getFullYear() === year && date.getMonth() === month
            });
        }

        return days;
    }

    function setDisplayedMonth(year, month) {
        const normalizedMonth = new Date(year, month, 1);
        displayedYear = normalizedMonth.getFullYear();
        displayedMonth = normalizedMonth.getMonth();
    }

    function changeMonth(offset) {
        setDisplayedMonth(displayedYear, displayedMonth + offset);
    }

    function selectDay(year, month, day) {
        selectedDate = new Date(year, month, day);
        if (year !== displayedYear || month !== displayedMonth)
            setDisplayedMonth(year, month);
    }

    function goToToday() {
        const now = calendarClock.date;
        setDisplayedMonth(now.getFullYear(), now.getMonth());
        selectedDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    }

    function openPanel() {
        // Each opening starts on the current local month and selects today's date.
        goToToday();
        visible = true;
    }

    function closePanel() {
        visible = false;
    }

    function togglePanel() {
        if (visible)
            closePanel();
        else
            openPanel();
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: root.closePanel()
    }

    Rectangle {
        id: outerBorder
        focus: root.visible
        anchors.fill: parent
        color: root.panelColor
        radius: 0
        border.width: 1
        border.color: root.borderColor

        Column {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 7

            Item {
                id: dateHeader
                width: parent.width
                height: 30

                Text {
                    id: timeLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatTime(calendarClock.date)
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    anchors.left: timeLabel.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatFullDate(calendarClock.date)
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: root.separatorColor
            }

            Row {
                id: monthNavigation
                width: parent.width
                height: 27
                spacing: 5

                Rectangle {
                    width: 26
                    height: parent.height
                    radius: 0
                    color: previousMouse.containsMouse ? "#1c1c1c" : "#0c0c0c"
                    border.width: 1
                    border.color: "#373737"

                    Text {
                        anchors.centerIn: parent
                        text: "<"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: previousMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.changeMonth(-1)
                    }
                }

                Item {
                    width: parent.width - 26 - 26 - 48 - (parent.spacing * 3)
                    height: parent.height

                    Text {
                        anchors.centerIn: parent
                        text: root.monthNames[root.displayedMonth].toUpperCase() + " " + root.displayedYear
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: 26
                    height: parent.height
                    radius: 0
                    color: nextMouse.containsMouse ? "#1c1c1c" : "#0c0c0c"
                    border.width: 1
                    border.color: "#373737"

                    Text {
                        anchors.centerIn: parent
                        text: ">"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.changeMonth(1)
                    }
                }

                Rectangle {
                    width: 48
                    height: parent.height
                    radius: 0
                    color: todayMouse.containsMouse ? "#1c1c1c" : "#0c0c0c"
                    border.width: 1
                    border.color: "#373737"

                    Text {
                        anchors.centerIn: parent
                        text: "TODAY"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 8
                        font.bold: true
                    }

                    MouseArea {
                        id: todayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.goToToday()
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: root.separatorColor
            }

            Row {
                id: weekdayHeader
                width: parent.width
                height: 16
                spacing: 2

                Repeater {
                    model: root.weekdayNames

                    delegate: Item {
                        required property string modelData
                        width: (weekdayHeader.width - (weekdayHeader.spacing * 6)) / 7
                        height: weekdayHeader.height

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 8
                            font.bold: true
                        }
                    }
                }
            }

            Grid {
                id: dayGrid
                width: parent.width
                height: (6 * 27) + (5 * 2)
                columns: 7
                rowSpacing: 2
                columnSpacing: 2

                Repeater {
                    model: root.calendarDays

                    delegate: Item {
                        id: dayCell
                        required property var modelData

                        width: (dayGrid.width - (dayGrid.columnSpacing * 6)) / 7
                        height: 27

                        readonly property bool isToday: modelData.key === root.todayKey
                        readonly property bool isSelected: modelData.key === root.selectedDateKey

                        Rectangle {
                            anchors.fill: parent
                            radius: 0
                            color: dayCell.isSelected
                                ? "#ffffff"
                                : (dayMouse.containsMouse ? "#111111" : "#000000")
                            border.width: dayCell.isToday && !dayCell.isSelected ? 1 : 0
                            border.color: root.borderColor
                        }

                        Text {
                            anchors.centerIn: parent
                            text: String(dayCell.modelData.day)
                            color: dayCell.isSelected
                                ? "#000000"
                                : (dayCell.modelData.currentMonth ? root.foregroundColor : "#626262")
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            font.bold: dayCell.isSelected || dayCell.isToday
                        }

                        Rectangle {
                            visible: dayCell.isToday && dayCell.isSelected
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 9
                            height: 1
                            color: "#000000"
                        }

                        MouseArea {
                            id: dayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectDay(
                                dayCell.modelData.year,
                                dayCell.modelData.month,
                                dayCell.modelData.day
                            )
                        }
                    }
                }
            }
        }
    }
}
