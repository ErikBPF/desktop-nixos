_: {
  flake.modules.nixos.audio = {pkgs, ...}: let
    # Virtual "Filtered Microphone" exposed by the filter-chain below.
    virtSrc = "effect_output.deepfilter";
    # Capture side of the filter-chain (where the real mic feeds in).
    filtIn = "effect_input.deepfilter";

    # Tier-2 hotplug daemon: keeps the DeepFilter capture wired to whatever the
    # active hardware mic is, and re-asserts the treated source as the default.
    # The capture node has autoconnect=false (see filter-chain config) so it never
    # auto-links to the default source — that would feed the virtual source back
    # into itself. Only this script links it, deterministically.
    autobind = pkgs.writeShellApplication {
      name = "deepfilter-autobind";
      runtimeInputs = with pkgs; [pipewire wireplumber jq gnugrep coreutils];
      text = ''
        FILT_IN="${filtIn}"
        VIRT_SRC="${virtSrc}"

        log() { echo "deepfilter-autobind: $*" >&2; }

        mic_output_ports() { pw-link -o 2>/dev/null | grep -E "^$1:" || true; }
        filter_input_ports() { pw-link -i 2>/dev/null | grep -E "^''${FILT_IN}:" || true; }

        # Reconcile from a single pw-dump snapshot (passed on stdin as $1's source
        # is the cached dump). Poll-based, NOT event-based: every pw-dump/pw-link/
        # wpctl call is itself a transient pipewire client whose connect+disconnect
        # emits bus events — a pw-mon watcher would react to its own footprints and
        # spin forever. Polling a cached snapshot sidesteps that entirely.
        # Idempotent: relink only when the bound mic changed; set-default only when
        # the treated source isn't already the default.
        reconcile() {
          local dump fid mic linked curdef vid inports outports

          dump="$(pw-dump)" || return 0

          fid="$(jq -r --arg n "$FILT_IN" \
            'first(.[]|select(.info.props["node.name"]==$n)|.id)//empty' <<< "$dump")"
          [ -z "$fid" ] && return 0 # filter graph not up yet

          mic="$(jq -r '
            [ .[]
              | select(.info.props["media.class"]=="Audio/Source")
              | select((.info.props["node.name"]//"")|startswith("alsa_input.")) ]
            | sort_by(.info.props["priority.session"]//0) | reverse
            | (.[0].info.props["node.name"])//empty' <<< "$dump")"
          [ -z "$mic" ] && return 0 # no hardware mic present

          linked="$(jq -r --arg fid "$fid" '
            (map(select(.type=="PipeWire:Interface:Node"))
             | map({key:(.id|tostring), value:.info.props["node.name"]}) | from_entries) as $names
            | .[] | select(.type=="PipeWire:Interface:Link")
                  | select(((.info.props["link.input.node"])|tostring)==$fid)
                  | $names[((.info.props["link.output.node"])|tostring)]//empty' <<< "$dump" \
            | sort -u)"

          if [ "$linked" != "$mic" ]; then
            # drop stale links, then mix every mic capture port into the (mono)
            # filter input. Handles mono mics (capture_MONO) and stereo (FL/FR).
            jq -r --arg fid "$fid" '
              .[] | select(.type=="PipeWire:Interface:Link")
                  | select(((.info.props["link.input.node"])|tostring)==$fid) | .id' <<< "$dump" \
              | while read -r lid; do [ -n "$lid" ] && pw-link -d "$lid" 2>/dev/null || true; done
            inports="$(filter_input_ports)"
            outports="$(mic_output_ports "$mic")"
            if [ -n "$inports" ] && [ -n "$outports" ]; then
              while read -r op; do
                [ -z "$op" ] && continue
                while read -r ip; do
                  [ -z "$ip" ] && continue
                  pw-link "$op" "$ip" 2>/dev/null || true
                done <<< "$inports"
              done <<< "$outports"
              log "bound $mic -> deepfilter"
            fi
          fi

          curdef="$(jq -r '
            first(.[]|select(.type=="PipeWire:Interface:Metadata")
                     |.metadata[]?|select(.key=="default.audio.source")|.value.name)//empty' <<< "$dump")"
          if [ "$curdef" != "$VIRT_SRC" ]; then
            vid="$(jq -r --arg n "$VIRT_SRC" \
              'first(.[]|select(.info.props["node.name"]==$n)|.id)//empty' <<< "$dump")"
            [ -n "$vid" ] && wpctl set-default "$vid" 2>/dev/null \
              && log "default source -> $VIRT_SRC"
          fi
        }

        # Poll. 5s is well under human hotplug expectations; reconcile is a no-op
        # (no pipewire mutations, just one pw-dump) when nothing moved.
        while true; do
          reconcile
          sleep 5
        done
      '';
    };
  in {
    services.pulseaudio.enable = false;
    services.pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
      jack.enable = true;
      wireplumber.enable = true;
      # Makes libdeep_filter_ladspa.so resolvable on pipewire's LADSPA_PATH.
      extraLadspaPackages = [pkgs.deepfilternet];

      # Declarative DeepFilterNet noise-cancelling source. Replaces NoiseTorch:
      # same idea (RNNoise/DeepFilter LADSPA plugin in a PipeWire filter-chain),
      # but no GUI, no setcap wrapper, survives reboot. High priority.session so
      # wireplumber picks it as the default mic; the daemon above re-asserts it.
      extraConfig.pipewire."99-deepfilter-source" = {
        "context.modules" = [
          {
            name = "libpipewire-module-filter-chain";
            args = {
              "node.description" = "Filtered Microphone (DeepFilter)";
              "media.name" = "Filtered Microphone (DeepFilter)";
              "filter.graph" = {
                nodes = [
                  {
                    type = "ladspa";
                    name = "deepfilter";
                    # Bare name, not an absolute path: pipewire's ladspa loader
                    # always prepends its LADSPA search dirs, so an abspath turns
                    # into "/usr/lib/ladspa//nix/store/…" → ENOENT. The dir is
                    # supplied via LADSPA_PATH on pipewire.service below.
                    plugin = "libdeep_filter_ladspa";
                    label = "deep_filter_mono";
                    # 100 = full suppression; 18-24 medium; 6-12 minimal.
                    # 30 = balanced: kills steady background, keeps voice natural.
                    control."Attenuation Limit (dB)" = 30;
                  }
                ];
              };
              "audio.rate" = 48000;
              "audio.position" = ["MONO"];
              "capture.props" = {
                "node.name" = filtIn;
                "node.passive" = true;
                # Never auto-link: only deepfilter-autobind wires this, so the
                # virtual source can be default without feeding back into itself.
                "node.autoconnect" = false;
              };
              "playback.props" = {
                "node.name" = virtSrc;
                "media.class" = "Audio/Source";
                "priority.session" = 2000;
              };
            };
          }
        ];
      };
    };
    security.rtkit.enable = true;

    systemd.user.services.deepfilter-autobind = {
      description = "Wire DeepFilter noise-cancel source to the active mic and keep it default";
      after = ["pipewire.service" "wireplumber.service"];
      wantedBy = ["default.target"];
      serviceConfig = {
        ExecStart = "${autobind}/bin/deepfilter-autobind";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
