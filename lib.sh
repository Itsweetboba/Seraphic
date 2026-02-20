#!/bin/bash

# ==========================================
# LIBRARY FUNCTIONS - SERAPHIC INSTALLER
# ==========================================

# ==========================================
# COLORS
# ==========================================
Color_Off='\033[0m'
Black='\033[0;30m'
Red='\033[0;31m'
Green='\033[0;32m'
Yellow='\033[0;33m'
Blue='\033[0;34m'
Purple='\033[0;35m'
Cyan='\033[0;36m'
White='\033[0;37m'

# Bold Colors
BBlack='\033[1;30m'
BRed='\033[1;31m'
BGreen='\033[1;32m'
BYellow='\033[1;33m'
BBlue='\033[1;34m'
BPurple='\033[1;35m'
BCyan='\033[1;36m'
BWhite='\033[1;37m'

# ==========================================
# GLOW TEXT
# ==========================================
Glow='\e[1;32m'

# ==========================================
# CHECK & SETUP DIALOG/WHIPTAIL
# ==========================================
function setup_dialog {
    # Cek apakah whiptail tersedia
    if ! command -v whiptail &> /dev/null; then
        echo -e "${Yellow}Menginstall whiptail...${Color_Off}"
        if [ -f /etc/debian_version ]; then
            apt-get update && apt-get install -y whiptail
        elif [ -f /etc/centos-release ]; then
            yum install -y newt
        fi
    fi

    # Setup GSUDO (Wrapper untuk whiptail)
    # GSUDO adalah variabel global yang akan kita gunakan untuk semua menu
    GSUDO="whiptail"
}

# ==========================================
# HELPER: PRINT WITH COLOR
# ==========================================
function print_info {
    echo -e "${Cyan}[INFO]${Color_Off} $1"
}

function print_success {
    echo -e "${Green}[SUCCESS]${Color_Off} $1"
}

function print_error {
    echo -e "${Red}[ERROR]${Color_Off} $1"
}

function print_warning {
    echo -e "${Yellow}[WARNING]${Color_Off} $1"
}

# ==========================================
# PROGRESS BAR (Untuk download/install panjang)
# ==========================================
# Usage: progress_bar 50 "Downloading file..."
function progress_bar {
    local percentage=$1
    local message=$2
    
    # Whiptail gauge tidak bisa dipanggil dari fungsi bash biasa
    # Jadi kita gunakan pendekatan sederhana dengan echo
    
    # Cara 1: Menggunakan whiptail --gauge
    if [ -z "$message" ]; then
        message="Mohon tunggu..."
    fi
    
    # Ini akan dijalankan di background oleh fungsi lain
    # Contoh penggunaan:
    # (for i in {0..100..10}; do sleep 1; echo $i; done) | whiptail --title "Install" --gauge "$message" 8 50 0
    :
}

# ==========================================
# LOADING ANIMATION
# ==========================================
function loading {
    local pid=$1
    local delay=0.5
    local spinstr='|/-\'

    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# ==========================================
# CHECK REQUIREMENTS
# ==========================================
function check_command {
    if ! command -v $1 &> /dev/null; then
        echo -e "${Yellow}Menginstall $1...${Color_Off}"
        if [ -f /etc/debian_version ]; then
            apt-get install -y $1
        elif [ -f /etc/centos-release ]; then
            yum install -y $1
        fi
    fi
}

function check_curl {
    if ! command -v curl &> /dev/null; then
        echo -e "${Yellow}Menginstall curl...${Color_Off}"
        if [ -f /etc/debian_version ]; then
            apt-get update && apt-get install -y curl
        elif [ -f /etc/centos-release ]; then
            yum install -y curl
        fi
    fi
}

function check_git {
    if ! command -v git &> /dev/null; then
        echo -e "${Yellow}Menginstall git...${Color_Off}"
        if [ -f /etc/debian_version ]; then
            apt-get update && apt-get install -y git
        elif [ -f /etc/centos-release ]; then
            yum install -y git
        fi
    fi
}

# ==========================================
# CONFIGURE FIREWALL (UFW)
# ==========================================
function configure_firewall {
    if command -v ufw &> /dev/null; then
        echo -e "${Cyan}[FIREWALL]${Color_Off} Mengkonfigurasi UFW..."
        
        # Allow SSH (PENTING agar tidak locked out)
        ufw --force allow ssh
        
        # Allow HTTP/HTTPS
        ufw --force allow http
        ufw --force allow https
        
        # Enable UFW
        echo "y" | ufw enable
    fi
}

# ==========================================
# PHP CONFIGURATION (Untuk Panel)
# ==========================================
function configure_php {
    local PHP_VERSION=$1 # contoh: 8.1
    
    echo -e "${Cyan}[PHP]${Color_Off} Mengkonfigurasi PHP..."
    
    # Update PHP-FPM configuration
    sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 100M/" /etc/php/$PHP_VERSION/fpm/php.ini
    sed -i "s/post_max_size = 8M/post_max_size = 100M/" /etc/php/$PHP_VERSION/fpm/php.ini
    sed -i "s/max_execution_time = 30/max_execution_time = 300/" /etc/php/$PHP_VERSION/fpm/php.ini
    sed -i "s/memory_limit = 128M/memory_limit = 512M/" /etc/php/$PHP_VERSION/fpm/php.ini
    
    # Restart PHP-FPM
    systemctl restart php$PHP_VERSION-fpm
    
    echo -e "${Green}✓${Color_Off} PHP dikonfigurasi"
}

# ==========================================
# NGINX CONFIGURATION HELPER
# ==========================================
function create_nginx_config {
    local domain=$1
    local doc_root=$2
    
    cat > /etc/nginx/sites-available/seraphic_$domain << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;

    root $doc_root;
    index index.php index.html index.htm;

    access_log /var/log/nginx/seraphic_${domain}_access.log;
    error_log /var/log/nginx/seraphic_${domain}_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/seraphic_$domain /etc/nginx/sites-enabled/seraphic_$domain
}

# ==========================================
# SYSTEMD SERVICE CREATOR
# ==========================================
function create_systemd_service {
    local service_name=$1
    local description=$2
    local exec_start=$3
    local user=$4
    
    cat > /etc/systemd/system/$service_name.service << EOF
[Unit]
Description=$description
After=network.target

[Service]
Type=simple
User=$user
WorkingDirectory=/var/www/seraphic
ExecStart=$exec_start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $service_name
}

# ==========================================
# RANDOM STRING GENERATOR (Untuk security keys)
# ==========================================
function generate_random_string {
    head -c 32 /dev/urandom | base64
}

# ==========================================
# INITIALIZE LIBRARY
# ==========================================
setup_dialog
