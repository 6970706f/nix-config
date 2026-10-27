import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import QtQuick
import QtQuick.Controls

PopupWindow {
    id: root

    property var anchorWindow: null

    readonly property color panelColor: "#000000"
    readonly property color foregroundColor: "#ffffff"
    readonly property color mutedColor: "#b8b8b8"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    readonly property int maxWidth: 1080
    readonly property int maxHeight: 780
    readonly property int outerMargin: 12
    readonly property int topGap: 8

    property string searchQuery: ""
    property int selectedIndex: 0
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
    property string searchEngineTemplate: "https://duckduckgo.com/?q=%s"
    readonly property string homeDirectory: String(Quickshell.env("HOME") || "")
    // Indexa apenas diretórios visíveis e úteis. Não varre a HOME inteira,
    // nem pastas ocultas; cada raiz tem um limite de resultados para evitar
    // travamentos em bibliotecas grandes.
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

        // O script é constante; diretórios são passados como argumentos separados
        // (sem interpolação em shell). head limita a saída por pasta a 120 itens.
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
                        ? "SYSTEM ACTION · Enter executes directly, without a terminal or shell"
                        : "COMMAND · Enter runs in Kitty without a shell")
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
                details: "WEB SEARCH · Enter opens the default browser",
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
                details: "GITHUB SEARCH · Enter opens github.com",
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
                details: "CALCULATOR RESULT · Enter copies the result",
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

    // Classifica arquivos para desenhar ícones vetoriais no próprio QML.
    // Assim os resultados de arquivos não dependem de ícones opcionais do tema.
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
            root.commandConfirmationRequired = false;
            root.closePanel();
        } catch (error) {
            console.error("AppLauncher: command launch failed:", error);
            root.launchError = "Unable to launch this command or action. Check the Quickshell log.";
        }
    }

    function buildSearchUrl(terms) {
        const encoded = encodeURIComponent(String(terms || "").trim());
        const template = root.searchEngineTemplate || "https://duckduckgo.com/?q=%s";
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

    function launchResult(item) {
        if (!item)
            return;
        if (item.type === "app") {
            root.launchApplication(item.entry);
        } else if (item.type === "file" || item.type === "directory") {
            try {
                Quickshell.execDetached({ command: ["xdg-open", String(item.path)] });
                root.recordHistory(item.type === "directory" ? "directory" : "file", item);
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
            root.anchorWindow.screen.height - root.anchorWindow.height - root.topGap - root.outerMargin
        ))
        : root.maxHeight

    color: "transparent"
    visible: false

    // Use a native popup like the other modules. Its focus grab dismisses it
    // on outside click without creating a full-screen input surface.
    anchor.window: root.anchorWindow
    anchor.rect.x: root.outerMargin
    anchor.rect.y: root.anchorWindow ? root.anchorWindow.height + root.topGap : 34
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

    Rectangle {
        id: outerSurface
        anchors.fill: parent
        color: root.panelColor
        border.width: 1
        border.color: "#ffffff"
        radius: 0
    }

    Rectangle {
        id: searchBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 14
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        height: 42
        color: "#080808"
        border.width: 1
        border.color: "#505050"
        radius: 0

        Text {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: root.mutedColor
            font.family: root.fontFamily
            font.pixelSize: 15
        }

        TextInput {
            id: searchInput
            anchors.left: searchIcon.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: root.foregroundColor
            selectionColor: "#ffffff"
            selectedTextColor: "#000000"
            font.family: root.fontFamily
            font.pixelSize: 13
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
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.searchQuery.trim().length > 0)
                        root.launchResult(root.searchResults[root.selectedIndex]);
                    else
                        root.launchApplication(root.allApplications[root.selectedIndex]);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    const step = root.searchQuery.trim().length > 0
                        ? 1
                        : (allAppsGrid.width >= 850 ? 5 : (allAppsGrid.width >= 560 ? 3 : 2));
                    root.moveSelection(step);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    const step = root.searchQuery.trim().length > 0
                        ? 1
                        : (allAppsGrid.width >= 850 ? 5 : (allAppsGrid.width >= 560 ? 3 : 2));
                    root.moveSelection(-step);
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

        Text {
            z: -1
            anchors.left: searchInput.left
            anchors.right: searchInput.right
            anchors.verticalCenter: searchInput.verticalCenter
            text: "Search apps, files, calculations, web (? ...) or commands (> ...)"
            color: "#808080"
            font.family: root.fontFamily
            font.pixelSize: 13
            visible: searchInput.text.length === 0
        }

        MouseArea {
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            z: 10
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 36
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
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        clip: true

        Item {
            id: defaultHome
            anchors.fill: parent
            visible: root.searchQuery.trim().length === 0 && root.launchError.length === 0

            Item {
                id: launcherHeader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 36

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        text: "APP LAUNCHER"
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        font.letterSpacing: 1.0
                    }

                    Text {
                        text: root.allApplications.length + " INSTALLED APPLICATIONS  /  " + root.topApplications.length + " QUICK PICKS"
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 9
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    visible: mainContent.width > 560

                    Repeater {
                        model: ["↑ ↓  NAVIGATE", "↵  LAUNCH", "ESC  CLOSE"]

                        delegate: Rectangle {
                            required property string modelData
                            width: hintText.implicitWidth + 14
                            height: 22
                            color: "#080808"
                            border.width: 1
                            border.color: "#363636"

                            Text {
                                id: hintText
                                anchors.centerIn: parent
                                text: modelData
                                color: root.mutedColor
                                font.family: root.fontFamily
                                font.pixelSize: 8
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: headerDivider
                anchors.top: launcherHeader.bottom
                anchors.topMargin: 9
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: "#343434"
            }

            Item {
                id: categoriesHeadingRow
                anchors.top: headerDivider.bottom
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.right: parent.right
                height: 14

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CATEGORIES"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0.8
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "FILTER THE LIBRARY"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 8
                }
            }

            Item {
                id: quickSearchArea
                anchors.top: categoriesHeadingRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 8
                height: quickSearchGrid.columns >= 6 ? 36 : 74

                Grid {
                    id: quickSearchGrid
                    anchors.fill: parent
                    columns: quickSearchArea.width >= 750 ? 6 : (quickSearchArea.width >= 400 ? 3 : 2)
                    spacing: 6

                    Repeater {
                        model: root.quickSearches

                        delegate: Item {
                            id: quickSearchTile
                            required property var modelData
                            required property int index

                            width: Math.floor((quickSearchArea.width - (quickSearchGrid.columns - 1) * quickSearchGrid.spacing) / quickSearchGrid.columns)
                            height: 34

                            Rectangle {
                                anchors.fill: parent
                                color: quickSearchMouse.containsMouse ? "#181818" : "#080808"
                                border.width: 1
                                border.color: quickSearchMouse.containsMouse ? "#666666" : "#363636"
                            }

                            Text {
                                id: quickSearchIcon
                                anchors.left: parent.left
                                anchors.leftMargin: 9
                                anchors.verticalCenter: parent.verticalCenter
                                text: quickSearchTile.modelData.icon
                                color: root.mutedColor
                                font.family: root.fontFamily
                                font.pixelSize: 12
                            }

                            Text {
                                id: quickSearchLabel
                                anchors.left: quickSearchIcon.right
                                anchors.leftMargin: 7
                                anchors.right: quickSearchCount.left
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                text: quickSearchTile.modelData.label
                                color: root.foregroundColor
                                font.family: root.fontFamily
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }

                            Text {
                                id: quickSearchCount
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(root.categoryApplicationCount(quickSearchTile.modelData))
                                color: root.mutedColor
                                font.family: root.fontFamily
                                font.pixelSize: 8
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
            }

            Item {
                id: quickLaunchHeadingRow
                anchors.top: quickSearchArea.bottom
                anchors.topMargin: 13
                anchors.left: parent.left
                anchors.right: parent.right
                height: 14

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "FAVORITES & RECENT"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0.8
                }

                Text {
                    id: quickLaunchHint
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CTRL+1–6 LAUNCH  ·  CTRL+SHIFT+DEL CLEARS HISTORY"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 8
                    visible: mainContent.width > 560
                }
            }

            GridView {
                id: topAppsGrid
                anchors.top: quickLaunchHeadingRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 8
                height: cellHeight * Math.ceil(root.topApplications.length / (width >= 750 ? 6 : 3))
                clip: true
                cellWidth: width / (width >= 750 ? 6 : 3)
                cellHeight: 88
                model: topApplicationsModel
                interactive: false
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: topAppTile
                    required property var modelData
                    required property int index

                    width: topAppsGrid.cellWidth - 7
                    height: topAppsGrid.cellHeight - 7

                    Rectangle {
                        anchors.fill: parent
                        color: topAppMouse.containsMouse ? "#171717" : "#070707"
                        border.width: 1
                        border.color: topAppMouse.containsMouse ? "#727272" : "#343434"
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 7
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        text: topAppTile.modelData.type === "app"
                            && root.favoriteIds.indexOf(topAppTile.modelData.id) >= 0 ? "★" : ""
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 11
                    }

                    IconImage {
                        id: topAppIcon
                        width: 27
                        height: 27
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        source: Quickshell.iconPath(
                            topAppTile.modelData.icon || "application-x-executable",
                            "application-x-executable"
                        )
                        asynchronous: true
                    }

                    Column {
                        anchors.left: topAppIcon.right
                        anchors.leftMargin: 9
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            width: parent.width
                            text: topAppTile.modelData.name || topAppTile.modelData.id
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: String((topAppTile.modelData.categories || [])[0] || "Application").toUpperCase()
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 7
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: topAppMouse
                        z: 10
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        preventStealing: true
                        onClicked: function(mouse) {
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

            Item {
                id: allApplicationsHeadingRow
                anchors.top: topAppsGrid.bottom
                anchors.topMargin: 11
                anchors.left: parent.left
                anchors.right: parent.right
                height: 14

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "INSTALLED APPLICATIONS"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0.8
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.allApplications.length + " APPS  ·  A–Z"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 8
                }
            }

            GridView {
                id: allAppsGrid
                anchors.top: allApplicationsHeadingRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.topMargin: 7
                clip: true
                cellWidth: width / (width >= 850 ? 5 : (width >= 560 ? 3 : 2))
                cellHeight: 69
                model: allApplicationsModel
                currentIndex: root.selectedIndex
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: allAppTile
                    required property var modelData
                    required property int index

                    width: allAppsGrid.cellWidth - 7
                    height: allAppsGrid.cellHeight - 6

                    Rectangle {
                        anchors.fill: parent
                        color: index === root.selectedIndex
                            ? "#171717"
                            : (allAppMouse.containsMouse ? "#111111" : "#050505")
                        border.width: 1
                        border.color: index === root.selectedIndex
                            ? "#777777"
                            : (allAppMouse.containsMouse ? "#555555" : "#282828")
                    }

                    Rectangle {
                        width: 2
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        color: "#ffffff"
                        visible: index === root.selectedIndex
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.top: parent.top
                        anchors.topMargin: 3
                        text: root.favoriteIds.indexOf(allAppTile.modelData.id) >= 0 ? "★" : ""
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 10
                    }

                    IconImage {
                        id: allAppIcon
                        width: 26
                        height: 26
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        source: Quickshell.iconPath(
                            allAppTile.modelData.icon || "application-x-executable",
                            "application-x-executable"
                        )
                        asynchronous: true
                    }

                    Column {
                        anchors.left: allAppIcon.right
                        anchors.leftMargin: 9
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            width: parent.width
                            text: allAppTile.modelData.name || allAppTile.modelData.id
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: String((allAppTile.modelData.categories || [])[0] || "Application").toUpperCase()
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: 7
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: allAppMouse
                        z: 10
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        preventStealing: true
                        onEntered: root.selectedIndex = allAppTile.index
                        onClicked: function(mouse) {
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
            height: 22
            visible: root.searchQuery.trim().length > 0 && root.launchError.length === 0

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "SEARCH RESULTS"
                color: root.foregroundColor
                font.family: root.fontFamily
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 0.8
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.searchResults.length + " RESULTS"
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: 9
            }
        }

        Rectangle {
            anchors.top: resultsHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: "#333333"
            visible: resultsHeader.visible
        }

        ListView {
            id: resultsList
            anchors.top: resultsHeader.bottom
            anchors.topMargin: 7
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            visible: root.searchQuery.trim().length > 0
                && root.searchResults.length > 0
                && root.launchError.length === 0
            clip: true
            spacing: 3
            model: filteredApplicationsModel
            currentIndex: root.selectedIndex
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: resultRow
                required property var modelData
                required property int index
                onModelDataChanged: if (specialModeIcon) specialModeIcon.requestPaint()

                width: resultsList.width
                height: 58

                Rectangle {
                    anchors.fill: parent
                    color: index === root.selectedIndex
                        ? "#171717"
                        : (resultMouse.containsMouse ? "#101010" : "#050505")
                    border.width: 1
                    border.color: index === root.selectedIndex ? "#777777" : "#292929"
                }

                Rectangle {
                    width: 2
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    color: "#ffffff"
                    visible: index === root.selectedIndex
                }

                // Command and web modes use a small vector icon drawn here,
                // rather than desktop-theme icons that may resolve to a missing-icon tile.
                IconImage {
                    id: resultIcon
                    width: 30
                    height: 30
                    anchors.left: parent.left
                    anchors.leftMargin: 12
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
                        ctx.strokeStyle = "#ffffff";
                        ctx.fillStyle = "#ffffff";
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
                            // Lupa para pesquisa na web e no GitHub.
                            ctx.beginPath();
                            ctx.arc(12, 12, 7, 0, Math.PI * 2);
                            ctx.moveTo(17.2, 17.2);
                            ctx.lineTo(23.5, 23.5);
                            ctx.stroke();
                        } else if (resultRow.modelData.type === "directory"
                                || root.fileIconKind(resultRow.modelData) === "folder") {
                            // Pasta com aba superior.
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
                            // Folha com canto dobrado, personalizada pelo tipo do arquivo.
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
                                // Documento genérico e texto: linhas de conteúdo.
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
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: resultRow.modelData.type === "app" ? 46 : 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        text: resultRow.modelData.name || resultRow.modelData.id
                        color: root.foregroundColor
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: resultRow.modelData.details || resultRow.modelData.genericName
                            || resultRow.modelData.comment || String((resultRow.modelData.categories || [])[0] || "Application")
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                Text {
                    id: resultFavoriteIcon
                    z: 11
                    anchors.right: parent.right
                    anchors.rightMargin: 13
                    anchors.verticalCenter: parent.verticalCenter
                    visible: resultRow.modelData.type === "app"
                    text: visible && root.favoriteIds.indexOf(resultRow.modelData.id) >= 0 ? "★" : "☆"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 17

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

        Column {
            anchors.centerIn: parent
            spacing: 8
            visible: root.searchQuery.trim().length > 0
                && root.searchResults.length === 0
                && root.launchError.length === 0

            Text {
                width: mainContent.width - 40
                text: "NO RESULTS FOUND"
                color: root.foregroundColor
                font.family: root.fontFamily
                font.pixelSize: 12
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: mainContent.width - 40
                text: root.fileIndexReady ? "Try another search or use ? for web, > for commands." : "Applications are ready; file indexing is still running."
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: 9
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8
            visible: root.searchQuery.trim().length === 0
                && root.allApplications.length === 0
                && root.launchError.length === 0

            Text {
                width: mainContent.width - 40
                text: "NO APPLICATIONS FOUND"
                color: root.foregroundColor
                font.family: root.fontFamily
                font.pixelSize: 12
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: mainContent.width - 40
                text: "Installed desktop entries will appear here."
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: 9
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.launchError.length > 0
            text: root.launchError
            color: root.mutedColor
            font.family: root.fontFamily
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            width: Math.min(parent.width - 40, 420)
        }
    }

    Item {
        id: commandConfirmationOverlay
        anchors.fill: parent
        visible: root.visible && root.commandConfirmationRequired
        z: 1000

        Rectangle {
            anchors.fill: parent
            color: "#c0000000"
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: {}
            }
        }

        Rectangle {
            width: Math.min(parent.width - 36, 480)
            height: 190
            anchors.centerIn: parent
            color: "#050505"
            border.width: 1
            border.color: "#ffffff"

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                Text {
                    width: parent.width
                    text: "CONFIRM COMMAND"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }

                Text {
                    width: parent.width
                    text: "This command may modify system files, require privileges, or stop services. Continue only if you understand its effect."
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                }

                Text {
                    width: parent.width
                    text: root.pendingCommandText
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8

                    Rectangle {
                        width: 108
                        height: 30
                        color: cancelMouse.containsMouse ? "#202020" : "#0b0b0b"
                        border.width: 1
                        border.color: "#555555"
                        Text {
                            anchors.centerIn: parent
                            text: "CANCEL"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 9
                        }
                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.commandConfirmationRequired = false;
                                searchInput.forceActiveFocus();
                            }
                        }
                    }

                    Rectangle {
                        width: 126
                        height: 30
                        color: confirmMouse.containsMouse ? "#292929" : "#151515"
                        border.width: 1
                        border.color: "#aaaaaa"
                        Text {
                            anchors.centerIn: parent
                            text: "RUN IN KITTY"
                            color: root.foregroundColor
                            font.family: root.fontFamily
                            font.pixelSize: 9
                        }
                        MouseArea {
                            id: confirmMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.executePendingCommand()
                        }
                    }
                }
            }
        }
    }
}
