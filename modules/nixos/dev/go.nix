{
  config,
  pkgs,
  lib,
  ...
}: {
  config = lib.mkIf config.modules.dev.enable {
    # Go packages
    environment.systemPackages = with pkgs; [
      # Go language and tools
      go
      gopls # Go language server
      go-tools # Go tools (gofmt, goimports, etc.)
      delve # Go debugger
      gomodifytags # Go struct tag modifier
      gore # Go REPL
      gotests # Generate Go tests
      gotestsum # Go test runner with better output
      golangci-lint # Go linter aggregator
      gofumpt # Stricter gofmt
      gosec # Go security checker
      govulncheck # Go vulnerability checker
      air # Live reload for Go apps
      richgo # Enriched go test output
      protoc-gen-go # Go protobuf compiler
      protoc-gen-go-grpc # Go gRPC compiler
    ];

    # Environment variables for Go
    environment.sessionVariables = {
      # Go settings
      GOPATH = "$HOME/go";
      # Don't set GOROOT - let Go find it automatically from the binary path
      # GOROOT = "${pkgs.go}/share/go";
      GO111MODULE = "on";
      GOPROXY = "https://proxy.golang.org,direct";
      GOSUMDB = "sum.golang.org";
      GONOPROXY = "";
      GONOSUMDB = "";
      GOPRIVATE = "";
      GOCACHE = "$HOME/.cache/go-build";
      GOMODCACHE = "$HOME/go/pkg/mod";

      # Go development settings
      GOFLAGS = "-mod=readonly";
      CGO_ENABLED = "1";
    };
  };
}
