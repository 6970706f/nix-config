import Quickshell
import Quickshell.Io
import QtQuick

PopupWindow {
    id: root

    property var anchorWindow: null
    property var anchorItem: null

    readonly property string weatherLocation: "Medianeira, PR"
    property var weatherByDate: ({})
    property string weatherStatus: "Carregando previsão"
    property string currentWeather: ""
    property int currentWeatherCode: -1

    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    readonly property var weekdayNames: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
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

    width: 344 + Theme.popupPadX * 2
    height: (selectedForecast ? 638 : 488) + Theme.popupPadY
    color: "transparent"
    visible: false

    // Native popup grab: dismiss automatically on outside click and release focus on close.
    anchor.window: root.anchorWindow
    anchor.rect.x: root.panelLeft
    anchor.rect.y: root.anchorWindow ? root.anchorWindow.height : 34
    grabFocus: true

    readonly property int panelLeft: {
        if (!root.anchorItem || !root.anchorWindow)
            return 0;

        // Re-read the anchor on open: bar tabs shift as their content changes.
        root.visible;
        const point = root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0);
        const maximumX = Math.max(0, root.anchorWindow.width - root.width);
        return Math.max(0, Math.min(
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
                    root.currentWeatherCode = data.current.weather_code;
                    root.currentWeather = Math.round(data.current.temperature_2m) + "°";
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
        if (code === 0) return Theme.icons.sun;
        if (code === 1 || code === 2) return Theme.icons.partlyCloudy;
        if (code === 3) return Theme.icons.cloudy;
        if (code === 45 || code === 48) return Theme.icons.fog;
        if (code >= 51 && code <= 67) return Theme.icons.rain;
        if (code >= 71 && code <= 77) return Theme.icons.snow;
        if (code >= 80 && code <= 82) return Theme.icons.rain;
        if (code >= 95) return Theme.icons.storm;
        return Theme.icons.cloudy;
    }

    function weatherColor(code) {
        if (code === 0) return Theme.gold;
        if (code === 1 || code === 2) return Theme.rose;
        if (code >= 95) return Theme.iris;
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return Theme.foam;
        return Theme.subtle;
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

    PanelSurface {
        id: outerBorder
        window: root
        accent: Theme.rose

        Column {
            id: contentColumn
            anchors.fill: parent
            spacing: 8

            // Hero: the one fully saturated surface in the shell.
            Rectangle {
                id: dateHeader
                width: parent.width
                height: 96
                radius: 18
                gradient: Theme.dusk

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    UiText {
                        id: timeLabel
                        text: root.formatTime(calendarClock.date)
                        color: Theme.onAccent
                        font.family: Theme.displayFont
                        font.pixelSize: 40
                        font.weight: Font.Bold
                    }

                    UiText {
                        text: root.formatFullDate(calendarClock.date)
                        color: Theme.onAccent
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Icon {
                        anchors.right: parent.right
                        text: root.selectedForecast
                            ? root.weatherSymbol(root.selectedForecast.code)
                            : (root.currentWeatherCode >= 0 ? root.weatherSymbol(root.currentWeatherCode) : "")
                        color: Theme.onAccent
                        font.pixelSize: 26
                    }

                    UiText {
                        anchors.right: parent.right
                        text: root.selectedForecast
                            ? root.selectedForecast.high + "° / " + root.selectedForecast.low + "°"
                            : (root.selectedDateKey === root.todayKey && root.currentWeather.length
                                ? "Now " + root.currentWeather
                                : "No forecast")
                        color: Theme.onAccent
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }

                    UiText {
                        anchors.right: parent.right
                        text: root.weatherLocation
                        color: Theme.onAccent
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }
            }

            Item {
                id: monthNavigation
                width: parent.width
                height: 32

                SoftButton {
                    id: previousMonthButton
                    anchors.left: parent.left
                    variant: "ghost"
                    glyph: Theme.icons.chevronLeft
                    onClicked: root.changeMonth(-1)
                }

                UiText {
                    anchors.centerIn: parent
                    text: root.monthNames[root.displayedMonth] + " " + root.displayedYear
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }

                SoftButton {
                    id: nextMonthButton
                    anchors.right: todayButton.left
                    anchors.rightMargin: 2
                    variant: "ghost"
                    glyph: Theme.icons.chevronRight
                    onClicked: root.changeMonth(1)
                }

                SoftButton {
                    id: todayButton
                    anchors.right: parent.right
                    label: "Today"
                    fontSize: 11
                    onClicked: root.goToToday()
                }
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
                        required property int index
                        width: (weekdayHeader.width - (weekdayHeader.spacing * 6)) / 7
                        height: weekdayHeader.height

                        UiText {
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.index >= 5 ? Theme.rose : Theme.muted
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }

            Grid {
                id: dayGrid
                width: parent.width
                height: (6 * 46) + (5 * 2)
                columns: 7
                rowSpacing: 2
                columnSpacing: 2

                Repeater {
                    model: root.calendarDays

                    delegate: Item {
                        id: dayCell
                        required property var modelData

                        width: (dayGrid.width - (dayGrid.columnSpacing * 6)) / 7
                        height: 46

                        readonly property bool isToday: modelData.key === root.todayKey
                        readonly property bool isSelected: modelData.key === root.selectedDateKey
                        readonly property var forecast: root.weatherByDate[modelData.key]
                        readonly property color inkColor: isSelected
                            ? Theme.onAccent
                            : (modelData.currentMonth ? Theme.text : Theme.muted)

                        Rectangle {
                            anchors.fill: parent
                            radius: 13
                            color: dayMouse.containsMouse ? Theme.raised : "transparent"
                            border.width: dayCell.isToday && !dayCell.isSelected ? 1.5 : 0
                            border.color: Theme.rose

                            Behavior on color {
                                ColorAnimation { duration: Theme.fast }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 13
                            visible: dayCell.isSelected
                            gradient: Theme.dusk
                        }

                        UiText {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.leftMargin: 6
                            anchors.topMargin: 4
                            text: String(dayCell.modelData.day)
                            color: dayCell.inkColor
                            font.pixelSize: 12
                            font.weight: dayCell.isToday || dayCell.isSelected ? Font.Bold : Font.Medium
                        }

                        Icon {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: 5
                            anchors.topMargin: 4
                            text: dayCell.forecast ? root.weatherSymbol(dayCell.forecast.code) : ""
                            color: dayCell.isSelected
                                ? Theme.onAccent
                                : (dayCell.forecast ? root.weatherColor(dayCell.forecast.code) : Theme.subtle)
                            font.pixelSize: 13
                        }

                        UiText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            text: dayCell.forecast ? dayCell.forecast.high + "° " + dayCell.forecast.low + "°" : ""
                            color: dayCell.isSelected
                                ? Theme.onAccent
                                : (dayCell.modelData.currentMonth ? Theme.subtle : Theme.muted)
                            font.pixelSize: 9
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
                height: 142
                radius: Theme.radiusTile
                color: Theme.surface

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 3

                    UiText {
                        width: parent.width
                        text: root.formatFullDate(root.selectedDate)
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
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

                            const left = 16;
                            const right = width - 16;
                            const top = 18;
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
                            const trace = function() {
                                ctx.moveTo(xAt(0), yAt(values[0]));
                                for (let i = 1; i < hours.length; i++) {
                                    const middleX = (xAt(i - 1) + xAt(i)) / 2;
                                    ctx.bezierCurveTo(middleX, yAt(values[i - 1]), middleX, yAt(values[i]), xAt(i), yAt(values[i]));
                                }
                            };

                            const area = ctx.createLinearGradient(0, top, 0, bottom);
                            area.addColorStop(0, Theme.tint(Theme.rose, 0.38).toString());
                            area.addColorStop(1, Theme.tint(Theme.rose, 0).toString());
                            ctx.beginPath();
                            trace();
                            ctx.lineTo(right, bottom);
                            ctx.lineTo(left, bottom);
                            ctx.closePath();
                            ctx.fillStyle = area;
                            ctx.fill();

                            const line = ctx.createLinearGradient(left, 0, right, 0);
                            line.addColorStop(0, Theme.foam.toString());
                            line.addColorStop(0.5, Theme.rose.toString());
                            line.addColorStop(1, Theme.iris.toString());
                            ctx.beginPath();
                            trace();
                            ctx.strokeStyle = line;
                            ctx.lineWidth = 2.5;
                            ctx.lineCap = "round";
                            ctx.stroke();

                            ctx.font = "600 9px " + Theme.fontFamily;
                            ctx.textAlign = "center";
                            const labelStep = Math.max(1, Math.floor((hours.length - 1) / 5));
                            for (let i = 0; i < hours.length; i += labelStep) {
                                const x = xAt(i);
                                const y = yAt(values[i]);
                                ctx.fillStyle = Theme.text.toString();
                                ctx.beginPath();
                                ctx.arc(x, y, 2.5, 0, Math.PI * 2);
                                ctx.fill();
                                ctx.fillText(values[i] + "°", x, Math.max(10, y - 6));
                                ctx.fillStyle = Theme.muted.toString();
                                ctx.fillText(hours[i].time.slice(0, 5), x, height - 3);
                            }
                        }
                    }

                    UiText {
                        width: parent.width
                        text: {
                            const hours = root.selectedHours || [];
                            if (hours.length === 0) return "Hourly details unavailable";
                            const rain = Math.max.apply(null, hours.map(function(item) { return item.rain; }));
                            const wind = Math.round(hours.reduce(function(total, item) { return total + item.wind; }, 0) / hours.length);
                            return "Rain up to " + rain + "%   ·   Wind " + wind + " km/h";
                        }
                        color: Theme.subtle
                        font.pixelSize: 10
                    }
                }
            }
        }
    }
}
