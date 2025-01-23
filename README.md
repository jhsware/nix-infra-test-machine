# nix-infra-test-machine
This is a standalone setup for testing nix-infra. It is intended to allow you to try out nix-infra with minimal configuration. All you need is a Hetzner account and some super basic configuration.

1. Download [nix-infra](https://github.com/jhsware/nix-infra/releases) and install it

## Run a fully automated test script

2. Run [this script](https://github.com/jhsware/nix-infra-test-machine/blob/main/scripts/get-test.sh) in the terminal to download test scripts:

```sh
sh <(curl -L https://raw.githubusercontent.com/jhsware/nix-infra-test-machine/refs/heads/main/scripts/get-test.sh)
```
3. Get an API-key for an empty Hetzner Cloud project

4. Edit the .env in the created folder

5. Run the test script

```sh
test-nix-infra-machine/test-nix-infra-machine.sh --env=nix-infra-machine/.env
```

Once you have set up .env properly, the downloaded script will provision, configure and deploy your fleet. It will then run some tests to check that it is working properly and finish by tearing down the fleet.

## Create your custom config

2. Clone [this repos](https://github.com/jhsware/nix-infra-test-machine):

```sh
git clone git@github.com:jhsware/nix-infra-test-machine.git [my-new-repo]
```

3. Get an API-key for an empty Hetzner Cloud project

4. Edit the .env in the created folder

3. Get an API-key for an empty Hetzner Cloud project

4. Edit the .env in the created folder

```sh
cp .env.in .env
nano .env
```

5. Initialise the repo

```sh
scripts/cli init --env=.env
```

6. Work with your fleet

```sh
scripts/cli create --env=.env node001
scripts/cli ssh --env=.env node001
scripts/cli cmd --env=.env --target=node001 ls -alh
scripts/cli destroy --env=.env --target=node001
scripts/cli update --env=.env node001
```

To create custom configurationsm add them to the `nodes/` sub-directory and then run the `create`or `update` command above. The custom configuration is optional, if you want to create a fleet of equivalent machines you can add configuration files to `node_types/` and edit the cli script to allow you to select which type to use.

## Test Script Options

To build without immediately tearing down the cluster:

```sh
test-nix-infra-machine.sh --no-teardown --env=nix-infra-machine/.env
```

Useful commands to explore the running test cluster (check the bash script for more):

```sh
test-nix-infra-machine.sh cmd --target=node001 "uptime" --env=nix-infra-machine/.env
test-nix-infra-machine.sh ssh node001 --env=nix-infra-machine/.env
```

To tear down the cluster:

```sh
test-nix-infra-machine.sh teardown --env=nix-infra-machine/.env
```

## Deploying an Application
Each node has it's own configuration in the `nodes/` folder.

In this configuration you can configure what apps to run on that node and how you want them to be configured.

The actual deployment is done using the `deploy-apps` command and specifying the target nodes you want to update. All app configurations or the node will be affected.

### Secrets
To securely provide secrets to your application, store them using the CLI `secrets` command or as an output from a CLI `action`command using the option `--store-as-secret=[name]`.

The secret will be encrypted in your local cluster configuration directory. When deploying an application, the CLI will pass any required secrets to the target and store it as a systemd credential. Systemd credentials are automatically encrypted/decrypted on demand.
