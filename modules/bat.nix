_: {
  flake.modules.home.bat = _: {
    home.file.".config/bat/config".text = ''
      --style="numbers,changes,grid"
      --paging=auto
    '';
  };
}
