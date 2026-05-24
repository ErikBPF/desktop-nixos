{config, ...}: let
  inherit (config) username;
  vaultRelPath = "Documents/erik/obsidian/vault";
  vaultAbsPath = "/home/${username}/${vaultRelPath}";
  vaultId = "097778516a065bad";
  vaultGitRemote = "git@github_erikbpf:ErikBPF/vault.git";

  # All community plugins fetched declaratively from GitHub releases.
  # To bump a plugin: update `version`, then run `just build` — error will print expected hash.
  pluginSpecs = {
    obsidian-llm-wiki = {
      version = "1.10.2";
      owner = "green-dalii";
      repo = "obsidian-llm-wiki";
      hashes = {
        "main.js" = "sha256-ys0VJu86kXURpxaszeWRO2hp/8UFSQpWuoswpQ7ek60=";
        "manifest.json" = "sha256-UBAUAGtChn5BqUhNQHXai5py9r6pzYQi92+rD7b9MAE=";
        "styles.css" = "sha256-ITYivo/lHSzfnriG8s9mILz69U+G+Bcis/i8KK8gqsI=";
      };
    };
    smart-connections = {
      version = "4.5.0";
      owner = "brianpetro";
      repo = "obsidian-smart-connections";
      hashes = {
        "main.js" = "sha256-VjRItzwwcQD5Wwrq0xerXwqpblDqEpAFYxLrB17yVHo=";
        "manifest.json" = "sha256-kxYPrIVhGhy6h8C7A8xYw5GfKwT83ubLQ3O8G6cRsxY=";
        "styles.css" = "sha256-G+afasCSrObA/coLkiV/aOSqCNWv5ivYEV/kq1mW3sI=";
      };
    };
    quickadd = {
      version = "2.12.1";
      owner = "chhoumann";
      repo = "quickadd";
      hashes = {
        "main.js" = "sha256-l++Fq4eEs/HISTq1NauhbmXz58WptxNG14NJ6qu5ztg=";
        "manifest.json" = "sha256-YYqptQOu0i6/V1wtNw6jhWSUXt+c4c6O38Dah59Oc70=";
        "styles.css" = "sha256-+0+f1mOTQF1OdlUIUJB6NcSwCDIju27J7BMQ97cuvzg=";
      };
    };
    periodic-notes = {
      version = "1.0.0-beta.3";
      owner = "liamcain";
      repo = "obsidian-periodic-notes";
      hashes = {
        "main.js" = "sha256-k0ypQ1m2pLnwIJPUpE+lllTFI3sxzwLXuYLFgWiFG7E=";
        "manifest.json" = "sha256-vaKTI/ddOz/L2kiTNYJbl/5LV0kU0EY16afmfyQUBJw=";
        "styles.css" = "sha256-/ywAte550Y0C56j0jLLmUSyRL3X4juBT2UZoyQqWs5o=";
      };
    };
    obsidian-advanced-uri = {
      version = "1.46.1";
      owner = "Vinzent03";
      repo = "obsidian-advanced-uri";
      hashes = {
        "main.js" = "sha256-0QMA+2Z+uek0F0J/w+oBD0bbAgiF0pxd7MeHNcFKsWI=";
        "manifest.json" = "sha256-+hLVSIvx1huCknKxXecv6ifR8tashU+X7JemzCeEwvE=";
      };
    };
    recent-files-obsidian = {
      version = "1.7.9";
      owner = "tgrosinger";
      repo = "recent-files-obsidian";
      hashes = {
        "main.js" = "sha256-gXvD5i/jATDs0UYtJGzNenJDQ3A8yGR/84BlYFQFTuQ=";
        "manifest.json" = "sha256-tmrW8N1WHzL8g1/cHyYh8Q0pAKaRnRnSfKhJ1XZrsvo=";
        "styles.css" = "sha256-LuSckqsLuEgiGglib3umdrvoU3LEyAZe53kLCDLLPds=";
      };
    };
    paste-url-into-selection = {
      version = "1.11.4";
      owner = "denolehov";
      repo = "obsidian-url-into-selection";
      hashes = {
        "main.js" = "sha256-N3iD0vwqH+65a+ho9xEHgodCBsswZWNSgeif39xubXc=";
        "manifest.json" = "sha256-ZXPA7yd7DrNm4ZrNVYRFpGRzpfzPC36AueB9yV+LBEM=";
      };
    };
    calendar = {
      version = "1.5.10";
      owner = "liamcain";
      repo = "obsidian-calendar-plugin";
      hashes = {
        "main.js" = "sha256-f7M56c+f2+WoAforirhbNmtbN3f70ZPLyHKLwncR0SU=";
        "manifest.json" = "sha256-8+lYEzhkhRK6oS1bRYSQ9/02eRj3vba9hhcc5Xvn0Is=";
      };
    };
    copilot = {
      version = "3.3.3";
      owner = "logancyang";
      repo = "obsidian-copilot";
      hashes = {
        "main.js" = "sha256-QBihMZXmU8soIpM6VOlJrlHnphIHAKONzycl171C4e4=";
        "manifest.json" = "sha256-8htX39WmRMYd72NNFItaoT7Z3e+aaqwunB6o6hOcbEw=";
        "styles.css" = "sha256-c8Jzi9+vN7dVqO71m937SqV63Z4hwVvSuJZxk5OoxpI=";
      };
    };
    dataview = {
      version = "0.5.68";
      owner = "blacksmithgu";
      repo = "obsidian-dataview";
      hashes = {
        "main.js" = "sha256-eU6ert5zkgu41UsO2k9d4hgtaYzGOHdFAPJPFLzU2gs=";
        "manifest.json" = "sha256-kjXbRxEtqBuFWRx57LmuJXTl5yIHBW6XZHL5BhYoYYU=";
        "styles.css" = "sha256-MwbdkDLgD5ibpyM6N/0lW8TT9DQM7mYXYulS8/aqHek=";
      };
    };
    obsidian-excalidraw-plugin = {
      version = "2.23.3";
      owner = "zsviczian";
      repo = "obsidian-excalidraw-plugin";
      hashes = {
        "main.js" = "sha256-q0A/yNq7i2Y9JrZs3MjWgSe3bATucN+FlUlitvu+c5Q=";
        "manifest.json" = "sha256-tWUVC2VyxaHRxsZ0z22bXk0aKdTa8yBuVP5Z2CMbEEw=";
        "styles.css" = "sha256-DNHQPpMXathUaWTUxzQcMArMEu4lGqPzaZ4OE1vB1wo=";
      };
    };
    obsidian-git = {
      version = "2.38.3";
      owner = "Vinzent03";
      repo = "obsidian-git";
      hashes = {
        "main.js" = "sha256-l/zQtjQlXEpntKnyF9iXZLxr0pIz3lNrgCfGPiWkIvU=";
        "manifest.json" = "sha256-JvDvaEkCfuMVmJ9TmoRqQr06iBEvAlzu5uMD/y9kvoU=";
        "styles.css" = "sha256-9auT9NW03RvR5XeGTFx5CH9639RIrDRuBInlhHzmki0=";
      };
    };
    obsidian-icon-folder = {
      version = "2.14.7";
      owner = "FlorianWoelki";
      repo = "obsidian-iconize";
      hashes = {
        "main.js" = "sha256-raCwCXBlVsmBAflTpqh/XK/TABCF31k9O+KO7uohggE=";
        "manifest.json" = "sha256-9SShjWnpkKJEFzo1lWgcOaILy8ncGLWa9R5FZg/vXKI=";
        "styles.css" = "sha256-Vv/rg0n0r5fauKFPytywAZ07N7EW16NKoh6VjphFWok=";
      };
    };
    obsidian-linter = {
      version = "1.31.2";
      owner = "platers";
      repo = "obsidian-linter";
      hashes = {
        "main.js" = "sha256-MRfAV1JgbV0mVZ4R/AwtjhLvb1py8Fw2SVCRkRdLh1A=";
        "manifest.json" = "sha256-TTMc3t4azAMoyobqX2f7ZU0XVwFQ5VmPftmbBkRX5xI=";
        "styles.css" = "sha256-DM9QiwWpRF3HxDOxrPyun0Cy2OIY1T/f/q3XTUE8Its=";
      };
    };
    obsidian-style-settings = {
      version = "1.0.9";
      owner = "obsidian-community";
      repo = "obsidian-style-settings";
      hashes = {
        "main.js" = "sha256-GCirqs2rTFV4twWmJcWFswUS+O+tTHz8WhjnDMNVdGg=";
        "manifest.json" = "sha256-nP/cIM8qoTVIIOAFC2lLD5tXZEbj1dRKNq6LAYflv7g=";
        "styles.css" = "sha256-7nk30r5QZTqJzLMK5fBXKyNQfVt/EyjQBScaNjB1v9g=";
      };
    };
    obsidian-tasks-plugin = {
      version = "8.0.0";
      owner = "obsidian-tasks-group";
      repo = "obsidian-tasks";
      hashes = {
        "main.js" = "sha256-ekfMkVdtKniTL5JQc6hojPywa8H9+hlWUEP4q5l5q1Y=";
        "manifest.json" = "sha256-FQzsEV39g/L5XE7dUV33JU4RAsEWAyvQmY3JDWcThzc=";
        "styles.css" = "sha256-YoZeAfuvhBhjXA7qzCfU9zUskPB+gbG+OWrNGh9+q7w=";
      };
    };
    omnisearch = {
      version = "1.29.2";
      owner = "scambier";
      repo = "obsidian-omnisearch";
      hashes = {
        "main.js" = "sha256-ht5hCEGn1I+3KGp6ufVXvSz1HKbIS6WYdGQiGfOfYzI=";
        "manifest.json" = "sha256-2n4letsH5Akpbm24C05v9SyAxl65oYZc8hXsOfhuMVY=";
        "styles.css" = "sha256-gY5rNh5CarOoaKRSSiDfWmQWv2FIdrYe3jQND3jJ68g=";
      };
    };
    templater-obsidian = {
      version = "2.20.5";
      owner = "SilentVoid13";
      repo = "Templater";
      hashes = {
        "main.js" = "sha256-gcjQuyEsnBJpkC7O7kuqIcg7qF1tjfo0ioBBa8csXuw=";
        "manifest.json" = "sha256-XfFFHinKveykRd3zRuUfrAqT8Ae/D40QCSTTXXo6A9g=";
        "styles.css" = "sha256-fYW80Snp84qJMkVb3wXJYpzkZqsSNtyTO3t66lU1DAQ=";
      };
    };
  };

  enabledPlugins = builtins.attrNames pluginSpecs;

  corePlugins = {
    file-explorer = true;
    global-search = true;
    switcher = true;
    graph = true;
    backlink = true;
    canvas = true;
    outgoing-link = true;
    tag-pane = true;
    footnotes = false;
    properties = true;
    page-preview = true;
    daily-notes = false;
    templates = true;
    note-composer = true;
    command-palette = true;
    slash-command = false;
    editor-status = true;
    bookmarks = true;
    markdown-importer = false;
    zk-prefixer = false;
    random-note = false;
    outline = true;
    word-count = true;
    slides = false;
    audio-recorder = false;
    workspaces = false;
    file-recovery = true;
    publish = false;
    sync = false;
    bases = true;
    webviewer = false;
  };

  appearance = {
    baseFontSize = 18;
    baseFontSizeAction = true;
    cssTheme = "Tokyo Night";
    theme = "system";
  };

  app = {
    livePreview = true;
    readableLineLength = true;
    strictLineBreaks = false;
    defaultViewMode = "source";
    newLinkFormat = "relative";
    useMarkdownLinks = false;
    attachmentFolderPath = "raw/_attachments";
    promptDelete = false;
    showLineNumber = true;
    spellcheck = true;
    showFrontmatter = true;
    foldHeading = true;
    foldIndent = true;
    alwaysUpdateLinks = true;
    useTab = false;
    tabSize = 2;
    autoConvertHtml = true;
    trashOption = "system";
  };

  hotkeys = {
    "quickadd:choice:ingest-url" = [
      {
        modifiers = ["Mod" "Shift"];
        key = "I";
      }
    ];
    "quickadd:choice:process-inbox" = [
      {
        modifiers = ["Mod" "Shift"];
        key = "P";
      }
    ];
    "quickadd:choice:lint-wiki" = [
      {
        modifiers = ["Mod" "Shift"];
        key = "L";
      }
    ];
    "obsidian-tasks-plugin:edit-task" = [
      {
        modifiers = ["Mod"];
        key = "Enter";
      }
    ];
    "obsidian-git:push" = [
      {
        modifiers = ["Mod" "Shift"];
        key = "K";
      }
    ];
    "obsidian-git:pull" = [
      {
        modifiers = ["Mod" "Shift"];
        key = "J";
      }
    ];
    "graph:open" = [
      {
        modifiers = ["Mod" "Shift"];
        key = "G";
      }
    ];
    "smart-connections:open-view" = [
      {
        modifiers = ["Mod" "Shift"];
        key = "S";
      }
    ];
  };

  bookmarks = {
    items = [
      {
        type = "file";
        path = "index.md";
        title = "Index";
      }
      {
        type = "file";
        path = "log.md";
        title = "Log";
      }
      {
        type = "file";
        path = "inbox.md";
        title = "Inbox";
      }
      {
        type = "file";
        path = "AGENTS.md";
        title = "Schema (AGENTS)";
      }
    ];
  };

  periodicNotes = {
    daily = {
      enabled = true;
      folder = "log/daily";
      format = "YYYY-MM-DD";
      template = "templates/daily.md";
    };
    weekly = {
      enabled = true;
      folder = "log/weekly";
      format = "YYYY-[W]ww";
      template = "templates/weekly.md";
    };
    monthly = {enabled = false;};
  };

  templatesCore = {
    folder = "templates";
    dateFormat = "YYYY-MM-DD";
    timeFormat = "HH:mm";
  };

  templater = {
    templates_folder = "templates";
    trigger_on_file_creation = true;
    auto_jump_to_cursor = true;
    enable_system_commands = false;
    enabled_templates_hotkeys = [""];
    folder_templates = [
      {
        folder = "raw";
        template = "templates/source.md";
      }
      {
        folder = "wiki";
        template = "templates/entity.md";
      }
      {
        folder = "log/daily";
        template = "templates/daily.md";
      }
    ];
    syntax_highlighting = true;
    user_scripts_folder = "templates/scripts";
  };

  obsidianGit = {
    commitMessage = "vault: {{date}} {{numFiles}} files";
    commitDateFormat = "YYYY-MM-DD HH:mm:ss";
    autoSaveInterval = 10;
    autoPushInterval = 15;
    autoPullInterval = 5;
    autoPullOnBoot = true;
    disablePush = false;
    pullBeforePush = true;
    syncMethod = "rebase";
    customMessageOnAutoBackup = false;
    disablePopups = false;
    listChangedFilesInMessageBody = true;
    showStatusBar = true;
    updateSubmodules = false;
    differentIntervalCommitAndPush = true;
    gitPath = "";
    username = "ErikBPF";
    treeStructure = false;
    refreshSourceControl = true;
    basePath = "";
    differentBranchInRemote = false;
    showFileMenu = true;
  };

  linter = {
    ruleConfigs = {
      "format-tags-in-yaml" = {enabled = true;};
      "trailing-spaces" = {enabled = true;};
      "consecutive-blank-lines" = {enabled = true;};
      "yaml-title-alias" = {enabled = true;};
      "remove-trailing-punctuation-in-heading" = {enabled = false;};
    };
    lintOnSave = true;
    displayChanged = false;
    foldersToIgnore = ["raw/_attachments"];
  };

  dataview = {
    enableInlineDataview = true;
    enableJsDataviewQueries = true;
    enableDataviewJs = true;
    inlineQueryPrefix = "=";
    inlineJsQueryPrefix = "$=";
    defaultDateFormat = "yyyy-MM-dd";
    defaultDateTimeFormat = "yyyy-MM-dd HH:mm";
  };

  tasks = {
    globalFilter = "#task";
    setDoneDate = true;
    setCreatedDate = true;
    autoSuggestInEditor = true;
  };

  quickadd = {
    choices = [
      {
        name = "ingest-url";
        type = "Capture";
        captureTo = "inbox.md";
        format = {
          enabled = true;
          format = "- [ ] [{{VALUE:title}}]({{VALUE:url}}) — {{DATE:YYYY-MM-DD}}\n";
        };
        prepend = false;
      }
      {
        name = "process-inbox";
        type = "Template";
        templatePath = "templates/process-inbox.md";
      }
      {
        name = "lint-wiki";
        type = "Template";
        templatePath = "templates/lint-wiki.md";
      }
    ];
  };

  obsidianRegistry = {
    vaults.${vaultId} = {
      path = vaultAbsPath;
      ts = 1775839395343;
      open = true;
    };
  };

  inherit (builtins) toJSON;
  vaultGitignore = ''
    # Nix-managed configs (symlinks to /nix/store — useless in git)
    .obsidian/app.json
    .obsidian/appearance.json
    .obsidian/core-plugins.json
    .obsidian/community-plugins.json
    .obsidian/hotkeys.json
    .obsidian/bookmarks.json
    .obsidian/templates.json

    # Nix-managed plugin binaries
    .obsidian/plugins/*/main.js
    .obsidian/plugins/*/manifest.json
    .obsidian/plugins/*/styles.css

    # Obsidian runtime + collision artifacts
    .obsidian/workspace.json
    .obsidian/workspace-mobile.json
    .obsidian/cache/
    .obsidian/*.backup
    .obsidian/plugins/*/*.backup
    .obsidian/plugins/*/data.json.backup

    # Dropped plugins
    .obsidian/plugins/obsidian-markmind/
    .obsidian/plugins/table-editor-obsidian/

    # Trash + temp
    .trash/
    *.tmp
    raw/_attachments/*.tmp
  '';

  seedFiles = {
    "log.md" = ''
      # Log

      Append-only chronological record. New entries added by LLM ingest/query/lint ops.

      Format: `## [YYYY-MM-DD] <op> | <title>`
    '';
    "index.md" = ''
      # Index

      Catalog of wiki pages. Maintained by LLM. Do not hand-edit.

      ## Concepts
      ## Entities
      ## Sources
    '';
    "inbox.md" = ''
      # Inbox

      Fleeting captures. Processed by `/process-inbox` into `raw/` or `wiki/`.
    '';
    "AGENTS.md" = ''
      # AGENTS — Karpathy LLM Wiki Schema

      You are the maintainer of this vault. Obsidian is the IDE, you are the programmer, the wiki is the codebase.

      ## Layout

      - `raw/` — immutable source material (papers, articles, transcripts, screenshots). Never edit.
      - `wiki/` — your output. Summary pages, concept pages, entity pages. You own this.
      - `log/` — periodic notes (daily/weekly) + `log.md` append-only ledger.
      - `templates/` — templater templates. Reference, do not modify.
      - `index.md` — top-level catalog. Update on every ingest.
      - `inbox.md` — fleeting captures to process.

      ## Operations

      ### ingest <source>
      1. Place verbatim source in `raw/YYYY-MM-DD-<slug>.md` with frontmatter `{source_url, captured_at, type}`.
      2. Read source end-to-end. Identify entities, concepts, claims.
      3. Write `wiki/<concept-slug>.md` summary. Use frontmatter `{type, aliases, sources, updated}`.
      4. For each entity/concept already in wiki: update with new cross-reference. Touch every page that references this.
      5. Append `index.md` under correct section.
      6. Append `log.md`: `## [YYYY-MM-DD] ingest | <title>`.

      ### query <question>
      1. Read `index.md`, then relevant `wiki/` pages.
      2. Synthesize with inline citations: `[[wiki/page-name]]`.
      3. If answer represents a NEW concept worth preserving: write new `wiki/` page, update index, append log entry `## [YYYY-MM-DD] query-derived | <concept>`.

      ### lint
      1. Find orphan pages (no inbound links).
      2. Find broken `[[wiki/...]]` links.
      3. Find contradictions across pages.
      4. Find stale claims (sources older than referenced material).
      5. Find missing cross-references.
      6. Report findings, then fix in batch with user approval.

      ## Frontmatter Contract

      ```yaml
      ---
      type: concept | entity | source | log
      aliases: [list of synonyms]
      sources: [list of raw/... paths]
      updated: YYYY-MM-DD
      tags: [#topic, #status]
      ---
      ```

      ## Hard Rules

      - Never edit `raw/`. Immutable.
      - Never delete `log.md` entries. Append-only.
      - Use relative `[[wiki/foo]]` links, not absolute paths.
      - Slugs: kebab-case, lowercase, ASCII.
      - One concept per file. Split when length exceeds ~2000 words.
      - Cite every claim in summaries with `[[raw/<source>]]`.
    '';
    "templates/daily.md" = ''
      ---
      type: log
      date: <% tp.date.now("YYYY-MM-DD") %>
      ---

      # <% tp.date.now("YYYY-MM-DD dddd") %>

      ## Notes

      ## Tasks
      - [ ] #task

      ## Links

    '';
    "templates/weekly.md" = ''
      ---
      type: log
      week: <% tp.date.now("YYYY-[W]ww") %>
      ---

      # Week <% tp.date.now("YYYY-[W]ww") %>

      ## Highlights

      ## Open Threads

      ## Review
    '';
    "templates/source.md" = ''
      ---
      type: source
      captured_at: <% tp.date.now("YYYY-MM-DD HH:mm") %>
      source_url:
      source_type:
      tags:
      ---

      # <% tp.file.title %>

      > Immutable. Do not edit. Summarize in `wiki/`.

    '';
    "templates/entity.md" = ''
      ---
      type: entity
      aliases: []
      sources: []
      updated: <% tp.date.now("YYYY-MM-DD") %>
      tags:
      ---

      # <% tp.file.title %>

      ## Summary

      ## Key Facts

      ## Related
      - [[wiki/]]

      ## Sources
      - [[raw/]]
    '';
    "templates/process-inbox.md" = ''
      ---
      type: agent-task
      op: process-inbox
      ---

      # Process Inbox

      Agent: read `inbox.md`. For each line:
      1. Classify as `source` (URL) → fetch via `/ingest-url`, place in `raw/`.
      2. Classify as `thought` → integrate into existing `wiki/` page or create new.
      3. Clear processed lines from `inbox.md`.
      4. Log each action in `log.md`.
    '';
    "templates/lint-wiki.md" = ''
      ---
      type: agent-task
      op: lint
      ---

      # Lint Wiki

      Run lint per `AGENTS.md` op:
      - Orphan pages
      - Broken links
      - Contradictions
      - Stale claims
      - Missing cross-refs

      Report findings. Wait for user approval before batch-fixing.
    '';
    ".gitignore" = vaultGitignore;
  };
in {
  flake.modules.home.obsidian = {
    lib,
    pkgs,
    ...
  }: let
    mkPlugin = id: spec:
      pkgs.stdenvNoCC.mkDerivation {
        pname = "obsidian-plugin-${id}";
        inherit (spec) version;
        srcs = lib.mapAttrsToList (filename: hash:
          pkgs.fetchurl {
            url = "https://github.com/${spec.owner}/${spec.repo}/releases/download/${spec.version}/${filename}";
            inherit hash;
          })
        spec.hashes;
        dontUnpack = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          for f in $srcs; do
            cp "$f" "$out/$(stripHash "$f")"
          done
          runHook postInstall
        '';
      };

    pluginPkgs = lib.mapAttrs mkPlugin pluginSpecs;

    # Per-plugin file → home.file entry. Symlinks main.js, manifest.json, styles.css
    # into the vault. data.json is left mutable (managed by Obsidian + activation seed).
    pluginFiles =
      lib.foldlAttrs (
        acc: id: spec:
          acc
          // (lib.mapAttrs' (filename: _:
            lib.nameValuePair "${vaultRelPath}/.obsidian/plugins/${id}/${filename}" {
              source = "${pluginPkgs.${id}}/${filename}";
            })
          spec.hashes)
      ) {}
      pluginSpecs;

    mkSeed = path: content: ''
            if [ ! -e "${vaultAbsPath}/${path}" ]; then
              mkdir -p "$(dirname "${vaultAbsPath}/${path}")"
              cat > "${vaultAbsPath}/${path}" <<'EOF_SEED'
      ${content}EOF_SEED
            fi
    '';

    mkPluginData = id: data: ''
      mkdir -p "${vaultAbsPath}/.obsidian/plugins/${id}"
      if [ ! -e "${vaultAbsPath}/.obsidian/plugins/${id}/data.json" ]; then
        printf '%s' '${toJSON data}' > "${vaultAbsPath}/.obsidian/plugins/${id}/data.json"
      fi
    '';

    seedScript = lib.concatStringsSep "\n" [
      "mkdir -p ${vaultAbsPath}/{raw,raw/_attachments,wiki,log/daily,log/weekly,templates,templates/scripts}"
      (lib.concatStringsSep "\n" (lib.mapAttrsToList mkSeed seedFiles))
      (mkPluginData "obsidian-git" obsidianGit)
      (mkPluginData "obsidian-linter" linter)
      (mkPluginData "dataview" dataview)
      (mkPluginData "obsidian-tasks-plugin" tasks)
      (mkPluginData "templater-obsidian" templater)
      (mkPluginData "quickadd" quickadd)
      (mkPluginData "periodic-notes" periodicNotes)
      "rm -f ${vaultAbsPath}/.obsidian/*.backup ${vaultAbsPath}/.obsidian/plugins/*/*.backup 2>/dev/null || true"
    ];

    gitRemoteScript = ''
      if [ -d "${vaultAbsPath}/.git" ]; then
        cd "${vaultAbsPath}"
        if ! ${pkgs.git}/bin/git remote get-url origin >/dev/null 2>&1; then
          ${pkgs.git}/bin/git remote add origin ${vaultGitRemote}
        else
          current=$(${pkgs.git}/bin/git remote get-url origin)
          if [ "$current" != "${vaultGitRemote}" ]; then
            ${pkgs.git}/bin/git remote set-url origin ${vaultGitRemote}
          fi
        fi
      fi
    '';
  in {
    home.file =
      {
        ".config/obsidian/obsidian.json".text = toJSON obsidianRegistry;
        "${vaultRelPath}/.obsidian/community-plugins.json".text = toJSON enabledPlugins;
        "${vaultRelPath}/.obsidian/core-plugins.json".text = toJSON corePlugins;
        "${vaultRelPath}/.obsidian/appearance.json".text = toJSON appearance;
        "${vaultRelPath}/.obsidian/app.json".text = toJSON app;
        "${vaultRelPath}/.obsidian/hotkeys.json".text = toJSON hotkeys;
        "${vaultRelPath}/.obsidian/bookmarks.json".text = toJSON bookmarks;
        "${vaultRelPath}/.obsidian/templates.json".text = toJSON templatesCore;
      }
      // pluginFiles;

    home.activation.obsidian-vault-seed = lib.hm.dag.entryAfter ["writeBoundary"] seedScript;
    home.activation.obsidian-git-remote = lib.hm.dag.entryAfter ["writeBoundary"] gitRemoteScript;
  };
}
