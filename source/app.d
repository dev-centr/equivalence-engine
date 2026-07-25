import std.stdio;
import std.file;
import std.path;
import std.regex;
import std.array;
import std.getopt;
import std.algorithm;
import std.container;
import sdlang;
import std.process;
import std.uni;
import equivalence.engine;
import equivalence.path;
import equivalence.cli;

class EquivalenceCLI {
    RuleEngine engine;

    this() {
        engine = new RuleEngine();
    }

    void printSummary(string rulesDir) {
        writeln("\n=======================================================");
        writeln("              EQUIVALENCE SUMMARY");
        writeln("=======================================================");
        stdout.flush();

        if (engine.rules.length == 0) {
            writeln("No rules were loaded.");
        } else {
            if (engine.findings.length == 0) {
                writeln("SUCCESS: No manual actions required.");
            } else {
                auto keys = engine.findings.keys;
                keys.sort();
                foreach (file; keys) {
                    writeln("\nFile: ", file);
                    foreach (f; engine.findings[file]) {
                        writeln("  [", f.type, "] ", f.message);
                    }
                }
            }
        }

        writeln("\n-------------------------------------------------------");
        writeln("Ruleset Source:     ", rulesDir);
        writeln("Report Engine Bug:  https://github.com/dev-centr/equivalence-engine/issues");
        if (engine.currentRepo != "") {
            writeln("Report Ruleset Bug: ", engine.currentRepo, "/issues");
        }
        writeln("=======================================================\n");
        stdout.flush();
    }
}

int main(string[] args) {
    string path = ".";
    string rulesDir = "rules";
    string rulesRepo = "";
    string rulesRepoBranch = "main";
    string fromVer = "";
    string toVer = "";
    string library = "";
    string extensions = ".py,.cpp,.h,.js,.ts,.astro";
    string domain = "code";
    string outDir = "";
    bool inPlace = false;
    bool dryRun = true;
    bool preferImmutable = true;

    auto helpInformation = getopt(
        args,
        "path|p", "Path to process", &path,
        "rules-dir|R", "Directory containing SDL rules (local)", &rulesDir,
        "rules-repo", "Git repository URL for rulesets", &rulesRepo,
        "rules-repo-branch", "Branch for the rules repository (default: main)", &rulesRepoBranch,
        "library|L", "Library/Binding subpath (e.g., python/qt)", &library,
        "from|f", "Source version (e.g., 5.15)", &fromVer,
        "to|t", "Target context or version", &toVer,
        "extensions|e", "Comma-separated extensions", &extensions,
        "domain|D", "Domain: code|filesystem|cli", &domain,
        "out-dir|o", "Output directory for transformed files", &outDir,
        "in-place|i", "Modify files in-place (destructive)", &inPlace,
        "dry-run|d", "Explicit dry run (default)", &dryRun,
        "prefer-mutable", "Prefer mutable package managers over Nix/Guix", &preferImmutable
    );

    if (inPlace) dryRun = false;
    if (outDir != "") dryRun = false;
    preferImmutable = !preferImmutable;

    if (helpInformation.helpWanted) {
        defaultGetoptPrinter("\u2261quivalence \u2261ngine (dev-centr)", helpInformation.options);
        return 0;
    }

    string actualRulesDir = rulesDir;
    if (rulesDir.startsWith("http://") || rulesDir.startsWith("https://")) {
        string tempRoot = buildPath(tempDir(), "equivalence-engine-cache");
        import std.digest.md;
        string urlHash = rulesDir.digest!MD5.toHexString().idup;
        string downloadPath;
        if (rulesDir.endsWith(".zip")) downloadPath = buildPath(tempRoot, urlHash ~ ".zip");
        else if (rulesDir.endsWith(".tar.gz") || rulesDir.endsWith(".tgz")) downloadPath = buildPath(tempRoot, urlHash ~ ".tar.gz");
        else { writeln("Unrecognized remote archive format."); return 1; }

        if (!exists(downloadPath)) {
            mkdirRecurse(tempRoot);
            auto pid = spawnProcess(["curl", "-L", "-o", downloadPath, rulesDir]);
            if (wait(pid) != 0) { writeln("Error downloading rules."); return 1; }
        }
        actualRulesDir = downloadPath;
    }

    string archivePath = "";
    string subPath = "";
    string[] pathParts = actualRulesDir.split(dirSeparator);
    foreach (i, part; pathParts) {
        if (part.endsWith(".zip") || part.endsWith(".tar.gz") || part.endsWith(".tgz")) {
            archivePath = pathParts[0 .. i+1].join(dirSeparator);
            subPath = pathParts[i+1 .. $].join(dirSeparator);
            break;
        }
    }

    if (archivePath != "") {
        string tempRoot = buildPath(tempDir(), "equivalence-engine-cache");
        import std.digest.md;
        string hash = archivePath.digest!MD5.toHexString();
        string extractDir = buildPath(tempRoot, hash);
        if (!exists(extractDir)) {
            mkdirRecurse(extractDir);
            if (archivePath.endsWith(".zip")) {
                import std.zip;
                auto zip = new ZipArchive(read(archivePath));
                foreach (name, am; zip.directory) {
                    zip.expand(am);
                    string target = buildPath(extractDir, name);
                    if (name.endsWith("/") || name.endsWith("\\")) { if (!exists(target)) mkdirRecurse(target); }
                    else { string d = dirName(target); if (!exists(d)) mkdirRecurse(d); std.file.write(target, am.expandedData); }
                }
            } else {
                auto pid = spawnProcess(["tar", "-xzf", archivePath, "-C", extractDir]);
                if (wait(pid) != 0) { writeln("Error extracting archive."); return 1; }
            }
        }
        if (subPath == "") {
            auto entries = dirEntries(extractDir, SpanMode.shallow).filter!(e => e.isDir).array;
            actualRulesDir = (entries.length == 1) ? entries[0].name : extractDir;
        } else actualRulesDir = buildPath(extractDir, subPath);
    }

    if (exists(buildPath(actualRulesDir, "rules"))) {
         bool looksLikeRuleset = false;
         if (domain == "filesystem") {
             string[] osFolders = ["linux", "windows", "mac", "bsd", "darwin"];
             foreach(os; osFolders) if(exists(buildPath(actualRulesDir, os))) { looksLikeRuleset = true; break; }
         } else if (domain == "cli") {
             looksLikeRuleset = exists(buildPath(actualRulesDir, "catalog", "tools.sdl"));
         } else {
             foreach(e; dirEntries(actualRulesDir, SpanMode.shallow)) if(e.name.endsWith(".sdl")) { looksLikeRuleset = true; break; }
         }
         if (!looksLikeRuleset) actualRulesDir = buildPath(actualRulesDir, "rules");
    }
    rulesDir = actualRulesDir;

    string tmpRulesDir = ".equivalence-rules-tmp";
    auto cleanup = {
        if (exists(tmpRulesDir)) {
            version(Windows) executeShell("rmdir /s /q " ~ tmpRulesDir);
            else rmdirRecurse(tmpRulesDir);
        }
    };

    if (rulesRepo != "") {
        cleanup();
        try {
            import repoget;
            auto provider = getProvider(rulesRepo);
            writeln("Cloning rules from ", rulesRepo, "...");
            provider.clone(rulesRepo, tmpRulesDir);
            rulesDir = tmpRulesDir;
        } catch (Exception e) {
            writeln("Failed to clone rules repository: ", e.msg);
            return 1;
        }
    }
    scope(exit) if (rulesRepo != "") cleanup();

    if (exists(buildPath(rulesDir, "catalog", "tools.sdl")))
        rulesDir = buildPath(rulesDir, "catalog");
    else if (domain != "cli" && exists(buildPath(rulesDir, "rules")))
        rulesDir = buildPath(rulesDir, "rules");

    if (domain == "cli") {
        string context = toVer;
        string toolId = args.length > 1 ? args[1] : "";
        if (context == "" || toolId == "") {
            writeln("Usage: equivalence-engine --domain cli --to <context> <toolId>");
            writeln("Example: equivalence-engine --domain cli --rules-repo https://github.com/dev-centr/equivalence-rules-cli --to linux/nix/default gh");
            return 1;
        }

        string catalogPath = buildPath(rulesDir, "tools.sdl");
        if (!exists(catalogPath))
            catalogPath = buildPath(rulesDir, "..", "catalog", "tools.sdl");

        CliInstallMethod method;
        if (exists(catalogPath))
            method = resolveCliInstall(catalogPath, context, toolId, preferImmutable);
        else
            method = resolveCliInstallFromRulesDir(rulesDir, context, toolId);

        if (method.command == "") {
            writeln("No install method for tool '", toolId, "' on context '", context, "'");
            return 1;
        }

        writeln("tool:       ", toolId);
        writeln("context:    ", method.context.length ? method.context : context);
        writeln("mutable:    ", method.mutableInstall ? "yes" : "no (immutable)");
        writeln("interactive:", method.interactive ? "yes" : "no");
        if (method.auditNote.length) writeln("note:       ", method.auditNote);
        writeln("command:    ", method.command);
        if (method.verifyCommand.length) writeln("verify:     ", method.verifyCommand);
        return 0;
    }

    auto cli = new EquivalenceCLI();
    string[] ruleFiles;

    if (domain == "filesystem") {
        string toContext = toVer;
        string intent = args.length > 1 ? args[1] : "";
        if (toContext == "") { writeln("Error: --to (context) required."); return 1; }
        if (intent == "") { writeln("Error: intent name required."); return 1; }
        ruleFiles = resolveIntent(rulesDir, toContext, intent);
    } else {
        if (fromVer != "" && toVer != "") {
            string searchDir = buildPath(rulesDir, library);
            ruleFiles = findMigrationPath(searchDir, fromVer, toVer);
        }
    }

    if (ruleFiles.length == 0) {
        writeln("No rules found for ", domain, (library != "" ? " (" ~ library ~ ")" : ""), " from ", fromVer, " to ", toVer, " in ", rulesDir);
        return 1;
    }

    if (domain == "code") {
        writeln("Migration path: ", fromVer, " -> ", toVer);
        string currentVer = fromVer;
        foreach (f; ruleFiles) {
            auto base = baseName(f, ".sdl");
            auto rb = base.split("-");
            if (rb.length == 2) {
                if (currentVer != rb[0]) {
                    writeln(" - Version ", currentVer, " recognized; mapping to ", rb[0], "-", rb[1], ".sdl via aliasing");
                }
                writeln(" - Applying rules from: ", f);
                currentVer = rb[1];
            } else {
                writeln(" - Applying rules from: ", f);
            }
            cli.engine.loadRules(f);
        }
        writeln("Engine loaded total rules: ", cli.engine.rules.length);
    } else {
        writeln("Resolved: ", ruleFiles);
        foreach (f; ruleFiles) {
            cli.engine.loadRules(f);
        }
        writeln("Engine loaded total rules: ", cli.engine.rules.length);
    }

    auto extList = extensions.split(",");
    if (!exists(path)) { writeln("Path does not exist: ", path); return 1; }

    if (isDir(path)) {
        foreach (DirEntry entry; dirEntries(path, SpanMode.depth)) {
            if (entry.isFile && extList.canFind(extension(entry.name))) {
                processFile(entry.name, cli.engine, dryRun, outDir, path);
            }
        }
    } else {
        processFile(path, cli.engine, dryRun, outDir, dirName(path));
    }

    cli.printSummary(rulesDir);
    return 0;
}

void processFile(string fileName, RuleEngine engine, bool dryRun, string outDir, string baseRoot) {
    auto content = readText(fileName);
    auto newContent = engine.applyRules(content, fileName);

    if (newContent != content) {
        if (dryRun) {
            writeln("Plan: update ", fileName);
        } else {
            string targetPath = fileName;
            if (outDir != "") {
                string relative = fileName.relativePath(baseRoot);
                targetPath = buildPath(outDir, relative);
                string d = dirName(targetPath);
                if (!exists(d)) mkdirRecurse(d);
            }
            std.file.write(targetPath, newContent);
            writeln("Updated: ", targetPath);
        }
    }
}
