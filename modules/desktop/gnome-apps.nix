_: {
  # GNOME/GTK apps (nautilus, ...) on the Hyprland session expect two GNOME
  # session services the compositor doesn't pull in on its own. Without them
  # every cold GTK start pays a stall:
  #   * at-spi2-core provides org.a11y.Bus — otherwise GTK probes a dead
  #     accessibility bus ("org.a11y.Bus was not provided by any .service files").
  #   * localsearch (TinySPARQL) is the file indexer nautilus reaches for
  #     search — otherwise it stalls on "Tracker indexer: name not activatable".
  flake.modules.nixos.gnome-apps = {
    services.gnome.at-spi2-core.enable = true;
    services.gnome.localsearch.enable = true;
  };
}
