_: {
  flake.modules.nixos.dev-go = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      go
      gopls
      go-tools
      delve
      gomodifytags
      gore
      gotests
      gotestsum
      golangci-lint
      gofumpt
      gosec
      govulncheck
      air
      richgo
      protoc-gen-go
      protoc-gen-go-grpc
    ];

    environment.sessionVariables = {
      GOPATH = "$HOME/go";
      GO111MODULE = "on";
      GOPROXY = "https://proxy.golang.org,direct";
      GOSUMDB = "sum.golang.org";
      GONOPROXY = "";
      GONOSUMDB = "";
      GOPRIVATE = "";
      GOCACHE = "$HOME/.cache/go-build";
      GOMODCACHE = "$HOME/go/pkg/mod";
      GOFLAGS = "-mod=readonly";
      CGO_ENABLED = "1";
    };
  };
}
