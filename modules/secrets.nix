{lib, ...}: {
  options.syncthingDeviceIDs = lib.mkOption {
    type = lib.types.attrs;
    default = {
      discovery_id = "2U4FN2A-6CTHQXQ-S3OCKLI-NLCLBWR-FUZ6D3B-BTE7EPO-G32ZR5M-A5VCLA6";
      archlinux_id = "RDDQ2HJ-W6WTFYH-TFMVC5Y-2QOM76N-6YAHYPL-3CXESPC-PWHQ4NP-7XNALQB";
      workstation_id = "CWISZ34-JSQV6XK-UIEF47O-4ODJBNA-EXTJPWC-CJLEZYY-VRDN4GP-O2QNOQE";
      orion_id = "C2K3MXJ-KIFV2LJ-264GF6T-NCTMCUF-R7NFRXT-L5LXI7X-7NJH6FN-EYCPUQP";
      kepler_id = "PLACEHOLDER-GENERATE-AFTER-FIRST-SYNCTHING-RUN-ON-KEPLER";
    };
    description = "Syncthing device IDs (public identifiers, not secrets)";
  };
}
