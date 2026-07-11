{lib, ...}: {
  options.syncthingDeviceIDs = lib.mkOption {
    type = lib.types.attrs;
    default = {
      discovery_id = "EDAFRIE-KXTJ2ML-RD7NOC4-UPSGFLK-QQFVKKN-M4UL35Y-QUE3GHG-WJIRIQ3";
      laptop_id = "T27S3JE-UBN6SKS-4WYUR2F-BIGC3WG-N5DNUY7-6BVN3SY-4FZBYKE-F77NFAQ";
      pathfinder_id = "U3OU7KP-XLWDXZK-UCCHG7F-7UDN4GJ-CIZFOOQ-YGFTYAM-PTZF7HY-ERVVVA6";
      workstation_id = "CWISZ34-JSQV6XK-UIEF47O-4ODJBNA-EXTJPWC-CJLEZYY-VRDN4GP-O2QNOQE";
      orion_id = "C2K3MXJ-KIFV2LJ-264GF6T-NCTMCUF-R7NFRXT-L5LXI7X-7NJH6FN-EYCPUQP";
      kepler_id = "YBBP2DR-4N53ZGB-AVOVSHP-R3ZHCQB-VHJFA4U-SZNKD23-DJSLEDA-7BMDDQI";
      # orion dev-sandbox container (see the orion dev-sandbox RFC).
      gemini_id = "KM4GD44-5TS53KN-UR7AUX4-CMYPCNK-TQMYPJY-LGEMYLK-J7VMALT-A27PNAA";
    };
    description = "Syncthing device IDs (public identifiers, not secrets)";
  };
}
