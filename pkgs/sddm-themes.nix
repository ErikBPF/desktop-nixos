{ stdenv, fetchFromGitHub }:
{
 sddm-tokyo-night = stdenv.mkDerivation rec {
    pname = "sddm-tokyo-night";
    version = "320c8e74ade1e94f640708eee0b9a75a395697c6";
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/share/sddm/themes
      cp -aR $src $out/share/sddm/themes/${pname}
    '';
    src = fetchFromGitHub {
      owner = "rototrash";
      repo = "tokyo-night-sddm";
      rev = "${version}";
      sha256 = "sha256-JRVVzyefqR2L3UrEK2iWyhUKfPMUNUnfRZmwdz05wL0=";
    };
  };

}
