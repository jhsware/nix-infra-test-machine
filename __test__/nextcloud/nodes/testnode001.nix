{ config, pkgs, lib, ... }: {
  # ==========================================================================
  # Redis for Nextcloud Caching
  # ==========================================================================
  config.services.redis.servers.nextcloud = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
  };

  # ==========================================================================
  # Nextcloud Configuration
  # ==========================================================================
  config.infrastructure.nextcloud = {
    enable = true;
    package = pkgs.nextcloud31;
    hostName = "localhost";
    https = false;

    admin = {
      user = "admin";
      passwordFile = "/run/secrets/nextcloud-admin-pass";
    };

    database = {
      type = "pgsql";
      name = "nextcloud";
      user = "nextcloud";
      host = "/run/postgresql";
      createLocally = true;  # Let Nextcloud module handle PostgreSQL setup
    };

    caching = {
      redis = true;
      apcu = true;
    };

    maxUploadSize = "1G";

    settings = {
      default_phone_region = "US";
      log_type = "file";
      loglevel = 2;
    };
  };

  # ==========================================================================
  # Create admin password file
  # ==========================================================================
  config.systemd.services.nextcloud-create-admin-pass = {
    description = "Create Nextcloud admin password file";
    wantedBy = [ "multi-user.target" ];
    before = [ "nextcloud-setup.service" ];
    requiredBy = [ "nextcloud-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /run/secrets
      echo "testadminpass123" > /run/secrets/nextcloud-admin-pass
      chmod 400 /run/secrets/nextcloud-admin-pass
      chown nextcloud:nextcloud /run/secrets/nextcloud-admin-pass
    '';
  };

  # ==========================================================================
  # Ensure correct service ordering
  # ==========================================================================
  
  # Nextcloud setup depends on PostgreSQL and Redis
  config.systemd.services.nextcloud-setup = {
    after = [ 
      "postgresql.service" 
      "redis-nextcloud.service"
      "nextcloud-create-admin-pass.service"
    ];
    requires = [ 
      "postgresql.service" 
    ];
    wants = [
      "redis-nextcloud.service"
      "nextcloud-create-admin-pass.service"
    ];
  };

  # PHP-FPM depends on nextcloud-setup
  config.systemd.services.phpfpm-nextcloud = {
    after = [ 
      "nextcloud-setup.service"
    ];
    requires = [
      "nextcloud-setup.service"
    ];
  };

  # Nginx depends on PHP-FPM
  config.systemd.services.nginx = {
    after = [ 
      "phpfpm-nextcloud.service" 
    ];
    wants = [
      "phpfpm-nextcloud.service"
    ];
  };

  # ==========================================================================
  # Test utilities
  # ==========================================================================
  config.environment.systemPackages = with pkgs; [
    curl
    jq
    postgresql
    redis
  ];
}