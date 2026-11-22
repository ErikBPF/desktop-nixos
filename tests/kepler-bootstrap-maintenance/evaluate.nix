let
  fixture = import ./fixture.nix;
in
  assert !(builtins.elem "k3s.service" fixture.wants);
  assert builtins.elem "k3s.service" fixture.after;
  assert builtins.elem "multi-user.target" fixture.wantedBy;
  assert builtins.match ".*/bin/systemctl is-active --quiet k3s.service" fixture.condition != null;
  assert fixture.timer.OnBootSec == "30s";
  assert fixture.timer.OnUnitActiveSec == "15m"; "KEPLER_BOOTSTRAP_MAINTENANCE_EVAL_OK"
