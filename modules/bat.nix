{...}: {
  flake.modules.home.bat = {...}: {
    home.file.".config/bat/config".text = ''
      --style="numbers,changes,grid"
      --paging=auto
    '';
  };
}
