#!/usr/bin/env bash
CLI_DIR=$(dirname $0)/..
WORKING_DIR='../TEST'
source $CLI_DIR/common.sh

NODES=${@:-"ingress001 registry001 worker001 worker002 service001 service002 service003"}

init

_start=`date +%s`

# update-ingress "ingress001"
update-node "$NODES"

cmd "$NODES" "nixos-rebuild switch --fast"
cmd "$NODES" "systemctl restart confd"

_end=`date +%s`

result=""
echo "******************************************"
_secs=$((_end-_start))
printf '** Total %s\n' $(printTime $_start $_end)
echo -e "$result"
echo "******************************************"

# export ETCDCTL_DIAL_TIMEOUT=3s
# export ETCDCTL_CACERT=/root/certs/ca-chain.cert.pem
# export ETCDCTL_CERT=/root/certs/$(hostname)-client-tls.cert.pem
# export ETCDCTL_KEY=/root/certs/$(hostname)-client-tls.key.pem
# export ETCDCTL_API=3
# export ETCD_IP=
# etcdctl --endpoints=https://$ETCD_IP:2379 get --prefix /cluster
