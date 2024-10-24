#!/usr/bin/env bash
CLI_BIN=$(realpath ~/DEV/nix-infra/dart_cluster/bin)
DIR=$(realpath ~/DEV/nix-infra/TEST)

dart run --verbosity=error $CLI_BIN/dart_cluster.dart port-forward -d $DIR --env="$DIR/.env" \
    --target="$1" \
    --local-port="$2" \
    --remote-port="$3"
