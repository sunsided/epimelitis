[private]
help:
    @just --list --unsorted

# Apply current cluster configuration
apply-cluster:
    kubectl kustomize --enable-helm cluster | kubectl apply -f -
