_: {
  flake.modules.nixos.kepler-development = {pkgs, ...}: {
    programs.tmux = {
      enable = true;
      terminal = "tmux-256color";
      extraConfig = "set -g status-right '#H | %H:%M'";
    };
    environment.systemPackages = [
      pkgs.ghostty.terminfo
      (pkgs.writeShellApplication {
        name = "tmux-resume";
        runtimeInputs = [pkgs.tmux pkgs.fzf];
        text = ''
          exec ${pkgs.python3}/bin/python3 ${../../terminal/_tmux-resume.py} "$@"
        '';
      })
    ];
  };
}
