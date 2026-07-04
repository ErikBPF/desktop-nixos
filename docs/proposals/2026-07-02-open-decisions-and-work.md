# Backlog da frota — decisões pendentes e implementações a fazer

**Date:** 2026-07-02
**Status:** Backlog (tracked, not scheduled) — consolidado da auditoria de
propostas de 2026-07-02 (três leitores paralelos, evidência em código) + das
threads abertas dos RFCs recém-graduados. Cada item aponta o doc-fonte; ao
concluir, atualize o doc-fonte e risque aqui. Itens hermes ficam nos backlogs
próprios ([`2026-06-25-hermes-deferred-plans.md`](2026-06-25-hermes-deferred-plans.md),
[`2026-06-29-hermes-deferred-improvements.md`](2026-06-29-hermes-deferred-improvements.md))
— não duplicados aqui.

---

## A. Decisões a tomar (julgamento humano — `TODO(erik)`)

| # | Decisão | Contexto / doc-fonte | Opções em jogo |
|---|---------|----------------------|----------------|
| A1 | **lazy-trees: seguir ou aposentar o RFC** | [`2026-06-20-lazy-trees-determinate-nix.md`](2026-06-20-lazy-trees-determinate-nix.md) — zero progresso desde 2026-06-20; 4 decisões abertas (knob do installer, escopo free-tier, canário orion, escopo da frota) | Decidir e executar, ou deletar o RFC (proposals/ é só para RFC ativo) |
| A2 | **`k8s-apiserver` no stack networking do discovery ainda é desejado?** | [`../implemented/2026-06-29-discovery-resilience-fixes.md`](../implemented/2026-06-29-discovery-resilience-fixes.md) P1-1 — drift de project-name recorrente | Manter (e padronizar `--project-name`) vs remover do stack |
| A3 | **Split de DNS do discovery (self-dependency)** | mesmo doc, P1-2 — resolução do próprio host não pode depender do AdGuard que ele mesmo roda | Definir caminho não-self para o resolver do host vs aceitar o risco |
| A4 | **repo-structure Fases 1–5: go/no-go** | [`2026-06-24-repo-structure-improvements.md`](2026-06-24-repo-structure-improvements.md) — Fase 0 (contrato + `structure-check`) entregue; 1–5 são refactor grande da árvore | Executar em etapas, ou aceitar a árvore atual e fechar o RFC na Fase 0 |
| A5 | **Sudo hardening nos servers (P0.3)** | [`2026-06-24-source-backed-host-improvements.md`](2026-06-24-source-backed-host-improvements.md) — foi adiado até o caminho de sudo do deploy provar estabilidade; deploy-rs agora é padrão da frota → possivelmente desbloqueado | Apertar agora vs esperar mais ciclos de deploy-rs |
| A6 | **Escopo P2+ de host-improvements** | mesmo doc — impermanence seletiva, sandboxing de serviços, testes de aceitação, role-profiles estreitos | Priorizar subconjunto vs backlog permanente |
| A7 | **Harbor pull-through P1: Job declarativo vs setup manual documentado** | [`../implemented/2026-06-22-harbor-pullthrough-mirror.md`](../implemented/2026-06-22-harbor-pullthrough-mirror.md) — mirror já funcional de execução manual; RFC recomenda o Job (sobrevive a reinstall do Harbor) | Job no homelab-gitops (recomendado) vs doc manual |
| A9 | **kepler-k3s: julgamentos adiados** | [`../implemented/2026-06-19-kepler-k3s-microvm-cluster.md`](../implemented/2026-06-19-kepler-k3s-microvm-cluster.md) §5–§14 — rolling CP restart (vale o custo?), helper `just scale-down N`/`cluster-status`/`cluster-reset`, split de repo (Option 0 agora vs Option 2 depois) | Observar padrão de deploys antes de decidir o rolling restart |
| A10 | **OpenBao: segundo guardião de unseal-key / root break-glass no password manager** | [`../implemented/2026-06-30-openbao-root-recovery.md`](../implemented/2026-06-30-openbao-root-recovery.md) — token perdido uma vez; incidente sealed-21h de 2026-07-01 reforça | Definir custódia antes do próximo incidente |
| A11 | **HA declarative: seguir Fase 1 ou aposentar** | [`2026-05-23-home-assistant-declarative.md`](2026-05-23-home-assistant-declarative.md) — git-sync (`backup2git.sh`), GHA validate e Direction B nunca começaram; o fluxo PR atual + auto-update na prática cobre parte do valor | Executar Fase 1, re-escopar, ou aposentar o RFC |
| A12 | **Voice assistant §6: quais sinergias valem** | [`2026-05-27-home-assistant-voice-assistant.md`](../implemented/2026-05-27-home-assistant-voice-assistant.md) — núcleo entregue; aberto só: visão por câmera, ponte hermes-MCP, clone de voz f5-tts, memória RAG, anúncios Alexa | Escolher 0–2 para RFC próprio; o resto morre |

## B. Implementações a fazer (decisão já tomada ou não requerida)

| # | Trabalho | Doc-fonte / onde | Próximo passo concreto |
|---|----------|------------------|------------------------|
| B2 | **Drill trimestral de restore do OpenBao** (agendar + executar 1º) | [`../implemented/2026-06-29-vault-backup-plan.md`](../implemented/2026-06-29-vault-backup-plan.md) §7; runbook [`../reference/vault-disaster-recovery.md`](../reference/vault-disaster-recovery.md) | Janela de manutenção; considerar lembrete automatizado (cron/ntfy) |
| B3 | **Drill do runbook etcd (k3s)** — documentado, nunca testado | [`../implemented/2026-06-19-kepler-k3s-microvm-cluster.md`](../implemented/2026-06-19-kepler-k3s-microvm-cluster.md) §15 | Janela própria no kepler |
| B4 | **Custódia do escrow — parte física restante**: escrow ON voyager verificado 2026-07-04 (`~/escrow/age-key.age` = age-scrypt válido + `sops-config.tar.gz` presentes, offsite). Falta só o que é físico: cópia offline da passphrase fora de casa + cópia break-glass da age key **fora da frota** (+ apagar output do generator) | crown-jewels §11c; [`../implemented/2026-06-29-vault-secrets-platform.md`](../implemented/2026-06-29-vault-secrets-platform.md) | Verificação física/password-manager (só erik); 30 min |
| B5 | **Deploy do `k3s-manifest-reconcile`** — código pronto em `modules/services/_k3s-node.nix`, falta bounce dos guests | [`2026-06-22-declarative-implementation-plan.md`](2026-06-22-declarative-implementation-plan.md) item C | Combinar na MESMA janela: bounce staggered + verificação Harbor P1 (`crictl pull` via mirror) — um restart, não três |
| B6 | **Observabilidade etcd** — scrape no alloy-metrics (gitops) + dashboard (servarr) | mesmo doc, item D.3 — métricas já fluem em `:2381` | Par com B5/Fase 3 |
| B7 | **Grafana Fase 3: alertas do cluster k3s** | [`2026-06-29-grafana-fleet-monitoring.md`](../implemented/2026-06-29-grafana-fleet-monitoring.md) — kube-state-metrics já roda no cluster | Escrever rules KSM (pod crashloop, PVC, node) no rules.yaml do servarr |
| B8 | **Grafana Fase 2: alertas por container** — bloqueado pelo gap de name-labels do cadvisor | mesmo doc; gotcha em memória (rootless podman `/run/user/1000` 0700; docker sem labels) | Trabalho real = consertar o pipeline de métricas, não as rules |
| B9 | **telstar: provisionar quando houver capacidade A1** | [`2026-07-01-telstar-oracle-arm-host.md`](2026-07-01-telstar-oracle-arm-host.md) — 100% staged; captura agora é **serviço declarativo persistente** `discovery-telstar-capture` (`modules/hosts/discovery/telstar-capture.nix`, 2026-07-04) tentando a cada 60s até liberar slot | Sem ação até liberar (serviço já loopando); sucesso → setar `hosts.telstar.ip` → `just fleet-json` → `just deploy-telstar` + `just switch-telstar` → graduar o RFC |
| B10 | **discovery P2: root-cause da instabilidade** — fase de coleta ativa | [`../implemented/2026-06-29-discovery-resilience-fixes.md`](../implemented/2026-06-29-discovery-resilience-fixes.md) | Após o próximo evento: analisar journal persistente + `net-watch` + sysstat |
| B11 | **P3.3 servarr→Vault: cauda** — harbor (special-case) + reavaliar chaves mantidas em sops de propósito (`LITELLM_MASTER_KEY`, `MINIO_*`) | [`../implemented/2026-06-29-vault-secrets-platform.md`](../implemented/2026-06-29-vault-secrets-platform.md) | Migrar harbor ou registrar decisão de mantê-lo em sops |
| B12 | **iac: sobras do repo-ssot** — `terragrunt import` da reserva HA `.115`; limpeza das reservas velhas `.205`/`.40` | [`../implemented/2026-06-29-repo-ssot-srp.md`](../implemented/2026-06-29-repo-ssot-srp.md) P1 | Host cabeado; revisar `tofu plan` antes do apply |

## Já fechado (não retrabalhar)

Verificados nesta sessão de 2026-07-01/02 — constam aqui só para não
reabrirem: monitoramento do voyager (§11b), guard `rtk proxy sops` no hook,
unseal fail-loud + probe `openbao_sealed` + rule Grafana, cloudflare.ini do
SWAG (dry-run de renovação provado), revogação do token temporário
`cfut_9tU2…` (sweep da conta limpo — só bootstrap + swag-dns01), tailscale
OAuth sem expiração, kepler `:7860` (rota removida do SSOT), **migração do
token Cloudflare** (escopado/revogável, implementada — RFC 2026-06-28; um
bootstrap token permanece manual por design; helper `just sync-cf-token` para
>1 token bridged é opcional, não bloqueia), **drill de restore do voyager**
(2026-07-04 PASS — restore da REST append-only via creds sops: 38 arquivos, tier
de tofu-state completo/atual, JSON OpenTofu válido com envelope pbkdf2; registrado
em `../reference/voyager-offsite-maintenance.md`).
