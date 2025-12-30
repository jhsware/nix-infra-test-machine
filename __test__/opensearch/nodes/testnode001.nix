{ config, pkgs, lib, ... }: {
  # Enable OpenSearch standalone instance using native NixOS service
  config.services.opensearch = {
    enable = true;
    package = pkgs.opensearch;
    dataDir = "/var/lib/opensearch";

    settings = {
      "network.host" = "127.0.0.1";
      "http.port" = 9201;
      "transport.port" = 9301;
      "cluster.name" = "test-cluster";
      "discovery.type" = "single-node";
    };

    extraJavaOptions = [
      "-Xms512m"
      "-Xmx512m"
    ];
  };

  # Install curl and jq for API access
  config.environment.systemPackages = with pkgs; [
    curl
    jq
  ];

  # Open firewall for OpenSearch (only if external access needed)
  # config.networking.firewall.allowedTCPPorts = [ 9201 9301 ];
}
