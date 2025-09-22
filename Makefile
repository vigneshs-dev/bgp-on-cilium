.PHONY: all deploy-kind deploy-clab deploy-clab-ui check-connectivity install-cilium deploy-policies test-connectivity clean destroy-all check-kind check-clab check-clab-ui check-cilium

# Utility targets for checking status
check-kind:
	@if kind get clusters | grep -q "^kind$$"; then \
		echo "Kind cluster already exists."; \
		exit 0; \
	else \
		echo "Kind cluster does not exist."; \
		exit 1; \
	fi

check-clab:
	@if containerlab inspect -t topo.yaml 2>/dev/null | grep -q "running"; then \
		echo "ContainerLab topology already running."; \
		exit 0; \
	else \
		echo "ContainerLab topology not running."; \
		exit 1; \
	fi

check-clab-ui:
	@if docker ps --format '{{.Names}}' | grep -q "^clab-ui$$"; then \
		echo "ContainerLab UI already running."; \
		exit 0; \
	else \
		echo "ContainerLab UI not running."; \
		exit 1; \
	fi

check-cilium:
	@if kubectl -n kube-system get ds/cilium >/dev/null 2>&1; then \
		echo "Cilium is already installed."; \
		exit 0; \
	else \
		echo "Cilium is not installed."; \
		exit 1; \
	fi

all: deploy-kind deploy-clab deploy-clab-ui install-cilium deploy-policies test-connectivity

deploy-kind:
	@if ! make check-kind >/dev/null 2>&1; then \
		echo "Creating Kind cluster..."; \
		kind create cluster --config cluster.yaml; \
	else \
		echo "Kind cluster already exists, skipping creation."; \
	fi

deploy-clab:
	@if ! make check-clab >/dev/null 2>&1; then \
		echo "Deploying ContainerLab topology..."; \
		containerlab -t topo.yaml deploy; \
	else \
		echo "ContainerLab topology already running, skipping deployment."; \
	fi

deploy-clab-ui:
	@if ! make check-clab-ui >/dev/null 2>&1; then \
		echo "Deploying ContainerLab UI..."; \
		docker run -d \
			--name clab-ui \
			-p 50080:50080 \
			-v $$(pwd)/topo.yaml:/topo.yaml \
			-v /var/run/docker.sock:/var/run/docker.sock \
			ghcr.io/srl-labs/clab:0.59.0 \
			containerlab graph -t /topo.yaml; \
	else \
		echo "ContainerLab UI already running, skipping deployment."; \
	fi

check-connectivity:
	@echo "Checking BGP connectivity..."
	@if ! docker exec -it clab-bgp-topo-router0 vtysh -c 'show bgp ipv4 summary wide'; then \
		echo "Error: Could not connect to router0. Make sure ContainerLab is running."; \
		exit 1; \
	fi
	@if ! docker exec -it clab-bgp-topo-tor0 vtysh -c 'show bgp ipv4 summary wide'; then \
		echo "Error: Could not connect to tor0. Make sure ContainerLab is running."; \
		exit 1; \
	fi
	@if ! docker exec -it clab-bgp-topo-tor1 vtysh -c 'show bgp ipv4 summary wide'; then \
		echo "Error: Could not connect to tor1. Make sure ContainerLab is running."; \
		exit 1; \
	fi

install-cilium:
	@if ! make check-cilium >/dev/null 2>&1; then \
		echo "Installing Cilium..."; \
		cilium install \
			--version v1.17.4 \
			--set ipam.mode=kubernetes \
			--set routingMode=native \
			--set ipv4NativeRoutingCIDR="10.0.0.0/8" \
			--set bgpControlPlane.enabled=true \
			--set k8s.requireIPv4PodCIDR=true; \
		echo "Waiting for Cilium to be ready..."; \
		kubectl -n kube-system rollout status ds/cilium --timeout=300s; \
	else \
		echo "Cilium already installed, skipping installation."; \
	fi
	@echo "Verifying BGP configuration..."
	cilium config view | grep enable-bgp || true
	kubectl get nodes -l 'rack in (rack0,rack1)' || true

deploy-policies:
	@echo "Deploying BGP peering policies..."
	kubectl apply -f cilium-bgp-peering-policies.yaml
	@echo "Deploying netshoot daemonset..."
	kubectl apply -f netshoot-ds.yaml
	kubectl rollout status ds/netshoot -w

test-connectivity:
	@echo "Waiting for pods to be ready..."
	@kubectl wait --for=condition=ready pods --all --timeout=300s
	$(eval SRC_POD := $(shell kubectl get pods -o wide | grep "kind-worker " | awk '{ print($$1); }'))
	$(eval DST_IP := $(shell kubectl get pods -o wide | grep worker3 | awk '{ print($$6); }'))
	@if [ -z "$(SRC_POD)" ] || [ -z "$(DST_IP)" ]; then \
		echo "Error: Could not find source pod or destination IP"; \
		exit 1; \
	fi
	@echo "Testing connectivity from $(SRC_POD) to $(DST_IP)..."
	kubectl exec -it $(SRC_POD) -- ping -c 4 $(DST_IP)

clean:
	@echo "Cleaning up Kind cluster..."
	@if make check-kind >/dev/null 2>&1; then \
		kind delete cluster; \
	else \
		echo "No Kind cluster found to clean up."; \
	fi
	@echo "Stopping and removing clab-ui container..."
	@if make check-clab-ui >/dev/null 2>&1; then \
		docker stop clab-ui && docker rm clab-ui; \
	else \
		echo "No ContainerLab UI found to clean up."; \
	fi

destroy-all: clean
	@echo "Destroying ContainerLab topology..."
	@if make check-clab >/dev/null 2>&1; then \
		containerlab -t topo.yaml destroy; \
	else \
		echo "No ContainerLab topology found to destroy."; \
	fi

help:
	@echo "Available targets:"
	@echo "  all               - Deploy everything (kind, containerlab, cilium, policies)"
	@echo "  deploy-kind       - Create Kind cluster"
	@echo "  deploy-clab      - Deploy ContainerLab topology"
	@echo "  deploy-clab-ui   - Deploy ContainerLab UI"
	@echo "  check-connectivity - Check BGP connectivity"
	@echo "  install-cilium   - Install and configure Cilium"
	@echo "  deploy-policies  - Deploy BGP peering policies and netshoot"
	@echo "  test-connectivity - Test pod connectivity"
	@echo "  clean            - Delete Kind cluster and stop UI"
	@echo "  destroy-all      - Clean everything including ContainerLab topology"
	@echo "  help             - Show this help message"