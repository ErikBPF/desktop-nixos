_: {
  # LACT undervolt / OC profile for Orion's RX 9070 XT (gfx1201).
  #
  # Stage B from servarr/machines/orion/KERNEL-TUNING.md item 9 (LLM undervolt).
  # Targets sustained-boost stability for 24/7 llama-chat inference, not peak
  # benchmark scores. Numbers from the community-benchmark research in the
  # KERNEL-TUNING.md note + per-GPU info LACT reported on Orion:
  #
  #   GPU: AMD Radeon RX 9070 XT (ASRock, vbios 023.008.000.068.000001)
  #   Stock power limit: 304W (range 212-374W, hardware enforced)
  #   Stock memory clock: 1258 MHz
  #
  # Stage B knobs:
  #   voltage_offset:    -80 mV  (community-validated sweet spot; -110 mV is
  #                               unstable on most samples)
  #   max_memory_clock:  1375 MHz (+9.3% — proven uplift in llama.cpp
  #                               discussion #21043; GDDR6 has no ECC, watch
  #                               for token-determinism regressions)
  #   power_cap:         274 W   (-10% from 304W; matches the "-10% with
  #                               -80mV" combo reported by pixelrtx.com 9070
  #                               XT test)
  #   fan_control:       longevity-biased curve keyed on junction temp.
  #                               24/7 inference makes fan bearing wear the
  #                               real failure mode — not thermal headroom.
  #                               Caps at 85% even at sustained 92°C; never
  #                               100%. If junction climbs past 92°C, the
  #                               cabinet airflow is the bottleneck, not the
  #                               GPU fan duty cycle. RDNA4 hardware throttle
  #                               trips around 95°C junction, well above our
  #                               curve's ceiling, so the kernel will protect
  #                               the silicon if airflow ever fails.
  #
  # PCI ID captured from `lact cli list` on the host (ASRock 9070 XT in PCIe
  # slot 0a:00.0). Will change if the card is moved between slots.
  #
  # Determinism gate before promoting this profile from staging to "good":
  #   1. boot, lactd active, lact cli stats shows offsets applied
  #   2. benchmark.sh post-uv-b
  #   3. uv-validate.sh: 3x prompt at temp=0 seed=42, byte-diff outputs
  #   4. 30-min sustained inference loop, no vk::DeviceLost in dmesg
  #
  # Rollback (no rebuild):
  #   sudo systemctl stop lactd amdgpu-od-apply
  #   for f in /sys/class/drm/card*/device/pp_od_clk_voltage; do
  #     echo r | sudo tee "$f" >/dev/null
  #   done
  # Or remove this module.
  #
  # YAML is written literally so integer fan-curve keys and floats survive
  # round-tripping (lib.generators.toYAML emits JSON-flow style which serde
  # may not accept for HashMap<u32, f32>).
  #
  # Fan curve constraint: RDNA4 PMFW exposes a fixed-size 5-point curve
  # table. More points cause LACT to reject the whole config apply with
  # "The GPU only supports 5 curve points, given N", silently skipping
  # voltage_offset and clocks as a side effect. Keep curve at exactly 5.
  # Inline YAML comments must not be added inside the heredoc — they
  # offset surrounding indentation and corrupt the deserialiser.
  flake.modules.nixos.orion-lact = {
    pkgs,
    config,
    lib,
    ...
  }: let
    cfg = config.orionGpu;
    # Two GPU tuning profiles (see options.orionGpu.profile below):
    #   inference = +9.3% mem OC (1375) + 274W — 24/7 llama-chat throughput.
    #   training  = STOCK mem (1258) + 230W — the +9.3% GDDR6 OC is the prime
    #               trigger for the "data fabric sync flood" MCE (a memory/
    #               Infinity-Fabric error) under sustained LoRA load; drop it +
    #               trim power transients. Pairs with processor.max_cstate=1.
    memClock =
      if cfg.profile == "training"
      then 1258
      else 1375;
    powerCap =
      if cfg.profile == "training"
      then "230.0"
      else "274.0";
    # training = STOCK voltage (0mV). The -80mV undervolt (fine for inference)
    # starves compute under sustained LoRA load → "Memory access fault by GPU
    # node" (UTCL2/TCP page fault). 0mV gives the voltage headroom training needs.
    voltageOffset =
      if cfg.profile == "training"
      then 0
      else -80;
    lactConfigYaml = ''
      version: 5
      apply_settings_timer: 5
      auto_switch_profiles: false
      current_profile: null
      daemon:
        log_level: info
        admin_group: wheel
        # disable_clocks_cleanup: true is required while amdgpu-od-apply is
        # the source of truth for voltage_offset / max_memory_clock. With
        # cleanup enabled, lactd resets pp_od_clk_voltage to zero on every
        # config reload or shutdown; because LACT 0.9.0 silently no-ops the
        # subsequent clocks_configuration write on RDNA4, the reset wins and
        # the -80mV / 1375MHz values disappear. Once LACT lands RDNA4 OD
        # support, flip this back to false so the daemon owns the lifecycle.
        disable_clocks_cleanup: true
      gpus:
        "1002:7550-1849:5417-0000:0a:00.0":
          performance_level: manual
          fan_control_enabled: true
          fan_control_settings:
            mode: curve
            static_speed: 0.5
            temperature_key: junction
            interval_ms: 500
            spindown_delay_ms: 5000
            change_threshold: 3
            curve:
              45: 0.20
              60: 0.35
              75: 0.55
              85: 0.75
              92: 0.85
          power_cap: ${powerCap}
          clocks_configuration:
            voltage_offset: ${toString voltageOffset}
            max_memory_clock: ${toString memClock}
      profiles: {}
    '';
  in {
    options.orionGpu.profile = lib.mkOption {
      type = lib.types.enum ["training" "inference"];
      default = "inference";
      description = ''
        orion RX 9070 XT (gfx1201) GPU tuning profile.
        "inference": +9.3% memory OC (1375 MHz) + 274 W cap — max 24/7
          llama-chat throughput (default; the served-brain steady state).
        "training": stock memory (1258 MHz) + 230 W cap — drops the mem OC
          that triggers the data-fabric-sync-flood under sustained LoRA load.
          Switch to this before an orion training run, back after.
      '';
    };
    config = {
      # LACT 0.9.0 honours `performance_level`, `power_cap`, and the fan curve
      # on RDNA4, but silently skips `clocks_configuration` writes (no error in
      # journal — pp_od_clk_voltage stays at zero). Apply voltage offset and
      # memory clock directly to sysfs after lactd has flipped the perf level
      # to manual. Direct writes are confirmed working on the host:
      #   $ echo "vo -80" >  /sys/class/drm/card1/device/pp_od_clk_voltage
      #   $ echo "m 1 1375" >  ...
      #   $ echo "c" >  ...
      # leaves VDDGFX_OFFSET=-80mV and OD_MCLK upper bound at 1375MHz.
      #
      # When LACT lands a fix for RDNA4 OD (track ilya-zlobintsev/LACT), delete
      # this service and let LACT own the apply.
      systemd.services.amdgpu-od-apply = {
        description = "Apply RDNA4 OD voltage offset + mem clock (LACT 0.9.0 workaround)";
        # wantedBy=lactd.service (not multi-user.target). LACT's upstream unit
        # declares BOTH After=multi-user.target and WantedBy=multi-user.target,
        # so a sibling oneshot ordered After=lactd.service AND
        # WantedBy=multi-user.target produces "Found ordering cycle:
        # amdgpu-od-apply -> lactd -> multi-user.target -> amdgpu-od-apply" and
        # systemd silently drops the start job. Anchoring this service's
        # wantedBy to lactd.service activates it whenever lactd starts (which
        # is at multi-user.target by transitive want) without entering the
        # cycle.
        wantedBy = ["lactd.service"];
        after = ["lactd.service"];
        # bindsTo (not requires): propagates stop signals from lactd back to
        # this oneshot. A `systemctl restart lactd` (or any nixos-rebuild
        # switch that re-runs lactd) stops amdgpu-od-apply and re-triggers it
        # via the wantedBy=lactd.service wiring, so OD is re-applied after
        # lactd comes back up. With plain `requires` the oneshot stays
        # Active=yes forever and the OD writes are never repeated.
        bindsTo = ["lactd.service"];
        # Re-run on any LACT config change. lactd does a file-watch reload
        # (not a service restart) when /etc/lact/config.yaml changes, so
        # bindsTo alone does not catch config-only `nixos-rebuild switch`.
        # restartTriggers re-stamps amdgpu-od-apply whenever the config text
        # changes, ensuring OD values are re-applied right after lactd reloads.
        restartTriggers = [lactConfigYaml];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # Resolve the amdgpu sysfs node at runtime. DRM card numbering is not
          # guaranteed stable across kernel/firmware updates; hardcoding card1
          # silently breaks if enumeration shifts.
          SYSFS=$(${pkgs.coreutils}/bin/ls /sys/class/drm/card*/device/pp_od_clk_voltage 2>/dev/null | ${pkgs.coreutils}/bin/head -1)
          if [ -z "$SYSFS" ]; then
            echo "amdgpu pp_od_clk_voltage node not found — aborting" >&2
            exit 1
          fi
          PERF_LEVEL=$(${pkgs.coreutils}/bin/dirname "$SYSFS")/power_dpm_force_performance_level

          # Wait for lactd to flip perf level to manual (it writes synchronously
          # at startup, but the file may briefly read "auto" during init).
          for i in $(${pkgs.coreutils}/bin/seq 1 20); do
            if [ "$(${pkgs.coreutils}/bin/cat "$PERF_LEVEL")" = "manual" ]; then break; fi
            ${pkgs.coreutils}/bin/sleep 0.5
          done
          ${pkgs.coreutils}/bin/echo manual    > "$PERF_LEVEL"
          ${pkgs.coreutils}/bin/echo "vo ${toString voltageOffset}" > "$SYSFS"
          ${pkgs.coreutils}/bin/echo "m 1 ${toString memClock}" > "$SYSFS"
          ${pkgs.coreutils}/bin/echo "c"        > "$SYSFS"
        '';
      };

      environment.etc."lact/config.yaml".text = lactConfigYaml;
    };
  };
}
