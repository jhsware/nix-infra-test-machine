{ config, pkgs, lib, ... }: {
  # Enable Elasticsearch standalone instance using native NixOS service
  config.services.elasticsearch = {
    enable = true;
    package = pkgs.elasticsearch;
    dataDir = "/var/lib/elasticsearch";
    cluster_name = "test-cluster";
    listenAddress = "127.0.0.1";
    port = 9202;
    tcp_port = 9302;
    single_node = true;

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

  # Open firewall for Elasticsearch (only if external access needed)
  # config.networking.firewall.allowedTCPPorts = [ 9202 9302 ];
}
