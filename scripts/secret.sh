#!/usr/bin/env bash
CLI_DIR=$(dirname $0)/..
DIR='../TEST'
source $CLI_DIR/common.sh

_start=`date +%s`

dart run --verbosity=error bin/dart_cluster.dart store-secret -d $DIR --env=$DIR/.env $@
