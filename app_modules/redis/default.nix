{ config, pkgs, lib, ... }:
let
  appName = "redis";
  defaultPort = 6379;

  cfg = config.infrastructure.${appName};
in
{
  options.infrastructure.${appName} = {
    enable = lib.mkEnableOption "infrastructure.redis";

    package = lib.mkOption {
      type = lib.types.package;
      description = "Redis package to use.";
      default = pkgs.redis;
      example = "pkgs.redis";
    };

    bindToIp = lib.mkOption {
      type = lib.types.str;
      description = "IP address to bind.";
      default = "127.0.0.1";
    };

    bindToPort = lib.mkOption {
      type = lib.types.int;
      description = "Port to bind.";
      default = defaultPort;
    };

    maxMemory = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      description = "Maximum memory Redis can use (e.g., '256mb', '1gb'). Null for unlimited.";
      default = null;
      example = "256mb";
    };

    maxMemoryPolicy = lib.mkOption {
      type = lib.types.enum [ "noeviction" "allkeys-lru" "volatile-lru" "allkeys-random" "volatile-random" "volatile-ttl" ];
      description = "Policy for handling keys when maxMemory is reached.";
      default = "noeviction";
    };

    requirePass = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      description = "Password for Redis authentication. Null for no authentication.";
      default = null;
    };

    databases = lib.mkOption {
      type = lib.types.int;
      description = "Number of databases to configure.";
      default = 16;
    };

    appendOnly = lib.mkOption {
      type = lib.types.bool;
      description = "Enable append-only file persistence.";
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    # Set the package at the top level
    services.redis.package = cfg.package;

    services.redis.servers."" = {
      enable = true;
      bind = cfg.bindToIp;
      port = cfg.bindToPort;
      databases = cfg.databases;
      appendOnly = cfg.appendOnly;
      requirePass = cfg.requirePass;
      settings = lib.mkMerge [
        (lib.mkIf (cfg.maxMemory != null) {
          maxmemory = cfg.maxMemory;
          maxmemory-policy = cfg.maxMemoryPolicy;
        })
      ];
    };

    # Install redis-cli for CLI access
    environment.systemPackages = [ cfg.package ];

    # Open firewall for Redis if binding to non-localhost
    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.bindToIp != "127.0.0.1") [ cfg.bindToPort ];
  };
}
