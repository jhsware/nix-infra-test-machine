#!/usr/bin/env sh
read -p "Enter folder name [nix-infra-test]: " name
name=${name:-test-nix-infra-machine}

mkdir -p $name

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -s $2 -o $3
  elif command -v wget >/dev/null 2>&1; then
    wget -q $2 -O $3
  else
    echo "neither curl nor wget is installed. Please install and try again."
    exit 1
  fi
  chmod $1 $3
}

fetch 755 https://raw.githubusercontent.com/jhsware/nix-infra/refs/heads/main/scripts/test-nix-infra-machine.sh $name/test-nix-infra-machine.sh
fetch 644 https://raw.githubusercontent.com/jhsware/nix-infra/refs/heads/main/scripts/check.sh $name/check.sh
fetch 644 https://raw.githubusercontent.com/jhsware/nix-infra-test-machine/refs/heads/main/.env.in $name/.env
echo "Done!"
echo
echo "Make sure you have installed nix-infra, then:"
echo "1. Edit $name/.env"
echo "2. Run $name/test-nix-infra-machine.sh --env=$name/.env"
echo
