{lib, ...}: {
  options.monitors = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        name = lib.mkOption {type = lib.types.str;};
        resolution = lib.mkOption {type = lib.types.str;};
        refreshRate = lib.mkOption {
          type = lib.types.int;
          default = 60;
        };
        scale = lib.mkOption {
          type = lib.types.float;
          default = 1.0;
        };
        position = lib.mkOption {
          type = lib.types.str;
          default = "auto";
        };
      };
    });
    default = [];
  };

  options.workspaces = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        id = lib.mkOption {type = lib.types.int;};
        monitor = lib.mkOption {type = lib.types.str;};
        default = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
      };
    });
    default = [];
  };
}
