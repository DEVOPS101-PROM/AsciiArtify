k3d cluster create my-cluster --api-port 6550 --servers 1 --agents 2 --k3s-arg "--disable=traefik@server:0" 
kubectl get nodes
echo "APPLY Gateway API"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml 

sleep 30
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
sleep 30

echo "admin Password"
kubectl -n argocd  get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d | xargs echo

