# Create the Pod from the YAML file
kubectl apply -f pod.yaml

# Check Pod status and IP address
kubectl get pod nginx-pod -o wide

# View detailed events and configuration
kubectl describe pod nginx-pod

# Delete the Pod
kubectl delete -f pod.yaml