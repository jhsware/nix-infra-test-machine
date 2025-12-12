# nix-infra-machine

A standalone machine template for [nix-infra](https://github.com/jhsware/nix-infra). This template allows you to deploy and manage individual machines (or fleets of machines) with minimal configuration. All you need is a Hetzner Cloud account.

## Prerequisites

- [nix-infra CLI](https://github.com/jhsware/nix-infra/releases) installed
- A Hetzner Cloud account with an API token
- Git installed

Optional but recommended: Install [Nix](https://docs.determinate.systems/determinate-nix/) and work in a nix-shell for reproducible environments.

## Quick Start

1. Run this script to clone the template:

```sh
sh <(curl -L https://raw.githubusercontent.com/jhsware/nix-infra-machine/refs/heads/main/scripts/get-test.sh)
```

2. Get an API token from your Hetzner Cloud project

3. Edit the `.env` file in the created folder with your token and settings

4. Explore available commands:

```sh
cd test-nix-infra-machine

# Infrastructure management (create, destroy, ssh, etc.)
./cli --help

# Run test suite against machines
./__test__/run-tests.sh --help
```

## CLI Commands

The `cli` script is your main interface for managing infrastructure:

```sh
# Create a machine
./cli create node001

# Create multiple machines
./cli create node001 node002 node003

# SSH into a machine
./cli ssh node001

# Run commands on machines
./cli cmd --target=node001 "systemctl status nginx"

# Update configuration and deploy apps
./cli update node001

# Upgrade NixOS version
./cli upgrade node001

# Rollback to previous configuration
./cli rollback node001

# Run app module actions
./cli action --target=node001 myapp status

# Port forward from remote to local
./cli port-forward --target=node001 --port-mapping=8080:80

# Destroy machines
./cli destroy --target="node001 node002"

# Launch Claude with MCP integration
./cli claude
```

## Running Tests

The test workflow has two stages:

### 1. Create the test machines

The `create` command provisions the base machines and verifies basic functionality:

```sh
# Provision machines and run basic health checks
./__test__/run-tests.sh create
```

This creates and verifies: NixOS installation and basic system health.

### 2. Run app_module tests against the machines

Once you have running machines, use `run` to test specific app_modules:

```sh
# Run a single app test (e.g., mongodb)
./__test__/run-tests.sh run mongodb

# Keep test apps deployed after running
./__test__/run-tests.sh run --no-teardown mongodb
```

Available tests are defined in `__test__/<test-name>/test.sh`. List available tests:

```sh
ls __test__/*/test.sh
```

### Other test commands

```sh
# Reset machine state between test runs
./__test__/run-tests.sh reset mongodb

# Destroy all test machines
./__test__/run-tests.sh destroy

# Check machine health
./__test__/run-tests.sh test
```

Useful commands for exploring running test machines:

```sh
./__test__/run-tests.sh ssh node001
./__test__/run-tests.sh cmd --target=node001 "uptime"
```

## Custom Configuration

To create your own configuration from scratch:

1. Clone this repository:

```sh
git clone git@github.com:jhsware/nix-infra-machine.git my-infrastructure
cd my-infrastructure
```

2. Set up environment:

```sh
cp .env.in .env
nano .env  # Add your HCLOUD_TOKEN and other settings
```

3. Create and manage your machines:

```sh
./cli create node001
./cli ssh node001
./cli update node001
```

## Directory Structure

```
.
├── cli                 # Main CLI for infrastructure management
├── .env                # Environment configuration (create from .env.in)
├── nodes/              # Per-node configuration files
├── node_types/         # Node type templates (standalone_machine.nix)
├── app_modules/        # Application module definitions
├── __test__/           # Test scripts and test definitions
└── scripts/            # Utility scripts
```

## Deploying Applications

Each node has its configuration in `nodes/`. Configure what apps to run and their settings here.

Deploy using the `update` command:

```sh
./cli update node001 node002
```

You can specify a custom node module:

```sh
./cli create --node-module=node_types/custom_machine.nix node001
```

## Secrets

Store secrets securely using the nix-infra CLI:

```sh
nix-infra secrets store -d . --secret="my-secret-value" --name="app.secret"
```

Or save action output as a secret:

```sh
./cli action --target=node001 myapp create-credentials --save-as-secret="myapp.credentials"
```

Secrets are encrypted locally and deployed as systemd credentials (automatically encrypted/decrypted on demand).

## Node Types

The default node type is `node_types/standalone_machine.nix`. Create custom node types in `node_types/` for different machine configurations, then reference them with `--node-module`.
