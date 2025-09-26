{
  pkgs,
  ...
}: {
  # Go packages
  home.packages = with pkgs; [
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
    staticcheck # Go static analysis
    govulncheck # Go vulnerability checker
    air # Live reload for Go apps
    richgo # Enriched go test output
    gomobile # Go mobile development
    protoc-gen-go # Go protobuf compiler
    protoc-gen-go-grpc # Go gRPC compiler
  ];

  # Environment variables for Go
  home.sessionVariables = {
    # Go settings
    GOPATH = "$HOME/go";
    GOROOT = "${pkgs.go}";
    GO111MODULE = "on";
    GOSUMDB = "sum.golang.org";
    GONOPROXY = "";
    GONOSUMDB = "";
    GOPRIVATE = "";
    GOCACHE = "$HOME/.cache/go-build";
    GOMODCACHE = "$HOME/go/pkg/mod";
    
    # Go development settings
    GOFLAGS = "-mod=readonly";
    CGO_ENABLED = "1";
    
    # Path configuration
    PATH = "$PATH:$HOME/go/bin:${pkgs.go}/bin";
  };
}
