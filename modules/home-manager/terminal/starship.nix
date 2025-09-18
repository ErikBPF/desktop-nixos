{ ... }:
let
  c = {
    red = "#f7768e";
    orange = "#ff9e64";
    yellow = "#e0af68";
    light_grey = "#cfc9c2";
    green = "#9ece6a";
    teal = "#73dacb";
    cyan = "#b4f9f8";
    sky = "#2ac3de";
    blue = "#7dcfff";
    cornflower = "#7aa2f7";
    purple = "#bb9af7";
    fg = "#c0caf5";
    grey = "#a9b1d6";
    dark_grey = "#9aa5ce";
    blue_grey = "#565f89";
    dark_blue = "#414868";
    bg = "#1a1b26";
  };

in
{
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      format = "[  ](bold ${c.cyan})$username$hostname$directory$git_branch$git_state$git_status$git_metrics$fill$cmd_duration$jobs$direnv$time$line_break$character";
      # Custom Modules
      custom.times = {
        description = "Display Execution Times (Start and End Time)";
        command = "echo $STARSHIP_CUSTOM_START $STARSHIP_CUSTOM_END";
        format = "[$output]($style)";
        style = "${c.blue_grey}";
        when = true;
      };

      # --- Main Modules ---
      username = {
        format = "[$user]($style)";
        show_always = true;
        style_user = "${c.blue}";
      };

      hostname = {
        format = " on [$hostname]($style) ";
        style = "bold ${c.purple}";
        ssh_only = false;
        ssh_symbol = "󰒋 ";
      };

      shlvl = {
        disabled = false;
        format = "[$shlvl]($style) ";
        repeat = true;
        style = "${c.teal}";
        symbol = "T";
        threshold = 3; # HACK: We increase threshold from 2 to 3 since niri creates new shell session, so it always shows 2
      };

      cmd_duration = {
        format = "⑄ [$duration]($style) ";
        style = "${c.dark_grey}";
      };

      directory = {
        fish_style_pwd_dir_length = 1;
        format = "[$path]($style) ";
        read_only = "⌽ ";
        style = "bold ${c.teal}";
        truncate_to_repo = false;
        truncation_length = 3;
      };

      nix_shell = {
        format = "[($name <- )$symbol]($style) ";
        impure_msg = "impure";
        style = "${c.red}";
        symbol = " ";
        pure_msg = "pure";
        unknown_msg = "";
        disabled = false;
        heuristic = false;
      };

      character = {
        error_symbol = "[❯](${c.red})";
        success_symbol = "[❯](${c.blue_grey})";
        vimcmd_replace_one_symbol = "[❮](${c.blue_grey})";
        vimcmd_replace_symbol = "[❮](${c.blue_grey})";
        vimcmd_symbol = "[❮](${c.yellow})";
        vimcmd_visual_symbol = "[❮](${c.teal})";
      };

      time = {
        format = "\\[[$time]($style)\\]";
        style = "${c.teal}";
        disabled = false;
      };
      aws = {
        disabled = false;
        symbol = " ";
        format = "[$symbol$profile(\\($region\\))]($style)";
      };
      gcloud = {
        disabled = true;
        format = "[$symbol$active(/$project)(\\($region\\))]($style)";
        symbol = "󱇶 ";
      };
      azure = {
        disabled = true;
        symbol = "󰠅 ";
      };
      openstack = {
        disabled = true;
        symbol = " ";
      };

      # --- Containerization & Virtualization ---
      container = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.dark_blue}";
        disabled = true;
      };
      docker_context = {
        symbol = "  ";
        format = "[$symbol($version )]($style)";
        style = "${c.dark_blue}";
        disabled = false;
      };
      kubernetes = {
        symbol = "󱃾 ";
        format = "[$symbol$context( \\($namespace\\))]($style) ";
        style = "${c.cyan} bold";
        disabled = false;
        detect_extensions = [ ];
        detect_files = [
          "k8s.yaml"
          "kubernetes.yaml"
          ".kubeconfig"
        ];
        detect_folders = [ ".kube" ];
        detect_env_vars = [ "KUBECONFIG" ];
      };
      vagrant = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.dark_blue}";
        disabled = true;
      };

      # --- File System & Package Management ---
      package = {
        symbol = "󰏗 ";
        disabled = false;
      };

      # --- Infrastructure & DevOps ---
      direnv = {
        symbol = " ";
        style = "${c.sky}";
        disabled = false;
      };
      pulumi = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.dark_blue}";
        disabled = true;
      };
      terraform = {
        symbol = "󱁢 ";
        format = "[$symbol($version )]($style)";
        style = "${c.dark_blue}";
        disabled = false;
      };

      # --- Languages & Runtimes ---
      buf = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.grey}";
        disabled = true;
      };
      bun = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.yellow}";
        disabled = true;
      };
      c = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.blue}";
        disabled = true;
      };
      cmake = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.dark_grey}";
        disabled = true;
      };
      cobol = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.grey}";
        disabled = true;
      };
      conda = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.green}";
        disabled = false;
      };
      crystal = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.grey}";
        disabled = true;
      };
      daml = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.yellow}";
        disabled = true;
      };
      dart = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.blue}";
        disabled = true;
      };
      deno = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.yellow}";
        disabled = true;
      };
      dotnet = {
        symbol = "󰪮 ";
        format = "[$symbol($version )]($style)";
        style = "${c.blue}";
        disabled = true;
      };
      elixir = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.grey}";
        disabled = false;
      };
      elm = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.green}";
        disabled = true;
      };
      erlang = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.red}";
        disabled = false;
      };
      fennel = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.grey}";
        disabled = true;
      };
      gleam = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.green}";
        disabled = true;
      };
      golang = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.blue}";
        disabled = false;
      };
      gradle = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.dark_grey}";
        disabled = true;
      };
      guix_shell = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.green}";
        disabled = true;
      };
      haskell = {
        format = "[$symbol($version )]($style)";
        style = "${c.purple}";
        disabled = false;
        symbol = " ";
        detect_extensions = [
          "hs"
          "cabal"
          "hs-boot"
        ];
        detect_files = [
          "stack.yaml"
          "cabal.project"
          "package.yaml"
        ];
        detect_folders = [ ];
      };
      haxe = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.red}";
        disabled = true;
      };
      helm = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.blue}";
        disabled = true;
      };
      java = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.grey}";
        disabled = true;
      };
      julia = {
        format = "[$symbol($version )]($style)";
        symbol = " ";
        style = "${c.red}";
        disabled = false;
        detect_extensions = [ "jl" ];
        detect_files = [
          "Project.toml"
          "Manifest.toml"
        ];
        detect_folders = [ ];
      };
      kotlin = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.dark_blue}";
        disabled = true;
      };
      lua = {
        symbol = "󰢱 ";
        format = "[$symbol($version )]($style)";
        style = "${c.dark_blue}";
        disabled = false;
        detect_extensions = [ "lua" ];
        detect_files = [
          ".luarc.json"
          ".luacheckrc"
          "stylua.toml"
        ];
        detect_folders = [ ];
      };
      meson = {
        symbol = "󰔷 ";
        format = "[$symbol($version )]($style)";
        style = "${c.dark_grey}";
        disabled = true;
      };
      mise = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.yellow}";
        disabled = true;
      };
      mojo = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.red}";
        disabled = true;
      };
      nim = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.yellow}";
        disabled = true;
      };
      nodejs = {
        symbol = "󰎙 ";
        format = "[$symbol($version )]($style)";
        style = "${c.dark_blue}";
        disabled = false;
      };
      ocaml = {
        format = "[$symbol($version )]($style)";
        symbol = " ";
        style = "${c.yellow}";
        disabled = false;
        detect_extensions = [
          "ml"
          "mli"
          "re"
          "rei"
        ];
        detect_files = [
          "dune-project"
          "dune"
          "jbuild"
          ".merlin"
          "esy.lock"
        ];
        detect_folders = [ ];
      };
      odin = {
        format = "[$symbol($version )]($style)";
        symbol = "󰹩 ";
        style = "${c.blue_grey}";
        disabled = false;
        detect_extensions = [ "odin" ];
        detect_files = [ "ols.json" ];
        detect_folders = [ ];
      };
      opa = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.grey}";
        disabled = true;
      };
      perl = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.grey}";
        disabled = true;
      };
      php = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.grey}";
        disabled = true;
      };
      pixi = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.green}";
        disabled = true;
      };
      purescript = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.grey}";
        disabled = true;
      };
      python = {
        format = "[$symbol($version )]($style)";
        symbol = " ";
        style = "${c.yellow}";
        disabled = false;
        python_binary = [
          "python3"
          "python"
        ];
        detect_extensions = [ "py" ];
        detect_files = [
          "setup.py"
          "pyproject.toml"
          "requirements.txt"
          "__init__.py"
        ];
        detect_folders = [ ];
      };
      quarto = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.blue}";
        disabled = true;
      };
      raku = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.grey}";
        disabled = true;
      };
      red = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.red}";
        disabled = true;
      };
      rlang = {
        format = "[$symbol($version )]($style)";
        symbol = "󰟔 ";
        style = "${c.blue}";
        disabled = false;
        detect_extensions = [
          "R"
          "Rd"
          "Rmd"
          "Rproj"
        ];
        detect_files = [
          ".Rprofile"
          ".Rproj"
          "renv.lock"
        ];
        detect_folders = [ ];
      };
      ruby = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.red}";
        disabled = true;
      };
      rust = {
        symbol = " ";
        style = "${c.red}";
        disabled = false;
        detect_extensions = [ "rs" ];
        detect_files = [
          "Cargo.toml"
          "Cargo.lock"
        ];
        detect_folders = [ ];
      };
      scala = {
        format = "[$symbol($version )]($style)";
        symbol = " ";
        style = "${c.red}";
        disabled = false;
        detect_extensions = [
          "scala"
          "sbt"
        ];
        detect_files = [
          "build.sbt"
          "build.sc"
          "project/build.properties"
        ];
        detect_folders = [ ];
      };
      solidity = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.grey}";
        disabled = true;
      };
      swift = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.orange}";
        disabled = true;
      };
      typst = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.blue}";
        disabled = false;
      };
      vlang = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.blue}";
        disabled = true;
      };
      zig = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
        style = "${c.yellow}";
        disabled = false;
        detect_extensions = [
          "zig"
          "zon"
        ];
        detect_files = [
          "build.zig"
          "build.zig.zon"
        ];
        detect_folders = [ ];
      };

      # --- Shells ---
      shell = {
        format = "[$indicator]($style) ";
        style = "white dimmed";
        disabled = true;
        bash_indicator = " ";
        fish_indicator = "󰈺 ";
        zsh_indicator = "󰬡 ";
        powershell_indicator = "󰨊 ";
        ion_indicator = " ";
        elvish_indicator = " ";
        tcsh_indicator = " ";
        xonsh_indicator = " ";
        cmd_indicator = " ";
        nu_indicator = "󰿈 ";
        unknown_indicator = " ";
      };

      # --- System & Environment ---
      battery = {
        disabled = true;
        full_symbol = "󰁹 ";
        charging_symbol = "󰂄 ";
        discharging_symbol = "󰂃 ";
        unknown_symbol = "󰁽 ";
        empty_symbol = "󰂎 ";
      };
      jobs = {
        symbol = "⛭ ";
      };
      memory_usage = {
        symbol = "󰍛 ";
      };
      os.symbols = {
        AIX = " ";
        Alpaquita = " ";
        AlmaLinux = " ";
        Alpine = " ";
        Amazon = " ";
        Android = " ";
        Arch = " ";
        Artix = " ";
        CentOS = " ";
        Debian = " ";
        DragonFly = " ";
        Emscripten = " ";
        EndeavourOS = " ";
        Fedora = " ";
        FreeBSD = " ";
        Garuda = " ";
        Gentoo = " ";
        HardenedBSD = "󰞌 ";
        Illumos = "󰈸 ";
        Linux = " ";
        Mabox = " ";
        Macos = " ";
        Manjaro = " ";
        Mariner = " ";
        MidnightBSD = " ";
        Mint = " ";
        NetBSD = " ";
        NixOS = " ";
        OpenBSD = " ";
        openSUSE = " ";
        OracleLinux = "󰌷 ";
        Pop = " ";
        Raspbian = " ";
        Redhat = " ";
        RedHatEnterprise = " ";
        RockyLinux = " ";
        Redox = "󰀘 ";
        Solus = "󰠳 ";
        SUSE = " ";
        Ubuntu = " ";
        Unknown = " ";
        Windows = " ";
      };
      status = {
        symbol = "⨯";
        success_symbol = "✓";
        not_executable_symbol = "⊘";
        not_found_symbol = "?";
        sigint_symbol = "⊗";
        signal_symbol = "∿";
      };
      sudo = {
        symbol = "♰";
      };

      # --- Version Control ---
      git_branch = {
        disabled = false;
        format = "([$symbol$branch]($style) )";
        style = "bold ${c.purple}";
        symbol = " ";
      };
      git_state = {
        am = "✉";
        am_or_rebase = "⟳";
        bisect = "⊟";
        cherry_pick = "⊚";
        merge = "∩";
        rebase = "↻";
        revert = "↺";
      };
      git_status = {
        format = "([\\[$all_status$ahead_behind\\]]($style) )";
        style = "bold ${c.red}";
        ahead = "⇡";
        behind = "⇣";
        conflicted = "≠";
        deleted = "⨯";
        diverged = "⫩";
        modified = "◌";
        renamed = "↪";
        staged = "+";
        stashed = "‡";
        typechanged = "⊙";
        untracked = "?";
        up_to_date = "";
      };
      git_commit = {
        tag_symbol = "◈";
      };
      git_metrics = {
        disabled = false;
        added_style = "${c.purple}";
        deleted_style = "${c.purple}";
        format = "([\\[[$added]($added_style) ± [$deleted]($deleted_style)\\]](${c.purple}) )";
      };

      # --- Others ---
      fossil_branch = {
        symbol = "⌘";
      };
      hg_branch = {
        symbol = "☿";
      };
      pijul_channel = {
        symbol = "⊶";
      };
      vcsh = {
        symbol = "∇";
      };

      # --- Networking ---
      nats = {
        symbol = " ";
      };
      netns = {
        symbol = "󰀂 ";
      };

      # --- Misc ---
      fill = {
        symbol = " ";
      };
      line_break = {
        disabled = false;
      };
      spack = {
        symbol = " ";
      };
      singularity = {
        symbol = " ";
      };
    };
  };
}
