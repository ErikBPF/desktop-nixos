_: {
  flake.modules.nixos.dev-javascript = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      nodejs_22
      nodePackages.npm
      nodePackages.yarn
      nodePackages.pnpm
      nodePackages.typescript
      nodePackages.typescript-language-server
      nodePackages.eslint
      nodePackages.prettier
      nodePackages.nodemon
      nodePackages.npm-check-updates
    ];

    environment.sessionVariables = {
      NODE_PATH = "$HOME/.npm-packages/lib/node_modules:$NODE_PATH";
      NPM_CONFIG_PREFIX = "$HOME/.npm-packages";
      NODE_ENV = "development";
      NODE_OPTIONS = "--max-old-space-size=4096";
      NPM_CONFIG_FUND = "false";
      NPM_CONFIG_AUDIT = "false";
      NPM_CONFIG_UPDATE_NOTIFIER = "false";
    };

    system.activationScripts.npmSetup = ''
          for user in /home/*; do
            if [ -d "$user" ]; then
              username=$(basename "$user")
              mkdir -p "$user/.npm-packages"
              chown -R $username:users "$user/.npm-packages" 2>/dev/null || true
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
  };
}
