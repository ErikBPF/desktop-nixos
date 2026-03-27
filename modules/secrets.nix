{lib, ...}: {
  options.secrets = lib.mkOption {
    type = lib.types.attrs;
    default = {
      syncthing = {
        moon_id = "734S3SW-4NQNPZI-XJ6EXL7-WQEOIUO-6FGTDPR-CEF4FRQ-GZZVTCW-DEVX4QB";
        archlinux_id = "RDDQ2HJ-W6WTFYH-TFMVC5Y-2QOM76N-6YAHYPL-3CXESPC-PWHQ4NP-7XNALQB";
        workstation_id = "CWISZ34-JSQV6XK-UIEF47O-4ODJBNA-EXTJPWC-CJLEZYY-VRDN4GP-O2QNOQE";
      };
    };
    description = "Syncthing device IDs (public identifiers, not secrets)";
  };
}
