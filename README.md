# nix-infra-test-machine
This is a standalone setup for testing nix-infra. It is intended to allow you to try out nix-infra with minimal configuration. All you need is a Hetzner account and some super basic configuration.

1. Download [nix-infra](https://github.com/jhsware/nix-infra/releases) and install it

2. Run [this script](https://github.com/jhsware/nix-infra-test-machine/blob/main/scripts/get-test.sh) in the terminal to download test scripts:

```sh
sh <(curl -L https://raw.githubusercontent.com/jhsware/nix-infra-test-machine/refs/heads/main/scripts/get-test.sh)
```
3. Get an API-key for an empty Hetzner Cloud project

4. Edit the .env in the created folder

5. Run the test script

```sh
nix-infra-test-machine/test-nix-infra-machine.sh --env=nix-infra-test/.env
```

Once you have set up .env properly, the downloaded script will provision, configure and deploy your cluster. It will then run some tests to check that it is working properly and finish by tearing down the cluster. Copy and modify the script to create your own experimental cluster.

## Test Script Options

To build without immediately tearing down the cluster:

```sh
test-nix-infra-machine.sh --no-teardown --env=nix-infra-test/.env
```

Useful commands to explore the running test cluster (check the bash script for more):

```sh
test-nix-infra-machine.sh cmd --target=node001 "uptime" --env=nix-infra-test/.env
test-nix-infra-machine.sh ssh node001 --env=nix-infra-test/.env
```

To tear down the cluster:

```sh
test-nix-infra-machine.sh teardown --env=nix-infra-test/.env
```

## Deploying an Application
Each node has it's own configuration in the `nodes/` folder.

In this configuration you can configure what apps to run on that node and how you want them to be configured.

The actual deployment is done using the `deploy-apps` command and specifying the target nodes you want to update. All app configurations or the node will be affected.

### Secrets
To securely provide secrets to your application, store them using the CLI `secrets` command or as an output from a CLI `action`command using the option `--store-as-secret=[name]`.

The secret will be encrypted in your local cluster configuration directory. When deploying an application, the CLI will pass any required secrets to the target and store it as a systemd credential. Systemd credentials are automatically encrypted/decrypted on demand.
