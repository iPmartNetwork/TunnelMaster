#!/bin/bash

# ============================================================
#  TunnelMaster v2.0 — Tunnel Manager
#  Anti-DPI + High Performance Tunneling
#  Backends: Gost, Chisel, frp
#  Target OS: Ubuntu 20.04 / 22.04 / 24.04, Debian 11/12
# ============================================================

# ─── Colors ───────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# ─── Helpers ──────────────────────────────────────────────────

log()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✗]${NC} $1"; }
info()   { echo -e "${CYAN}[i]${NC} $1"; }
header() { echo -e "\n${BLUE}${BOLD}═══════════════════════════════════════${NC}"; echo -e "${BLUE}${BOLD}  $1${NC}"; echo -e "${BLUE}${BOLD}═══════════════════════════════════════${NC}\n"; }

press_enter() {
    echo ""
    read -rp "Press Enter to return to menu..."
}

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octets <<< "$ip"
        for oct in "${octets[@]}"; do
            (( oct > 255 )) && return 1
        done
        return 0
    fi
    # Allow IPv6
    if [[ "$ip" =~ : ]]; then
        return 0
    fi
    return 1
}

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

ask_ip() {
    local prompt="$1" var
    while true; do
        read -rp "$prompt" var
        if validate_ip "$var"; then
            echo "$var"
            return
        fi
        error "Invalid IP address. Try again."
    done
}

ask_port() {
    local prompt="$1" default="$2" var
    while true; do
        read -rp "$prompt [${default}]: " var
        var="${var:-$default}"
        if validate_port "$var"; then
            echo "$var"
            return
        fi
        error "Invalid port (1-65535). Try again."
    done
}

# ─── Server Role / Settings ───────────────────────────────────

load_settings() {
    [[ -f "$TM_CONFIG" ]] && source "$TM_CONFIG"
}

save_settings() {
    mkdir -p "$CONFIG_DIR"
    cat > "$TM_CONFIG" <<EOF
# TunnelMaster settings
SERVER_ROLE="${SERVER_ROLE}"
EOF
    chmod 600 "$TM_CONFIG"
}

choose_server_role() {
    echo ""
    echo -e "${CYAN}${BOLD}Where is this server located?${NC}"
    echo "  1) Iran   (inside — users connect to this server)"
    echo "  2) Kharej (outside — services/panel live here)"
    echo ""
    local choice
    while true; do
        read -rp "Select [1/2]: " choice
        case "$choice" in
            1) SERVER_ROLE="iran";   break ;;
            2) SERVER_ROLE="kharej"; break ;;
            *) error "Invalid choice." ;;
        esac
    done
    save_settings
    log "Server role set to: ${SERVER_ROLE}"
}

# Prompt for role only if not already configured
ensure_server_role() {
    [[ -z "$SERVER_ROLE" ]] && choose_server_role
}

# role_for <direct|reverse> — map SERVER_ROLE to the legacy 1/2 role number
#   direct:  Kharej = server (1), Iran   = client (2)
#   reverse: Iran   = server (1), Kharej = client (2)
role_for() {
    if [[ "$1" == "direct" ]]; then
        [[ "$SERVER_ROLE" == "kharej" ]] && echo 1 || echo 2
    else
        [[ "$SERVER_ROLE" == "iran" ]] && echo 1 || echo 2
    fi
}

# Show which side this wizard will configure, based on the saved role
announce_role() {
    local side="$1"  # "server" or "client"
    info "This server is: ${BOLD}${SERVER_ROLE}${NC} → configuring the ${BOLD}${side}${NC} side."
}

# ─── Variables ────────────────────────────────────────────────

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/tunnelmaster"
PROFILE_DIR="/etc/tunnelmaster/profiles"
SERVICE_DIR="/etc/systemd/system"
TM_CONFIG="/etc/tunnelmaster/tunnelmaster.conf"

# Server role: "iran" or "kharej" (loaded from TM_CONFIG)
SERVER_ROLE=""

CHISEL_VERSION="1.11.5"
GOST_VERSION="2.12.0"
FRP_VERSION="0.69.1"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    armv7l)  ARCH_SUFFIX="armv7" ;;
    *)       error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ─── Pre-checks ──────────────────────────────────────────────

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)."
        exit 1
    fi
}

check_os() {
    if ! grep -qi 'ubuntu\|debian' /etc/os-release 2>/dev/null; then
        warn "This script is designed for Ubuntu/Debian. Other distros may have issues."
    fi
}

install_dependencies() {
    info "Installing dependencies..."
    apt-get update -qq > /dev/null 2>&1
    apt-get install -y -qq wget curl unzip jq openssl > /dev/null 2>&1
    log "Dependencies installed."
}

# ─── Binary Installers ───────────────────────────────────────

install_chisel() {
    if [[ -f "$INSTALL_DIR/chisel" ]]; then
        log "Chisel v${CHISEL_VERSION} already installed."
        return 0
    fi
    info "Downloading Chisel v${CHISEL_VERSION}..."
    local url="https://github.com/jpillora/chisel/releases/download/v${CHISEL_VERSION}/chisel_${CHISEL_VERSION}_linux_${ARCH_SUFFIX}.gz"
    if ! wget -qO /tmp/chisel.gz "$url"; then
        error "Failed to download Chisel."; return 1
    fi
    gunzip -f /tmp/chisel.gz
    mv /tmp/chisel "$INSTALL_DIR/chisel"
    chmod +x "$INSTALL_DIR/chisel"
    log "Chisel installed."
}

install_gost() {
    if [[ -f "$INSTALL_DIR/gost" ]]; then
        log "Gost v${GOST_VERSION} already installed."
        return 0
    fi
    info "Downloading Gost v${GOST_VERSION}..."
    local url="https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost_${GOST_VERSION}_linux_${ARCH_SUFFIX}.tar.gz"
    if ! wget -qO /tmp/gost.tar.gz "$url"; then
        error "Failed to download Gost."; return 1
    fi
    tar -xzf /tmp/gost.tar.gz -C /tmp/
    mv /tmp/gost "$INSTALL_DIR/gost"
    chmod +x "$INSTALL_DIR/gost"
    rm -f /tmp/gost.tar.gz
    log "Gost installed."
}

install_frp() {
    if [[ -f "$INSTALL_DIR/frps" ]] && [[ -f "$INSTALL_DIR/frpc" ]]; then
        log "frp v${FRP_VERSION} already installed."
        return 0
    fi
    info "Downloading frp v${FRP_VERSION}..."
    local url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH_SUFFIX}.tar.gz"
    if ! wget -qO /tmp/frp.tar.gz "$url"; then
        error "Failed to download frp."; return 1
    fi
    tar -xzf /tmp/frp.tar.gz -C /tmp/
    mv "/tmp/frp_${FRP_VERSION}_linux_${ARCH_SUFFIX}/frps" "$INSTALL_DIR/frps"
    mv "/tmp/frp_${FRP_VERSION}_linux_${ARCH_SUFFIX}/frpc" "$INSTALL_DIR/frpc"
    chmod +x "$INSTALL_DIR/frps" "$INSTALL_DIR/frpc"
    rm -rf "/tmp/frp_${FRP_VERSION}_linux_${ARCH_SUFFIX}" /tmp/frp.tar.gz
    log "frp installed."
}

install_all_binaries() {
    header "Installing Tunnel Binaries"
    mkdir -p "$CONFIG_DIR"
    install_chisel
    install_gost
    install_frp
    echo ""
    log "All binaries ready."
}

# ─── Profile Management ──────────────────────────────────────

# save_profile <name> <method> <desc> <cmd> [EXTRA_KEY="val" ...]
# Stores a tunnel as a readable .conf file — the source of truth for
# listing, editing, backup and restore. The systemd service is built
# from this profile.
save_profile() {
    local name="$1" method="$2" desc="$3" cmd="$4"
    shift 4
    mkdir -p "$PROFILE_DIR"
    local profile="${PROFILE_DIR}/${name}.conf"
    {
        echo "NAME=\"${name}\""
        echo "METHOD=\"${method}\""
        echo "DESC=\"${desc}\""
        echo "SERVICE=\"tm-${name}\""
        echo "CREATED=\"$(date '+%Y-%m-%d %H:%M:%S')\""
        echo "CMD=\"${cmd}\""
        local kv
        for kv in "$@"; do
            echo "$kv"
        done
    } > "$profile"
    chmod 600 "$profile"
    log "Profile saved: ${profile}"
}

# register_tunnel <name> <method> <desc> <cmd> [EXTRA_KEY="val" ...]
# Convenience wrapper: save the profile, then create & start the service.
register_tunnel() {
    local name="$1" method="$2" desc="$3" cmd="$4"
    shift 4
    save_profile "$name" "$method" "$desc" "$cmd" "$@"
    create_service "$name" "$cmd" "$desc"
}

delete_profile() {
    local name="$1"
    rm -f "${PROFILE_DIR}/${name}.conf"
}

# ─── Service Management ──────────────────────────────────────

create_service() {
    local name="$1"
    local exec_cmd="$2"
    local desc="$3"

    cat > "${SERVICE_DIR}/tm-${name}.service" <<EOF
[Unit]
Description=TunnelMaster - ${desc}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${exec_cmd}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "tm-${name}.service" > /dev/null 2>&1
    systemctl restart "tm-${name}.service"
    log "Service [tm-${name}] created and started."
}

stop_and_remove_service() {
    local name="$1"
    if [[ -f "${SERVICE_DIR}/tm-${name}.service" ]]; then
        systemctl stop "tm-${name}.service" 2>/dev/null
        systemctl disable "tm-${name}.service" 2>/dev/null
        rm -f "${SERVICE_DIR}/tm-${name}.service"
        # Remove wrapper script if exists
        rm -f "${CONFIG_DIR}/run-${name}.sh"
        delete_profile "$name"
        systemctl daemon-reload
        log "Service [tm-${name}] stopped and removed."
    else
        error "Service [tm-${name}] not found."
    fi
}

list_services() {
    local services
    services=$(systemctl list-units --type=service --all --no-legend 2>/dev/null | grep "tm-" | awk '{print $1, $3, $4}')
    if [[ -z "$services" ]]; then
        warn "No TunnelMaster services found."
        return 1
    fi
    echo ""
    echo -e "${BOLD}  #   Service Name                          Status${NC}"
    echo "  ─── ─────────────────────────────────── ──────"
    local i=1
    while IFS= read -r line; do
        local svc_name=$(echo "$line" | awk '{print $1}')
        local svc_status=$(echo "$line" | awk '{print $2}')
        if [[ "$svc_status" == "active" ]]; then
            printf "  %-3s ${GREEN}●${NC} %-38s ${GREEN}%s${NC}\n" "$i" "$svc_name" "$svc_status"
        else
            printf "  %-3s ${RED}●${NC} %-38s ${RED}%s${NC}\n" "$i" "$svc_name" "$svc_status"
        fi
        ((i++))
    done <<< "$services"
    echo ""
    return 0
}

# ─── Performance & Optimization ──────────────────────────────

optimize_system() {
    header "System Optimization (BBR + Kernel Tuning)"

    # BBR
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        log "BBR already enabled."
    else
        info "Enabling BBR..."
        modprobe tcp_bbr 2>/dev/null || true
        echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf 2>/dev/null || true
        log "BBR enabled."
    fi

    # Kernel params
    info "Applying kernel optimizations..."
    cat > /etc/sysctl.d/99-tunnelmaster.conf <<EOF
# ═══ TunnelMaster Optimizations ═══

# BBR Congestion Control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP Buffer Sizes (64MB max)
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# TCP Fast Open (client + server)
net.ipv4.tcp_fastopen = 3

# Connection Reuse
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# Backlog & Connections
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 65535

# Disable slow start after idle
net.ipv4.tcp_slow_start_after_idle = 0

# IP Forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Conntrack
net.netfilter.nf_conntrack_max = 1048576

# File descriptors
fs.file-max = 1048576
EOF

    sysctl --system > /dev/null 2>&1

    # File descriptor limits
    cat > /etc/security/limits.d/99-tunnelmaster.conf <<EOF
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF

    log "Kernel optimized for high-throughput tunneling."
    info "Changes applied. Some require reboot to fully take effect."
    press_enter
}

# ─── Direct Tunnel: Gost Simple ──────────────────────────────

setup_direct_simple() {
    header "Direct Tunnel — Gost Simple (TCP/UDP)"
    info "Simple port forwarding. No encryption. Fast but detectable."
    info "This tunnel runs on the ${BOLD}Iran${NC} side only (forwards Iran → Kharej)."
    echo ""

    if [[ "$SERVER_ROLE" == "kharej" ]]; then
        warn "This server is set as Kharej, but Gost Simple is configured on Iran."
        read -rp "Continue anyway? [y/N]: " c
        [[ "${c,,}" != "y" ]] && { press_enter; return; }
    fi

    local local_port=$(ask_port "Iran listen port: " "443")
    local remote_ip=$(ask_ip "Kharej server IP: ")
    local remote_port=$(ask_port "Kharej destination port: " "443")

    echo ""
    read -rp "Protocol (tcp/udp) [tcp]: " proto
    proto="${proto:-tcp}"

    local cmd="$INSTALL_DIR/gost -L=${proto}://:${local_port}/${remote_ip}:${remote_port}"

    echo ""
    info "Command: $cmd"
    echo ""
    read -rp "Apply and start? [y/N]: " confirm
    [[ "${confirm,,}" != "y" ]] && { warn "Cancelled."; press_enter; return; }

    register_tunnel "direct-simple-${local_port}" "direct-simple" "Gost Direct :${local_port}->${remote_ip}:${remote_port}" "$cmd" \
        "LOCAL_PORT=\"${local_port}\"" \
        "REMOTE_IP=\"${remote_ip}\"" \
        "REMOTE_PORT=\"${remote_port}\"" \
        "PROTOCOL=\"${proto}\""
    press_enter
}

# ─── Direct Tunnel: Gost WSS (Anti-DPI) ─────────────────────

setup_direct_wss() {
    header "Direct Tunnel — Gost WSS + MUX (Anti-DPI)"
    info "Multiplexed WebSocket over TLS. Looks like HTTPS traffic."
    info "Optional SNI camouflage makes it even harder to detect."
    echo ""

    local role; role=$(role_for direct)
    announce_role "$([[ "$role" == 1 ]] && echo server || echo client)"

    if [[ "$role" == "1" ]]; then
        echo ""
        local tunnel_port=$(ask_port "Tunnel port (WSS listen): " "6060")
        local dest_port=$(ask_port "Destination port (Xray inbound): " "8080")

        local cmd="$INSTALL_DIR/gost -L=mwss://:${tunnel_port}/:${dest_port}"
        echo ""
        info "Command: $cmd"
        info "WSS listens on :${tunnel_port} → forwards to 127.0.0.1:${dest_port}"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "direct-wss-server-${tunnel_port}" "direct-wss" "Gost WSS Server :${tunnel_port}->:${dest_port}" "$cmd" \
            "ROLE=\"server\"" \
            "TUNNEL_PORT=\"${tunnel_port}\"" \
            "DEST_PORT=\"${dest_port}\""

    elif [[ "$role" == "2" ]]; then
        echo ""
        local local_port=$(ask_port "Iran listen port (users connect here): " "8080")
        local remote_ip=$(ask_ip "Kharej IP: ")
        local tunnel_port=$(ask_port "Kharej tunnel port (WSS): " "6060")
        read -rp "SNI domain for camouflage (e.g. dl.google.com) [empty=none]: " sni

        local gost_args="-L=tcp://:${local_port}"
        if [[ -n "$sni" ]]; then
            gost_args+=" -F=mwss://${remote_ip}:${tunnel_port}?host=${sni}"
        else
            gost_args+=" -F=mwss://${remote_ip}:${tunnel_port}"
        fi

        # Use wrapper script to avoid systemd quoting issues
        local wrapper="${CONFIG_DIR}/run-direct-wss-client-${local_port}.sh"
        cat > "$wrapper" <<SCRIPT
#!/bin/bash
exec $INSTALL_DIR/gost ${gost_args}
SCRIPT
        chmod +x "$wrapper"

        echo ""
        info "Command: gost ${gost_args}"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "direct-wss-client-${local_port}" "direct-wss" "Gost WSS Client :${local_port}->${remote_ip}:${tunnel_port}" "$wrapper" \
            "ROLE=\"client\"" \
            "LOCAL_PORT=\"${local_port}\"" \
            "REMOTE_IP=\"${remote_ip}\"" \
            "TUNNEL_PORT=\"${tunnel_port}\"" \
            "SNI=\"${sni}\"" \
            "GOST_ARGS=\"${gost_args}\"" \
            "WRAPPER=\"${wrapper}\""
    else
        warn "Invalid choice."
    fi
    press_enter
}

# ─── Direct Tunnel: Chisel ───────────────────────────────────

setup_direct_chisel() {
    header "Direct Tunnel — Chisel (HTTP + SSH Encryption)"
    info "TCP/UDP over HTTP with SSH encryption. Auto-reconnect."
    echo ""

    local role; role=$(role_for direct)
    announce_role "$([[ "$role" == 1 ]] && echo server || echo client)"

    if [[ "$role" == "1" ]]; then
        echo ""
        local server_port=$(ask_port "Chisel listen port: " "8080")
        local cmd="$INSTALL_DIR/chisel server --port ${server_port}"

        echo ""
        info "Command: $cmd"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "direct-chisel-server-${server_port}" "direct-chisel" "Chisel Server :${server_port}" "$cmd" \
            "ROLE=\"server\"" \
            "SERVER_PORT=\"${server_port}\""

    elif [[ "$role" == "2" ]]; then
        echo ""
        local remote_ip=$(ask_ip "Kharej IP: ")
        local remote_port=$(ask_port "Kharej Chisel port: " "8080")
        local local_port=$(ask_port "Iran listen port (users connect here): " "443")
        local dest_port=$(ask_port "Destination port on Kharej: " "$local_port")

        local cmd="$INSTALL_DIR/chisel client ${remote_ip}:${remote_port} ${local_port}:127.0.0.1:${dest_port}"

        echo ""
        info "Command: $cmd"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "direct-chisel-client-${local_port}" "direct-chisel" "Chisel Client :${local_port}->${remote_ip}:${dest_port}" "$cmd" \
            "ROLE=\"client\"" \
            "REMOTE_IP=\"${remote_ip}\"" \
            "REMOTE_PORT=\"${remote_port}\"" \
            "LOCAL_PORT=\"${local_port}\"" \
            "DEST_PORT=\"${dest_port}\""
    else
        warn "Invalid choice."
    fi
    press_enter
}

# ─── Direct Tunnel: Gost QUIC ────────────────────────────────

setup_direct_quic() {
    header "Direct Tunnel — Gost QUIC (UDP Transport)"
    info "QUIC protocol. Fast on lossy networks. May be blocked by some ISPs."
    echo ""

    local role; role=$(role_for direct)
    announce_role "$([[ "$role" == 1 ]] && echo server || echo client)"

    if [[ "$role" == "1" ]]; then
        echo ""
        local listen_port=$(ask_port "QUIC listen port on Kharej: " "443")
        local cmd="$INSTALL_DIR/gost -L=quic://:${listen_port}"

        echo ""
        info "Command: $cmd"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "direct-quic-server-${listen_port}" "direct-quic" "Gost QUIC Server :${listen_port}" "$cmd" \
            "ROLE=\"server\"" \
            "LISTEN_PORT=\"${listen_port}\""

    elif [[ "$role" == "2" ]]; then
        echo ""
        local local_port=$(ask_port "Iran listen port: " "443")
        local remote_ip=$(ask_ip "Kharej IP: ")
        local remote_port=$(ask_port "Kharej QUIC port: " "443")

        local cmd="$INSTALL_DIR/gost -L=tcp://:${local_port} -F=quic://${remote_ip}:${remote_port}"

        echo ""
        info "Command: $cmd"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "direct-quic-client-${local_port}" "direct-quic" "Gost QUIC Client :${local_port}->${remote_ip}:${remote_port}" "$cmd" \
            "ROLE=\"client\"" \
            "LOCAL_PORT=\"${local_port}\"" \
            "REMOTE_IP=\"${remote_ip}\"" \
            "REMOTE_PORT=\"${remote_port}\""
    else
        warn "Invalid choice."
    fi
    press_enter
}

# ─── Reverse Tunnel: Chisel ──────────────────────────────────

setup_reverse_chisel() {
    header "Reverse Tunnel — Chisel (WebSocket + SSH)"
    info "Kharej connects TO Iran. Good for dirty Iran IPs."
    echo ""

    local role; role=$(role_for reverse)
    announce_role "$([[ "$role" == 1 ]] && echo server || echo client)"

    if [[ "$role" == "1" ]]; then
        echo ""
        local server_port=$(ask_port "Iran listen port: " "443")
        local cmd="$INSTALL_DIR/chisel server --port ${server_port} --reverse"

        echo ""
        info "Command: $cmd"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "reverse-chisel-server-${server_port}" "reverse-chisel" "Chisel Reverse Server :${server_port}" "$cmd" \
            "ROLE=\"server\"" \
            "SERVER_PORT=\"${server_port}\""

    elif [[ "$role" == "2" ]]; then
        echo ""
        local iran_ip=$(ask_ip "Iran server IP: ")
        local iran_port=$(ask_port "Iran Chisel port: " "443")
        local expose_port=$(ask_port "Port to expose on Iran (users connect here): " "443")
        local local_port=$(ask_port "Local port on this Kharej server: " "2083")

        local cmd="$INSTALL_DIR/chisel client ${iran_ip}:${iran_port} R:${expose_port}:127.0.0.1:${local_port}"

        echo ""
        info "Command: $cmd"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "reverse-chisel-client-${expose_port}" "reverse-chisel" "Chisel Reverse R:${expose_port}->:${local_port}" "$cmd" \
            "ROLE=\"client\"" \
            "IRAN_IP=\"${iran_ip}\"" \
            "IRAN_PORT=\"${iran_port}\"" \
            "EXPOSE_PORT=\"${expose_port}\"" \
            "LOCAL_PORT=\"${local_port}\""
    else
        warn "Invalid choice."
    fi
    press_enter
}

# ─── Reverse Tunnel: Chisel + TLS + SNI ─────────────────────

setup_reverse_chisel_tls() {
    header "Reverse Tunnel — Chisel + TLS + SNI (Maximum Stealth)"
    info "TLS encrypted reverse tunnel. Looks like HTTPS to DPI."
    info "Optional SNI camouflage for extra stealth."
    echo ""

    local role; role=$(role_for reverse)
    announce_role "$([[ "$role" == 1 ]] && echo server || echo client)"

    if [[ "$role" == "1" ]]; then
        echo ""
        local server_port=$(ask_port "Iran listen port: " "443")

        # Generate TLS cert if needed
        if [[ ! -f "${CONFIG_DIR}/server.crt" ]]; then
            info "Generating TLS certificate..."
            mkdir -p "$CONFIG_DIR"
            openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
                -keyout "${CONFIG_DIR}/server.key" \
                -out "${CONFIG_DIR}/server.crt" \
                -subj "/CN=www.microsoft.com/O=Microsoft/C=US" > /dev/null 2>&1
            log "TLS certificate generated (CN=www.microsoft.com)."
        else
            log "TLS certificate already exists."
        fi

        local cmd="$INSTALL_DIR/chisel server --port ${server_port} --reverse --tls-key ${CONFIG_DIR}/server.key --tls-cert ${CONFIG_DIR}/server.crt"

        echo ""
        info "Command: $cmd"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "reverse-chisel-tls-server-${server_port}" "reverse-chisel-tls" "Chisel TLS Reverse Server :${server_port}" "$cmd" \
            "ROLE=\"server\"" \
            "SERVER_PORT=\"${server_port}\"" \
            "TLS_CERT=\"${CONFIG_DIR}/server.crt\"" \
            "TLS_KEY=\"${CONFIG_DIR}/server.key\""

    elif [[ "$role" == "2" ]]; then
        echo ""
        local iran_ip=$(ask_ip "Iran server IP: ")
        local iran_port=$(ask_port "Iran Chisel port: " "443")
        local expose_port=$(ask_port "Port to expose on Iran: " "443")
        local local_port=$(ask_port "Local port on Kharej: " "2083")
        read -rp "SNI hostname camouflage (e.g. www.google.com) [empty=none]: " hostname

        local cmd="$INSTALL_DIR/chisel client --tls-skip-verify"
        [[ -n "$hostname" ]] && cmd+=" --hostname ${hostname}"
        cmd+=" https://${iran_ip}:${iran_port} R:${expose_port}:127.0.0.1:${local_port}"

        echo ""
        info "Command: $cmd"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "reverse-chisel-tls-client-${expose_port}" "reverse-chisel-tls" "Chisel TLS Reverse R:${expose_port}->:${local_port}" "$cmd" \
            "ROLE=\"client\"" \
            "IRAN_IP=\"${iran_ip}\"" \
            "IRAN_PORT=\"${iran_port}\"" \
            "EXPOSE_PORT=\"${expose_port}\"" \
            "LOCAL_PORT=\"${local_port}\"" \
            "SNI=\"${hostname}\""
    else
        warn "Invalid choice."
    fi
    press_enter
}

# ─── Reverse Tunnel: frp ─────────────────────────────────────

setup_reverse_frp() {
    header "Reverse Tunnel — frp (Multi-Server Hub)"
    info "One Iran hub can accept many Kharej servers, each on different ports."
    echo ""

    local role; role=$(role_for reverse)
    announce_role "$([[ "$role" == 1 ]] && echo server || echo client)"

    if [[ "$role" == "1" ]]; then
        # ── Iran: central hub (frps) — accepts all Kharej servers ──
        echo ""
        info "This is the central hub on Iran. Every Kharej server connects here."
        local bind_port=$(ask_port "frps bind port (Kharej servers connect here): " "7000")
        read -rp "Authentication token (shared by all Kharej servers): " token
        [[ -z "$token" ]] && { error "Token cannot be empty."; press_enter; return; }

        local dash_port="" dash_user="" dash_pass="" dash
        read -rp "Enable web dashboard to monitor all Kharej servers? [y/N]: " dash
        if [[ "${dash,,}" == "y" ]]; then
            dash_port=$(ask_port "Dashboard port: " "7500")
            read -rp "Dashboard username [admin]: " dash_user; dash_user="${dash_user:-admin}"
            read -rp "Dashboard password: " dash_pass
            [[ -z "$dash_pass" ]] && { warn "Empty password — dashboard disabled."; dash_port=""; }
        fi

        mkdir -p "$CONFIG_DIR"
        {
            echo "bindPort = ${bind_port}"
            echo "auth.method = \"token\""
            echo "auth.token = \"${token}\""
            if [[ -n "$dash_port" ]]; then
                echo ""
                echo "webServer.addr = \"0.0.0.0\""
                echo "webServer.port = ${dash_port}"
                echo "webServer.user = \"${dash_user}\""
                echo "webServer.password = \"${dash_pass}\""
            fi
        } > "${CONFIG_DIR}/frps.toml"

        local cmd="$INSTALL_DIR/frps -c ${CONFIG_DIR}/frps.toml"

        echo ""
        info "Config: ${CONFIG_DIR}/frps.toml"
        [[ -n "$dash_port" ]] && info "Dashboard: http://<IRAN_IP>:${dash_port}  (user: ${dash_user})"
        info "Give each Kharej server → Iran IP, hub port ${bind_port}, and the token above."
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "reverse-frps-${bind_port}" "reverse-frp" "frp Hub :${bind_port}" "$cmd" \
            "ROLE=\"server\"" \
            "BIND_PORT=\"${bind_port}\"" \
            "TOKEN=\"${token}\"" \
            "DASHBOARD_PORT=\"${dash_port}\"" \
            "FRP_CONFIG=\"${CONFIG_DIR}/frps.toml\""

    elif [[ "$role" == "2" ]]; then
        # ── Kharej: join the hub (frpc) — one or more port mappings ──
        echo ""
        local iran_ip=$(ask_ip "Iran hub IP: ")
        local iran_port=$(ask_port "frps port on Iran: " "7000")
        read -rp "Authentication token (same as Iran hub): " token
        [[ -z "$token" ]] && { error "Token cannot be empty."; press_enter; return; }

        local label
        while true; do
            read -rp "Label for THIS Kharej server (e.g. de1, finland): " label
            label=$(echo "$label" | tr -cd '[:alnum:]_-')
            [[ -n "$label" ]] && break
            error "Label must contain letters/digits/_/- only."
        done

        local cfg="${CONFIG_DIR}/frpc-${label}.toml"
        mkdir -p "$CONFIG_DIR"
        {
            echo "serverAddr = \"${iran_ip}\""
            echo "serverPort = ${iran_port}"
            echo "auth.method = \"token\""
            echo "auth.token = \"${token}\""
        } > "$cfg"

        local mappings="" count=0
        while true; do
            echo ""
            info "Port mapping #$((count+1)) for [${label}]"
            local remote_port=$(ask_port "  Port to expose on Iran (users connect here): " "443")
            local local_port=$(ask_port "  Local port on this Kharej: " "2083")
            local proto
            read -rp "  Protocol (tcp/udp) [tcp]: " proto; proto="${proto:-tcp}"
            {
                echo ""
                echo "[[proxies]]"
                echo "name = \"${label}-${remote_port}\""
                echo "type = \"${proto}\""
                echo "localIP = \"127.0.0.1\""
                echo "localPort = ${local_port}"
                echo "remotePort = ${remote_port}"
            } >> "$cfg"
            mappings+="${local_port}->${remote_port}/${proto},"
            count=$((count+1))
            local more
            read -rp "Add another port mapping for this Kharej? [y/N]: " more
            [[ "${more,,}" != "y" ]] && break
        done

        local cmd="$INSTALL_DIR/frpc -c ${cfg}"

        echo ""
        info "Config: ${cfg}"
        info "Mappings (${count}): ${mappings%,}"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "reverse-frpc-${label}" "reverse-frp" "frp Client [${label}] ${count} port(s)" "$cmd" \
            "ROLE=\"client\"" \
            "LABEL=\"${label}\"" \
            "IRAN_IP=\"${iran_ip}\"" \
            "IRAN_PORT=\"${iran_port}\"" \
            "TOKEN=\"${token}\"" \
            "MAPPINGS=\"${mappings%,}\"" \
            "FRP_CONFIG=\"${cfg}\""
    else
        warn "Invalid choice."
    fi
    press_enter
}

# ─── Reverse Tunnel: Gost WSS ────────────────────────────────

setup_reverse_gost_wss() {
    header "Reverse Tunnel — Gost Relay + WSS (Anti-DPI)"
    info "Reverse relay over WebSocket TLS. Encrypted + camouflaged."
    echo ""

    local role; role=$(role_for reverse)
    announce_role "$([[ "$role" == 1 ]] && echo server || echo client)"

    if [[ "$role" == "1" ]]; then
        echo ""
        local user_port=$(ask_port "Port users connect to on Iran: " "443")
        local relay_port=$(ask_port "Relay port (Kharej connects here): " "4443")

        local cmd="$INSTALL_DIR/gost -L=tcp://:${user_port} -L=relay+wss://:${relay_port}"

        echo ""
        info "Command: $cmd"
        info "Users connect to :${user_port} | Kharej connects to :${relay_port}"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "reverse-gost-server-${relay_port}" "reverse-gost-wss" "Gost Reverse Server relay:${relay_port} user:${user_port}" "$cmd" \
            "ROLE=\"server\"" \
            "USER_PORT=\"${user_port}\"" \
            "RELAY_PORT=\"${relay_port}\""

    elif [[ "$role" == "2" ]]; then
        echo ""
        local iran_ip=$(ask_ip "Iran IP: ")
        local relay_port=$(ask_port "Iran relay port: " "4443")
        local local_port=$(ask_port "Local destination port on Kharej: " "2083")

        local cmd="$INSTALL_DIR/gost -L=rtcp://:0/127.0.0.1:${local_port} -F=relay+wss://${iran_ip}:${relay_port}"

        echo ""
        info "Command: $cmd"
        read -rp "Apply and start? [y/N]: " confirm
        [[ "${confirm,,}" != "y" ]] && { press_enter; return; }
        register_tunnel "reverse-gost-client-${local_port}" "reverse-gost-wss" "Gost Reverse Client ->${iran_ip}:${relay_port}" "$cmd" \
            "ROLE=\"client\"" \
            "IRAN_IP=\"${iran_ip}\"" \
            "RELAY_PORT=\"${relay_port}\"" \
            "LOCAL_PORT=\"${local_port}\""
    else
        warn "Invalid choice."
    fi
    press_enter
}

# ─── Status ───────────────────────────────────────────────────

show_status() {
    header "TunnelMaster Status"

    echo -e "${BOLD}Installed Binaries:${NC}"
    if [[ -f "$INSTALL_DIR/chisel" ]]; then
        local cv=$("$INSTALL_DIR/chisel" --version 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}●${NC} Chisel  ($cv)"
    else
        echo -e "  ${RED}○${NC} Chisel  (not installed)"
    fi
    if [[ -f "$INSTALL_DIR/gost" ]]; then
        echo -e "  ${GREEN}●${NC} Gost    (v${GOST_VERSION})"
    else
        echo -e "  ${RED}○${NC} Gost    (not installed)"
    fi
    if [[ -f "$INSTALL_DIR/frps" ]]; then
        echo -e "  ${GREEN}●${NC} frp     (v${FRP_VERSION})"
    else
        echo -e "  ${RED}○${NC} frp     (not installed)"
    fi

    echo ""
    echo -e "${BOLD}BBR Status:${NC}"
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        echo -e "  ${GREEN}●${NC} BBR enabled"
    else
        echo -e "  ${YELLOW}○${NC} BBR not enabled (use option 9)"
    fi

    echo ""
    echo -e "${BOLD}Active Tunnel Services:${NC}"
    list_services || true
    press_enter
}

# ─── Profile Listing & Management ────────────────────────────

# read_profile_field <file> <key> — safely extract a quoted value
read_profile_field() {
    sed -n "s/^${2}=\"\(.*\)\"\$/\1/p" "$1" 2>/dev/null | head -1
}

list_profiles() {
    shopt -s nullglob
    local files=("$PROFILE_DIR"/*.conf)
    shopt -u nullglob
    if [[ ${#files[@]} -eq 0 ]]; then
        warn "No tunnel profiles found."
        return 1
    fi
    echo ""
    printf "  ${BOLD}%-3s %-32s %-18s %-7s %s${NC}\n" "#" "Name" "Method" "Role" "Status"
    echo "  ──────────────────────────────────────────────────────────────────────────"
    local i=1 f
    for f in "${files[@]}"; do
        local name method role svc status dot
        name=$(read_profile_field "$f" NAME)
        method=$(read_profile_field "$f" METHOD)
        role=$(read_profile_field "$f" ROLE)
        svc=$(read_profile_field "$f" SERVICE)
        [[ -z "$role" ]] && role="-"
        status=$(systemctl is-active "${svc}.service" 2>/dev/null)
        [[ -z "$status" ]] && status="unknown"
        if [[ "$status" == "active" ]]; then dot="${GREEN}●${NC}"; else dot="${RED}●${NC}"; fi
        printf "  %-3s %-32s %-18s %-7s ${dot} %s\n" "$i" "$name" "$method" "$role" "$status"
        ((i++))
    done
    echo ""
    return 0
}

show_profile_detail() {
    local f="$1"
    [[ -f "$f" ]] || { error "Profile not found."; return 1; }
    local name method role svc desc created status
    name=$(read_profile_field "$f" NAME)
    method=$(read_profile_field "$f" METHOD)
    role=$(read_profile_field "$f" ROLE)
    svc=$(read_profile_field "$f" SERVICE)
    desc=$(read_profile_field "$f" DESC)
    created=$(read_profile_field "$f" CREATED)
    status=$(systemctl is-active "${svc}.service" 2>/dev/null)
    [[ -z "$status" ]] && status="unknown"

    header "Profile — ${name}"
    echo -e "  ${BOLD}Method   :${NC} ${method}"
    [[ -n "$role" ]] && echo -e "  ${BOLD}Role     :${NC} ${role}"
    echo -e "  ${BOLD}Service  :${NC} ${svc}"
    if [[ "$status" == "active" ]]; then
        echo -e "  ${BOLD}Status   :${NC} ${GREEN}● ${status}${NC}"
    else
        echo -e "  ${BOLD}Status   :${NC} ${RED}● ${status}${NC}"
    fi
    echo -e "  ${BOLD}Created  :${NC} ${created}"
    echo -e "  ${BOLD}Summary  :${NC} ${desc}"
    echo ""
    echo -e "  ${BOLD}Parameters:${NC}"
    # Print method-specific fields, skipping the common/internal ones
    local line key val
    while IFS= read -r line; do
        key="${line%%=*}"
        case "$key" in
            NAME|METHOD|ROLE|SERVICE|DESC|CREATED|CMD) continue ;;
        esac
        val=$(read_profile_field "$f" "$key")
        printf "    %-14s %s\n" "$key" "$val"
    done < "$f"
}

profile_actions() {
    local f="$1"
    local name svc
    name=$(read_profile_field "$f" NAME)
    svc=$(read_profile_field "$f" SERVICE)
    while true; do
        clear 2>/dev/null || true
        show_profile_detail "$f"
        echo ""
        echo -e "  ${CYAN}1)${NC} Start         ${CYAN}2)${NC} Stop          ${CYAN}3)${NC} Restart"
        echo -e "  ${CYAN}4)${NC} Edit (wizard) ${CYAN}5)${NC} Edit raw conf ${CYAN}6)${NC} View command"
        echo -e "  ${CYAN}7)${NC} Remove tunnel"
        echo -e "  ${CYAN}0)${NC} Back"
        echo ""
        read -rp "  Action: " a
        case "$a" in
            1) systemctl start "${svc}.service" 2>/dev/null && log "Started." || error "Start failed."; sleep 1 ;;
            2) systemctl stop "${svc}.service" 2>/dev/null && log "Stopped." || error "Stop failed."; sleep 1 ;;
            3) systemctl restart "${svc}.service" 2>/dev/null && log "Restarted." || error "Restart failed."; sleep 1 ;;
            4) edit_profile "$f"; press_enter; return ;;
            5) edit_profile_raw "$f"; press_enter ;;
            6) echo ""; info "ExecStart command:"; echo "    $(read_profile_field "$f" CMD)"; press_enter ;;
            7) read -rp "  Confirm remove of [${name}]? [y/N]: " c
               if [[ "${c,,}" == "y" ]]; then
                   stop_and_remove_service "$name"
                   press_enter
                   return
               fi ;;
            0) return ;;
            *) error "Invalid option."; sleep 1 ;;
        esac
    done
}

menu_profiles() {
    while true; do
        clear 2>/dev/null || true
        header "Tunnel Profiles"
        shopt -s nullglob
        local files=("$PROFILE_DIR"/*.conf)
        shopt -u nullglob
        if [[ ${#files[@]} -eq 0 ]]; then
            warn "No tunnel profiles found. Create a tunnel first."
            press_enter
            return
        fi
        list_profiles
        echo -e "  ${BOLD}Commands:${NC} ${CYAN}#${NC}=details  ${CYAN}S${NC}=start all  ${CYAN}T${NC}=stop all  ${CYAN}0${NC}=back"
        echo ""
        read -rp "  Select: " choice
        case "$choice" in
            0|"") return ;;
            [Ss]) start_all_profiles; press_enter ;;
            [Tt]) stop_all_profiles; press_enter ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#files[@]} )); then
                    profile_actions "${files[$((choice-1))]}"
                else
                    error "Invalid selection."; sleep 1
                fi
                ;;
        esac
    done
}

start_all_profiles() {
    shopt -s nullglob
    local files=("$PROFILE_DIR"/*.conf)
    shopt -u nullglob
    [[ ${#files[@]} -eq 0 ]] && { warn "No profiles to start."; return; }
    local f svc
    for f in "${files[@]}"; do
        svc=$(read_profile_field "$f" SERVICE)
        if systemctl start "${svc}.service" 2>/dev/null; then
            log "Started ${svc}"
        else
            warn "Failed to start ${svc}"
        fi
    done
}

stop_all_profiles() {
    shopt -s nullglob
    local files=("$PROFILE_DIR"/*.conf)
    shopt -u nullglob
    [[ ${#files[@]} -eq 0 ]] && { warn "No profiles to stop."; return; }
    local f svc
    for f in "${files[@]}"; do
        svc=$(read_profile_field "$f" SERVICE)
        if systemctl stop "${svc}.service" 2>/dev/null; then
            log "Stopped ${svc}"
        else
            warn "Failed to stop ${svc}"
        fi
    done
}

# run_setup_for_method <method> — launch the matching create wizard
run_setup_for_method() {
    case "$1" in
        direct-simple)      setup_direct_simple ;;
        direct-wss)         setup_direct_wss ;;
        direct-quic)        setup_direct_quic ;;
        direct-chisel)      setup_direct_chisel ;;
        reverse-chisel)     setup_reverse_chisel ;;
        reverse-chisel-tls) setup_reverse_chisel_tls ;;
        reverse-frp)        setup_reverse_frp ;;
        reverse-gost-wss)   setup_reverse_gost_wss ;;
        *) error "Unknown tunnel method: $1"; return 1 ;;
    esac
}

# edit_profile <file> — guided edit: remove the tunnel and re-run its wizard
edit_profile() {
    local f="$1"
    [[ -f "$f" ]] || { error "Profile not found."; return 1; }
    local method oldname
    method=$(read_profile_field "$f" METHOD)
    oldname=$(read_profile_field "$f" NAME)

    clear 2>/dev/null || true
    show_profile_detail "$f"
    echo ""
    warn "Editing will REMOVE this tunnel and re-run the setup wizard."
    info "The current settings are shown above — use them as a reference while re-entering."
    read -rp "  Proceed with edit? [y/N]: " c
    [[ "${c,,}" != "y" ]] && { warn "Cancelled."; return; }

    stop_and_remove_service "$oldname"
    echo ""
    info "Re-create the tunnel with your new settings:"
    run_setup_for_method "$method"
}

# edit_profile_raw <file> — advanced: edit the .conf in $EDITOR, rebuild from CMD
edit_profile_raw() {
    local f="$1"
    [[ -f "$f" ]] || { error "Profile not found."; return 1; }
    local editor="${EDITOR:-}"
    if [[ -z "$editor" ]]; then
        if command -v nano >/dev/null 2>&1; then editor="nano"
        elif command -v vi >/dev/null 2>&1; then editor="vi"
        else error "No editor found (set \$EDITOR or install nano/vi)."; return 1; fi
    fi
    warn "The systemd service is rebuilt from the CMD field — edit CMD to change runtime behavior."
    sleep 2
    "$editor" "$f"

    local name cmd desc
    name=$(read_profile_field "$f" NAME)
    cmd=$(read_profile_field "$f" CMD)
    desc=$(read_profile_field "$f" DESC)
    if [[ -z "$name" || -z "$cmd" ]]; then
        error "Profile is missing NAME or CMD — service not rebuilt."
        return 1
    fi
    create_service "$name" "$cmd" "$desc"
    log "Profile updated and service rebuilt."
}

# Recreate systemd services for every saved profile (used after restore)
rebuild_services_from_profiles() {
    shopt -s nullglob
    local files=("$PROFILE_DIR"/*.conf)
    shopt -u nullglob
    [[ ${#files[@]} -eq 0 ]] && { warn "No profiles to rebuild."; return; }
    local f name cmd desc
    for f in "${files[@]}"; do
        name=$(read_profile_field "$f" NAME)
        cmd=$(read_profile_field "$f" CMD)
        desc=$(read_profile_field "$f" DESC)
        if [[ -n "$name" && -n "$cmd" ]]; then
            create_service "$name" "$cmd" "$desc"
        else
            warn "Skipping malformed profile: $(basename "$f")"
        fi
    done
}

# ─── Backup & Restore ────────────────────────────────────────

backup_config() {
    header "Backup Configuration"
    if [[ ! -d "$CONFIG_DIR" ]]; then
        warn "Nothing to back up (config directory missing)."
        press_enter
        return
    fi
    local backup_root="${CONFIG_DIR}/backups"
    mkdir -p "$backup_root"
    local stamp file
    stamp=$(date '+%Y%m%d-%H%M%S')
    file="${backup_root}/tunnelmaster-${stamp}.tar.gz"

    # Archive everything under CONFIG_DIR (profiles, *.toml, certs, wrappers)
    # except the backups directory itself.
    if tar -czf "$file" -C "$CONFIG_DIR" --exclude='./backups' . 2>/dev/null; then
        log "Backup created: ${file}"
        chmod 600 "$file"
    else
        error "Backup failed."
        press_enter
        return
    fi

    # Rotation: keep the 10 most recent backups
    local old
    old=$(ls -1t "${backup_root}"/tunnelmaster-*.tar.gz 2>/dev/null | tail -n +11)
    if [[ -n "$old" ]]; then
        echo "$old" | xargs -r rm -f
        info "Old backups rotated (kept last 10)."
    fi
    press_enter
}

restore_config() {
    header "Restore Configuration"
    local file="$1"
    local backup_root="${CONFIG_DIR}/backups"

    if [[ -z "$file" ]]; then
        file=$(ls -1t "${backup_root}"/tunnelmaster-*.tar.gz 2>/dev/null | head -1)
    fi
    if [[ -z "$file" || ! -f "$file" ]]; then
        error "No backup file found."
        press_enter
        return
    fi

    info "Restoring from: ${file}"
    read -rp "This will overwrite current configs and rebuild services. Continue? [y/N]: " confirm
    [[ "${confirm,,}" != "y" ]] && { warn "Cancelled."; press_enter; return; }

    mkdir -p "$CONFIG_DIR"
    if ! tar -xzf "$file" -C "$CONFIG_DIR" 2>/dev/null; then
        error "Failed to extract backup."
        press_enter
        return
    fi
    log "Files restored."

    info "Rebuilding services from profiles..."
    rebuild_services_from_profiles
    log "Restore complete."
    press_enter
}

menu_backup() {
    while true; do
        clear 2>/dev/null || true
        header "Backup & Restore"
        echo -e "  ${CYAN}1)${NC} Create backup now"
        echo -e "  ${CYAN}2)${NC} Restore from latest backup"
        echo -e "  ${CYAN}3)${NC} Restore from a specific file"
        echo -e "  ${CYAN}4)${NC} List backups"
        echo -e "  ${CYAN}0)${NC} Back"
        echo ""
        read -rp "  Select: " choice
        case "$choice" in
            1) backup_config ;;
            2) restore_config "" ;;
            3) read -rp "  Path to backup file: " bf; restore_config "$bf" ;;
            4)
                echo ""
                if ls -1t "${CONFIG_DIR}/backups"/tunnelmaster-*.tar.gz 2>/dev/null; then
                    :
                else
                    warn "No backups found."
                fi
                press_enter
                ;;
            0|"") return ;;
            *) error "Invalid option."; sleep 1 ;;
        esac
    done
}

# ─── Stop Service Menu ────────────────────────────────────────

menu_stop_service() {
    header "Stop & Remove a Service"

    local services
    services=$(systemctl list-units --type=service --all --no-legend 2>/dev/null | grep "tm-" | awk '{print $1}')
    if [[ -z "$services" ]]; then
        warn "No TunnelMaster services found."
        press_enter
        return
    fi

    echo -e "${BOLD}Active services:${NC}"
    local i=1
    local svc_array=()
    while IFS= read -r svc; do
        local status=$(systemctl is-active "$svc" 2>/dev/null)
        svc_array+=("$svc")
        if [[ "$status" == "active" ]]; then
            printf "  ${CYAN}%d)${NC} ${GREEN}●${NC} %s\n" "$i" "$svc"
        else
            printf "  ${CYAN}%d)${NC} ${RED}●${NC} %s (%s)\n" "$i" "$svc" "$status"
        fi
        ((i++))
    done <<< "$services"

    echo ""
    echo -e "  ${CYAN}0)${NC} Cancel"
    echo ""
    read -rp "Select service to remove: " choice

    if [[ "$choice" == "0" ]] || [[ -z "$choice" ]]; then
        return
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#svc_array[@]} )); then
        local selected="${svc_array[$((choice-1))]}"
        local name="${selected#tm-}"
        name="${name%.service}"
        warn "Removing: $selected"
        read -rp "Confirm? [y/N]: " confirm
        [[ "${confirm,,}" == "y" ]] && stop_and_remove_service "$name"
    else
        error "Invalid selection."
    fi
    press_enter
}

# ─── Uninstall ────────────────────────────────────────────────

uninstall_all() {
    header "Uninstall TunnelMaster"
    warn "This will STOP all tunnel services and REMOVE all binaries."
    echo ""
    read -rp "Type 'yes' to confirm: " confirm
    [[ "$confirm" != "yes" ]] && { warn "Cancelled."; press_enter; return; }

    info "Stopping all services..."
    local services
    services=$(systemctl list-units --type=service --all --no-legend 2>/dev/null | grep "tm-" | awk '{print $1}')
    if [[ -n "$services" ]]; then
        while IFS= read -r svc; do
            systemctl stop "$svc" 2>/dev/null
            systemctl disable "$svc" 2>/dev/null
            rm -f "${SERVICE_DIR}/$svc"
        done <<< "$services"
        systemctl daemon-reload
    fi

    info "Removing binaries..."
    rm -f "$INSTALL_DIR/chisel" "$INSTALL_DIR/gost" "$INSTALL_DIR/frps" "$INSTALL_DIR/frpc"

    info "Removing config..."
    rm -rf "$CONFIG_DIR"

    info "Removing kernel optimizations..."
    rm -f /etc/sysctl.d/99-tunnelmaster.conf
    rm -f /etc/security/limits.d/99-tunnelmaster.conf
    sysctl --system > /dev/null 2>&1

    echo ""
    log "TunnelMaster completely removed."
    press_enter
}

# ─── Main Menu ────────────────────────────────────────────────

main_menu() {
    while true; do
        clear 2>/dev/null || true
        echo ""
        echo -e "${MAGENTA}${BOLD}╔═══════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}${BOLD}║         TunnelMaster v2.0                     ║${NC}"
        echo -e "${MAGENTA}${BOLD}║     Anti-DPI Tunnel Manager                   ║${NC}"
        echo -e "${MAGENTA}${BOLD}╚═══════════════════════════════════════════════╝${NC}"
        echo ""
        if [[ "$SERVER_ROLE" == "iran" ]]; then
            echo -e "   Server role: ${GREEN}${BOLD}IRAN (inside)${NC}"
        elif [[ "$SERVER_ROLE" == "kharej" ]]; then
            echo -e "   Server role: ${CYAN}${BOLD}KHAREJ (outside)${NC}"
        else
            echo -e "   Server role: ${RED}${BOLD}not set${NC}"
        fi
        echo ""
        echo -e " ${BOLD}── Direct Tunnels (Iran → Kharej) ──────────────${NC}"
        echo -e "  ${CYAN}1)${NC} Gost Simple         ${YELLOW}(TCP/UDP, no encryption)${NC}"
        echo -e "  ${CYAN}2)${NC} Gost WSS + MUX      ${GREEN}(Anti-DPI, TLS, SNI camouflage)${NC} ★"
        echo -e "  ${CYAN}3)${NC} Gost QUIC           ${YELLOW}(UDP transport, fast)${NC}"
        echo -e "  ${CYAN}4)${NC} Chisel              ${YELLOW}(HTTP tunnel, SSH encryption)${NC}"
        echo ""
        echo -e " ${BOLD}── Reverse Tunnels (Kharej → Iran) ─────────────${NC}"
        echo -e "  ${CYAN}5)${NC} Chisel Reverse      ${YELLOW}(WebSocket + SSH)${NC}"
        echo -e "  ${CYAN}6)${NC} Chisel Reverse+TLS  ${GREEN}(TLS + SNI, maximum stealth)${NC} ★"
        echo -e "  ${CYAN}7)${NC} frp Reverse         ${GREEN}(Multi-server hub, many Kharej → 1 Iran)${NC} ★"
        echo -e "  ${CYAN}8)${NC} Gost Reverse WSS    ${GREEN}(Relay + WSS, Anti-DPI)${NC} ★"
        echo ""
        echo -e " ${BOLD}── System & Management ──────────────────────────${NC}"
        echo -e "  ${CYAN}p)${NC}  Manage Profiles    ${GREEN}(list, start/stop, edit, remove)${NC}"
        echo -e "  ${CYAN}b)${NC}  Backup / Restore   ${GREEN}(save & restore configs)${NC}"
        echo -e "  ${CYAN}r)${NC}  Change Server Role ${GREEN}(Iran / Kharej)${NC}"
        echo -e "  ${CYAN}9)${NC}  Optimize System    ${GREEN}(BBR + Kernel tuning)${NC}"
        echo -e "  ${CYAN}10)${NC} Show Status"
        echo -e "  ${CYAN}11)${NC} Stop/Remove a Tunnel"
        echo -e "  ${CYAN}12)${NC} Reinstall Binaries"
        echo -e "  ${CYAN}13)${NC} Uninstall Everything"
        echo ""
        echo -e "  ${CYAN}0)${NC}  Exit"
        echo ""
        echo -e " ${GREEN}★ = Recommended for bypassing DPI${NC}"
        echo ""
        read -rp " Select: " choice

        case "$choice" in
            1)  setup_direct_simple ;;
            2)  setup_direct_wss ;;
            3)  setup_direct_quic ;;
            4)  setup_direct_chisel ;;
            5)  setup_reverse_chisel ;;
            6)  setup_reverse_chisel_tls ;;
            7)  setup_reverse_frp ;;
            8)  setup_reverse_gost_wss ;;
            p|P) menu_profiles ;;
            b|B) menu_backup ;;
            r|R) choose_server_role; press_enter ;;
            9)  optimize_system ;;
            10) show_status ;;
            11) menu_stop_service ;;
            12) install_all_binaries; press_enter ;;
            13) uninstall_all ;;
            0)  echo -e "\n${GREEN}Goodbye!${NC}\n"; exit 0 ;;
            *)  warn "Invalid option."; sleep 1 ;;
        esac
    done
}

# ─── Entry Point ──────────────────────────────────────────────

require_root
check_os
load_settings

case "${1:-}" in
    install)
        install_dependencies
        install_all_binaries
        log "Installation complete. Run again without arguments to configure."
        exit 0
        ;;
    role)
        choose_server_role
        exit 0
        ;;
    status)
        show_status
        exit 0
        ;;
    list)
        list_profiles
        exit 0
        ;;
    start-all)
        start_all_profiles
        exit 0
        ;;
    stop-all)
        stop_all_profiles
        exit 0
        ;;
    backup)
        backup_config
        exit 0
        ;;
    restore)
        restore_config "${2:-}"
        exit 0
        ;;
    optimize)
        optimize_system
        exit 0
        ;;
    uninstall)
        uninstall_all
        exit 0
        ;;
    *)
        # First run — install if missing
        if [[ ! -f "$INSTALL_DIR/chisel" ]] || [[ ! -f "$INSTALL_DIR/gost" ]] || [[ ! -f "$INSTALL_DIR/frps" ]]; then
            info "First run — installing dependencies and binaries..."
            install_dependencies
            install_all_binaries
            echo ""
        fi
        ensure_server_role
        main_menu
        ;;
esac
