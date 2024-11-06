#!/usr/bin/env sh
read -p "Enter folder name [nix-infra-test]: " name
name=${name:-nix-infra-test}

mkdir -p $name

if command -v curl >/dev/null 2>&1; then
  curl -s https://raw.githubusercontent.com/jhsware/nix-infra/refs/heads/main/scripts/test-nix-infra-with-apps.sh -o $name/test-nix-infra-with-apps.sh
  curl -s https://raw.githubusercontent.com/jhsware/nix-infra/refs/heads/main/scripts/check.sh -o $name/check.sh
  curl -s https://raw.githubusercontent.com/jhsware/nix-infra-test/refs/heads/main/.env.in -o $name/.env
elif command -v wget >/dev/null 2>&1; then
  wget -q https://raw.githubusercontent.com/jhsware/nix-infra/refs/heads/main/scripts/test-nix-infra-with-apps.sh -O $name/test-nix-infra-with-apps.sh
  wget -q https://raw.githubusercontent.com/jhsware/nix-infra/refs/heads/main/scripts/check.sh -O $name/check.sh
  wget -q https://raw.githubusercontent.com/jhsware/nix-infra-test/refs/heads/main/.env.in -O $name/.env
else
  echo "neither curl nor wget is installed. Please install and try again."
  exit 1
fi
