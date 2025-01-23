let
  sources = import ./nix/sources.nix;
  pkgs = import sources.nixpkgs {};
  hcloud = pkgs.callPackage nix/hcloud.nix {};

  isMacOS = builtins.match ".*-darwin" pkgs.stdenv.hostPlatform.system != null;
in pkgs.mkShell rec {
  name = "nix-infra";

  buildInputs = with pkgs; [    
    pkgs.openssl
    # pkgs.hcloud
    hcloud
  ] ++ (if !isMacOS then [
    pkgs.openssh
  ] else []);

  shellHook = ''

  '';
}
