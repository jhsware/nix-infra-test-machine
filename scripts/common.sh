#!/usr/bin/env bash
TEMPL_DIR="$CLI_DIR/../configuration"
APP_CMD=${APP_CMD:-'nix-infra'}
NIXOS_VERSION=24.05

init () {
  local DIR=${WORKING_DIR}

  mkdir -p $DIR

  if [ ! -d "$DIR/ca" ]
  then
    CA_PASS="$CERT_PWD" INTERMEDIATE_CA_PASS="$CERT_PWD" $APP_CMD init -d $DIR --env="$DIR/.env"
  fi

  mkdir -p $DIR/{modules,app_modules,nodes,node_types,openssl}

  # Create all the subdirectories in app_modules
  for dir_path in $(cd $TEMPL_DIR; find ./app_modules -type d); do
    if [ ! -d $WORKING_DIR/$dir_path ]; then
      mkdir -p $WORKING_DIR/$dir_path
    fi
  done

  # Update all the configuration files for the project
  for file_path in $(cd $TEMPL_DIR; find . -type f); do
    # if [ -f $WORKING_DIR/$file_path ]; then
    #   echo "File $file_path already exists, skipping"
    #   continue
    # fi
    echo $file_path
    cp -f $TEMPL_DIR/$file_path $WORKING_DIR/$file_path
  done
}

init-apps () {
  local DIR=${WORKING_DIR}

  # Create all the subdirectories in app_modules
  for dir_path in $(cd $TEMPL_DIR; find ./app_modules -type d); do
    if [ ! -d $WORKING_DIR/$dir_path ]; then
      mkdir -p $WORKING_DIR/$dir_path
    fi
  done

  # Update all the configuration files for app_modules and nodes
  for file_path in $(cd $TEMPL_DIR; find ./app_modules -type f); do
    cp -f $TEMPL_DIR/$file_path $WORKING_DIR/$file_path
  done
  
  for file_path in $(cd "$TEMPL_DIR" && find ./nodes -type f); do
    cp -f $TEMPL_DIR/$file_path $WORKING_DIR/$file_path
  done
}

provision () {
  local DIR=${WORKING_DIR}
  $APP_CMD provision -d $DIR --env="$DIR/.env" \
    --nixos-version=$NIXOS_VERSION \
    --ssh-key=deis \
    --location=hel1 \
    --machine-type=cpx21 \
    --node-names="$@"
} # cx22

init-ctrl() {
  local DIR=${WORKING_DIR}
  local CTRL=${1:-'etcd001 etcd002 etcd003'}
  $APP_CMD init-ctrl -d $DIR --env="$DIR/.env" \
    --nixos-version=$NIXOS_VERSION \
    --cluster-uuid="d6b76143-bcfa-490a-8f38-91d79be62fab" \
    --target="$CTRL"
}

init-node() {
  local DIR=${WORKING_DIR}
  local NODES="$1"
  local SERVICE_GROUP="$2"
  local CTRL=${3:-'etcd001 etcd002 etcd003'}
  $APP_CMD init-node -d $DIR --env="$DIR/.env" \
    --nixos-version=$NIXOS_VERSION \
    --target="$NODES" \
    --node-module="node_types/cluster_node.nix" \
    --service-group="$SERVICE_GROUP" \
    --ctrl-nodes="$CTRL"
}

deploy-apps() {
  local DIR=${WORKING_DIR}
  local NODES="$1"
  $APP_CMD deploy-apps -d $DIR --env="$DIR/.env" \
    --target="$NODES"
}

init-ingress() {
  local DIR=${WORKING_DIR}
  local NODES="$1"
  local CTRL=${2:-'etcd001 etcd002 etcd003'}
  $APP_CMD init-node -d $DIR --env="$DIR/.env" \
    --nixos-version=$NIXOS_VERSION \
    --target="$NODES" \
    --node-module="node_types/ingress_node.nix" \
    --service-group="ingress" \
    --ctrl-nodes="$CTRL"
}

update-node() {
  local DIR=${WORKING_DIR}
  local NODES="$1"
  local CTRL=${2:-'etcd001 etcd002 etcd003'}
  $APP_CMD update-node -d $DIR --env="$DIR/.env" \
    --nixos-version=$NIXOS_VERSION \
    --target="$NODES" \
    --node-module="node_types/cluster_node.nix" \
    --ctrl-nodes="$CTRL" \
    # --rebuild
}

update-ingress() {
  local DIR=${WORKING_DIR}
  local NODES="$1"
  local CTRL=${2:-'etcd001 etcd002 etcd003'}
  $APP_CMD update-node -d $DIR --env="$DIR/.env" \
    --nixos-version=$NIXOS_VERSION \
    --target="$NODES" \
    --node-module="node_types/ingress_node.nix" \
    --ctrl-nodes="$CTRL" \
}

destroy () {
  local DIR=${WORKING_DIR}
  local NODES="$1"
  local CTRL=${2:-'etcd001 etcd002 etcd003'}
  $APP_CMD destroy -d $DIR \
    --target="$NODES" \
    --ctrl-nodes="$CTRL"
}

cmd () {
  local DIR=${WORKING_DIR}
  $APP_CMD cmd -d $DIR --target="$1" "$2"
}

# utils
appendWithLineBreak() {
  if [ -z "$1" ]; then
    printf "$2"
  else
    printf "$1\n$2"
  fi
}

printTime() {
  local _start=$1
  local _end=$2
  _secs=$((_end-_start))
  printf '%02dh:%02dm:%02ds' $(($_secs/3600)) $(($_secs%3600/60)) $(($_secs%60))
}


publishImage() {
  local DIR=${WORKING_DIR}
  local NAME="$1"
  local IMAGE="$2"
  local TARGET_HOST="$3"

  $APP_CMD publish-image -d $DIR --env="$DIR/.env" \
    --target="$TARGET_HOST" \
    --image="$IMAGE" \
    --image-name="$NAME"
}

listImages() {
  local DIR=${WORKING_DIR}
  local TARGET_HOST="$1"

  $APP_CMD list-images -d $DIR --env="$DIR/.env" \
    --target="$TARGET_HOST";
}

exitOnFail() {
  local _res=$1;
  if [ $_res -ne 0 ]; then
    echo "Provision failed (code: $_res)"
    exit 1
  fi
}
