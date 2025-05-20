# Variables
BACKEND ?= docker
K3D_VERSION ?= v5.6.0
KUBECTL_VERSION ?= v1.29.2
HELM_VERSION ?= v3.17.3
ARGOCD_VERSION ?= v2.9.3
K3D_CLUSTER_NAME ?= local-cluster
ARGOCD_NAMESPACE ?= argocd
ARGOCD_SECRET ?= argocd-secret

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
			# --agents 2 \
			--port 80:80@loadbalancer \
			--port 443:443@loadbalancer \
			# --k3s-arg '--disable=traefik@server:0' \
			# --k3s-arg '--tls-san=127.0.0.1@server:0' \
			--wait; \
		echo "Updating kubeconfig..."; \
		k3d kubeconfig merge $(K3D_CLUSTER_NAME) --kubeconfig-switch-context; \
		echo "k3d cluster created successfully"; \
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
	else \
		echo "Creating default ArgoCD admin credentials..."; \
		kubectl -n $(ARGOCD_NAMESPACE) create secret generic argocd-initial-admin-secret \
			--from-literal=username=admin \
			--from-literal=password=admin \
			--dry-run=client -o yaml | kubectl apply -f -; \
		echo "Default ArgoCD credentials:"; \
		echo "Username: admin"; \
		echo "Password: admin"; \
	fi
	@echo "Waiting for ArgoCD to be ready..."
	@kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n $(ARGOCD_NAMESPACE)
	@echo "ArgoCD installed successfully"
	@echo "You can access ArgoCD UI at: http://localhost:8001/api/v1/namespaces/$(ARGOCD_NAMESPACE)/services/argocd-server:80/proxy"

seed-argoctl: check-kubectl
	@echo "Installing ArgoCD CLI..."
	@curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/$(ARGOCD_VERSION)/argocd-linux-amd64
	@sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
	@rm argocd-linux-amd64
	@echo "ArgoCD CLI installed successfully"

seed-proxy: seed-argocd check-kubectl
	@echo "Starting kubectl proxy for ArgoCD UI..."
	@echo "ArgoCD UI will be available at: http://localhost:8001/api/v1/namespaces/$(ARGOCD_NAMESPACE)/services/argocd-server:80/proxy"
	@kubectl proxy