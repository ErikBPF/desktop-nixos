# goose persistent instructions

Injected into goose's working memory every turn via `GOOSE_MOIM_MESSAGE_FILE`
(wired in `modules/dev/goose.nix`). Kept separate from `AGENTS.md` so goose and
opencode can coexist without sharing an instruction surface.

## Shell command routing

When `rtk` is on `PATH`, prefix read-heavy shell commands with it to cut token
usage — `rtk git/ls/grep/find/docker/log/json/read …` instead of the raw
command. Mutating commands (`commit`, `push`, `rm`, `run`, `nixos-rebuild`) stay
raw. If `rtk` is not on `PATH`, run the command normally; never fail a command
just because the binary is missing.
