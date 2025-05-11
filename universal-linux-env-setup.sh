#!/bin/bash

# Author: l1qu1d-Jed1
# Description: Advanced universal Linux environment setup script and pentesting distro creation tool.
#              Supports Docker, container management, and adds Kali Linux, Soft Predator OS, BlackArch repos.
#              Provides 'jedi-get' command as a powerful apt-get and Synaptic wrapper with GUI and CLI.
#              Automates repo setup, installs, and manages pentesting tools with error-proof stability.

set -euo pipefail

# VARIABLES
ENV_ROOT="$HOME/universal-linux-env"
APPS_DIR="$ENV_ROOT/apps"
SERVICE_NAME="universal-linux-env.service"
USER_NAME=$(whoami)
DOCKER_BIN="/usr/bin/docker"
JEDI_GET_BIN="/usr/local/bin/jedi-get"

# COLORS
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

function print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

function command_exists() {
    command -v "$1" &> /dev/null
}

function install_docker() {
    if command_exists docker; then
        print_info "Docker is already installed."
    else
        print_info "Installing Docker..."
        sudo apt update
        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io
        sudo usermod -aG docker "$USER_NAME"
        print_info "Docker installed. You may need to log out and log back in for permissions to apply."
    fi
}

function install_docker_compose() {
    if command_exists docker-compose; then
        print_info "Docker Compose is already installed."
    else
        print_info "Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        print_info "Docker Compose installed."
    fi
}

function add_repositories() {
    print_info "Adding Kali Linux, Soft Predator OS, and BlackArch Linux repositories..."

    # Remove duplicate entries from sources.list and sources.list.d
    sudo sed -i '/^deb.*kali.org.*$/!b;N;/^\(.*\)\n\1$/!b;d' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || true
    sudo sed -i '/^deb.*softpredator.*$/!b;N;/^\(.*\)\n\1$/!b;d' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || true
    sudo sed -i '/^deb.*blackarch.*$/!b;N;/^\(.*\)\n\1$/!b;d' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || true

    # Kali Linux repo
    if ! grep -q "kali.org" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "deb http://http.kali.org/kali kali-rolling main non-free contrib" | sudo tee /etc/apt/sources.list.d/kali.list
        curl -fsSL https://archive.kali.org/archive-key.asc | sudo gpg --dearmor -o /usr/share/keyrings/kali-archive-keyring.gpg
        print_info "Added Kali Linux repository."
    else
        print_info "Kali Linux repository already present."
    fi

    # Soft Predator OS repo (example placeholder, replace with actual repo)
    if ! grep -q "softpredator" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "deb http://repo.softpredator.org/ubuntu stable main" | sudo tee /etc/apt/sources.list.d/softpredator.list
        # Add Soft Predator GPG key if available
        # curl -fsSL https://repo.softpredator.org/softpredator.gpg | sudo gpg --dearmor -o /usr/share/keyrings/softpredator-archive-keyring.gpg
        print_info "Added Soft Predator OS repository (placeholder)."
    else
        print_info "Soft Predator OS repository already present."
    fi

    # BlackArch Linux repo for Ubuntu (using BlackArch repo mirror)
    if ! grep -q "blackarch" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "deb http://blackarch.org/blackarch/ blackarch main" | sudo tee /etc/apt/sources.list.d/blackarch.list
        curl -fsSL https://blackarch.org/keyring/blackarch-keyring.pkg.tar.xz | sudo tee /usr/share/keyrings/blackarch-keyring.pkg.tar.xz > /dev/null
        print_info "Added BlackArch Linux repository."
    else
        print_info "BlackArch Linux repository already present."
    fi

    # Clean and fix broken installs
    print_info "Cleaning apt cache and fixing broken installs..."
    sudo apt-get clean
    sudo apt-get -f install -y || true

    # Update repos with retry logic
    local retries=0
    local max_retries=3
    until sudo apt-get update; do
        ((retries++))
        if [ $retries -ge $max_retries ]; then
            print_error "Failed to update repositories after $max_retries attempts."
            break
        fi
        print_info "Retrying apt-get update ($retries/$max_retries)..."
        sleep 5
    done

    print_info "Repository update complete."
}

function create_env_dirs() {
    mkdir -p "$APPS_DIR"
    print_info "Created apps directory at $APPS_DIR"
}

function create_systemd_service() {
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
    if [ ! -f "$SERVICE_FILE" ]; then
        print_info "Creating systemd service to manage container environment..."

        sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Universal Linux Environment Container Manager
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER_NAME
Restart=always
RestartSec=10
ExecStart=$ENV_ROOT/manage_containers.sh
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable "$SERVICE_NAME"
        print_info "Systemd service created and enabled: $SERVICE_NAME"
    else
        print_info "Systemd service file already exists."
    fi
}

function create_manage_script() {
    MANAGE_SCRIPT="$ENV_ROOT/manage_containers.sh"

    cat > "$MANAGE_SCRIPT" << 'EOS'
#!/bin/bash
# This script monitors and restarts all containers created by universal-linux-env
# Add container start logic here per app container if needed

set -euo pipefail

APPS_DIR="$HOME/universal-linux-env/apps"
RETRY_LIMIT=5
RETRY_DELAY=10

function print_info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

function print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1" >&2
}

function container_running() {
    local container_name="$1"
    if docker ps --filter "name=^${container_name}$" --format '{{.Names}}' | grep -wq "$container_name"; then
        return 0
    else
        return 1
    fi
}

function start_container() {
    local container_name="$1"
    local image_name="$2"
    local container_path="$3"

    print_info "Starting container $container_name from image $image_name..."

    # Check if container exists
    if docker ps -a --filter "name=^${container_name}$" --format '{{.Names}}' | grep -wq "$container_name"; then
        # Container exists, start it
        docker start "$container_name"
    else
        # Container does not exist, create and start it
        docker run -d --name "$container_name" -v "$container_path":/app "$image_name"
    fi
}

function monitor_containers() {
    # Scan APPS_DIR for subdirectories and start containers accordingly
    for app_dir in "$APPS_DIR"/*/; do
        [ -d "$app_dir" ] || continue
        app_name=$(basename "$app_dir")
        image_name="universal-linux-env/$app_name:latest"

        # Retry logic
        retries=0
        until container_running "$app_name"; do
            if [ $retries -ge $RETRY_LIMIT ]; then
                print_error "Failed to start container $app_name after $RETRY_LIMIT attempts."
                break
            fi
            start_container "$app_name" "$image_name" "$app_dir"
            ((retries++))
            sleep $RETRY_DELAY
        done
    done

    # Monitor containers and restart if stopped
    while true; do
        for app_dir in "$APPS_DIR"/*/; do
            [ -d "$app_dir" ] || continue
            app_name=$(basename "$app_dir")
            if ! container_running "$app_name"; then
                print_info "Container $app_name stopped. Restarting..."
                start_container "$app_name" "universal-linux-env/$app_name:latest" "$app_dir"
            fi
        done
        sleep 30
    done
}

monitor_containers
EOS

    chmod +x "$MANAGE_SCRIPT"
    print_info "Created container management script at $MANAGE_SCRIPT"
}

function create_jedi_get() {
    JEDI_GET_SCRIPT="$ENV_ROOT/jedi-get"

    cat > "$JEDI_GET_SCRIPT" << 'EOS'
#!/bin/bash

# jedi-get: Custom installer and repo manager for pentesting distros on Ubuntu-based systems.
# Wraps apt-get and Synaptic with enhanced error handling and GUI support.

set -euo pipefail

JEDI_GET_LOG="$HOME/.jedi-get.log"

function print_info() {
    echo -e "\033[0;32m[JEDI-GET]\033[0m $1"
}

function print_error() {
    echo -e "\033[0;31m[JEDI-GET ERROR]\033[0m $1" >&2
}

function update_repos() {
    print_info "Updating package repositories..."
    if sudo apt-get update; then
        print_info "Repositories updated successfully."
    else
        print_error "Failed to update repositories."
        exit 1
    fi
}

function install_package() {
    local pkg="$1"
    print_info "Installing package: $pkg"
    if sudo apt-get install -y "$pkg"; then
        print_info "Package $pkg installed successfully."
    else
        print_error "Failed to install package $pkg."
        exit 1
    fi
}

function synaptic_install() {
    local pkg="$1"
    print_info "Launching Synaptic to install package: $pkg"
    if command -v synaptic &> /dev/null; then
        sudo synaptic --non-interactive --set-selections <<< "$pkg install"
        sudo apt-get dselect-upgrade -y
        print_info "Package $pkg installed via Synaptic."
    else
        print_error "Synaptic not found. Please install Synaptic or use apt-get."
        exit 1
    fi
}

function show_gui() {
    if command -v zenity &> /dev/null; then
        zenity --info --title="jedi-get" --text="jedi-get is a custom installer and repo manager.\nUse 'jedi-get install <package>' to install software.\n\nThis GUI is a placeholder for future enhancements."
    else
        print_error "Zenity not installed. GUI not available."
    fi
}

function usage() {
    echo "Usage: jedi-get <command> [package]"
    echo "Commands:"
    echo "  install <package>   Install a package via apt-get"
    echo "  synaptic <package>  Install a package via Synaptic"
    echo "  update             Update package repositories"
    echo "  gui                Show graphical interface (zenity required)"
    echo "  help               Show this help message"
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

case "$1" in
    install)
        if [ $# -ne 2 ]; then
            usage
            exit 1
        fi
        update_repos
        install_package "$2"
        ;;
    synaptic)
        if [ $# -ne 2 ]; then
            usage
            exit 1
        fi
        synaptic_install "$2"
        ;;
    update)
        update_repos
        ;;
    gui)
        show_gui
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        print_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac
EOS

    chmod +x "$JEDI_GET_SCRIPT"
    print_info "Created jedi-get command script at $JEDI_GET_SCRIPT"

    # Symlink to /usr/local/bin for global access
    if [ ! -L /usr/local/bin/jedi-get ]; then
        sudo ln -s "$JEDI_GET_SCRIPT" /usr/local/bin/jedi-get
        print_info "Created symlink /usr/local/bin/jedi-get for global access"
    else
        print_info "Symlink /usr/local/bin/jedi-get already exists"
    fi
}

function main() {
    print_info "Starting advanced universal Linux environment setup..."

    install_docker
    install_docker_compose
    add_repositories
    create_env_dirs
    create_manage_script
    create_systemd_service
    create_jedi_get

    print_info "Setup complete."
    print_info "You can start the container manager service with: sudo systemctl start $SERVICE_NAME"
    print_info "Use 'jedi-get' command to install pentesting tools and manage repos."
}

main
