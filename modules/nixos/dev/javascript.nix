{pkgs, ...}: {
  # Node.js and JavaScript packages
  environment.systemPackages = with pkgs; [
    # Node.js runtime
    nodejs_22
    
    # Package managers
    nodePackages.npm
    nodePackages.yarn
    nodePackages.pnpm
    
    # Global npm packages
    (pkgs.buildEnv {
      name = "nodejs-global-packages";
      paths = [
        (pkgs.runCommand "fission-openspec" {} ''
          mkdir -p $out/bin
          ${pkgs.nodejs_22}/bin/npm install -g --prefix $out @fission-ai/openspec@latest
        '')
      ];
    })
    
    # Development tools
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.eslint
    nodePackages.prettier
    nodePackages.nodemon
    nodePackages.npm-check-updates
    
    # Build tools
    nodePackages.webpack
    nodePackages.vite
    
    # Testing tools
    nodePackages.jest
  ];

  # Environment variables for Node.js
  environment.sessionVariables = {
    # Node.js settings
    NODE_PATH = "$HOME/.npm-global/lib/node_modules:$NODE_PATH";
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    
    # Development settings
    NODE_ENV = "development";
    NODE_OPTIONS = "--max-old-space-size=4096";
    
    # npm settings
    NPM_CONFIG_FUND = "false";
    NPM_CONFIG_AUDIT = "false";
    NPM_CONFIG_UPDATE_NOTIFIER = "false";
  };
}

