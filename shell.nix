let
  sources = import ./nix/sources.nix;
  pkgs = import sources.nixpkgs {};
  hcloud = pkgs.callPackage nix/hcloud.nix {};

  isMacOS = builtins.match ".*-darwin" pkgs.stdenv.hostPlatform.system != null;
in pkgs.mkShell rec {
  name = "nix-infra-machine";

  buildInputs = with pkgs; [
    hcloud
  ] ++ (if !isMacOS then [
  ] else []);

  shellHook = ''

  '';
}
