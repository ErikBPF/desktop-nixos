{
  pkgs,
  ...
}: {
  # Java packages
  home.packages = with pkgs; [
    # Java Development Kit
    zulu23 # OpenJDK 23
    zulu17 # OpenJDK 17 (LTS)
    zulu11 # OpenJDK 11 (LTS)
    jre21_minimal # Minimal JRE 21
    
    # Java build tools
    gradle # Gradle build system
    maven # Apache Maven
    ant # Apache Ant
    
    # Java development tools
    jdt-language-server # Java language server
    java-language-server # Alternative Java LSP
    checkstyle # Java code style checker
    spotbugs # Java bug finder
    pmd # Java source code analyzer
    jacoco # Java code coverage
    jdeps # Java dependency analyzer
    jps # Java process status
    jstat # Java statistics monitoring
    jstack # Java stack trace
    jmap # Java memory map
    jhat # Java heap analysis tool
    jconsole # Java monitoring and management console
    jvisualvm # Java visual VM
    jprofiler # Java profiler
    jmeter # Apache JMeter for testing
    junit # JUnit testing framework
    testng # TestNG testing framework
    mockito # Mockito mocking framework
    spring-boot-cli # Spring Boot CLI
    groovy # Groovy language
    kotlin # Kotlin language
    scala # Scala language
    sbt # Scala build tool
    
    # Additional tools
    maven-dependency-analyzer # Maven dependency analyzer
    maven-shade-plugin # Maven shade plugin
    maven-compiler-plugin # Maven compiler plugin
  ];

  # Environment variables for Java
  home.sessionVariables = {
    # Java settings
    JAVA_HOME = "${pkgs.zulu23}";
    JDK_HOME = "${pkgs.zulu23}";
    JRE_HOME = "${pkgs.zulu23}";
    
    # Java development settings
    JAVA_OPTS = "-Xmx2g -XX:+UseG1GC -XX:+UseStringDeduplication";
    MAVEN_OPTS = "-Xmx1g -XX:+UseG1GC";
    GRADLE_OPTS = "-Xmx1g -XX:+UseG1GC -Dorg.gradle.daemon=true";
    
    # Java tool settings
    JAVA_TOOL_OPTIONS = "-Dfile.encoding=UTF-8 -Duser.timezone=UTC";
    
    # Path configuration
    PATH = "$PATH:${pkgs.zulu23}/bin:${pkgs.gradle}/bin:${pkgs.maven}/bin";
  };
}
