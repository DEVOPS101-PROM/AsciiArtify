# Variables
BACKEND ?= docker
K3D_VERSION ?= v5.6.0
KUBECTL_VERSION ?= v1.29.2
HELM_VERSION ?= v3.14.2

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

.PHONY: help check-backend check-k3d check-kubectl check-helm install-k3d install-kubectl install-helm update-kubectl update-helm all remove-k3d remove-kubectl remove-helm clear system-check

help:
	@echo "Available commands:"
	@echo "  make help        - Show this help message"
	@echo "  make all         - Check and install all components"
	@echo "  make system-check - Check system for all components"
	@echo "  make clear       - Remove all components"
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
		if [ "$$CURRENT_VERSION" != "$(HELM_VERSION:v%=%)" ]; then \
			echo "helm version $$CURRENT_VERSION is outdated. Current version is $(HELM_VERSION:v%=%)"; \
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

clear: remove-k3d remove-kubectl remove-helm
	@echo "All components have been removed." 