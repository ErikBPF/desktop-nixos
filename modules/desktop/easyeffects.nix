_: {
  flake.modules.home.easyeffects = {lib, ...}: let
    # EasyEffects EQ presets, each a parametric EQ derived from AutoEq's
    # optimizer run against the named measurement. Filter type maps to
    # EasyEffects band types: PK→Bell, LSC→Lo-shelf, HSC→Hi-shelf. The APO
    # "Preamp" becomes the equalizer input-gain (headroom so positive-gain
    # bands never clip).
    mkBand = i: f:
      lib.nameValuePair "band${toString i}" {
        inherit (f) type frequency gain q;
        mode = "RLC (BT)";
        slope = "x1";
        mute = false;
        solo = false;
      };
    mkPreset = {
      preamp,
      filters,
    }: let
      # split-channels=false → only the left bank applies; mirror to right so
      # the preset stays self-consistent if channels are split in the GUI.
      bands = builtins.listToAttrs (lib.imap0 mkBand filters);
    in {
      output = {
        blocklist = [];
        plugins_order = ["equalizer"];
        equalizer = {
          bypass = false;
          input-gain = preamp;
          output-gain = 0.0;
          mode = "IIR";
          num-bands = builtins.length filters;
          split-channels = false;
          left = bands;
          right = bands;
        };
      };
    };
  in {
    services.easyeffects = {
      enable = true;
      # Zero:RED is the daily driver; the others are activated on demand from
      # the EasyEffects preset picker.
      preset = "truthear-zero-red-crinacle";
      extraPresets = {
        # TRUTHEAR x Crinacle Zero:RED — crinacle 711-coupler measurement.
        truthear-zero-red-crinacle = mkPreset {
          preamp = -3.2;
          filters = [
            {
              type = "Lo-shelf";
              frequency = 105;
              gain = 1.5;
              q = 0.7;
            }
            {
              type = "Bell";
              frequency = 6877;
              gain = 3.9;
              q = 0.5;
            }
            {
              type = "Bell";
              frequency = 335;
              gain = -1.2;
              q = 1.26;
            }
            {
              type = "Bell";
              frequency = 1556;
              gain = -2.0;
              q = 2.24;
            }
            {
              type = "Bell";
              frequency = 3765;
              gain = -2.7;
              q = 1.2;
            }
            {
              type = "Hi-shelf";
              frequency = 10000;
              gain = -2.3;
              q = 0.7;
            }
            {
              type = "Bell";
              frequency = 893;
              gain = 0.5;
              q = 2.68;
            }
            {
              type = "Bell";
              frequency = 35;
              gain = -0.1;
              q = 2.03;
            }
            {
              type = "Bell";
              frequency = 5984;
              gain = 0.7;
              q = 6.0;
            }
            {
              type = "Bell";
              frequency = 1206;
              gain = -0.4;
              q = 4.33;
            }
          ];
        };
        # Zero:RED with Crinacle's "Bass+" tuning target — same measurement.
        truthear-zero-red-crinacle-bassplus = mkPreset {
          preamp = -4.0;
          filters = [
            {
              type = "Lo-shelf";
              frequency = 105;
              gain = -1.0;
              q = 0.7;
            }
            {
              type = "Bell";
              frequency = 7923;
              gain = 4.3;
              q = 0.94;
            }
            {
              type = "Bell";
              frequency = 252;
              gain = -1.7;
              q = 0.55;
            }
            {
              type = "Bell";
              frequency = 835;
              gain = 1.2;
              q = 1.52;
            }
            {
              type = "Bell";
              frequency = 1495;
              gain = -1.4;
              q = 2.1;
            }
            {
              type = "Hi-shelf";
              frequency = 10000;
              gain = -1.3;
              q = 0.7;
            }
            {
              type = "Bell";
              frequency = 3847;
              gain = -0.6;
              q = 2.36;
            }
            {
              type = "Bell";
              frequency = 5761;
              gain = 1.0;
              q = 4.79;
            }
            {
              type = "Bell";
              frequency = 35;
              gain = -0.2;
              q = 1.93;
            }
            {
              type = "Bell";
              frequency = 64;
              gain = 0.3;
              q = 2.22;
            }
          ];
        };
        # HIFIMAN HE400se — crinacle GRAS 43AG-7 over-ear measurement.
        hifiman-he400se-crinacle = mkPreset {
          preamp = -6.3;
          filters = [
            {
              type = "Lo-shelf";
              frequency = 105;
              gain = 6.5;
              q = 0.7;
            }
            {
              type = "Bell";
              frequency = 1896;
              gain = 5.9;
              q = 2.74;
            }
            {
              type = "Bell";
              frequency = 197;
              gain = -1.6;
              q = 0.4;
            }
            {
              type = "Bell";
              frequency = 943;
              gain = -2.4;
              q = 2.96;
            }
            {
              type = "Bell";
              frequency = 73;
              gain = -1.9;
              q = 1.78;
            }
            {
              type = "Hi-shelf";
              frequency = 10000;
              gain = -2.7;
              q = 0.7;
            }
            {
              type = "Bell";
              frequency = 3291;
              gain = -1.6;
              q = 5.04;
            }
            {
              type = "Bell";
              frequency = 1248;
              gain = 1.4;
              q = 5.75;
            }
            {
              type = "Bell";
              frequency = 1071;
              gain = -1.0;
              q = 6.0;
            }
            {
              type = "Bell";
              frequency = 4165;
              gain = 1.0;
              q = 6.0;
            }
          ];
        };
      };
    };
  };
}
