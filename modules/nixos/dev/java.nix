{
  config,
  pkgs,
  lib,
  ...
}: {
  config = lib.mkIf config.modules.dev.enable {
    # Java packages
    environment.systemPackages = with pkgs; [
      # Java Development Kit
      jdk # OpenJDK 23
      zulu17 # OpenJDK 17 (LTS)
      zulu11 # OpenJDK 11 (LTS)
      jre21_minimal # Minimal JRE 21
      spark # A unified analytics engine for large-scale data processing

      # Java build tools
      gradle # Gradle build system
      maven # Apache Maven
      ant # Apache Ant

      # Java development tools
      jdt-language-server # Java language server
      java-language-server # Alternative Java LSP
      checkstyle # Java code style checker
      pmd # Java source code analyzer
      jacoco # Java code coverage
      groovy # Groovy language
      kotlin # Kotlin language
      scala # Scala language
      sbt # Scala build tool
    ];

    # Environment variables for Java
    environment.sessionVariables = {
      # Java settings
      JAVA_HOME = "${pkgs.jdk}";
      JDK_HOME = "${pkgs.jdk}";
      JRE_HOME = "${pkgs.jdk}";

      # Java development settings
      JAVA_OPTS = "-Xmx2g -XX:+UseG1GC -XX:+UseStringDeduplication";
      MAVEN_OPTS = "-Xmx1g -XX:+UseG1GC";
      GRADLE_OPTS = "-Xmx1g -XX:+UseG1GC -Dorg.gradle.daemon=true";

      # Java tool settings
      JAVA_TOOL_OPTIONS = "-Dfile.encoding=UTF-8 -Duser.timezone=UTC";
    };
  };
}
