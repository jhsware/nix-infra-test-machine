{ config, pkgs, lib, ... }: {
  # ==========================================================================
  # n8n Configuration (using infrastructure module with SQLite)
  # ==========================================================================
  config.infrastructure.n8n = {
    enable = true;

    # Network settings
    bindToIp = "0.0.0.0";
    bindToPort = 5678;
    openFirewall = true;

    # Use SQLite database (default)
    database = {
      type = "sqlite";
    };

    # Execution settings
    executions = {
      pruneData = true;
      pruneDataMaxAge = 168;  # 7 days for testing
      pruneDataMaxCount = 1000;
    };

    # Additional settings (environment variables)
    settings = {
      GENERIC_TIMEZONE = "UTC";
    };

  };

  # ==========================================================================
  # Test utilities
  # ==========================================================================
  config.environment.systemPackages = with pkgs; [
    curl
    jq
  ];
}
