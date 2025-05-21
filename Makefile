# Variables
BACKEND ?= docker
K3D_VERSION ?= v5.6.0
KUBECTL_VERSION ?= v1.29.2
HELM_VERSION ?= v3.17.3
ARGOCD_VERSION ?= v2.9.3
K3D_CLUSTER_NAME ?= local-cluster
ARGOCD_NAMESPACE ?= argocd
ARGOCD_SECRET ?= argocd-secret
ACCESS_TYPE ?= loadbalancer # Options: loadbalancer, ingress
LOCAL_IP ?= $(shell hostname -I | awk '{print $$1}')

# Colors
GREEN := \033[0;32m
RED := \033[0;31m
NC := \033[0m # No Color

# Detect OS
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    OS := linux
else ifeq ($(UNAME_S),Darwin)
    OS := darwin
else
    $(error Unsupported operating system: $(UNAME_S))
endif

# Detect architecture
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),x86_64)
    ARCH := amd64
else ifeq ($(UNAME_M),aarch64)
    ARCH := arm64
else
    $(error Unsupported architecture: $(UNAME_M))
endif

.PHONY: help check-backend check-k3d check-kubectl check-helm install-k3d install-kubectl install-helm update-kubectl update-helm all remove-k3d remove-kubectl remove-helm clear system-check seed seed-create seed-destroy seed-argocd seed-argoctl seed-proxy

help:
	@echo "Available commands:"
	@echo "  make help        - Show this help message"
	@echo "  make all         - Check and install all components"
	@echo "  make system-check - Check system for all components"
	@echo "  make clear       - Remove all components"
	@echo "  make seed        - Create and setup k3d cluster with ArgoCD"
	@echo ""
	@echo "Seed commands:"
	@echo "  make seed-create  - Create k3d cluster"
	@echo "  make seed-destroy - Destroy k3d cluster"
	@echo "  make seed-argocd  - Install ArgoCD in the cluster"
	@echo "  make seed-argoctl - Install ArgoCD CLI"
	@echo "  make seed-proxy   - Start kubectl proxy for ArgoCD UI"
	@echo ""
	@echo "Installation commands:"
	@echo "  make install-k3d     - Install k3d"
	@echo "  make install-kubectl - Install kubectl"
	@echo "  make install-helm    - Install helm"
	@echo ""
	@echo "Removal commands:"
	@echo "  make remove-k3d     - Remove k3d"
	@echo "  make remove-kubectl - Remove kubectl"
	@echo "  make remove-helm    - Remove helm"
	@echo ""
	@echo "Variables:"
	@echo "  BACKEND=docker|podman - Choose container backend (default: docker)"

system-check:
	@echo "System Check Results:"
	@echo "===================="
	@# Check Docker
	@if command -v docker >/dev/null 2>&1; then \
		echo -e "Docker: $(GREEN)Installed$(NC) ($$(docker --version))"; \
	else \
		echo -e "Docker: $(RED)Not Installed$(NC)"; \
	fi
	@# Check Podman
	@if command -v podman >/dev/null 2>&1; then \
		echo -e "Podman: $(GREEN)Installed$(NC) ($$(podman --version))"; \
	else \
		echo -e "Podman: $(RED)Not Installed$(NC)"; \
	fi
	@# Check k3d
	@if command -v k3d >/dev/null 2>&1; then \
		echo -e "k3d: $(GREEN)Installed$(NC) ($$(k3d version))"; \
	else \
		echo -e "k3d: $(RED)Not Installed$(NC)"; \
	fi
	@# Check kubectl
	@if command -v kubectl >/dev/null 2>&1; then \
		echo -e "kubectl: $(GREEN)Installed$(NC) ($$(kubectl version --client -o json | grep -o '"gitVersion": "[^"]*"' | cut -d'"' -f4))"; \
	else \
		echo -e "kubectl: $(RED)Not Installed$(NC)"; \
	fi
	@# Check helm
	@if command -v helm >/dev/null 2>&1; then \
		echo -e "helm: $(GREEN)Installed$(NC) ($$(helm version --template='{{.Version}}'))"; \
	else \
		echo -e "helm: $(RED)Not Installed$(NC)"; \
	fi
	@echo ""
	@echo "Missing components:"
	@if ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then \
		echo -e "$(RED)No container backend (Docker or Podman) is installed$(NC)"; \
	fi
	@if ! command -v k3d >/dev/null 2>&1; then \
		echo -e "$(RED)k3d is not installed$(NC)"; \
	fi
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo -e "$(RED)kubectl is not installed$(NC)"; \
	fi
	@if ! command -v helm >/dev/null 2>&1; then \
		echo -e "$(RED)helm is not installed$(NC)"; \
	fi
	@echo ""
	@echo "To install missing components, run: make all"

all: system-check
	@echo ""
	@echo "Starting installation process..."
	@$(MAKE) check-backend
	@$(MAKE) check-k3d
	@$(MAKE) check-kubectl
	@$(MAKE) check-helm

check-backend:
	@echo "Checking backend..."
	@if [ "$(BACKEND)" = "docker" ]; then \
		if ! command -v docker >/dev/null 2>&1; then \
			echo "Docker is not installed. Please install Docker first."; \
			exit 1; \
		fi; \
	elif [ "$(BACKEND)" = "podman" ]; then \
		if ! command -v podman >/dev/null 2>&1; then \
			echo "Podman is not installed. Please install Podman first."; \
			exit 1; \
		fi; \
	else \
		echo "Invalid backend. Please choose either 'docker' or 'podman'."; \
		exit 1; \
	fi
	@echo "Backend $(BACKEND) is available."

check-k3d:
	@echo "Checking k3d installation..."
	@if ! command -v k3d >/dev/null 2>&1; then \
		echo "k3d is not installed. Installing..."; \
		$(MAKE) install-k3d; \
	else \
		echo "k3d is installed."; \
	fi

check-kubectl:
	@echo "Checking kubectl installation..."
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo "kubectl is not installed. Installing..."; \
		$(MAKE) install-kubectl; \
	else \
		CURRENT_VERSION=$$(kubectl version --client -o json | grep -o '"gitVersion": "[^"]*"' | cut -d'"' -f4); \
		if [ "$$CURRENT_VERSION" != "$(KUBECTL_VERSION)" ]; then \
			echo "kubectl version $$CURRENT_VERSION is outdated. Current version is $(KUBECTL_VERSION)"; \
			read -p "Do you want to update kubectl? (y/n) " answer; \
			if [ "$$answer" = "y" ]; then \
				$(MAKE) update-kubectl; \
			fi; \
		else \
			echo "kubectl is up to date."; \
		fi; \
	fi

check-helm:
	@echo "Checking helm installation..."
	@if ! command -v helm >/dev/null 2>&1; then \
		echo "helm is not installed. Installing..."; \
		$(MAKE) install-helm; \
	else \
		CURRENT_VERSION=$$(helm version --template='{{.Version}}' | cut -d'v' -f2); \
		TARGET_VERSION=$$(echo $(HELM_VERSION) | cut -d'v' -f2); \
		if [ "$$CURRENT_VERSION" != "$$TARGET_VERSION" ]; then \
			echo "helm version $$CURRENT_VERSION is outdated. Current version is $$TARGET_VERSION"; \
			read -p "Do you want to update helm? (y/n) " answer; \
			if [ "$$answer" = "y" ]; then \
				$(MAKE) update-helm; \
			fi; \
		else \
			echo "helm is up to date."; \
		fi; \
	fi

install-k3d:
	@echo "Installing k3d..."
	@curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
	@echo "k3d installation completed."

install-kubectl:
	@echo "Installing kubectl..."
	@curl -LO "https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(OS)/$(ARCH)/kubectl"
	@chmod +x kubectl
	@sudo mv kubectl /usr/local/bin/
	@echo "kubectl installation completed."

install-helm:
	@echo "Installing helm..."
	@curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
	@chmod 700 get_helm.sh
	@./get_helm.sh --version $(HELM_VERSION)
	@rm get_helm.sh
	@echo "helm installation completed."

update-kubectl:
	@echo "Updating kubectl..."
	@curl -LO "https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(OS)/$(ARCH)/kubectl"
	@chmod +x kubectl
	@sudo mv kubectl /usr/local/bin/
	@echo "kubectl update completed."

update-helm:
	@echo "Updating helm..."
	@curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
	@chmod 700 get_helm.sh
	@./get_helm.sh --version $(HELM_VERSION)
	@rm get_helm.sh
	@echo "helm update completed."

remove-k3d:
	@echo "Removing k3d..."
	@if command -v k3d >/dev/null 2>&1; then \
		sudo rm -f /usr/local/bin/k3d; \
		echo "k3d has been removed."; \
	else \
		echo "k3d is not installed."; \
	fi

remove-kubectl:
	@echo "Removing kubectl..."
	@if command -v kubectl >/dev/null 2>&1; then \
		sudo rm -f /usr/local/bin/kubectl; \
		echo "kubectl has been removed."; \
	else \
		echo "kubectl is not installed."; \
	fi

remove-helm:
	@echo "Removing helm..."
	@if command -v helm >/dev/null 2>&1; then \
		sudo rm -f /usr/local/bin/helm; \
		echo "helm has been removed."; \
	else \
		echo "helm is not installed."; \
	fi

clear: seed-destroy remove-k3d remove-kubectl remove-helm 
	@echo "All components have been removed."

# Seed targets
seed: seed-create seed-argocd seed-argoctl
	@echo "Seed setup completed successfully"

seed-create: check-backend check-k3d check-kubectl
	@echo "Checking k3d cluster status..."
	@if k3d cluster list | grep -q "$(K3D_CLUSTER_NAME)"; then \
		echo "Cluster $(K3D_CLUSTER_NAME) already exists, skipping creation..."; \
	else \
		echo "Creating k3d cluster..."; \
		k3d cluster create $(K3D_CLUSTER_NAME) \
			--api-port 56443 \
			--servers 1 \
			--agents 1 \
			--k3s-arg '--tls-san=127.0.0.1@server:0' \
			--wait; \
		echo "Updating kubeconfig..."; \
		k3d kubeconfig merge $(K3D_CLUSTER_NAME) --kubeconfig-switch-context; \
		echo "k3d cluster created successfully"; \
		echo ""; \
	fi

seed-destroy: check-backend check-k3d check-kubectl
	@echo "Destroying k3d cluster..."
	@if k3d cluster list | grep -q "$(K3D_CLUSTER_NAME)"; then \
		k3d cluster delete $(K3D_CLUSTER_NAME); \
		echo "k3d cluster destroyed successfully"; \
	else \
		echo "Cluster $(K3D_CLUSTER_NAME) does not exist, nothing to destroy."; \
	fi

seed-argocd: seed-create check-kubectl check-helm
	@echo "Installing ArgoCD..."
	@kubectl config use-context k3d-$(K3D_CLUSTER_NAME)
	@kubectl create namespace $(ARGOCD_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -n $(ARGOCD_NAMESPACE) -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	@if [ -n "$(ARGOCD_SECRET)" ] && [ -f "$(ARGOCD_SECRET)" ]; then \
		echo "Applying custom secret from $(ARGOCD_SECRET)..."; \
		kubectl apply -f $(ARGOCD_SECRET) -n $(ARGOCD_NAMESPACE); \
	fi
	@echo "Waiting for ArgoCD to be ready..."
	@kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n $(ARGOCD_NAMESPACE)
	
	@echo "Installing NGINX Ingress Controller..."
	@kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
	@echo "Waiting for Ingress Controller to be ready..."
	@kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
	
	@echo "Configuring ArgoCD Ingress..."
	@echo "apiVersion: networking.k8s.io/v1" > /tmp/argocd-ingress.yaml
	@echo "kind: Ingress" >> /tmp/argocd-ingress.yaml
	@echo "metadata:" >> /tmp/argocd-ingress.yaml
	@echo "  name: argocd-server-ingress" >> /tmp/argocd-ingress.yaml
	@echo "  namespace: $(ARGOCD_NAMESPACE)" >> /tmp/argocd-ingress.yaml
	@echo "  annotations:" >> /tmp/argocd-ingress.yaml
	@echo "    nginx.ingress.kubernetes.io/ssl-passthrough: \"true\"" >> /tmp/argocd-ingress.yaml
	@echo "    nginx.ingress.kubernetes.io/backend-protocol: \"HTTPS\"" >> /tmp/argocd-ingress.yaml
	@echo "spec:" >> /tmp/argocd-ingress.yaml
	@echo "  ingressClassName: nginx" >> /tmp/argocd-ingress.yaml
	@echo "  rules:" >> /tmp/argocd-ingress.yaml
	@echo "  - host: argocd.$(LOCAL_IP).nip.io" >> /tmp/argocd-ingress.yaml
	@echo "    http:" >> /tmp/argocd-ingress.yaml
	@echo "      paths:" >> /tmp/argocd-ingress.yaml
	@echo "      - path: /" >> /tmp/argocd-ingress.yaml
	@echo "        pathType: Prefix" >> /tmp/argocd-ingress.yaml
	@echo "        backend:" >> /tmp/argocd-ingress.yaml
	@echo "          service:" >> /tmp/argocd-ingress.yaml
	@echo "            name: argocd-server" >> /tmp/argocd-ingress.yaml
	@echo "            port:" >> /tmp/argocd-ingress.yaml
	@echo "              name: https" >> /tmp/argocd-ingress.yaml
	@kubectl apply -f /tmp/argocd-ingress.yaml
	@rm /tmp/argocd-ingress.yaml
	@echo "Ingress configured for: https://argocd.$(LOCAL_IP).nip.io"

	@echo "Waiting for ArgoCD to initialize..."
	@sleep 10
	@echo "\n\n~~~~~~~~"
	@echo "Current ArgoCD credentials:"
	@echo "Username: $(GREEN)admin$(NC)"
	@if [ -n "$(ARGOCD_SECRET)" ] && [ -f "$(ARGOCD_SECRET)" ]; then \
		echo "Using custom password from $(RED)$(ARGOCD_SECRET)$(NC)"; \
	else \
		echo "Password: $(RED)$$(kubectl -n $(ARGOCD_NAMESPACE) get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)$(NC)"; \
	fi
	@echo "~~~~~~~~\n\n"
	@echo "ArgoCD UI is available at: https://argocd.$(LOCAL_IP).nip.io"
	@echo "Note: You might need to accept the self-signed certificate in your browser"

seed-argoctl: check-kubectl
	@echo "Installing ArgoCD CLI..."
	@curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/$(ARGOCD_VERSION)/argocd-linux-amd64
	@sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
	@rm argocd-linux-amd64
	@echo "ArgoCD CLI installed successfully"

seed-proxy: check-kubectl
	@echo "Checking ArgoCD installation..."
	@if ! kubectl get namespace $(ARGOCD_NAMESPACE) >/dev/null 2>&1; then \
		echo "ArgoCD namespace not found. Installing ArgoCD..."; \
		$(MAKE) seed-argocd; \
	fi
	@if ! kubectl get deployment argocd-server -n $(ARGOCD_NAMESPACE) >/dev/null 2>&1; then \
		echo "ArgoCD server not found. Installing ArgoCD..."; \
		$(MAKE) seed-argocd; \
	fi
	@echo "Checking ArgoCD server status..."
	@if ! kubectl get deployment argocd-server -n $(ARGOCD_NAMESPACE) -o jsonpath='{.status.availableReplicas}' | grep -q "1"; then \
		echo "Waiting for ArgoCD server to be ready..."; \
		kubectl wait --for=condition=available --timeout=30s deployment/argocd-server -n $(ARGOCD_NAMESPACE); \
	fi
	@echo "Starting port-forward for ArgoCD UI..."
	@echo "ArgoCD UI will be available at: https://localhost:8080"
	@echo "Press Ctrl+C to stop the port-forward"
	@kubectl port-forward -n $(ARGOCD_NAMESPACE) svc/argocd-server 8080:443