import Quickshell
import Quickshell.Io
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
    readonly property string fontFamily: "JetBrainsMono Nerd Font ExtraLight"
    readonly property string weatherLocation: "MEDIANEIRA, PR"
    property var weatherByDate: ({})
    property string weatherStatus: "Carregando previsão"
    property string currentWeather: ""

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
    readonly property var selectedForecast: weatherByDate[selectedDateKey]
    readonly property var selectedHours: selectedForecast ? selectedForecast.hours : []

    width: 310
    height: selectedForecast ? 565 : 450
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

    // Open-Meteo provides current conditions and an eight-day local forecast.
    Process {
        id: weatherProcess
        command: ["curl", "-fsS", "--max-time", "12",
            "https://api.open-meteo.com/v1/forecast?latitude=-25.2953&longitude=-54.0939&current=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&hourly=temperature_2m,precipitation_probability,wind_speed_10m&forecast_days=8&timezone=America%2FSao_Paulo"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text);
                    const daily = data.daily;
                    const forecast = {};
                    const hourly = data.hourly;
                    for (let i = 0; i < daily.time.length; i++) {
                        forecast[daily.time[i]] = {
                            code: daily.weather_code[i],
                            high: Math.round(daily.temperature_2m_max[i]),
                            low: Math.round(daily.temperature_2m_min[i]),
                            hours: []
                        };
                    }
                    for (let i = 0; i < hourly.time.length; i++) {
                        const key = hourly.time[i].slice(0, 10);
                        if (forecast[key]) {
                            forecast[key].hours.push({
                                time: hourly.time[i].slice(11, 16),
                                temperature: Math.round(hourly.temperature_2m[i]),
                                rain: hourly.precipitation_probability[i],
                                wind: Math.round(hourly.wind_speed_10m[i])
                            });
                        }
                    }
                    root.weatherByDate = forecast;
                    root.currentWeather = root.weatherSymbol(data.current.weather_code)
                        + " " + Math.round(data.current.temperature_2m) + "°";
                    root.weatherStatus = "Updated at " + root.formatTime(calendarClock.date);
                } catch (error) {
                    root.weatherStatus = "Forecast unavailable";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0 && Object.keys(root.weatherByDate).length === 0)
                    root.weatherStatus = "No connection to forecast";
            }
        }
    }

    Timer {
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        onTriggered: if (!weatherProcess.running) weatherProcess.running = true
    }

    function weatherSymbol(code) {
        if (code === 0) return "☀";
        if (code === 1 || code === 2) return "◐";
        if (code === 3) return "☁";
        if (code === 45 || code === 48) return "≋";
        if (code >= 51 && code <= 67) return "☂";
        if (code >= 71 && code <= 77) return "❄";
        if (code >= 80 && code <= 82) return "☂";
        if (code >= 95) return "⚡";
        return "·";
    }

    function updateWeatherChart() {
        weatherChart.requestPaint();
    }

    onSelectedDateKeyChanged: updateWeatherChart()
    onWeatherByDateChanged: updateWeatherChart()

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
            spacing: 6

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
                    font.pixelSize: 12
                    font.bold: false
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
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }

            Item {
                width: parent.width
                height: 36
                Column {
                    anchors.fill: parent
                    spacing: 1
                    Text {
                        text: root.weatherLocation
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                    }
                    Text {
                        text: root.selectedForecast
                            ? root.weatherSymbol(root.selectedForecast.code) + "   HIGH " + root.selectedForecast.high + "°   LOW " + root.selectedForecast.low + "°"
                            : (root.selectedDateKey === root.todayKey && root.currentWeather.length
                                ? "NOW  " + root.currentWeather
                                : "NO FORECAST FOR THIS DAY")
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                    }
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
                        font.pixelSize: 12
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
                        font.pixelSize: 12
                        font.bold: false
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
                        font.pixelSize: 12
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
                        font.pixelSize: 9
                        font.bold: false
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
                            font.pixelSize: 9
                            font.bold: false
                        }
                    }
                }
            }

            Grid {
                id: dayGrid
                width: parent.width
                height: (6 * 40) + (5 * 2)
                columns: 7
                rowSpacing: 2
                columnSpacing: 2

                Repeater {
                    model: root.calendarDays

                    delegate: Item {
                        id: dayCell
                        required property var modelData

                        width: (dayGrid.width - (dayGrid.columnSpacing * 6)) / 7
                        height: 40

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
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.leftMargin: 4
                            anchors.topMargin: 2
                            text: String(dayCell.modelData.day)
                            color: dayCell.isSelected
                                ? "#000000"
                                : (dayCell.modelData.currentMonth ? root.foregroundColor : "#626262")
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.bold: false
                        }

                        Text {
                            readonly property var forecast: root.weatherByDate[dayCell.modelData.key]
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 14
                            text: forecast ? root.weatherSymbol(forecast.code) : ""
                            color: dayCell.isSelected ? "#000000" : root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 15
                        }

                        Text {
                            readonly property var forecast: root.weatherByDate[dayCell.modelData.key]
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            text: forecast ? forecast.high + "° " + forecast.low + "°" : ""
                            color: dayCell.isSelected ? "#000000" : (dayCell.modelData.currentMonth ? root.foregroundColor : "#626262")
                            font.family: root.fontFamily
                            font.pixelSize: 9
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

            Rectangle {
                visible: !!root.selectedForecast
                width: parent.width
                height: 1
                color: root.separatorColor
            }

            Column {
                visible: !!root.selectedForecast
                width: parent.width
                spacing: 4

                Text {
                    width: parent.width
                    text: root.formatFullDate(root.selectedDate) + "  ·  "
                        + root.weatherSymbol(root.selectedForecast ? root.selectedForecast.code : 0)
                        + "  " + (root.selectedForecast ? root.selectedForecast.low : 0) + "°–"
                        + (root.selectedForecast ? root.selectedForecast.high : 0) + "°"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Canvas {
                    id: weatherChart
                    width: parent.width
                    height: 88

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        const hours = root.selectedHours;
                        if (!hours || hours.length === 0)
                            return;

                        const left = 18;
                        const right = width - 18;
                        const top = 16;
                        const bottom = height - 18;
                        const values = hours.map(function(item) { return item.temperature; });
                        const minValue = Math.min.apply(null, values) - 2;
                        const maxValue = Math.max.apply(null, values) + 2;
                        const xAt = function(index) {
                            return left + (right - left) * index / Math.max(1, hours.length - 1);
                        };
                        const yAt = function(value) {
                            return bottom - (value - minValue) / Math.max(1, maxValue - minValue) * (bottom - top);
                        };

                        ctx.strokeStyle = "#303030";
                        ctx.lineWidth = 1;
                        for (let line = 0; line < 3; line++) {
                            const y = top + (bottom - top) * line / 2;
                            ctx.beginPath();
                            ctx.moveTo(left, y);
                            ctx.lineTo(right, y);
                            ctx.stroke();
                        }

                        ctx.beginPath();
                        for (let i = 0; i < hours.length; i++) {
                            if (i === 0) ctx.moveTo(xAt(i), yAt(values[i]));
                            else ctx.lineTo(xAt(i), yAt(values[i]));
                        }
                        ctx.strokeStyle = "#ffffff";
                        ctx.lineWidth = 2;
                        ctx.stroke();

                        ctx.fillStyle = "#ffffff";
                        ctx.font = "9px JetBrainsMono Nerd Font ExtraLight";
                        ctx.textAlign = "center";
                        const labelStep = Math.max(1, Math.floor((hours.length - 1) / 5));
                        for (let i = 0; i < hours.length; i += labelStep) {
                            const x = xAt(i);
                            const y = yAt(values[i]);
                            ctx.beginPath();
                            ctx.arc(x, y, 2.5, 0, Math.PI * 2);
                            ctx.fill();
                            ctx.fillText(values[i] + "°", x, Math.max(10, y - 6));
                            ctx.fillStyle = "#b8b8b8";
                            ctx.fillText(hours[i].time.slice(0, 5), x, height - 3);
                            ctx.fillStyle = "#ffffff";
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: {
                        const hours = root.selectedHours || [];
                        if (hours.length === 0) return "Hourly details unavailable";
                        const rain = Math.max.apply(null, hours.map(function(item) { return item.rain; }));
                        const wind = Math.round(hours.reduce(function(total, item) { return total + item.wind; }, 0) / hours.length);
                        return "Rain up to " + rain + "%   ·   Wind " + wind + " km/h";
                    }
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 9
                }
            }
        }
    }
}
