{pkgs, ...}: {
  # Node.js and JavaScript packages
  environment.systemPackages = with pkgs; [
    # Node.js runtime
    nodejs_22

    # Package managers
    nodePackages.npm
    nodePackages.yarn
    nodePackages.pnpm

    # Development tools
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.eslint
    nodePackages.prettier
    nodePackages.nodemon
    nodePackages.npm-check-updates

    # Build tools
    nodePackages.webpack
  ];

  # Note: Install global packages after system rebuild with:
  # npm install -g @fission-ai/openspec@latest

  # Environment variables for Node.js
  environment.sessionVariables = {
    # Node.js settings

    NODE_PATH = "$HOME/.npm-packages/lib/node_modules:$NODE_PATH";
    NPM_CONFIG_PREFIX = "$HOME/.npm-packages";

    # Development settings
    NODE_ENV = "development";
    NODE_OPTIONS = "--max-old-space-size=4096";

    # npm settings
    NPM_CONFIG_FUND = "false";
    NPM_CONFIG_AUDIT = "false";
    NPM_CONFIG_UPDATE_NOTIFIER = "false";
  };

  # Create npm global directory and config
  system.activationScripts.npmSetup = ''
        for user in /home/*; do
          if [ -d "$user" ]; then
            username=$(basename "$user")
            # Create npm global directory
            mkdir -p "$user/.npm-packages"
            chown -R $username:users "$user/.npm-packages" 2>/dev/null || true

            # Create .npmrc config
            cat > "$user/.npmrc" << EOF
    prefix=$user/.npm-packages
    fund=false
    audit=false
    update-notifier=false
    EOF
            chown $username:users "$user/.npmrc" 2>/dev/null || true
          fi
        done
  '';
}
