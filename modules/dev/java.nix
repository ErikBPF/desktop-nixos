{...}: {
  flake.modules.nixos.dev-java = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      jdk
      zulu17
      zulu11
      jre21_minimal
      spark
      gradle
      maven
      ant
      jdt-language-server
      java-language-server
      checkstyle
      pmd
      jacoco
      groovy
      kotlin
      scala
      sbt
    ];

    environment.sessionVariables = {
      JAVA_HOME = "${pkgs.jdk}";
      JDK_HOME = "${pkgs.jdk}";
      JRE_HOME = "${pkgs.jdk}";
      JAVA_OPTS = "-Xmx2g -XX:+UseG1GC -XX:+UseStringDeduplication";
      MAVEN_OPTS = "-Xmx1g -XX:+UseG1GC";
      GRADLE_OPTS = "-Xmx1g -XX:+UseG1GC -Dorg.gradle.daemon=true";
      JAVA_TOOL_OPTIONS = "-Dfile.encoding=UTF-8 -Duser.timezone=UTC";
    };
  };
}
