{
  flake.modules.home.monitor-layout-docked = {lib, ...}: let
    c1Description = "Samsung Electric Company C27F390 HX5MB00876";
    c1 = "desc:${c1Description}";
    hotplugRecoveryDelayMs = 1000;
  in {
    wayland.windowManager.hyprland.settings = {
      on = [
        {
          _args = [
            "monitor.added"
            (lib.generators.mkLuaInline ''
              function(m)
                local c1Description = "${c1Description}"
                local hotplugRecoveryDelayMs = ${toString hotplugRecoveryDelayMs}
                if m.description ~= c1Description then
                  return
                end

                hl.timer(function()
                  local workspace = hl.get_workspace(10)
                  local target = hl.get_monitor("desc:" .. c1Description)
                  if workspace == nil or target == nil then
                    return
                  end

                  local wasActive = workspace.active
                  if workspace.monitor ~= nil and workspace.monitor.id == target.id then
                    for _, fallback in ipairs(hl.get_monitors()) do
                      if fallback.id ~= target.id then
                        hl.dispatch(hl.dsp.workspace.move({ workspace = workspace, monitor = fallback }))
                        break
                      end
                    end
                  end

                  hl.dispatch(hl.dsp.workspace.move({ workspace = workspace, monitor = target }))
                  if wasActive then
                    target:set_workspace({ workspace = workspace })
                  end
                end, { timeout = hotplugRecoveryDelayMs, type = "oneshot" })
              end
            '')
          ];
        }
      ];

      monitor = [
        {
          output = "";
          mode = "preferred";
          position = "auto";
          scale = 1;
        }
        {
          output = "eDP-1";
          mode = "preferred";
          position = "1400x1680";
          scale = 1;
        }
        {
          output = "desc:Samsung Electric Company QBQ90 0x01000E00";
          mode = "2560x1440";
          position = "1080x240";
          scale = 1;
          bitdepth = 10;
        }
        {
          output = "desc:Samsung Electric Company C27F390 HX5MB00876";
          mode = "1920x1080";
          position = "0x0";
          scale = 1;
          transform = 1;
        }
        {
          output = "desc:Samsung Electric Company C27F390 HX5MB00881";
          mode = "1920x1080";
          position = "3640x0";
          scale = 1;
          transform = 3;
        }
      ];

      workspace_rule = let
        qbq = "desc:Samsung Electric Company QBQ90 0x01000E00";
        c2 = "desc:Samsung Electric Company C27F390 HX5MB00881";
      in
        (map (workspace:
          {
            inherit workspace;
            monitor = qbq;
          }
          // (
            if workspace == "1"
            then {default = true;}
            else {}
          ))
        (map toString (builtins.genList (i: i + 1) 9)))
        ++ [
          {
            workspace = "10";
            monitor = c1;
          }
          {
            workspace = "11";
            monitor = c2;
          }
          {
            workspace = "12";
            monitor = "eDP-1";
          }
        ];
    };
  };

  flake.modules.home.monitor-layout-pathfinder = _: {
    wayland.windowManager.hyprland.settings = {
      monitor = [
        {
          output = "DP-1";
          mode = "1920x1080@60";
          position = "0x0";
          scale = 1;
        }
      ];
      workspace_rule = map (workspace:
        {
          inherit workspace;
          monitor = "DP-1";
        }
        // (
          if workspace == "1"
          then {default = true;}
          else {}
        )) (map toString (builtins.genList (i: i + 1) 5));
    };
  };
}
