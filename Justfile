[private]
help:
    @just --list --unsorted

# Apply current cluster configuration
apply-cluster:
    kubectl kustomize --enable-helm cluster | kubectl apply "--context=admin@talos-epimelitis" -f -

# Gets all Home Assistant pods
get-ha-pods:
    kubectl get pods "--context=admin@talos-epimelitis" -n home-assistant
