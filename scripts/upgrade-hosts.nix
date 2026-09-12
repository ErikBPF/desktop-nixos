hosts: builtins.filter (name: hosts.${name}.role != "appliance") (builtins.attrNames hosts)
