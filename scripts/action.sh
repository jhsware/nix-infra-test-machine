#!/usr/bin/env bash
CLI_DIR=$(dirname $0)
WORKING_DIR='../TEST'
source $CLI_DIR/common.sh

_start=`date +%s`

action () {
  local DIR=$WORKING_DIR
  WORKING_DIR=$DIR init
  local NODES="$1";
  local APP_MODULE="$2";
  local CMD="$3";
  local ENV_VARS="$4";
  local SECRET_NAMESPACE="$5";
  local _secrets_opts="";

  if [[ "$ENV_VARS" == "-" ]]; then
    ENV_VARS=""scip
  fi

  if [ ! -z "$SECRET_NAMESPACE" ]; then
    _secrets_opts="--save-as-secret=$SECRET_NAMESPACE"
  fi

  dart run --verbosity=error bin/dart_cluster.dart action -d $DIR --env="$DIR/.env" \
    --target="$NODES" \
    --app-module="$APP_MODULE" \
    --cmd="$CMD" \
    --env-vars="$ENV_VARS" \
    $_secrets_opts
}
action "$@"
# action-test-cluster.sh service001 mongodb.sh init "service001=[%%service001.overlayIp%%],service002=[%%service002.overlayIp%%],service003=[%%service003.overlayIp%%]"
# action-test-cluster.sh service001 mongodb.sh add-user "USERNAME=jhsware,PASSWORD=stuff"