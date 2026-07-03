{self, ...}: {
  # Declarative bootstrap for the native hermes LLM wiki: materialize the
  # vault.git-scoped deploy key from sops, clone vault.git @ `hermes` branch, and
  # seed the daily `wiki-consolidate` cron job — so the whole wiki survives a
  # reprovision / state wipe (previously all manual host state). See
  # docs/hermes-llm-wiki.md.
  flake.modules.nixos.discovery-hermes-wiki = {
    config,
    pkgs,
    lib,
    ...
  }: let
    wikiDir = "/var/lib/hermes-wiki";
    keyPath = config.sops.secrets."hermes_wiki/deploy_key".path;

    cronPrompt = ''
      Daily wiki consolidation. Your cwd is /opt/wiki — the LLM wiki (git checkout on the `hermes` branch); schema/ops in ./AGENTS.md.

      Sources (distilled + small — NEVER read raw /opt/data/sessions logs):
      - /opt/data/memories/MEMORY.md and USER.md  (long-term memory + user profile)
      - /opt/wiki/inbox.md                         (fleeting captures from sessions — process, then clear them)

      Task (one tight pass, <= ~15 tool calls):
      1. Read AGENTS.md, the sources above, and index.md.
      2. Promote durable items not yet in the wiki into wiki/<concept>.md (frontmatter contract + [[wikilinks]]); update index.md; append a log.md entry.
      3. Lint: fix broken [[wikilinks]] and obvious duplicate pages. Remove processed lines from inbox.md.
      4. Write files with shell redirection (the write_file tool is blocked for /opt).
      5. Publish (skip if nothing changed): git add -A && git commit -m "wiki: daily consolidation" && git push origin hermes
      6. Post a one-line result to Discord (skip if $DISCORD_WEBHOOK_DEPLOYS is unset): [ -n "$DISCORD_WEBHOOK_DEPLOYS" ] && curl -fsS -H "Content-Type: application/json" -d "{\"content\":\"wiki-consolidate: <short summary>\"}" "$DISCORD_WEBHOOK_DEPLOYS"
    '';

    # Idempotent-by-replace seed: drop any existing wiki-consolidate, recreate
    # with the canonical spec (so prompt/schedule/toolset edits propagate).
    seedPy = pkgs.writeText "wiki-cron-seed.py" ''
      import sys
      sys.path.insert(0, "/opt/hermes")
      from cron.jobs import load_jobs, save_jobs, create_job
      PROMPT = """${cronPrompt}"""
      jobs = [j for j in load_jobs() if j.get("name") != "wiki-consolidate"]
      save_jobs(jobs)
      create_job(prompt=PROMPT, schedule="0 4 * * *", name="wiki-consolidate",
                 model="glm-5", enabled_toolsets=["terminal"], workdir="/opt/wiki")
      print("seeded wiki-consolidate")
    '';

    seedScript = pkgs.writeShellApplication {
      name = "hermes-wiki-cron-seed";
      runtimeInputs = [pkgs.docker pkgs.coreutils];
      text = ''
        set -euo pipefail
        for _ in $(seq 1 30); do
          if docker exec hermes-agent test -d /opt/hermes 2>/dev/null; then break; fi
          sleep 4
        done
        docker cp ${seedPy} hermes-agent:/tmp/wiki-cron-seed.py
        docker exec -u 10000 -e HOME=/opt/data hermes-agent python3 /tmp/wiki-cron-seed.py
        docker exec hermes-agent rm -f /tmp/wiki-cron-seed.py
      '';
    };
  in {
    # Host user matching the container's internal uid/gid so sops can own the
    # key and the clone, and the clone oneshot can run as it.
    users.groups.hermes.gid = lib.mkDefault 10000;
    users.users.hermes = {
      isSystemUser = true;
      group = "hermes";
      uid = lib.mkDefault 10000;
      home = wikiDir;
      createHome = false;
    };

    sops.secrets."hermes_wiki/deploy_key" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      key = "hermes_wiki/deploy_key";
      owner = "hermes";
      group = "hermes";
      mode = "0400";
      restartUnits = ["hermes-wiki-clone.service"];
    };

    systemd.tmpfiles.rules = [
      "d ${wikiDir} 0750 hermes hermes -"
    ];

    # Host-side: clone/refresh the wiki working copy before the agent starts.
    systemd.services.hermes-wiki-clone = {
      description = "Bootstrap the hermes LLM-wiki clone (vault.git @ hermes)";
      wantedBy = ["multi-user.target"];
      before = ["docker-hermes-agent.service"];
      # nss-lookup.target for DNS; but network-online.target still fires before
      # the default route is actually usable on this host (seen at boot:
      # "ssh: connect to github.com port 22: Network is unreachable"), so retry.
      after = ["network-online.target" "nss-lookup.target" "sops-nix.service"];
      wants = ["network-online.target" "nss-lookup.target"];
      path = [pkgs.git pkgs.openssh pkgs.coreutils];
      # Boot network race: the github clone runs before routing is up on a cold
      # boot and fails. Retry a handful of times until the network settles rather
      # than failing the unit for the rest of the session.
      startLimitIntervalSec = 300;
      startLimitBurst = 10;
      serviceConfig = {
        Type = "oneshot";
        User = "hermes";
        Group = "hermes";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "15s";
      };
      script = ''
        set -euo pipefail
        export GIT_SSH_COMMAND="ssh -i ${keyPath} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=${wikiDir}/.known_hosts"
        if [ ! -d ${wikiDir}/.git ]; then
          git clone --branch hermes git@github.com:ErikBPF/vault.git ${wikiDir}
        else
          git -C ${wikiDir} fetch origin hermes
          git -C ${wikiDir} checkout hermes
          git -C ${wikiDir} reset --hard origin/hermes
        fi
        git -C ${wikiDir} config user.name hermes
        git -C ${wikiDir} config user.email hermes@homelab.pastelariadev.com
        git -C ${wikiDir} config core.sshCommand "ssh -i /opt/wiki-key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/opt/data/known_hosts"
      '';
    };

    # Seed the daily consolidation cron into the running container (idempotent).
    systemd.services.hermes-wiki-cron-seed = {
      description = "Seed the wiki-consolidate cron job";
      wantedBy = ["multi-user.target"];
      after = ["docker-hermes-agent.service"];
      requires = ["docker-hermes-agent.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${seedScript}/bin/hermes-wiki-cron-seed";
      };
    };
  };
}
