#!/usr/bin/env sh
TEMPLATE_REPO_BRANCH="git@github.com:jhsware/nix-infra-test-machine.git"
TEMPLATE_REPO=main


# Check for nix-infra CLI
if ! command -v git >/dev/null 2>&1; then
  echo "You need 'git' for this script to work."
  echo "Install git using your prefered package manager. If in doubt, install Determinate Nix"
  echo "https://docs.determinate.systems/determinate-nix/ and run: 'nix-shell -p git'"
  echo
  echo "With nix-shell you get ephemeral shell environments. Learn more:"
  echo "https://medium.com/@nonickedgr/exploring-nix-shell-a-game-changer-for-ephemeral-environments-5c622e4074a8"
  exit 1
fi


read -p "Enter folder name [test-nix-infra-machine]: " name
name=${name:-test-nix-infra-machine}



mkdir -p $name

if [ -d "./$name" ]; then
  echo "Folder $name already exists in this directory, aborting."
  exit 1
fi

git clone -b $TEMPLATE_REPO_BRANCH $TEMPLATE_REPO "$name"
cd "$name" || exit 1
cp .env.in .env

echo "Done!"
echo
echo "Make sure you have installed nix-infra, then:"
echo "1. Edit .env"
echo "2. Run scripts/cli --env=.env"
echo
