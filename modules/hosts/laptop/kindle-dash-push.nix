{config, ...}: let
  inherit (config) username;
in {
  # Pushes the real Claude subscription usage from this workstation to the
  # kindle-dash renderer on discovery. Source is `claude -p /usage`, which
  # reports the actual Pro/Max limits (session % + weekly %); we parse those
  # and POST them. Machine-local — does not include other devices or claude.ai.
  flake.modules.nixos.laptop-kindle-dash-push = {pkgs, ...}: let
    # kindle-dash via SWAG on discovery (plain-HTTP :80, LAN-only vhost — the
    # jailbroken Kindle can't do modern TLS, so this is not HTTPS).
    dashUrl = "http://kindle.homelab.pastelariadev.com/claude-usage";

    pushScript = pkgs.writeText "kindle-dash-push.py" ''
      import json, re, subprocess, urllib.request

      URL = "${dashUrl}"
      CLAUDE = "${pkgs.claude-code}/bin/claude"

      try:
          out = subprocess.run(
              [CLAUDE, "-p", "/usage"],
              capture_output=True, text=True, timeout=90,
          ).stdout
      except Exception as e:
          print(f"claude -p /usage failed: {e}")
          raise SystemExit(1)

      def parse(label):
          m = re.search(label + r"\s*(\d+)% used(?:\s*.\s*resets\s*([^()\n]+))?", out)
          if not m:
              return None, None
          return int(m.group(1)), (m.group(2) or "").strip()

      s_pct, s_reset = parse(r"Current session:")
      w_pct, w_reset = parse(r"Current week \(all models\):")

      if s_pct is None and w_pct is None:
          print("could not parse /usage output:\n" + out[:500])
          raise SystemExit(1)

      body = json.dumps({
          "session_pct": s_pct, "session_reset": s_reset,
          "week_pct": w_pct, "week_reset": w_reset,
      }).encode()
      req = urllib.request.Request(
          URL, data=body, headers={"Content-Type": "application/json"}, method="POST"
      )
      try:
          urllib.request.urlopen(req, timeout=10)
          print(f"pushed session={s_pct}% week={w_pct}%")
      except Exception as e:
          print(f"push failed: {e}")
          raise SystemExit(1)
    '';
  in {
    systemd.services.kindle-dash-push = {
      description = "Push real Claude usage (claude -p /usage) to kindle-dash on discovery";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        User = username;
        # claude -p /usage needs the user's HOME (auth/config in ~/.claude).
        Environment = "HOME=/home/${username}";
        TimeoutStartSec = "120";
        ExecStart = "${pkgs.python3}/bin/python3 ${pushScript}";
      };
    };

    systemd.timers.kindle-dash-push = {
      description = "Timer: push Claude usage to kindle-dash";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "10min";
        Persistent = true;
      };
    };
  };
}
