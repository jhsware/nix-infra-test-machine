#!/usr/bin/env bash
CLI_DIR=$(dirname $0)
WORKING_DIR='../TEST'
CERT_PWD="test"
source $CLI_DIR/common.sh

NODES=${@:-"registry001 worker001 worker002 service001 service002 service003"}

init-apps

_start=`date +%s`

# update-ingress "ingress001"
deploy-apps "$NODES"

cmd "$NODES" "nixos-rebuild switch --fast"

_end=`date +%s`

# echo "***** CHECKING CLUSTER *****"
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
# export HOST_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
# etcdctl --endpoints=https://$HOST_IP:2379 get --prefix /cluster
