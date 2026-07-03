{inputs, ...}: {
  # Neovim as a VSCode-like editor, fully declarative via nixvim (plugins pinned
  # to nixpkgs). Complements the lean VSCode setup — this one works in a
  # terminal / over SSH / inside zellij. LSP + formatters mirror the languages
  # used across this flake and its sister repos, and obey the same tools as CI
  # (alejandra, statix, ruff).
  flake.modules.home.nvim = {pkgs, ...}: {
    imports = [inputs.nixvim.homeModules.nixvim];

    programs.nixvim = {
      enable = true;
      defaultEditor = false; # leave $EDITOR as-is (cursor); nvim is opt-in

      # Formatter/linter binaries on nvim's PATH (conform/nvim-lint call these).
      extraPackages = with pkgs; [
        alejandra # nix fmt (same as `just fmt`)
        statix # nix lint (same as `just lint`)
        black
        isort # python fmt
        ruff # python lint
        gofumpt # go fmt
        prettierd # js/ts/json/yaml/md fmt
        shfmt # bash fmt
        stylua # lua fmt
        taplo # toml fmt/lsp
        qt6.qtdeclarative # qmlls (quickshell)
      ];

      globals.mapleader = " ";

      opts = {
        number = true;
        mouse = "a"; # full mouse support
        termguicolors = true;
        signcolumn = "yes";
        expandtab = true;
        shiftwidth = 2;
        tabstop = 2;
        smartindent = true;
        ignorecase = true;
        smartcase = true;
        scrolloff = 6;
        clipboard = "unnamedplus"; # share system clipboard (wl-clipboard)
        spell = true;
        spelllang = ["en" "pt_br"]; # matches your VSCode EN + PT-BR spell
      };

      # Tokyonight to match the desktop theme.
      colorschemes.tokyonight = {
        enable = true;
        settings.style = "night";
      };

      plugins = {
        web-devicons.enable = true; # icons, required by neo-tree/bufferline
        neo-tree.enable = true; # file-tree sidebar
        bufferline.enable = true; # editor tabs
        lualine.enable = true; # statusline
        which-key.enable = true; # keybinding hints
        gitsigns.enable = true; # git gutter signs
        treesitter.enable = true; # syntax
        comment.enable = true; # gc / gcc to toggle comments
        nvim-autopairs.enable = true;

        # --- Editor QoL (VSCode analogs) ---
        toggleterm.enable = true; # integrated terminal
        trouble.enable = true; # Problems / diagnostics panel
        todo-comments.enable = true; # highlight TODO/FIXME/HACK
        indent-blankline.enable = true; # indent guides
        colorizer.enable = true; # inline hex colour swatches
        render-markdown.enable = true; # pretty in-buffer markdown
        flash.enable = true; # jump-anywhere motion

        telescope = {
          enable = true; # fuzzy finder
          extensions.fzf-native.enable = true; # faster sorting
        };

        # Completion, VSCode-style.
        cmp = {
          enable = true;
          autoEnableSources = true;
          settings.sources = [
            {name = "nvim_lsp";}
            {name = "path";}
            {name = "buffer";}
          ];
          settings.mapping = {
            "<C-Space>" = "cmp.mapping.complete()";
            "<CR>" = "cmp.mapping.confirm({ select = true })";
            "<Tab>" = "cmp.mapping.select_next_item()";
            "<S-Tab>" = "cmp.mapping.select_prev_item()";
          };
        };

        # Format on save — mirrors `just fmt` toolchain.
        conform-nvim = {
          enable = true;
          settings = {
            format_on_save = {
              timeout_ms = 1500;
              lsp_format = "fallback";
            };
            formatters_by_ft = {
              nix = ["alejandra"];
              python = ["isort" "black"];
              go = ["gofumpt"];
              javascript = ["prettierd"];
              typescript = ["prettierd"];
              json = ["prettierd"];
              yaml = ["prettierd"];
              markdown = ["prettierd"];
              sh = ["shfmt"];
              bash = ["shfmt"];
              lua = ["stylua"];
              toml = ["taplo"];
            };
          };
        };

        # Linting — same tools as CI.
        lint = {
          enable = true;
          lintersByFt = {
            nix = ["statix"];
            python = ["ruff"];
          };
        };

        # LSP — covers every language in the flake + sister repos.
        lsp = {
          enable = true;
          servers = {
            nixd.enable = true; # nix (flake-aware; better than nil for this repo)
            lua_ls.enable = true;
            gopls.enable = true;
            pyright.enable = true;
            ts_ls.enable = true; # js/ts
            yamlls.enable = true; # k8s/compose/HA/alloy
            taplo.enable = true; # toml
            jsonls.enable = true;
            marksman.enable = true; # markdown
            bashls.enable = true;
            terraformls.enable = true; # homelab-iac
            dockerls.enable = true;
            docker_compose_language_service.enable = true; # servarr
            protols.enable = true; # protobuf
            qmlls.enable = true; # quickshell
          };
        };
      };

      # Trigger nvim-lint on the usual events.
      autoCmd = [
        {
          event = ["BufWritePost" "BufReadPost" "InsertLeave"];
          callback.__raw = "function() require('lint').try_lint() end";
        }
      ];

      # VSCode-like keybinds.
      keymaps = [
        {
          mode = "n";
          key = "<C-p>";
          action = "<cmd>Telescope find_files<cr>";
          options.desc = "Quick open (find files)";
        }
        {
          mode = "n";
          key = "<C-b>";
          action = "<cmd>Neotree toggle<cr>";
          options.desc = "Toggle file sidebar";
        }
        {
          mode = "n";
          key = "<leader>fg";
          action = "<cmd>Telescope live_grep<cr>";
          options.desc = "Search in files";
        }
        {
          mode = "n";
          key = "<leader>e";
          action = "<cmd>Neotree focus<cr>";
          options.desc = "Focus file sidebar";
        }
        {
          mode = "n";
          key = "<leader>xx";
          action = "<cmd>Trouble diagnostics toggle<cr>";
          options.desc = "Diagnostics panel";
        }
        {
          mode = "n";
          key = "<leader>tt";
          action = "<cmd>ToggleTerm<cr>";
          options.desc = "Toggle terminal";
        }
        {
          mode = "n";
          key = "<leader>f";
          action.__raw = "function() require('conform').format({ async = true, lsp_format = 'fallback' }) end";
          options.desc = "Format buffer";
        }
      ];
    };
  };
}
