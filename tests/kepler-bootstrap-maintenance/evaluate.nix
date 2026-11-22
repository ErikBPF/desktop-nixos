let
  fixture = import ./fixture.nix;
in
  assert builtins.elem "multi-user.target" fixture.normalNodeK3sWantedBy;
  assert !(builtins.elem "k3s.service" fixture.manifest.wants);
  assert builtins.elem "k3s.service" fixture.manifest.after;
  assert fixture.manifest.remainAfterExit;
  assert builtins.match ".*/bin/systemctl is-active --quiet k3s.service" fixture.manifest.condition != null;
  assert !(builtins.elem "k3s.service" fixture.wants);
  assert builtins.elem "k3s.service" fixture.after;
  assert builtins.elem "multi-user.target" fixture.wantedBy;
  assert builtins.match ".*/bin/systemctl is-active --quiet k3s.service" fixture.condition != null;
  assert fixture.timer.OnBootSec == "30s";
  assert fixture.timer.OnUnitActiveSec == "15m"; "KEPLER_BOOTSTRAP_MAINTENANCE_EVAL_OK"
