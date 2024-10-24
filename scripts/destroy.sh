#!/usr/bin/env bash
CLI_DIR=$(dirname $0)
WORKING_DIR='../TEST'
source $CLI_DIR/common.sh

_start=`date +%s`

destroy "etcd001 etcd002 etcd003 ingress001 registry001 worker001 worker002 service001 service002 service003"
rm -rf $WORKING_DIR/ca

_end=`date +%s`
_secs=$((_end-_start))

if [ -f $WORKING_DIR/flake.nix ]; then
  echo "Destroying cluster working dir"
  rm -rf $WORKING_DIR/*
  exit 1
fi

echo "******************************************"
printf '** Duration %02dh:%02dm:%02ds\n' $(($_secs/3600)) $(($_secs%3600/60)) $(($_secs%60))
echo "******************************************"
