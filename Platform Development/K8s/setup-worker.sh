#!/usr/bin/env bash
# =============================================================================
# Kubernetes Worker Node Setup Script
# =============================================================================
# Prepares a worker node and joins it to an existing kubeadm cluster.
# Designed for both amd64 (VMs) and arm64 (Raspberry Pi) architectures.
#
# Usage:
#   sudo ./setup-worker.sh --join-command "kubeadm join 192.168.1.x:6443 --token ... --discovery-token-ca-cert-hash ..."
#   sudo ./setup-worker.sh --control-plane-ip 192.168.1.x
#
# Options:
#   --join-command    Full kubeadm join command (from control plane)
#   --control-plane-ip  IP of control plane (will prompt to paste join command)
#   --k8s-version     Kubernetes minor version (default: 1.35)
#   --dry-run         Show what would be done without executing
#   --help            Show this help message
#
# Getting the join command (run on control plane node):
#   kubeadm token create --print-join-command
#
# What this script does:
#   1. Validates prerequisites (root, CPU, RAM)
#   2. Disables swap
#   3. Loads kernel modules for container networking
#   4. Configures sysctl for packet forwarding
#   5. Installs containerd with systemd cgroup driver
#   6. Installs kubelet and kubeadm (no kubectl — workers don't need it)
#   7. Joins the cluster using the provided join command
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration & Defaults
# =============================================================================
K8S_VERSION="1.35"
JOIN_COMMAND=""
CONTROL_PLANE_IP=""
DRY_RUN=false
LOG_FILE="/var/log/k8s-worker-setup.log"

# Worker nodes have lower requirements than control plane nodes
# because they don't run etcd, apiserver, scheduler, or controller-manager.
MIN_CPUS=1
MIN_RAM_MB=1024

# =============================================================================
# Colours & Logging
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
error()  { echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG_FILE"; }
info()   { echo -e "${BLUE}[i]${NC} $*" | tee -a "$LOG_FILE"; }
step()   { echo -e "\n${CYAN}━━━ $* ━━━${NC}" | tee -a "$LOG_FILE"; }

# =============================================================================
# Argument Parsing
# =============================================================================
parse_args() {
    require_value() {
        [[ $# -ge 2 && -n "${2:-}" && "${2:0:2}" != "--" ]] || {
            error "Option $1 requires a non-empty value"
            exit 1
        }
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --join-command)
                require_value "$@"
                JOIN_COMMAND="$2"; shift 2 ;;
            --control-plane-ip)
                require_value "$@"
                CONTROL_PLANE_IP="$2"; shift 2 ;;
            --k8s-version)
                require_value "$@"
                K8S_VERSION="$2"; shift 2 ;;
            --dry-run)          DRY_RUN=true; shift ;;
            --help)             head -28 "$0" | tail -23; exit 0 ;;
            *)                  error "Unknown option: $1"; exit 1 ;;
        esac
    done
}

# Dry run wrapper
run() {
    if $DRY_RUN; then
        echo "  [dry-run] $*" | tee -a "$LOG_FILE"
    else
        "$@" 2>&1 | tee -a "$LOG_FILE"
    fi
}

# =============================================================================
# Preflight Checks
# Worker requirements are lower than control plane — no etcd or apiserver
# to feed, so 1 CPU and 1GB RAM is sufficient (though 2 CPU / 2GB+ is better).
# =============================================================================
preflight_checks() {
    step "Step 0: Preflight Checks"

    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi

    local arch
    arch=$(dpkg --print-architecture)
    info "Architecture: ${arch}"
    info "Kubernetes version: v${K8S_VERSION}"
    info "Hostname: $(hostname)"

    # CPU check
    local cpus
    cpus=$(nproc)
    if [[ $cpus -lt $MIN_CPUS ]]; then
        error "Worker requires at least ${MIN_CPUS} CPU (found: ${cpus})"
        exit 1
    fi
    log "CPUs: ${cpus}"

    # RAM check
    local ram_mb
    ram_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
    if [[ $ram_mb -lt $MIN_RAM_MB ]]; then
        error "Worker requires at least ${MIN_RAM_MB}MB RAM (found: ${ram_mb}MB)"
        exit 1
    fi
    log "RAM: ${ram_mb}MB"

    # Check this node isn't already part of a cluster
    if [[ -f /etc/kubernetes/kubelet.conf ]]; then
        warn "This node appears to already be part of a cluster"
        warn "Run 'sudo kubeadm reset' first to leave the existing cluster"
        read -rp "Continue anyway? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
    fi

    # Validate we have a way to join the cluster
    if [[ -z "$JOIN_COMMAND" && -z "$CONTROL_PLANE_IP" ]]; then
        warn "No join command or control plane IP provided"
        warn "You can provide it later, or run setup with:"
        warn "  --join-command 'kubeadm join ...'"
        warn "  --control-plane-ip 192.168.1.x"
        echo ""
        read -rp "Continue without join command? Setup will stop before joining. (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
    fi

    log "Preflight checks passed"
}

# =============================================================================
# Disable Swap
# Same rationale as control plane — kubelet refuses to start with swap on.
# The scheduler's memory accounting breaks if the OS silently pages to disk.
# =============================================================================
disable_swap() {
    step "Step 1: Disabling Swap"

    if swapon --show | grep -q .; then
        run swapoff -a
        log "Swap disabled"
    else
        log "Swap already disabled"
    fi

    if grep -q '^\s*[^#].*\sswap\s' /etc/fstab; then
        run sed -i '/ swap / s/^/#/' /etc/fstab
        log "Swap entries commented out in /etc/fstab"
    else
        log "No active swap entries in /etc/fstab"
    fi
}

# =============================================================================
# Load Kernel Modules
# Same modules as control plane — overlay for container filesystems,
# br_netfilter so iptables can process bridged pod traffic.
# =============================================================================
load_kernel_modules() {
    step "Step 2: Loading Kernel Modules"

    cat <<EOF | run tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

    run modprobe overlay
    run modprobe br_netfilter
    log "Kernel modules loaded"
}

# =============================================================================
# Configure Sysctl
# =============================================================================
configure_sysctl() {
    step "Step 3: Configuring Sysctl Parameters"

    cat <<EOF | run tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    run sysctl --system > /dev/null
    log "Sysctl parameters configured"
}

# =============================================================================
# Install containerd
# Same configuration as control plane — SystemdCgroup must match the
# kubelet's cgroup driver. Mismatched drivers cause resource accounting
# failures and random pod kills.
# =============================================================================
install_containerd() {
    step "Step 4: Installing containerd"

    run apt-get update -qq
    run apt-get install -y -qq containerd

    run mkdir -p /etc/containerd
    if $DRY_RUN; then
        echo "  [dry-run] containerd config default > /etc/containerd/config.toml" | tee -a "$LOG_FILE"
        echo "  [dry-run] sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml" | tee -a "$LOG_FILE"
    else
        containerd config default 2>>"$LOG_FILE" > /etc/containerd/config.toml
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
        if ! grep -q '^\s*SystemdCgroup\s*=\s*true' /etc/containerd/config.toml; then
            error "Failed to set SystemdCgroup = true in /etc/containerd/config.toml"
            exit 1
        fi
    fi

    run systemctl restart containerd
    run systemctl enable containerd
    log "containerd installed with SystemdCgroup"
}

# =============================================================================
# Install Kubernetes Components
# Workers only need kubelet and kubeadm — NOT kubectl.
#   - kubelet: The agent that receives pod specs from the apiserver and
#              tells containerd to start/stop containers. Runs as a systemd service.
#   - kubeadm: Used once to join the cluster (and later for node upgrades).
#   - kubectl: NOT installed. It's a client tool — run it from the control
#              plane or your local machine. Fewer binaries = smaller attack surface.
# =============================================================================
install_kubernetes() {
    step "Step 5: Installing kubelet and kubeadm"

    run apt-get install -y -qq apt-transport-https ca-certificates curl gpg
    run mkdir -p -m 755 /etc/apt/keyrings

    # Each K8s minor version has its own signing key
    local key_url="https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key"
    if $DRY_RUN; then
        echo "  [dry-run] curl -fsSL ${key_url} | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg" | tee -a "$LOG_FILE"
        echo "  [dry-run] write /etc/apt/sources.list.d/kubernetes.list" | tee -a "$LOG_FILE"
    else
        curl -fsSL "$key_url" \
            | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>>"$LOG_FILE"
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
            > /etc/apt/sources.list.d/kubernetes.list
    fi

    run apt-get update -qq
    # Note: no kubectl here — workers don't need it
    run apt-get install -y -qq kubelet kubeadm
    run apt-mark hold kubelet kubeadm
    log "kubelet and kubeadm v${K8S_VERSION} installed and pinned"
}

# =============================================================================
# Join the Cluster
# The join command contains:
#   - Token: Short-lived credential (24h) proving this node is authorised
#   - CA cert hash: SHA256 fingerprint of the cluster CA, used to verify
#                   the apiserver's identity (prevents MITM attacks)
#
# After joining, the kubelet receives a client certificate signed by the
# cluster CA and begins accepting pod scheduling decisions from the apiserver.
# =============================================================================
join_cluster() {
    step "Step 6: Joining Cluster"

    # If no join command was provided, prompt for it
    if [[ -z "$JOIN_COMMAND" ]]; then
        if [[ -n "$CONTROL_PLANE_IP" ]]; then
            info "Connectivity check to control plane at ${CONTROL_PLANE_IP}:6443"
            if timeout 5 bash -c "echo > /dev/tcp/${CONTROL_PLANE_IP}/6443" 2>/dev/null; then
                log "Control plane is reachable"
            else
                warn "Cannot reach ${CONTROL_PLANE_IP}:6443 — check networking/firewall"
            fi
        fi

        echo ""
        echo -e "${YELLOW}Paste the join command from your control plane node.${NC}"
        echo -e "${YELLOW}Get it by running on the control plane:${NC}"
        echo "  kubeadm token create --print-join-command"
        echo ""
        read -rp "Join command: " JOIN_COMMAND
    fi

    if [[ -z "$JOIN_COMMAND" ]]; then
        warn "No join command provided — skipping cluster join"
        warn "Run manually later: sudo kubeadm join ..."
        return
    fi

    # Validate it looks like a real join command
    if [[ ! "$JOIN_COMMAND" =~ ^kubeadm\ join ]]; then
        # Prepend 'kubeadm join' if the user just pasted the args
        if [[ "$JOIN_COMMAND" =~ --token ]]; then
            JOIN_COMMAND="kubeadm join $JOIN_COMMAND"
        else
            error "Invalid join command format. Expected: kubeadm join <ip>:6443 --token ... --discovery-token-ca-cert-hash ..."
            exit 1
        fi
    fi

    info "Joining cluster..."
    # Split the join command into args to avoid relying on implicit word-splitting
    local join_args
    read -ra join_args <<< "$JOIN_COMMAND"
    if $DRY_RUN; then
        echo "  [dry-run] ${join_args[*]}" | tee -a "$LOG_FILE"
        log "Dry-run: join command validated (cluster not actually joined)"
    else
        if run "${join_args[@]}"; then
            log "Successfully joined the cluster"
        else
            error "Failed to join the cluster — check $LOG_FILE for details"
            exit 1
        fi
    fi
}

# =============================================================================
# Summary
# =============================================================================
print_summary() {
    step "Setup Complete"

    echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Kubernetes Worker Node Ready                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    info "Hostname           : $(hostname)"
    info "Architecture       : $(dpkg --print-architecture)"
    info "Kubernetes version : v${K8S_VERSION}"
    info "Setup log          : ${LOG_FILE}"
    echo ""
    echo -e "${YELLOW}Verify from the control plane:${NC}"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -n kube-system"
    echo ""
    echo -e "${YELLOW}If this node shows NotReady, check kubelet logs:${NC}"
    echo "  sudo journalctl -u kubelet -f"
    echo ""
}

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"

    {
        echo ""
        echo "=============================================================================="
        echo "New worker setup session — $(date)"
        echo "=============================================================================="
    } >> "$LOG_FILE"
    info "Starting Kubernetes worker setup — $(date)"

    preflight_checks
    disable_swap
    load_kernel_modules
    configure_sysctl
    install_containerd
    install_kubernetes
    join_cluster
    print_summary
}

main "$@"
