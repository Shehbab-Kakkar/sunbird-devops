#!/bin/sh

set -e

SCRIPT_BASE_DIR=$(dirname $0)
SUNBIRD_DEVOPS_FOLDER=$SCRIPT_BASE_DIR
#kali script
bash $SUNBIRD_DEVOPS_FOLDER/ansible-syntax-check.sh $SUNBIRD_DEVOPS_FOLDER/ansible/inventories/sample
