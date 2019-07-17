#!/bin/bash

# Wrapper to execute same command (or bunch of commands) in multiple directories on the same level
# Usage: ./script.sh <your command to execute in each target folder>
# Example: ./execute_in_folders.sh 'terraform init && terraform plan'


targets=(
    dir1
    dir2
    dir3
)

set -x

for CWD in ${targets[*]}; do
    cd $CWD
    pwd
    eval $@
    cd ..
done

