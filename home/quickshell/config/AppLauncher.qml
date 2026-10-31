import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import QtQuick
import QtQuick.Controls

PopupWindow {
    id: root

    property var anchorWindow: null


    readonly property int maxWidth: 1080 + Theme.popupPadX * 2
    readonly property int maxHeight: 740 + Theme.popupPadY
    readonly property int outerMargin: 12
    readonly property int topGap: 8

    property string searchQuery: ""
    property int selectedIndex: 0
    readonly property var selectedDirectory: {
        if (root.searchQuery.trim().length === 0 || root.wallpaperMode)
            return null;
        const item = root.searchResults[root.selectedIndex];
        return item && item.type === "directory" ? item : null;
    }
    property string launchError: ""
    property var categoryFilter: []
    property bool applyingQuickSearch: false
    property var launchCounts: ({})
    property var favoriteIds: []
    property var usageHistory: []
    property var fileIndex: []
    property bool fileIndexStarted: false
    property bool fileIndexReady: false
    property double fileIndexUpdatedAt: 0
    property bool persistentStateReady: false
    property bool stateSaveQueued: false
    property bool commandConfirmationRequired: false
    property var pendingCommandArgs: []
    property string pendingCommandText: ""

    // Configure this template to switch the default search provider.
    // It must contain %s where the encoded query will be inserted.
    property string searchEngineTemplate: "https://www.google.com/search?q=%s"
    readonly property string homeDirectory: String(Quickshell.env("HOME") || "")
    // Index only visible, useful directories. Do not scan the entire HOME directory,
    // or hidden folders; each root has a result limit to prevent
    // slowdowns in large libraries.
    readonly property var fileSearchDirectories: root.homeDirectory.length > 0 ? [
        root.homeDirectory + "/Documents",
        root.homeDirectory + "/Documentos",
        root.homeDirectory + "/Downloads",
        root.homeDirectory + "/Projects",
        root.homeDirectory + "/Projetos",
        root.homeDirectory + "/Desktop",
        root.homeDirectory + "/Área de Trabalho",
        root.homeDirectory + "/Code",
        root.homeDirectory + "/Código",
        root.homeDirectory + "/Development",
        root.homeDirectory + "/Desenvolvimento",
        root.homeDirectory + "/dev",
        root.homeDirectory + "/src",
        root.homeDirectory + "/Work",
        root.homeDirectory + "/Trabalho",
        root.homeDirectory + "/Pictures",
        root.homeDirectory + "/Imagens",
        root.homeDirectory + "/Videos",
        root.homeDirectory + "/Vídeos",
        root.homeDirectory + "/Music",
        root.homeDirectory + "/Música",
        root.homeDirectory + "/Public",
        root.homeDirectory + "/Templates",
        "/etc/nixos"
    ] : []
    readonly property var fileIndexCommand: {
        if (root.fileSearchDirectories.length === 0)
            return [];

        // The script is constant; directories are passed as separate arguments
        // (without shell interpolation). head limits output to 120 items per folder.
        const indexScript = [
            'for root in "$@"; do',
            '  [ -d "$root" ] || continue',
            "  find \"$root\" -maxdepth 4 -ignore_readdir_race \\",
            "    \\( -type d -name '.*' -prune \\) -o \\",
            "    \\( -type d \\( -name node_modules -o -name build -o -name dist -o -name target -o -name result -o -name venv -o -name .venv -o -name __pycache__ -o -name .pytest_cache -o -name .mypy_cache -o -name .tox -o -name .next -o -name .turbo -o -name .gradle -o -name Trash -o -name 'Code Cache' -o -name GPUCache \\) -prune \\) -o \\",
            "    \\( \\( -type f -o -type d \\) ! -name '.*' -printf '%y\\t%p\\0' \\) 2>/dev/null | head -z -n 120",
            'done'
        ].join("\n");
        return ["bash", "-c", indexScript, "AppLauncherIndexer"].concat(root.fileSearchDirectories);
    }

    readonly property var allApplications: {
        return [...DesktopEntries.applications.values]
            .filter(function(entry) {
                return entry && !entry.noDisplay && (entry.name || entry.id);
            })
            .sort(function(first, second) {
                return String(first.name || first.id).localeCompare(
                    String(second.name || second.id)
                );
            });
    }

    readonly property var usageSortedApplications: {
        const counts = root.launchCounts;
        return [...root.allApplications].sort(function(first, second) {
            const firstCount = Number(counts[first.id] || 0);
            const secondCount = Number(counts[second.id] || 0);
            return secondCount - firstCount
                || String(first.name || first.id).localeCompare(String(second.name || second.id));
        });
    }

    readonly property var topApplications: {
        const results = [];
        const seen = ({});
        const add = function(item) {
            if (!item || !item.id || seen[item.id])
                return;
            seen[item.id] = true;
            results.push(item);
        };

        // Favorites always lead the home highlights, followed by recent items.
        for (let i = 0; i < root.favoriteIds.length; i++) {
            const favoriteEntry = root.allApplications.find(function(entry) {
                return entry.id === root.favoriteIds[i];
            });
            if (favoriteEntry)
                add(root.applicationResult(favoriteEntry));
        }

        for (let i = 0; i < root.usageHistory.length; i++) {
            const historyItem = root.usageHistory[i];
            if (historyItem.type === "app") {
                const entry = root.allApplications.find(function(candidate) {
                    return candidate.id === historyItem.id;
                });
                if (entry)
                    add(root.applicationResult(entry));
            } else if (historyItem.type === "file" && historyItem.path) {
                add({
                    type: historyItem.isDirectory ? "directory" : "file",
                    id: "file:" + historyItem.path,
                    name: historyItem.name || root.fileName(historyItem.path),
                    icon: historyItem.isDirectory ? "folder" : "text-x-generic",
                    details: historyItem.path,
                    path: historyItem.path,
                    isDirectory: Boolean(historyItem.isDirectory),
                    categories: []
                });
            }
            if (results.length >= 6)
                break;
        }

        for (let i = 0; i < root.usageSortedApplications.length && results.length < 6; i++)
            add(root.applicationResult(root.usageSortedApplications[i]));

        return results.slice(0, 6);
    }

    readonly property var quickSearches: [
        { label: "Development", icon: "", categories: ["Development"] },
        { label: "Internet", icon: "", categories: ["Network", "WebBrowser"] },
        { label: "Settings", icon: "", categories: ["Settings", "System"] },
        { label: "Multimedia", icon: "", categories: ["AudioVideo", "Audio", "Video"] },
        { label: "Utilities", icon: "", categories: ["Utility"] },
        { label: "Games", icon: "", categories: ["Game"] }
    ]

    readonly property var filteredApplications: {
        const query = root.searchQuery.trim().toLowerCase();
        if (root.categoryFilter.length > 0) {
            return root.allApplications.filter(function(entry) {
                const categories = (entry.categories || []).map(function(category) {
                    return String(category).toLowerCase();
                });
                return root.categoryFilter.some(function(category) {
                    return categories.indexOf(String(category).toLowerCase()) !== -1;
                });
            });
        }
        if (query.length === 0)
            return root.usageSortedApplications;

        return root.allApplications.map(function(entry) {
            return { entry: entry, score: root.applicationMatchScore(entry, query) };
        }).filter(function(item) {
            return item.score >= 0;
        }).sort(function(first, second) {
            return second.score - first.score
                || String(first.entry.name || first.entry.id).localeCompare(
                    String(second.entry.name || second.entry.id)
                );
        }).map(function(item) { return item.entry; });
    }

    readonly property var searchResults: {
        const rawQuery = root.searchQuery.trim();
        if (rawQuery.length === 0)
            return [];

        const mode = root.queryMode;
        if (mode === "command") {
            const parsed = root.parseCommandLine(rawQuery.slice(1).trim());
            return [{
                type: "command",
                id: "command:current",
                name: parsed.valid ? parsed.args.join(" ") : "Run command in Kitty",
                icon: "utilities-terminal",
                details: parsed.valid
                    ? (root.commandRunsDirectly(parsed.args)
                        ? "System action · Enter executes directly, without a terminal or shell"
                        : "Command · Enter runs in Kitty without a shell")
                    : (rawQuery.slice(1).trim().length === 0
                        ? "Type a command after >"
                        : parsed.error),
                commandArgs: parsed.valid ? parsed.args : [],
                valid: parsed.valid
            }];
        }
        if (mode === "web") {
            const terms = rawQuery.slice(1).trim();
            if (terms.length === 0)
                return [];
            return [{
                type: "web",
                id: "web:" + terms,
                name: "Search the web for “" + terms + "”",
                icon: "web-browser",
                details: "Web search · Enter opens the default browser",
                url: root.buildSearchUrl(terms)
            }];
        }
        if (mode === "github") {
            const terms = rawQuery.replace(/^github\s+/i, "").trim();
            return [{
                type: "web",
                id: "github:" + terms,
                name: "Search GitHub for “" + terms + "”",
                icon: "github",
                details: "GitHub search · Enter opens github.com",
                url: "https://github.com/search?q=" + encodeURIComponent(terms)
            }];
        }
        if (mode === "calculator") {
            const value = root.tryCalculate(rawQuery);
            if (value === null)
                return [];
            return [{
                type: "calculator",
                id: "calculator:" + rawQuery,
                name: root.formatNumber(value),
                icon: "accessories-calculator",
                details: "Calculator result · Enter copies the result",
                result: root.formatNumber(value)
            }];
        }

        const q = rawQuery.toLowerCase();
        const appResults = root.filteredApplications.map(function(entry) {
            const score = root.applicationMatchScore(entry, q);
            return Object.assign(root.applicationResult(entry), {
                score: score + root.historyBoost("app", entry.id)
                    + (root.favoriteIds.indexOf(entry.id) >= 0 ? 220 : 0)
            });
        });

        const fileResults = [];
        if (root.categoryFilter.length === 0) {
            for (let i = 0; i < root.fileIndex.length; i++) {
                const file = root.fileIndex[i];
                const score = root.fileMatchScore(file, q);
                if (score < 0)
                    continue;
                fileResults.push(Object.assign({}, file, {
                    score: score + root.historyBoost("file", file.path)
                }));
            }
        }

        // Strong app-name matches outrank same-named files; an exact filename
        // can still outrank weak matches on unrelated app descriptions.
        return appResults.concat(fileResults).sort(function(first, second) {
            return second.score - first.score
                || String(first.name || "").localeCompare(String(second.name || ""));
        }).slice(0, 50);
    }

    readonly property string queryMode: {
        const query = root.searchQuery.trim();
        if (query.startsWith(">"))
            return "command";
        if (query.startsWith("?"))
            return "web";
        if (/^github\s+/i.test(query))
            return "github";
        return root.tryCalculate(query) !== null ? "calculator" : "search";
    }

    // A dedicated gallery mode inside the launcher. Extra terms filter the library.
    readonly property bool wallpaperMode: /^wall(?:\s|$)/i.test(root.searchQuery.trim())
    readonly property string wallpaperFilterText: root.searchQuery.trim().replace(/^wall\s*/i, "").trim()

    readonly property var allApplicationsModelValues: root.allApplications

    function fileName(path) {
        const parts = String(path || "").split("/");
        return parts.length > 0 ? parts[parts.length - 1] : String(path || "");
    }

    function isHiddenPath(path) {
        return String(path || "").split("/").some(function(part) {
            return part.length > 0 && part.startsWith(".");
        });
    }

    // Classify files to draw vector icons directly in QML.
    // This keeps file results independent of optional theme icons.
    function fileIconKind(item) {
        if (!item)
            return "generic";
        if (item.type === "directory" || item.isDirectory)
            return "folder";

        const filename = String(item.name || fileName(item.path || "")).toLowerCase();
        const path = String(item.path || filename).toLowerCase();
        const dot = filename.lastIndexOf(".");
        const ext = dot > 0 ? filename.slice(dot + 1) : "";
        const has = function(values) { return values.indexOf(ext) >= 0; };

        if (has(["pdf"])) return "pdf";
        if (has(["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "tif", "tiff", "ico"])) return "image";
        if (has(["mp4", "mkv", "webm", "mov", "avi", "m4v", "mpeg", "mpg", "ogv"])) return "video";
        if (has(["mp3", "wav", "flac", "ogg", "opus", "m4a", "aac", "wma"])) return "audio";
        if (has(["zip", "tar", "gz", "bz2", "xz", "7z", "rar", "zst", "tgz", "deb", "rpm"])) return "archive";
        if (has(["ods", "xls", "xlsx", "csv", "tsv"])) return "spreadsheet";
        if (has(["odp", "ppt", "pptx", "key"])) return "presentation";
        if (has(["ttf", "otf", "woff", "woff2"])) return "font";
        if (has(["qml", "js", "mjs", "ts", "jsx", "tsx", "json", "xml", "html", "htm", "css", "scss", "c", "h", "cpp", "hpp", "cs", "py", "sh", "bash", "zsh", "lua", "rs", "go", "java", "kt", "php", "rb", "sql", "nix", "yml", "yaml", "toml", "ini", "conf", "config", "gitignore", "dockerfile"])) return "code";
        if (has(["odt", "doc", "docx", "rtf", "md", "txt", "log", "rst"])) return "document";
        if (filename === "makefile" || filename === "dockerfile" || filename === "justfile" || path.endsWith("/makefile")) return "code";
        if (has(["exe", "appimage", "bin", "desktop"]) || filename.endsWith(".sh")) return "executable";
        return "generic";
    }

    function applicationResult(entry) {
        return {
            type: "app",
            id: entry.id,
            name: entry.name || entry.id,
            icon: entry.icon || "application-x-executable",
            details: entry.genericName || entry.comment
                || String((entry.categories || [])[0] || "Application"),
            categories: entry.categories || [],
            entry: entry
        };
    }

    function applicationMatchScore(entry, query) {
        const name = String(entry.name || "").toLowerCase();
        const id = String(entry.id || "").replace(/\.desktop$/i, "").toLowerCase();
        const generic = String(entry.genericName || "").toLowerCase();
        const comment = String(entry.comment || "").toLowerCase();
        const keywords = (entry.keywords || []).join(" ").toLowerCase();
        const categories = (entry.categories || []).join(" ").toLowerCase();
        const command = (entry.command || []).join(" ").toLowerCase();
        const searchable = [name, id, generic, comment, keywords, categories, command].join(" ");
        const terms = query.split(/\s+/).filter(function(term) { return term.length > 0; });

        if (name === query || id === query)
            return 12000;
        if (name.startsWith(query) || id.startsWith(query))
            return 9500;
        if (name.split(/\s+/).some(function(word) { return word.startsWith(query); }))
            return 8500;
        if (name.includes(query) || id.includes(query))
            return 7200;
        if (generic === query)
            return 6200;
        if (generic.includes(query))
            return 5000;
        if (terms.length > 0 && terms.every(function(term) { return searchable.includes(term); })) {
            if (keywords.includes(query)) return 4000;
            if (command.includes(query)) return 3600;
            if (categories.includes(query)) return 3000;
            return 2800;
        }
        if (comment.includes(query))
            return 2200;
        return -1;
    }

    function fileMatchScore(file, query) {
        const normalizedQuery = String(query || "").toLowerCase();
        const name = String(file.name || "").toLowerCase();
        const path = String(file.path || "").toLowerCase();
        const normalizedPathQuery = normalizedQuery.startsWith("~/") && root.homeDirectory.length > 0
            ? (root.homeDirectory + normalizedQuery.slice(1)).toLowerCase()
            : normalizedQuery;
        if (path === normalizedPathQuery)
            return 7600;
        if (normalizedPathQuery.indexOf("/") >= 0 && path.endsWith("/" + normalizedPathQuery))
            return 7300;
        if (name === normalizedQuery)
            return 6900;
        if (name.startsWith(normalizedQuery))
            return 5600;

        const terms = normalizedQuery.split(/\s+/).filter(function(term) { return term.length > 0; });
        if (terms.length > 1 && terms.every(function(term) { return name.includes(term); }))
            return 4900;
        if (name.includes(normalizedQuery))
            return 4300;
        if (path.includes(normalizedPathQuery))
            return 3200;
        const pathTerms = normalizedPathQuery.split(/\s+/).filter(function(term) { return term.length > 0; });
        if (pathTerms.length > 1 && pathTerms.every(function(term) { return path.includes(term); }))
            return 2800;
        return -1;
    }

    function historyBoost(type, key) {
        const storedType = type === "directory" ? "file" : type;
        const item = root.usageHistory.find(function(historyItem) {
            return historyItem.type === storedType
                && (storedType === "app" ? historyItem.id === key : historyItem.path === key);
        });
        if (!item)
            return 0;
        const countBoost = Math.min(100, Number(item.count || 1) * 12);
        const age = Math.max(0, Date.now() - Number(item.lastUsed || 0));
        const recentBoost = age < 86400000 ? 140 : (age < 604800000 ? 70 : 0);
        return countBoost + recentBoost;
    }

    function isCalculationIntent(expression) {
        const query = String(expression || "").trim();
        if (query.length === 0 || !/^[0-9a-zA-Z_+\-*/%^().,\s]+$/.test(query))
            return false;
        return /[+*/%^()]|\s-\s|^-\s*\d/.test(query)
            || /^(sqrt|abs|round|floor|ceil|sin|cos|tan|log|ln|min|max|pow)\s*\(/i.test(query);
    }

    function tryCalculate(expression) {
        const query = String(expression || "").trim();
        if (!root.isCalculationIntent(query))
            return null;
        const tokens = [];
        let offset = 0;
        while (offset < query.length) {
            const rest = query.slice(offset);
            const space = rest.match(/^\s+/);
            if (space) {
                offset += space[0].length;
                continue;
            }
            const number = rest.match(/^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+\-]?\d+)?/);
            if (number) {
                const value = Number(number[0]);
                if (!Number.isFinite(value))
                    return null;
                tokens.push({ type: "number", value: value });
                offset += number[0].length;
                continue;
            }
            const identifier = rest.match(/^[a-zA-Z]+/);
            if (identifier) {
                tokens.push({ type: "identifier", value: identifier[0].toLowerCase() });
                offset += identifier[0].length;
                continue;
            }
            const symbol = query[offset];
            if ("+-*/%^(),".includes(symbol)) {
                tokens.push({ type: "symbol", value: symbol });
                offset++;
                continue;
            }
            return null;
        }
        if (tokens.length === 0)
            return null;

        let index = 0;
        const peek = function() { return index < tokens.length ? tokens[index] : null; };
        const take = function() { return index < tokens.length ? tokens[index++] : null; };
        const expect = function(symbol) {
            const token = take();
            if (!token || token.type !== "symbol" || token.value !== symbol)
                throw new Error("Expected " + symbol);
        };
        const parseExpression = function() {
            let value = parseTerm();
            while (peek() && peek().type === "symbol"
                && (peek().value === "+" || peek().value === "-")) {
                const operator = take().value;
                const right = parseTerm();
                value = operator === "+" ? value + right : value - right;
            }
            return value;
        };
        const parseTerm = function() {
            let value = parseUnary();
            while (peek() && peek().type === "symbol"
                && ["*", "/", "%"].indexOf(peek().value) >= 0) {
                const operator = take().value;
                const right = parseUnary();
                if ((operator === "/" || operator === "%") && right === 0)
                    throw new Error("Division by zero");
                if (operator === "*") value *= right;
                else if (operator === "/") value /= right;
                else value %= right;
            }
            return value;
        };
        const parseUnary = function() {
            if (peek() && peek().type === "symbol" && peek().value === "+") {
                take();
                return parseUnary();
            }
            if (peek() && peek().type === "symbol" && peek().value === "-") {
                take();
                return -parseUnary();
            }
            return parsePower();
        };
        const parsePower = function() {
            let value = parsePrimary();
            if (peek() && peek().type === "symbol" && peek().value === "^") {
                take();
                value = Math.pow(value, parseUnary());
            }
            return value;
        };
        const parsePrimary = function() {
            const token = take();
            if (!token)
                throw new Error("Unexpected end of expression");
            if (token.type === "number")
                return token.value;
            if (token.type === "symbol" && token.value === "(") {
                const value = parseExpression();
                expect(")");
                return value;
            }
            if (token.type !== "identifier")
                throw new Error("Expected a number or function");

            const name = token.value;
            if (name === "pi") return Math.PI;
            if (name === "e") return Math.E;
            expect("(");
            const args = [];
            if (!(peek() && peek().type === "symbol" && peek().value === ")")) {
                args.push(parseExpression());
                while (peek() && peek().type === "symbol" && peek().value === ",") {
                    take();
                    args.push(parseExpression());
                }
            }
            expect(")");
            if (["sqrt", "abs", "round", "floor", "ceil", "sin", "cos", "tan", "log", "ln"].indexOf(name) >= 0 && args.length !== 1)
                throw new Error("Wrong number of function arguments");
            if (["min", "max"].indexOf(name) >= 0 && args.length < 1)
                throw new Error("Wrong number of function arguments");
            if (name === "sqrt") return Math.sqrt(args[0]);
            if (name === "abs") return Math.abs(args[0]);
            if (name === "round") return Math.round(args[0]);
            if (name === "floor") return Math.floor(args[0]);
            if (name === "ceil") return Math.ceil(args[0]);
            if (name === "sin") return Math.sin(args[0]);
            if (name === "cos") return Math.cos(args[0]);
            if (name === "tan") return Math.tan(args[0]);
            if (name === "log") return Math.log10(args[0]);
            if (name === "ln") return Math.log(args[0]);
            if (name === "min") return Math.min.apply(Math, args);
            if (name === "max") return Math.max.apply(Math, args);
            if (name === "pow" && args.length === 2) return Math.pow(args[0], args[1]);
            throw new Error("Unknown or unsupported function: " + name);
        };

        try {
            const result = parseExpression();
            if (index !== tokens.length || !Number.isFinite(result))
                return null;
            return result;
        } catch (error) {
            return null;
        }
    }

    function formatNumber(value) {
        if (!Number.isFinite(value))
            return "Invalid result";
        if (Math.abs(value - Math.round(value)) < 1e-10)
            return String(Math.round(value));
        return String(Number(value.toPrecision(12)));
    }

    function parseCommandLine(commandLine) {
        const input = String(commandLine || "").trim();
        if (/[\n\r]/.test(input))
            return { valid: false, args: [], error: "Commands must fit on one line." };

        const args = [];
        let token = "";
        let quote = "";
        let escaping = false;
        let tokenStarted = false;
        for (let i = 0; i < input.length; i++) {
            const character = input[i];
            if (escaping) {
                token += character;
                escaping = false;
                tokenStarted = true;
                continue;
            }
            if (character === "\\") {
                escaping = true;
                tokenStarted = true;
                continue;
            }
            if (quote) {
                if (character === quote)
                    quote = "";
                else
                    token += character;
                tokenStarted = true;
                continue;
            }
            if (character === "'" || character === '"') {
                quote = character;
                tokenStarted = true;
                continue;
            }
            if (";|&`$<>".includes(character))
                return { valid: false, args: [], error: "Shell operators are disabled. Use one command and its arguments." };
            if (/\s/.test(character)) {
                if (tokenStarted) {
                    args.push(token);
                    token = "";
                    tokenStarted = false;
                }
                continue;
            }
            token += character;
            tokenStarted = true;
        }
        if (escaping || quote)
            return { valid: false, args: [], error: "Unclosed quote or escape in command." };
        if (tokenStarted)
            args.push(token);
        if (args.length === 0 || args[0].length === 0)
            return { valid: false, args: [], error: "Type a command after >" };
        return { valid: true, args: args, error: "" };
    }

    function commandNeedsConfirmation(args) {
        if (!args || args.length === 0)
            return false;
        const command = root.fileName(args[0]).toLowerCase();
        if (["sudo", "sudoedit", "doas", "pkexec", "su", "rm", "rmdir", "mkfs", "dd", "wipefs", "shred", "shutdown", "reboot", "poweroff", "halt", "fdisk", "parted", "cryptsetup"].indexOf(command) >= 0
            || command.startsWith("mkfs."))
            return true;
        if (["sh", "bash", "zsh", "dash", "fish"].indexOf(command) >= 0
            && args.slice(1).some(function(argument) {
                return argument === "--command" || /^-[^-]*c/.test(argument);
            }))
            return true;
        // Inline code can alter files just as easily as a shell command.
        if (["python", "python2", "python3", "node", "nodejs", "ruby", "perl", "php", "lua"].indexOf(command) >= 0
            && args.slice(1).some(function(argument) {
                if (["python", "python2", "python3", "node", "nodejs"].indexOf(command) >= 0)
                    return argument === "-c" || argument === "--eval" || argument === "-e";
                if (command === "php")
                    return argument === "-r" || argument === "--run";
                return argument === "-e" || argument === "--eval";
            }))
            return true;
        if (args.some(function(argument) {
            const name = root.fileName(String(argument)).toLowerCase();
            return ["sudo", "sudoedit", "doas", "pkexec", "su", "rm", "rmdir", "mkfs", "dd", "wipefs", "shred", "shutdown", "reboot", "poweroff", "halt", "fdisk", "parted", "cryptsetup"].indexOf(name) >= 0
                || name.startsWith("mkfs.");
        }))
            return true;
        if (command === "chmod" || command === "chown")
            return args.indexOf("-R") >= 0 || args.indexOf("--recursive") >= 0;
        if (command === "systemctl" && ["stop", "disable", "mask", "reboot", "poweroff", "halt"].indexOf(String(args[1] || "")) >= 0)
            return true;
        if (command === "nix-collect-garbage" && args.indexOf("-d") >= 0)
            return true;
        return false;
    }

    function commandRunsDirectly(args) {
        if (!args || args.length === 0)
            return false;
        const command = root.fileName(String(args[0])).toLowerCase();
        const subcommand = String(args[1] || "").toLowerCase();
        if (command === "xdg-open" || command === "notify-send")
            return true;
        if (command === "gio" && subcommand === "open")
            return true;
        if (command === "wpctl"
            && ["set-volume", "set-mute", "set-default"].indexOf(subcommand) >= 0)
            return true;
        if (command === "playerctl"
            && ["play", "pause", "play-pause", "stop", "next", "previous", "volume"].indexOf(subcommand) >= 0)
            return true;
        if (command === "brightnessctl" && subcommand === "set")
            return true;
        if (command === "hyprctl" && subcommand === "dispatch") {
            const dispatch = String(args[2] || "").toLowerCase();
            return ["togglefloating", "fullscreen", "pin", "pseudo", "workspace",
                "movefocus", "focuswindow", "centerwindow"].indexOf(dispatch) >= 0;
        }
        return false;
    }

    function executeCommand() {
        const parsed = root.parseCommandLine(root.searchQuery.trim().slice(1).trim());
        if (!parsed.valid) {
            root.launchError = parsed.error;
            return;
        }
        root.pendingCommandArgs = parsed.args;
        root.pendingCommandText = parsed.args.join(" ");
        if (root.commandNeedsConfirmation(parsed.args)) {
            root.commandConfirmationRequired = true;
            return;
        }
        root.executePendingCommand();
    }

    function executePendingCommand() {
        if (!root.pendingCommandArgs || root.pendingCommandArgs.length === 0)
            return;
        try {
            // Pass argv directly. --hold keeps non-interactive command output visible in Kitty.
            const command = root.commandRunsDirectly(root.pendingCommandArgs)
                ? root.pendingCommandArgs
                : ["kitty", "--hold", "-e"].concat(root.pendingCommandArgs);
            Quickshell.execDetached({
                command: command,
                workingDirectory: root.homeDirectory
            });
            if (!root.commandRunsDirectly(root.pendingCommandArgs)) {
                // Hyprland initially places Kitty under the pointer. Center this launcher terminal
                // once its window exists; this only affects the terminal opened by `>`.
                Quickshell.execDetached({
                    command: ["sh", "-c", "sleep 0.25; hyprctl dispatch centerwindow"]
                });
            }
            root.commandConfirmationRequired = false;
            root.closePanel();
        } catch (error) {
            console.error("AppLauncher: command launch failed:", error);
            root.launchError = "Unable to launch this command or action. Check the Quickshell log.";
        }
    }

    function buildSearchUrl(terms) {
        const encoded = encodeURIComponent(String(terms || "").trim());
        const template = root.searchEngineTemplate || "https://www.google.com/search?q=%s";
        return template.indexOf("%s") >= 0
            ? template.replace("%s", encoded)
            : template + encoded;
    }

    function openExternal(url) {
        if (!url)
            return;
        try {
            Quickshell.execDetached({ command: ["xdg-open", String(url)] });
            root.closePanel();
        } catch (error) {
            console.error("AppLauncher: unable to open URL:", error);
            root.launchError = "Unable to open the default browser. Check that xdg-utils is installed.";
        }
    }

    function recordHistory(type, item) {
        if (type === "app") {
            const entry = item && item.entry ? item.entry : item;
            if (!entry || !entry.id)
                return;
            const counts = Object.assign({}, root.launchCounts);
            counts[entry.id] = Number(counts[entry.id] || 0) + 1;
            root.launchCounts = counts;
            const historyEntry = {
                type: "app",
                id: String(entry.id),
                name: String(entry.name || entry.id),
                count: 1,
                lastUsed: Date.now()
            };
            const existing = root.usageHistory.find(function(candidate) {
                return candidate.type === "app" && candidate.id === historyEntry.id;
            });
            historyEntry.count += existing ? Number(existing.count || 0) : 0;
            root.usageHistory = [historyEntry].concat(root.usageHistory.filter(function(candidate) {
                return !(candidate.type === "app" && candidate.id === historyEntry.id);
            })).slice(0, 40);
        } else if ((type === "file" || type === "directory") && item && item.path) {
            const path = String(item.path);
            if (!root.homeDirectory || !path.startsWith(root.homeDirectory + "/")
                || root.isHiddenPath(path)
                || /(password|secret|token|credential|\.pem($|\/)|\.key($|\/))/i.test(path))
                return;
            const historyEntry = {
                type: "file",
                id: "file:" + path,
                path: path,
                name: String(item.name || root.fileName(path)),
                isDirectory: type === "directory" || Boolean(item.isDirectory),
                count: 1,
                lastUsed: Date.now()
            };
            const existing = root.usageHistory.find(function(candidate) {
                return candidate.type === "file" && candidate.path === path;
            });
            historyEntry.count += existing ? Number(existing.count || 0) : 0;
            root.usageHistory = [historyEntry].concat(root.usageHistory.filter(function(candidate) {
                return !(candidate.type === "file" && candidate.path === path);
            })).slice(0, 40);
        }
        root.savePersistentState();
    }

    function toggleFavorite(item) {
        const entry = item && item.type === "app" ? item.entry : item;
        if (!entry || !entry.id)
            return;
        let favorites = root.favoriteIds.slice();
        if (favorites.indexOf(entry.id) >= 0)
            favorites = favorites.filter(function(id) { return id !== entry.id; });
        else
            favorites.push(entry.id);
        root.favoriteIds = favorites;
        root.savePersistentState();
    }

    function removeHistoryItem(item) {
        if (!item)
            return;
        root.usageHistory = root.usageHistory.filter(function(historyItem) {
            if (item.type === "app")
                return !(historyItem.type === "app" && historyItem.id === item.id);
            if (item.type === "file" || item.type === "directory")
                return !(historyItem.type === "file" && historyItem.path === item.path);
            return true;
        });
        root.savePersistentState();
    }

    function clearHistory() {
        root.usageHistory = [];
        root.launchCounts = ({});
        root.savePersistentState();
    }

    function savePersistentState() {
        if (!root.persistentStateReady) {
            root.stateSaveQueued = true;
            return;
        }
        const state = {
            version: 1,
            launchCounts: root.launchCounts,
            favorites: root.favoriteIds,
            history: root.usageHistory
        };
        try {
            launcherStateFile.setText(JSON.stringify(state));
            root.stateSaveQueued = false;
        } catch (error) {
            console.warn("AppLauncher: could not save state:", error);
        }
    }

    function restorePersistentState() {
        try {
            const raw = launcherStateFile.text();
            if (raw && raw.trim().length > 0) {
                const state = JSON.parse(raw);
                if (state && typeof state === "object") {
                    root.launchCounts = state.launchCounts && typeof state.launchCounts === "object"
                        ? state.launchCounts : ({});
                    root.favoriteIds = Array.isArray(state.favorites)
                        ? state.favorites.filter(function(id) { return typeof id === "string"; })
                        : [];
                    root.usageHistory = Array.isArray(state.history)
                        ? state.history.filter(function(item) {
                            if (!item || (item.type !== "app" && item.type !== "file"))
                                return false;
                            if (item.type === "app")
                                return typeof item.id === "string";
                            return typeof item.path === "string"
                                && root.homeDirectory.length > 0
                                && item.path.startsWith(root.homeDirectory + "/")
                                && !root.isHiddenPath(item.path)
                                && !/(password|secret|token|credential|\.pem($|\/)|\.key($|\/))/i.test(item.path);
                        }).slice(0, 40)
                        : [];
                }
            }
        } catch (error) {
            console.warn("AppLauncher: state file is invalid; starting with an empty history.", error);
        }
        root.persistentStateReady = true;
        if (root.stateSaveQueued)
            root.savePersistentState();
    }

    function parseFileIndex(output) {
        // NUL separators preserve filenames with tabs or newlines. The explicit
        // roots overlap HOME, so deduplicate paths before exposing the index.
        const lines = String(output || "").split("\u0000");
        const entries = [];
        const seenPaths = ({});
        for (let i = 0; i < lines.length && entries.length < 3000; i++) {
            const line = lines[i];
            const separator = line.indexOf("\t");
            if (separator < 1)
                continue;
            const kind = line.slice(0, separator);
            // Keep the path verbatim, including leading/trailing spaces.
            const path = line.slice(separator + 1).replace(/\r$/, "");
            if ((kind !== "f" && kind !== "d") || !path || path === root.homeDirectory || seenPaths[path])
                continue;
            // Never expose hidden files/folders, including paths from a stale index.
            if (root.isHiddenPath(path))
                continue;
            seenPaths[path] = true;
            entries.push({
                type: kind === "d" ? "directory" : "file",
                id: "file:" + path,
                name: root.fileName(path),
                path: path,
                isDirectory: kind === "d",
                icon: kind === "d" ? "folder" : "text-x-generic",
                details: path,
                categories: []
            });
        }
        root.fileIndex = entries;
        root.fileIndexUpdatedAt = Date.now();
        root.fileIndexReady = true;
    }

    function startFileIndex() {
        if (root.fileIndexCommand.length === 0) {
            root.fileIndexReady = true;
            return;
        }
        if (fileIndexProcess.running)
            return;

        // Refresh when reopening after two minutes so newly created files appear
        // without rescanning the filesystem on every keystroke or every toggle.
        if (root.fileIndexStarted
                && root.fileIndexUpdatedAt > 0
                && Date.now() - root.fileIndexUpdatedAt < 120000)
            return;

        root.fileIndexStarted = true;
        root.fileIndexReady = false;
        fileIndexProcess.running = true;
    }

    function categoryApplicationCount(searchItem) {
        const requiredCategories = (searchItem.categories || []).map(function(category) {
            return String(category).toLowerCase();
        });
        return root.allApplications.filter(function(entry) {
            const entryCategories = (entry.categories || []).map(function(category) {
                return String(category).toLowerCase();
            });
            return requiredCategories.some(function(category) {
                return entryCategories.indexOf(category) !== -1;
            });
        }).length;
    }

    function applyQuickSearch(searchItem) {
        root.applyingQuickSearch = true;
        root.categoryFilter = searchItem.categories;
        searchInput.text = searchItem.label;
        root.searchQuery = searchItem.label;
        root.selectedIndex = 0;
        root.launchError = "";
        root.applyingQuickSearch = false;
        searchInput.forceActiveFocus();
    }

    function launchApplication(entry) {
        if (!entry) {
            root.launchError = "Select an application first.";
            return;
        }
        const command = entry.command;
        if (!command || command.length === 0) {
            root.launchError = "No launch command is available for this application.";
            console.warn("AppLauncher: no parsed command for", entry.name || entry.id);
            return;
        }
        try {
            // Reuse Quickshell's parsed DesktopEntry argv; it is not passed through a shell.
            Quickshell.execDetached({
                command: command,
                workingDirectory: entry.workingDirectory
            });
            root.recordHistory("app", entry);
            root.closePanel();
        } catch (error) {
            console.error("AppLauncher: launch failed:", entry.name || entry.id, error);
            root.launchError = "Unable to launch " + (entry.name || "this application") + ". Check qs log.";
        }
    }

    function copyCalculationResult(item) {
        if (!item || item.type !== "calculator" || !item.result)
            return;
        Quickshell.clipboardText = String(item.result);
        root.closePanel();
    }

    // Enter opens a folder in the editor, Shift+Enter in the file manager.
    function openDirectory(item, command) {
        try {
            Quickshell.execDetached({ command: [command, String(item.path)] });
            root.recordHistory("directory", item);
            root.closePanel();
        } catch (error) {
            console.error("AppLauncher: unable to open folder:", error);
            root.launchError = "Unable to open this folder with " + command + ".";
        }
    }

    function launchResult(item) {
        if (!item)
            return;
        if (item.type === "app") {
            root.launchApplication(item.entry);
        } else if (item.type === "directory") {
            root.openDirectory(item, "code");
        } else if (item.type === "file") {
            try {
                Quickshell.execDetached({ command: ["xdg-open", String(item.path)] });
                root.recordHistory("file", item);
                root.closePanel();
            } catch (error) {
                console.error("AppLauncher: unable to open file:", error);
                root.launchError = "Unable to open this item. Check that xdg-utils is installed.";
            }
        } else if (item.type === "calculator") {
            root.copyCalculationResult(item);
        } else if (item.type === "web") {
            root.openExternal(item.url);
        } else if (item.type === "command") {
            if (item.valid)
                root.executeCommand();
            else
                root.launchError = item.details;
        }
    }

    function launchTopApplication(index) {
        if (index < 0 || index >= root.topApplications.length)
            return;
        root.launchResult(root.topApplications[index]);
    }

    function moveSelection(direction) {
        const count = root.searchQuery.trim().length > 0
            ? root.searchResults.length
            : root.allApplications.length;
        if (count === 0) {
            root.selectedIndex = 0;
            return;
        }
        root.selectedIndex = Math.max(0, Math.min(count - 1, root.selectedIndex + direction));
        if (root.searchQuery.trim().length > 0)
            resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        else
            allAppsGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
    }

    function toggleSelectedFavorite() {
        if (root.searchQuery.trim().length > 0) {
            const item = root.searchResults[root.selectedIndex];
            if (item && item.type === "app")
                root.toggleFavorite(item);
        } else {
            const entry = root.allApplications[root.selectedIndex];
            if (entry)
                root.toggleFavorite(entry);
        }
    }

    width: root.anchorWindow && root.anchorWindow.screen
        ? Math.max(320, Math.min(root.maxWidth, root.anchorWindow.screen.width - 24))
        : root.maxWidth
    height: root.anchorWindow && root.anchorWindow.screen
        ? Math.max(320, Math.min(
            root.maxHeight,
            root.anchorWindow.screen.height - root.anchorWindow.height
        ))
        : root.maxHeight

    color: "transparent"
    visible: false

    // Use a native popup like the other modules. Its focus grab dismisses it
    // on outside click without creating a full-screen input surface.
    anchor.window: root.anchorWindow
    anchor.rect.x: root.anchorWindow ? Math.round((root.anchorWindow.width - root.width) / 2) : root.outerMargin
    anchor.rect.y: root.anchorWindow ? root.anchorWindow.height : 34
    grabFocus: true

    function openPanel() {
        if (root.visible) {
            Qt.callLater(function() { searchInput.forceActiveFocus(); });
            return;
        }

        root.launchError = "";
        root.selectedIndex = 0;
        root.categoryFilter = [];
        root.applyingQuickSearch = false;
        searchInput.text = "";
        root.searchQuery = "";
        root.visible = true;
        root.startFileIndex();

        Qt.callLater(function() {
            if (!root.visible)
                return;
            searchInput.forceActiveFocus();
            searchInput.cursorPosition = searchInput.text.length;
        });
    }

    function closePanel() {
        if (!root.visible)
            return;

        root.visible = false;
        searchInput.text = "";
        root.searchQuery = "";
        root.categoryFilter = [];
        root.selectedIndex = 0;
        root.launchError = "";
        root.commandConfirmationRequired = false;
    }

    function togglePanel() {
        if (root.visible)
            root.closePanel();
        else
            root.openPanel();
    }

    onVisibleChanged: {
        if (root.visible) {
            Qt.callLater(function() {
                if (root.visible) {
                    searchInput.forceActiveFocus();
                    searchInput.cursorPosition = searchInput.text.length;
                }
            });
        } else {
            // PopupWindow.grabFocus can hide the window directly on outside
            // click, without calling closePanel(). Keep both close paths equal.
            searchInput.text = "";
            root.searchQuery = "";
            root.categoryFilter = [];
            root.selectedIndex = 0;
            root.launchError = "";
            root.applyingQuickSearch = false;
            root.commandConfirmationRequired = false;
        }
    }

    onSearchQueryChanged: {
        root.selectedIndex = 0;
        root.launchError = "";
    }

    onWallpaperFilterTextChanged: {
        if (wallpaperSelectorLoader.item)
            wallpaperSelectorLoader.item.filterText = root.wallpaperFilterText;
    }

    onSearchResultsChanged: {
        if (root.searchResults.length === 0)
            root.selectedIndex = 0;
        else
            root.selectedIndex = Math.min(root.selectedIndex, root.searchResults.length - 1);
    }

    ScriptModel {
        id: allApplicationsModel
        objectProp: "id"
        values: root.allApplications
    }

    ScriptModel {
        id: topApplicationsModel
        objectProp: "id"
        values: root.topApplications
    }

    ScriptModel {
        id: filteredApplicationsModel
        objectProp: "id"
        values: root.searchResults
    }

    FileView {
        id: launcherStateFile
        path: Quickshell.statePath("app-launcher.json")
        printErrors: false
        watchChanges: false
        onLoaded: root.restorePersistentState()
        onLoadFailed: root.persistentStateReady = true
        onSaveFailed: function(error) {
            console.warn("AppLauncher: persistent state write failed:", error);
        }
    }

    Process {
        id: fileIndexProcess
        command: root.fileIndexCommand
        stdout: StdioCollector {
            onStreamFinished: root.parseFileIndex(this.text)
        }
        onExited: function(exitCode, exitStatus) {
            // Missing or unreadable optional directories can make find return nonzero.
            // Keep the index usable and end the loading state regardless.
            if (!root.fileIndexReady) {
                root.fileIndexUpdatedAt = Date.now();
                root.fileIndexReady = true;
            }
        }
    }

    Shortcut {
        id: dismissShortcut
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.visible
        onActivated: root.closePanel()
    }

    readonly property var categoryAccents: [Theme.iris, Theme.foam, Theme.subtle, Theme.rose, Theme.gold, Theme.love]
    readonly property int allAppsColumns: allAppsGrid.width >= 700 ? 6 : (allAppsGrid.width >= 460 ? 4 : 3)

    // Tile shared by the quick picks and the full grid: icon over name.
    component AppTile: Item {
        id: tile

        required property var appData
        property bool selected: false
        property int iconSize: 40

        signal activated(var mouse)
        signal hoverStarted()

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusTile + 2
            color: tile.selected
                ? Theme.tint(Theme.iris, 0.22)
                : (tileMouse.containsMouse ? Theme.surface : "transparent")
            scale: tileMouse.pressed ? 0.95 : 1

            Behavior on color {
                ColorAnimation { duration: Theme.fast }
            }

            Behavior on scale {
                NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic }
            }
        }

        Icon {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.top: parent.top
            anchors.topMargin: 6
            visible: tile.appData.type !== "file" && tile.appData.type !== "directory"
                && root.favoriteIds.indexOf(tile.appData.id) >= 0
            text: Theme.icons.star
            color: Theme.gold
            font.pixelSize: 13
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - 12
            spacing: 6

            IconImage {
                anchors.horizontalCenter: parent.horizontalCenter
                width: tile.iconSize
                height: tile.iconSize
                source: Quickshell.iconPath(
                    tile.appData.icon || "application-x-executable",
                    "application-x-executable"
                )
                asynchronous: true
                scale: tileMouse.containsMouse || tile.selected ? 1.1 : 1

                Behavior on scale {
                    NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack }
                }
            }

            UiText {
                width: parent.width
                text: tile.appData.name || tile.appData.id
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        MouseArea {
            id: tileMouse
            z: 10
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            onEntered: tile.hoverStarted()
            onClicked: function(mouse) { tile.activated(mouse); }
        }
    }

    PanelSurface {
        id: outerSurface
        window: root
        accent: Theme.iris
        padding: 16

        Rectangle {
            id: searchBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 52
            radius: 20
            color: Theme.surface
            border.width: 1
            border.color: searchInput.activeFocus ? Theme.tint(Theme.iris, 0.5) : Theme.stroke

            Rectangle {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                radius: 13
                gradient: Theme.dusk

                Icon {
                    anchors.centerIn: parent
                    text: root.queryMode === "command"
                        ? ">"
                        : (root.queryMode === "web" ? "?" : Theme.icons.search)
                    color: Theme.onAccent
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
            }

            UiText {
                anchors.left: searchInput.left
                anchors.right: searchInput.right
                anchors.verticalCenter: searchInput.verticalCenter
                text: "Search apps, files, wall, calculations, web (? ...) or commands (> ...)"
                color: Theme.muted
                font.pixelSize: 15
                font.weight: Font.Normal
                elide: Text.ElideRight
                visible: searchInput.text.length === 0
            }

            TextInput {
                id: searchInput
                anchors.left: searchIcon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                color: Theme.text
                selectionColor: Theme.iris
                selectedTextColor: Theme.onAccent
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: Font.Medium
                verticalAlignment: TextInput.AlignVCenter
                focus: root.visible
                activeFocusOnTab: true
                selectByMouse: true
                clip: true
    
                onTextChanged: {
                    // Editing the query cancels any pending destructive-command confirmation.
                    // A pending command must never run after the user changes the input.
                    if (root.commandConfirmationRequired) {
                        root.commandConfirmationRequired = false;
                        root.pendingCommandArgs = [];
                        root.pendingCommandText = "";
                    }
                    root.searchQuery = text;
                    root.selectedIndex = 0;
                    root.launchError = "";
                    if (!root.applyingQuickSearch)
                        root.categoryFilter = [];
                }
    
                Keys.onPressed: function(event) {
                    if (root.commandConfirmationRequired
                        && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                        root.executePendingCommand();
                        event.accepted = true;
                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_D) {
                        root.toggleSelectedFavorite();
                        event.accepted = true;
                    } else if ((event.modifiers & Qt.ControlModifier)
                        && (event.modifiers & Qt.ShiftModifier)
                        && event.key === Qt.Key_Delete) {
                        root.clearHistory();
                        event.accepted = true;
                    } else if ((event.modifiers & Qt.ControlModifier)
                        && root.searchQuery.trim().length === 0
                        && event.key >= Qt.Key_1 && event.key <= Qt.Key_6) {
                        root.launchTopApplication(event.key - Qt.Key_1);
                        event.accepted = true;
                    } else if ((event.modifiers & Qt.ShiftModifier)
                        && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && root.selectedDirectory) {
                        root.openDirectory(root.selectedDirectory, "thunar");
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.wallpaperMode && wallpaperSelectorLoader.item)
                            wallpaperSelectorLoader.item.applySelected();
                        else if (root.searchQuery.trim().length > 0)
                            root.launchResult(root.searchResults[root.selectedIndex]);
                        else
                            root.launchApplication(root.allApplications[root.selectedIndex]);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                        if (root.wallpaperMode && wallpaperSelectorLoader.item)
                            wallpaperSelectorLoader.item.moveSelection(wallpaperSelectorLoader.item.columns);
                        else {
                            const step = root.searchQuery.trim().length > 0
                                ? 1
                                : root.allAppsColumns;
                            root.moveSelection(step);
                        }
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                        if (root.wallpaperMode && wallpaperSelectorLoader.item)
                            wallpaperSelectorLoader.item.moveSelection(-wallpaperSelectorLoader.item.columns);
                        else {
                            const step = root.searchQuery.trim().length > 0
                                ? 1
                                : root.allAppsColumns;
                            root.moveSelection(-step);
                        }
                        event.accepted = true;
                    } else if (root.wallpaperMode && event.key === Qt.Key_Right) {
                        if (wallpaperSelectorLoader.item)
                            wallpaperSelectorLoader.item.moveSelection(1);
                        event.accepted = true;
                    } else if (root.wallpaperMode && event.key === Qt.Key_Left) {
                        if (wallpaperSelectorLoader.item)
                            wallpaperSelectorLoader.item.moveSelection(-1);
                        event.accepted = true;
                    } else if (root.searchQuery.trim().length === 0 && event.key === Qt.Key_Right) {
                        root.moveSelection(1);
                        event.accepted = true;
                    } else if (root.searchQuery.trim().length === 0 && event.key === Qt.Key_Left) {
                        root.moveSelection(-1);
                        event.accepted = true;
                    }
                }
            }

            MouseArea {
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                z: 10
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 46
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                onClicked: searchInput.forceActiveFocus()
            }
        }

        Item {
            id: mainContent
            anchors.top: searchBar.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 14
            clip: true

            Item {
                id: defaultHome
                anchors.fill: parent
                visible: root.searchQuery.trim().length === 0 && root.launchError.length === 0

                // Rail: library summary, categories and shortcuts.
                Rectangle {
                    id: categoryRail
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 208
                    radius: 20
                    color: Theme.surface

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 4

                        Item {
                            width: parent.width
                            height: 56

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter

                                UiText {
                                    text: "Applications"
                                    font.family: Theme.displayFont
                                    font.pixelSize: 20
                                    font.weight: Font.Bold
                                }

                                UiText {
                                    text: root.allApplications.length + " installed"
                                    color: Theme.subtle
                                    font.pixelSize: 11
                                }
                            }
                        }

                        Repeater {
                            model: root.quickSearches

                            delegate: Rectangle {
                                id: quickSearchTile
                                required property var modelData
                                required property int index
                                readonly property color tileAccent: root.categoryAccents[index % root.categoryAccents.length]

                                width: parent.width
                                height: 42
                                radius: 14
                                color: quickSearchMouse.containsMouse ? Theme.tint(tileAccent, 0.18) : "transparent"

                                Behavior on color {
                                    ColorAnimation { duration: Theme.fast }
                                }

                                Rectangle {
                                    id: quickSearchBadge
                                    x: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 30
                                    height: 30
                                    radius: 11
                                    color: Theme.tint(quickSearchTile.tileAccent, 0.18)

                                    Icon {
                                        anchors.centerIn: parent
                                        text: quickSearchTile.modelData.icon
                                        color: quickSearchTile.tileAccent
                                        font.pixelSize: 14
                                    }
                                }

                                UiText {
                                    anchors.left: quickSearchBadge.right
                                    anchors.leftMargin: 10
                                    anchors.right: quickSearchCount.left
                                    anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: quickSearchTile.modelData.label
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }

                                UiText {
                                    id: quickSearchCount
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(root.categoryApplicationCount(quickSearchTile.modelData))
                                    color: Theme.subtle
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: quickSearchMouse
                                    z: 10
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton
                                    preventStealing: true
                                    onClicked: root.applyQuickSearch(quickSearchTile.modelData)
                                }
                            }
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 16
                        spacing: 5

                        Repeater {
                            model: [
                                { key: "↑ ↓ ← → Tab", action: "Navigate" },
                                { key: "Enter", action: "Launch" },
                                { key: "Ctrl 1–6", action: "Quick pick" },
                                { key: "Ctrl D", action: "Favorite" },
                                { key: "Esc", action: "Close" }
                            ]

                            delegate: Item {
                                required property var modelData
                                width: parent.width
                                height: 18

                                UiText {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.modelData.action
                                    color: Theme.subtle
                                    font.pixelSize: 10
                                }

                                UiText {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.modelData.key
                                    color: Theme.muted
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }

                UiText {
                    id: quickLaunchHeading
                    anchors.left: categoryRail.right
                    anchors.leftMargin: 18
                    anchors.top: parent.top
                    height: 22
                    text: "Favorites & recent"
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }

                UiText {
                    anchors.right: parent.right
                    anchors.verticalCenter: quickLaunchHeading.verticalCenter
                    text: "Ctrl+Shift+Del clears history"
                    color: Theme.muted
                    font.pixelSize: 10
                }

                GridView {
                    id: topAppsGrid
                    anchors.top: quickLaunchHeading.bottom
                    anchors.left: quickLaunchHeading.left
                    anchors.right: parent.right
                    anchors.topMargin: 6
                    height: cellHeight * Math.ceil(root.topApplications.length / 6)
                    clip: true
                    cellWidth: width / 6
                    cellHeight: 100
                    model: topApplicationsModel
                    interactive: false
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: topAppTile
                        required property var modelData
                        required property int index

                        width: topAppsGrid.cellWidth
                        height: topAppsGrid.cellHeight

                        AppTile {
                            anchors.fill: parent
                            anchors.margins: 3
                            appData: topAppTile.modelData
                            iconSize: 44
                            onActivated: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    if (topAppTile.modelData.type === "app")
                                        root.toggleFavorite(topAppTile.modelData);
                                    else
                                        root.removeHistoryItem(topAppTile.modelData);
                                } else {
                                    root.launchResult(topAppTile.modelData);
                                }
                            }
                        }
                    }
                }

                UiText {
                    id: allApplicationsHeading
                    anchors.left: quickLaunchHeading.left
                    anchors.top: topAppsGrid.bottom
                    anchors.topMargin: 8
                    height: 22
                    text: "All applications"
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }

                GridView {
                    id: allAppsGrid
                    anchors.top: allApplicationsHeading.bottom
                    anchors.left: quickLaunchHeading.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 6
                    clip: true
                    cellWidth: width / root.allAppsColumns
                    cellHeight: 92
                    model: allApplicationsModel
                    currentIndex: root.selectedIndex
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: allAppTile
                        required property var modelData
                        required property int index

                        width: allAppsGrid.cellWidth
                        height: allAppsGrid.cellHeight

                        AppTile {
                            anchors.fill: parent
                            anchors.margins: 3
                            appData: allAppTile.modelData
                            iconSize: 38
                            selected: allAppTile.index === root.selectedIndex
                            onHoverStarted: root.selectedIndex = allAppTile.index
                            onActivated: function(mouse) {
                                root.selectedIndex = allAppTile.index;
                                if (mouse.button === Qt.RightButton)
                                    root.toggleFavorite(allAppTile.modelData);
                                else
                                    root.launchApplication(allAppTile.modelData);
                            }
                        }
                    }
                }
            }

            Item {
                id: resultsHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 24
                visible: root.searchQuery.trim().length > 0 && !root.wallpaperMode && root.launchError.length === 0

                UiText {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search results"
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }

                UiText {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.searchResults.length + (root.searchResults.length === 1 ? " result" : " results")
                    color: Theme.subtle
                    font.pixelSize: 11
                }
            }

            ListView {
                id: resultsList
                anchors.top: resultsHeader.bottom
                anchors.topMargin: 8
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                visible: root.searchQuery.trim().length > 0
                    && !root.wallpaperMode
                    && root.searchResults.length > 0
                    && root.launchError.length === 0
                clip: true
                spacing: 4
                model: filteredApplicationsModel
                currentIndex: root.selectedIndex
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: resultRow
                    required property var modelData
                    required property int index
                    onModelDataChanged: if (specialModeIcon) specialModeIcon.requestPaint()

                    readonly property bool isSelected: index === root.selectedIndex

                    width: resultsList.width
                    height: 62

                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: resultRow.isSelected
                            ? Theme.tint(Theme.iris, 0.2)
                            : (resultMouse.containsMouse ? Theme.surface : "transparent")

                        Behavior on color {
                            ColorAnimation { duration: Theme.fast }
                        }
                    }

                    // Command and web modes use a small vector icon drawn here,
                    // rather than desktop-theme icons that may resolve to a missing-icon tile.
                    IconImage {
                        id: resultIcon
                        width: 34
                        height: 34
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: resultRow.modelData.type === "app"
                        source: Quickshell.iconPath(
                            resultRow.modelData.icon || "application-x-executable",
                            "application-x-executable"
                        )
                        asynchronous: true
                    }

                            Canvas {
                                id: specialModeIcon
                                width: 30
                                height: 30
                                anchors.left: resultIcon.left
                                anchors.verticalCenter: parent.verticalCenter
                                visible: resultRow.modelData.type !== "app"
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    ctx.strokeStyle = Theme.iris.toString();
                                    ctx.fillStyle = Theme.iris.toString();
                                    ctx.lineWidth = 1.7;
                                    ctx.lineCap = "round";
                                    ctx.lineJoin = "round";
            
                                    if (resultRow.modelData.type === "command") {
                                        // Terminal window, prompt chevron and cursor.
                                        ctx.strokeRect(3.5, 4.5, 23, 21);
                                        ctx.beginPath();
                                        ctx.moveTo(8, 10);
                                        ctx.lineTo(12, 13.5);
                                        ctx.lineTo(8, 17);
                                        ctx.moveTo(14.5, 17);
                                        ctx.lineTo(20, 17);
                                        ctx.stroke();
                                    } else if (resultRow.modelData.type === "calculator") {
                                        // Calculator outline, display and four clear key marks.
                                        ctx.strokeRect(6.5, 2.5, 17, 25);
                                        ctx.strokeRect(9.5, 5.5, 11, 5);
                                        ctx.beginPath();
                                        ctx.moveTo(10, 14);
                                        ctx.lineTo(12, 14);
                                        ctx.moveTo(17, 14);
                                        ctx.lineTo(19, 14);
                                        ctx.moveTo(10, 18);
                                        ctx.lineTo(12, 18);
                                        ctx.moveTo(17, 18);
                                        ctx.lineTo(19, 18);
                                        ctx.moveTo(10, 22);
                                        ctx.lineTo(12, 22);
                                        ctx.moveTo(17, 22);
                                        ctx.lineTo(19, 22);
                                        ctx.stroke();
                                    } else if (resultRow.modelData.type === "web") {
                                        // Magnifying glass for web and GitHub search.
                                        ctx.beginPath();
                                        ctx.arc(12, 12, 7, 0, Math.PI * 2);
                                        ctx.moveTo(17.2, 17.2);
                                        ctx.lineTo(23.5, 23.5);
                                        ctx.stroke();
                                    } else if (resultRow.modelData.type === "directory"
                                            || root.fileIconKind(resultRow.modelData) === "folder") {
                                        // Folder with a top tab.
                                        ctx.beginPath();
                                        ctx.moveTo(3.5, 8.5);
                                        ctx.lineTo(11, 8.5);
                                        ctx.lineTo(13.5, 11.5);
                                        ctx.lineTo(26.5, 11.5);
                                        ctx.lineTo(24.5, 25.5);
                                        ctx.lineTo(4.5, 25.5);
                                        ctx.closePath();
                                        ctx.moveTo(3.5, 8.5);
                                        ctx.lineTo(5, 23.5);
                                        ctx.stroke();
                                    } else {
                                        // Folded-corner document, customized by file type.
                                        const kind = root.fileIconKind(resultRow.modelData);
                                        ctx.beginPath();
                                        ctx.moveTo(7, 3);
                                        ctx.lineTo(18, 3);
                                        ctx.lineTo(24, 9);
                                        ctx.lineTo(24, 27);
                                        ctx.lineTo(7, 27);
                                        ctx.closePath();
                                        ctx.moveTo(18, 3);
                                        ctx.lineTo(18, 9);
                                        ctx.lineTo(24, 9);
                                        ctx.stroke();
            
                                        if (kind === "image") {
                                            ctx.strokeRect(10, 13, 11, 8);
                                            ctx.beginPath();
                                            ctx.arc(18, 15.5, 1.2, 0, Math.PI * 2);
                                            ctx.moveTo(11, 20);
                                            ctx.lineTo(14.5, 16.5);
                                            ctx.lineTo(17, 19);
                                            ctx.lineTo(19, 17.5);
                                            ctx.lineTo(21, 20);
                                            ctx.stroke();
                                        } else if (kind === "pdf") {
                                            ctx.font = "bold 6px sans-serif";
                                            ctx.fillText("PDF", 9, 19);
                                            ctx.beginPath();
                                            ctx.moveTo(10, 22);
                                            ctx.lineTo(21, 22);
                                            ctx.stroke();
                                        } else if (kind === "code") {
                                            ctx.beginPath();
                                            ctx.moveTo(13, 14);
                                            ctx.lineTo(10, 17);
                                            ctx.lineTo(13, 20);
                                            ctx.moveTo(18, 14);
                                            ctx.lineTo(21, 17);
                                            ctx.lineTo(18, 20);
                                            ctx.stroke();
                                        } else if (kind === "archive") {
                                            ctx.strokeRect(10, 13, 11, 9);
                                            ctx.beginPath();
                                            ctx.moveTo(15.5, 13);
                                            ctx.lineTo(15.5, 22);
                                            ctx.moveTo(14, 15);
                                            ctx.lineTo(17, 15);
                                            ctx.moveTo(14, 18);
                                            ctx.lineTo(17, 18);
                                            ctx.stroke();
                                        } else if (kind === "audio") {
                                            ctx.beginPath();
                                            ctx.moveTo(12, 20);
                                            ctx.lineTo(12, 14);
                                            ctx.lineTo(20, 12);
                                            ctx.lineTo(20, 19);
                                            ctx.stroke();
                                            ctx.beginPath();
                                            ctx.arc(10.5, 21, 2.5, 0, Math.PI * 2);
                                            ctx.arc(18.5, 19.5, 2.5, 0, Math.PI * 2);
                                            ctx.stroke();
                                        } else if (kind === "video") {
                                            ctx.strokeRect(10, 13, 11, 8);
                                            ctx.beginPath();
                                            ctx.moveTo(14, 15);
                                            ctx.lineTo(18, 17);
                                            ctx.lineTo(14, 19);
                                            ctx.closePath();
                                            ctx.stroke();
                                        } else if (kind === "spreadsheet") {
                                            ctx.strokeRect(10, 13, 11, 9);
                                            ctx.beginPath();
                                            ctx.moveTo(10, 16);
                                            ctx.lineTo(21, 16);
                                            ctx.moveTo(10, 19);
                                            ctx.lineTo(21, 19);
                                            ctx.moveTo(15.5, 13);
                                            ctx.lineTo(15.5, 22);
                                            ctx.stroke();
                                        } else if (kind === "presentation") {
                                            ctx.strokeRect(10, 13, 11, 7);
                                            ctx.beginPath();
                                            ctx.moveTo(15.5, 20);
                                            ctx.lineTo(15.5, 23);
                                            ctx.moveTo(12, 23);
                                            ctx.lineTo(19, 23);
                                            ctx.stroke();
                                        } else if (kind === "font") {
                                            ctx.font = "bold 10px sans-serif";
                                            ctx.fillText("Aa", 10, 20);
                                        } else if (kind === "executable") {
                                            ctx.beginPath();
                                            ctx.moveTo(12, 13);
                                            ctx.lineTo(12, 21);
                                            ctx.lineTo(19, 17);
                                            ctx.closePath();
                                            ctx.stroke();
                                        } else {
                                            // Generic document and text: content lines.
                                            ctx.beginPath();
                                            ctx.moveTo(10, 14);
                                            ctx.lineTo(21, 14);
                                            ctx.moveTo(10, 17.5);
                                            ctx.lineTo(21, 17.5);
                                            ctx.moveTo(10, 21);
                                            ctx.lineTo(19, 21);
                                            ctx.stroke();
                                        }
                                    }
                                }
                                onVisibleChanged: if (visible) requestPaint()
                                Component.onCompleted: requestPaint()
                            }

                    Column {
                        anchors.left: resultIcon.right
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: resultRow.modelData.type === "app"
                            ? 48
                            : (directoryOpeners.visible ? directoryOpeners.width + 28 : 14)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        UiText {
                            width: parent.width
                            text: resultRow.modelData.name || resultRow.modelData.id
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        UiText {
                            width: parent.width
                            text: resultRow.modelData.details || resultRow.modelData.genericName
                                || resultRow.modelData.comment || String((resultRow.modelData.categories || [])[0] || "Application")
                            color: Theme.subtle
                            font.pixelSize: 12
                            font.weight: Font.Normal
                            elide: Text.ElideRight
                        }
                    }

                    // Folder rows show both ways to open them while selected.
                    Row {
                        id: directoryOpeners
                        z: 11
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: resultRow.isSelected && resultRow.modelData.type === "directory"
                        spacing: 6

                        Repeater {
                            model: [
                                { label: "Code", hint: "Enter", command: "code" },
                                { label: "Thunar", hint: "Shift Enter", command: "thunar" }
                            ]

                            delegate: Rectangle {
                                id: openerChip
                                required property var modelData
                                width: openerContent.implicitWidth + 20
                                height: 30
                                radius: height / 2
                                color: openerMouse.containsMouse ? Theme.hover : Theme.raised

                                Behavior on color {
                                    ColorAnimation { duration: Theme.fast }
                                }

                                Row {
                                    id: openerContent
                                    anchors.centerIn: parent
                                    spacing: 6

                                    UiText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: openerChip.modelData.label
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }

                                    UiText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: openerChip.modelData.hint
                                        color: Theme.muted
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: openerMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openDirectory(resultRow.modelData, openerChip.modelData.command)
                                }
                            }
                        }
                    }

                    Icon {
                        id: resultFavoriteIcon
                        z: 11
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        visible: resultRow.modelData.type === "app"
                        readonly property bool isFavorite: visible && root.favoriteIds.indexOf(resultRow.modelData.id) >= 0
                        text: isFavorite ? Theme.icons.star : Theme.icons.starOutline
                        color: isFavorite ? Theme.gold : Theme.muted
                        font.pixelSize: 18

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -5
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleFavorite(resultRow.modelData)
                        }
                    }

                    MouseArea {
                        id: resultMouse
                        z: 10
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        preventStealing: true
                        onEntered: root.selectedIndex = resultRow.index
                        onClicked: function(mouse) {
                            root.selectedIndex = resultRow.index;
                            if (mouse.button === Qt.RightButton) {
                                if (resultRow.modelData.type === "app")
                                    root.toggleFavorite(resultRow.modelData);
                                else
                                    root.removeHistoryItem(resultRow.modelData);
                            } else {
                                root.launchResult(resultRow.modelData);
                            }
                        }
                    }
                }
            }

            Loader {
                id: wallpaperSelectorLoader
                anchors.fill: parent
                z: 30
                active: root.wallpaperMode
                visible: active
                source: "WallpaperSelector.qml"

                onLoaded: {
                    if (item)
                        item.filterText = root.wallpaperFilterText;
                }
            }

            Connections {
                target: wallpaperSelectorLoader.item
                function onWallpaperApplied(path) {
                    root.closePanel();
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 6
                visible: root.searchQuery.trim().length > 0
                    && !root.wallpaperMode
                    && root.searchResults.length === 0
                    && root.launchError.length === 0

                UiText {
                    width: mainContent.width - 40
                    text: "No results found"
                    font.family: Theme.displayFont
                    font.pixelSize: 20
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                }

                UiText {
                    width: mainContent.width - 40
                    text: root.fileIndexReady ? "Try another search or use ? for web, > for commands." : "Applications are ready; file indexing is still running."
                    color: Theme.subtle
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 6
                visible: root.searchQuery.trim().length === 0
                    && root.allApplications.length === 0
                    && root.launchError.length === 0

                UiText {
                    width: mainContent.width - 40
                    text: "No applications found"
                    font.family: Theme.displayFont
                    font.pixelSize: 20
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                }

                UiText {
                    width: mainContent.width - 40
                    text: "Installed desktop entries will appear here."
                    color: Theme.subtle
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            UiText {
                anchors.centerIn: parent
                visible: root.launchError.length > 0
                text: root.launchError
                color: Theme.love
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                width: Math.min(parent.width - 40, 420)
            }
        }

        Item {
            id: commandConfirmationOverlay
            anchors.fill: parent
            anchors.margins: -outerSurface.padding
            visible: root.visible && root.commandConfirmationRequired
            z: 1000

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusCard
                color: Theme.tint(Theme.base, 0.82)
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: {}
                }
            }

            Rectangle {
                width: Math.min(parent.width - 36, 480)
                height: 204
                anchors.centerIn: parent
                radius: Theme.radiusCard
                color: Theme.surface
                border.width: 1
                border.color: Theme.tint(Theme.love, 0.5)

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 10

                    UiText {
                        width: parent.width
                        text: "Confirm command"
                        font.family: Theme.displayFont
                        font.pixelSize: 20
                        font.weight: Font.Bold
                    }

                    UiText {
                        width: parent.width
                        text: "This command may modify system files, require privileges, or stop services. Continue only if you understand its effect."
                        color: Theme.subtle
                        font.pixelSize: 12
                        font.weight: Font.Normal
                        wrapMode: Text.Wrap
                    }

                    UiText {
                        width: parent.width
                        text: root.pendingCommandText
                        color: Theme.love
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8

                        SoftButton {
                            implicitHeight: 36
                            label: "Cancel"
                            onClicked: {
                                root.commandConfirmationRequired = false;
                                searchInput.forceActiveFocus();
                            }
                        }

                        SoftButton {
                            implicitHeight: 36
                            label: "Run in Kitty"
                            variant: "accent"
                            accent: Theme.love
                            onClicked: root.executePendingCommand()
                        }
                    }
                }
            }
        }
    }
}
