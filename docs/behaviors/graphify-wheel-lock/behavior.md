# Graphify wheel reproducibility

**Status:** Implemented and independently reviewed locally; hosted validation pending; no deployment.

Human seed, verbatim: “invoke subagents to check cis and address feedbacks. Continue implementations”.

Graphify remains version 0.9.53 with its MCP extra on x86_64-linux and Python
3.14. Every wheel in the previously passing dependency closure has an exact
public artifact URL and SHA256. Builds fetch those artifacts and install
offline; publishing another transitive dependency version must not change the
selected inputs. Missing or altered artifacts fail closed. Updating Graphify
or its dependencies is an explicit source change, separate from building or
deploying the host.

The updater must reject missing hashes, non-wheel sources, duplicate packages,
yanked artifacts, unexpected report schemas and non-public artifact origins.
It must not inherit private package indexes or credentials.

Native Python extension operations must work without workstation library-path
variables. Read-only checks also run on dependency PR bases; push-triggered
jobs remain limited to main. The secret scanner reads PR commits without
posting comments or acquiring write authority.
