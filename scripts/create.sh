#!/usr/bin/env bash
CLI_DIR=$(dirname $0)
WORKING_DIR='../TEST'
source $CLI_DIR/common.sh

init

_start=`date +%s`

provision "etcd001 etcd002 etcd003 ingress001 registry001 worker001 service001"
exitOnFail $?

_provision=`date +%s`

echo "Checking nixos"
_nixos_fail="";
for node in etcd001 etcd002 etcd003 ingress001 registry001 worker001 service001; do
  if [[ $(cmd "$node" "uname -a") == *"NixOS"* ]]; then
    result=$(appendWithLineBreak "$result" "** - nixos    : ok ($node)")
  else
    result=$(appendWithLineBreak "$result" "** - nixos    : fail ($node)")
    _nixos_fail="true";
  fi
done

if [ -n "$_nixos_fail" ]; then
  echo -e "$result"
  echo "********************************************************"
  echo " NixOS is required on all nodes for this script to work"
  echo "********************************************************"
  exit 1
fi


init-ctrl
_init_ctrl=`date +%s`

init-ingress "ingress001"
init-node "registry001 worker001" "frontends backends"
init-node "service001" "services"

echo "Update overlay IP settings and restart confd"
NODES="ingress001 registry001 worker001 service001"
update-node "$NODES"
cmd "$NODES" "nixos-rebuild switch --fast"
cmd "$NODES" "systemctl restart confd"

_end=`date +%s`

echo "***** CHECKING CLUSTER *****"
result=""

echo "Checking etcd"
for node in etcd001 etcd002 etcd003; do
  if [[ $(cmd "$node" "systemctl is-active etcd") == *"active"* ]]; then
    result=$(appendWithLineBreak "$result" "** - etcd     : ok ($node)")
  else
    result=$(appendWithLineBreak "$result" "** - etcd     : down ($node)")
  fi
done

echo "Checking wireguard"
for node in ingress001 registry001 worker001 worker002 service001 service002 service003; do
  if [[ $(cmd "$node" "wg show") == *"peer: "* ]]; then
    result=$(appendWithLineBreak "$result" "** - wireguard: ok ($node)")
  else
    result=$(appendWithLineBreak "$result" "** - wireguard: down ($node)")
  fi
done

echo "Checking confd"
for node in ingress001 registry001 worker001 worker002 service001 service002 service003; do
  if [[ $(cmd "$node" "grep -q \"$node\" /root/test.txt && echo true") == *"true"* ]]; then
    result=$(appendWithLineBreak "$result" "** - confd: ok ($node)")
  else
    result=$(appendWithLineBreak "$result" "** - confd: down ($node)")
  fi
done

echo "******************************************"
_secs=$((_end-_start))
printf '** Total %s\n' $(printTime $_start $_end)
printf '** - provision  %s\n' $(printTime $_start $_provision)
printf '** - init_ctrl  %s\n' $(printTime $_provision $_init_ctrl)
printf '** - init_nodes %s\n' $(printTime $_init_ctrl $_end)
echo -e "$result"
echo "******************************************"

# export ETCDCTL_DIAL_TIMEOUT=3s
# export ETCDCTL_CACERT=/root/certs/ca-chain.cert.pem
# export ETCDCTL_CERT=/root/certs/$(hostname)-client-tls.cert.pem
# export ETCDCTL_KEY=/root/certs/$(hostname)-client-tls.key.pem
# export ETCDCTL_API=3
# export HOST_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
# etcdctl --endpoints=https://$HOST_IP:2379 get --prefix /cluster


# scripts/create-test-cluster.sh 
# scripts/destroy.sh worker002


# How to create a test cluster
### TODO: Move the scripts to test-cluster/{create.sh,deploy.sh,destroy.sh,update.sh,action.sh}

# 
# Create Cluster
# scripts/test-cluster/create.sh

# Deploy Service Apps on Registry Node
# scripts/test-cluster/deploy.sh registry001

# Publish App
# scripts/publish app-pod b3424ddb2227 registry001

# Initialise Service App Harmonia
### TODO: Register the public key with etcd
# scripts/test-cluster/action.sh registry001 harmonia.sh init
# copy/paste pub key
# scripts/test-cluster/update.sh
### TODO: Read the public key from etcd and share through substition

# Deploy Apps
# scripts/test-cluster/deploy.sh

# Initialise MongoDB Service
# scripts/test-cluster/action.sh service001 mongodb.sh init "service001=[%%service001.overlayIp%%],service002=[%%service002.overlayIp%%],service003=[%%service003.overlayIp%%]"

# Destroy Cluster
# scripts/test-cluster/destroy.sh


# Jun 26 20:11:29 worker001 systemd[1]: /etc/systemd/system/podman-app-pod.service:15: Unknown key name 'ExecStopPre' in section 'Service', ignoring.

# Do everything in three simple steps...
# APP_CMD="bin/dart_cluster.exe"; scripts/test-cluster/create.sh && scripts/test-cluster/deploy.sh registry001 && scripts/publish app-pod 85238bc5e026 registry001 && scripts/publish app-mongodb-pod 439162e5d0f4 registry001 && scripts/test-cluster/action.sh registry001 harmonia.sh init
# -- copy paste /cache.flstr.cloud:.*=/.../
# APP_CMD="bin/dart_cluster.exe"; scripts/test-cluster/update.sh && scripts/test-cluster/deploy.sh && scripts/test-cluster/action.sh service001 mongodb.sh init "service001=[%%service001.overlayIp%%],service002=[%%service002.overlayIp%%],service003=[%%service003.overlayIp%%]"
# -- test it
# APP_CMD="bin/dart_cluster.exe"; scripts/cmd ingress001 "curl -s http://127.0.0.1:11211/hello"
# -- and end it
# APP_CMD="bin/dart_cluster.exe"; scripts/test-cluster/destroy.sh

# ...same but with timers
# _t1=`date +%s`; scripts/test-cluster/create.sh && scripts/test-cluster/deploy.sh registry001 && scripts/publish app-pod 85238bc5e026 registry001 && scripts/publish app-mongodb-pod 439162e5d0f4 registry001 && scripts/test-cluster/action.sh registry001 harmonia.sh init; _t2=`date +%s`; echo $((_t2-_t1)) secs
# -- copy paste /cache.flstr.cloud:.*=/.../
# _t1=`date +%s`; scripts/test-cluster/update.sh && scripts/test-cluster/deploy.sh && scripts/test-cluster/action.sh service001 mongodb.sh init "service001=[%%service001.overlayIp%%],service002=[%%service002.overlayIp%%],service003=[%%service003.overlayIp%%]"; _t2=`date +%s`; echo $((_t2-_t1)) secs
# -- test it
# scripts/cmd ingress001 "curl -s http://127.0.0.1:11211/hello"
# scripts/cmd ingress001 "curl -s http://127.0.0.1:11311/ping"
# scripts/cmd ingress001 'curl -s -X GET "http://127.0.0.1:11311/db?id=1&message=hello"'
# scripts/cmd ingress001 "curl -s http://127.0.0.1:11311/db/1"
# -- and end it
# scripts/test-cluster/destroy.sh


# scripts/publish app-mongodb-pod 439162e5d0f4 registry001 && scripts/test-cluster/deploy.sh worker001


# Generate the nix-store public key and store it as a secret
# scripts/test-cluster/action.sh registry001 harmonia.sh init - "nix-store.trusted-public-keys.registry001"