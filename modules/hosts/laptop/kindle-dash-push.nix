{...}: {
  # Pushes today's Claude Code usage tally from this workstation's ~/.claude
  # session logs to the kindle-dash renderer on discovery. The Pro/Max limit %
  # has no API (see docs), so we report the only locally-available real number:
  # tokens spent today, summed from the session JSONL. The dashboard draws it as
  # a bar against a soft target. cost is left null (pricing is model-specific).
  flake.modules.nixos.laptop-kindle-dash-push = {
    config,
    pkgs,
    ...
  }: let
    # discovery LAN IP : kindle-dash published port (see servarr kindle-dash.yml)
    dashUrl = "http://192.168.10.210:8810/claude-usage";

    pushScript = pkgs.writeText "kindle-dash-push.py" ''
      import glob, json, os, urllib.request
      from datetime import datetime

      URL = "${dashUrl}"
      home = os.path.expanduser("~")
      today = datetime.now().astimezone().date()
      total = 0

      for path in glob.glob(os.path.join(home, ".claude", "projects", "**", "*.jsonl"), recursive=True):
          try:
              with open(path) as f:
                  for line in f:
                      line = line.strip()
                      if not line:
                          continue
                      try:
                          rec = json.loads(line)
                      except Exception:
                          continue
                      ts = rec.get("timestamp")
                      if not ts:
                          continue
                      try:
                          d = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().date()
                      except Exception:
                          continue
                      if d != today:
                          continue
                      usage = (rec.get("message") or {}).get("usage") or {}
                      # input + output + cache-creation. Cache *reads* are excluded:
                      # they run to billions and are near-free, so including them
                      # would swamp the bar and make it meaningless.
                      total += (
                          usage.get("input_tokens", 0)
                          + usage.get("output_tokens", 0)
                          + usage.get("cache_creation_input_tokens", 0)
                      )
          except OSError:
              continue

      body = json.dumps({"tokens": total, "cost": None}).encode()
      req = urllib.request.Request(
          URL, data=body, headers={"Content-Type": "application/json"}, method="POST"
      )
      try:
          urllib.request.urlopen(req, timeout=10)
          print(f"pushed {total} tokens")
      except Exception as e:
          print(f"push failed: {e}")
          raise SystemExit(1)
    '';
  in {
    systemd.services.kindle-dash-push = {
      description = "Push today's Claude usage tally to kindle-dash on discovery";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        User = config.username;
        ExecStart = "${pkgs.python3}/bin/python3 ${pushScript}";
      };
    };

    systemd.timers.kindle-dash-push = {
      description = "Timer: push Claude usage tally to kindle-dash";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "10min";
        Persistent = true;
      };
    };
  };
}
