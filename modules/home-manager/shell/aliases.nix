{...}: {
  # --- Archive Management ---
  untar = "tar -xvf";
  untargz = "tar -xzvf";
  untarxz = "tar -xJvf";

  # --- Disk Usage ---
  du = "dust"; # Better disk usage analyzer
  df = "duf"; # Better df alternative

  # --- Docker ---
  d = "docker";
  dc = "docker compose";
  dps = "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'";
  k = "kubectl";
  kct = "kubectx";
  kns = "kubens";
  kubelc = "kubelogin convert-kubeconfig -l azurecli";

  # --- Editor ---
  vim = "nvim";
  vi = "nvim";
  v = "nvim";

  # --- File Operations ---
  cp = "cp -iv"; # Interactive & verbose copy
  mv = "mv -iv"; # Interactive & verbose move
  mkdir = "mkdir -pv"; # Create parent dirs & verbose

  # --- General ---
  cl = "clear"; # Clear previous commands
  htop = "btm"; # Bottom
  neofetch = "fastfetch"; # Fetch
  nf = "fastfetch"; # Fetch
  notify-catch = ''dbus-monitor "interface='org.freedesktop.Notifications'"''; # Catch notificaton info sent by d-bus

  # --- Git ---
  gad = "git add ."; # Stage all files under current dir
  gbp = "cz bump"; # Bump version and update changelog (commitizen)
  gch = "cz changelog"; # Generate changelog (commitizen)
  gck = "cz check"; # Validate commit messages (commitizen)
  gcm = "cz commit"; # Create a new commit (commitizen)
  gin = "cz init"; # Initialize Commitizen configuration (commitizen)
  gpu = "git push -u origin main"; # Push to main
  grm = "git rm -rf --cached ."; # Remove remote cache recursive force
  gst = "git status"; # Check git repo status
  gvr = "cz version"; # Show version information (commitizen)

  # --- History ---
  h = "fzf-history-widget"; # Interactive history search
  hs = "history | rg"; # Ripgrep history
  hsi = "history | rg -i"; # Grep history ignore case
  hist = "fzf-history-widget";

  # --- Ides ---
  code = "code 2>/dev/null"; # Launch code cleanly
  cursor = "cursor 2>/dev/null"; # Launch cursor cleanly

  nrs = "sudo nixos-rebuild switch";
  urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
  urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

  # --- List ---
  # List ->
  # ls = "eza -l";
  ls = "eza --icons -la";
  la = "eza -la";
  llc = "eza -1";
  lac = "eza -1a";
  lld = "eza -l";
  lad = "eza -la";
  lli = "eza --icons -l";
  lai = "eza --icons -la";

  # --- Network ---
  ping = "gping"; # Graph ping with TUI
  dig = "dog"; # Modern DNS lookup
  ip = "ip -c"; # Colorized ip command
  myip = "curl -s ifconfig.me";

  # --- Quick Edits ---
  bashrc = "nvim ~/.bashrc";
  zshrc = "nvim ~/.zshrc";

  # --- Safety Nets ---
  chown = "chown --preserve-root";
  chmod = "chmod --preserve-root";
  chgrp = "chgrp --preserve-root";

  # --- Search ---
  locate = "plocate";
  fda = "fd -Lu"; # Find All

  # --- See-utils ---
  sa = "alias | fzf"; # See aliases
  sv = "env | sort | fzf"; # See environment vars

  # --- View ---
  cat = "bat";
  cata = "cat * | wl-copy";
}
