#!/bin/bash
# ==============================================================================
# Script Setup Lab VM-02: Compromised Application Server (Ubuntu 24.04 LTS)
# ==============================================================================

# Pastikan script dijalankan sebagai root/sudo
if [ "$EUID" -ne 0 ]; then
  echo "[!] Dilarang menjalankan script ini tanpa akses root. Gunakan: sudo $0"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[+] Menginstal dependensi sistem (MySQL Server, OpenSSL, Zip, Unzip)..."
apt-get update -qq
apt-get install -y -qq mysql-server openssl zip unzip hashcat > /dev/null

echo "[+] Memastikan service MySQL berjalan..."
systemctl start mysql
systemctl enable mysql > /dev/null 2>&1

TARGET_DIR="/home/student/lab"

# Membuat user student jika belum ada di mesin VM
if ! id "student" &>/dev/null; then
    echo "[+] Membuat user 'student'..."
    useradd -m -s /bin/bash student
    echo "student:student123" | chpasswd
fi

echo "[+] Menyiapkan struktur folder lab..."
mkdir -p "$TARGET_DIR/dumps"
mkdir -p "$TARGET_DIR/wordlists"

# 1. README.txt
cat << 'EOF' > "$TARGET_DIR/README.txt"
===================================================================
LABORATORIUM INVESTIGASI APLIKASI — VM-02
===================================================================
Sebuah server aplikasi terindikasi kompromi.
Tugas Anda:
1. Hubungi MySQL lokal: mysql -u db_student -pstudent123 company_app
2. Temukan artefak kredensial pada tabel yang relevan.
3. Ekstrak hash dan lakukan analisis serangan berbasis Rule (Rule-based attack).

Wordlist tersedia di: wordlists/corporate_keywords.txt
EOF

# 2. Setup Database MySQL
echo "[+] Mengonfigurasi Database MySQL & Akses User..."
mysql << 'EOF'
CREATE DATABASE IF NOT EXISTS company_app;

CREATE USER IF NOT EXISTS 'db_student'@'localhost' IDENTIFIED BY 'student123';
GRANT SELECT ON company_app.* TO 'db_student'@'localhost';
FLUSH PRIVILEGES;

USE company_app;

-- Tabel Decoy 1: users (Data lama/diacak)
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50),
    email VARCHAR(100),
    password VARCHAR(255)
);
INSERT INTO users (username, email, password) VALUES
('guest', 'guest@company.local', '$6$salt1$dummyhashguest12345'),
('old_admin', 'old@company.local', '$6$salt2$dummyhasholdadmin6789');

-- Tabel Decoy 2: employees (Biodata)
CREATE TABLE IF NOT EXISTS employees (
    id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100),
    division VARCHAR(50),
    employee_code VARCHAR(20)
);
INSERT INTO employees (full_name, division, employee_code) VALUES
('Budi Santoso', 'IT Support', 'EMP-001'),
('Siti Aminah', 'Finance', 'EMP-002');

-- Tabel Decoy 3: application_config
CREATE TABLE IF NOT EXISTS application_config (
    config_key VARCHAR(50) PRIMARY KEY,
    config_value VARCHAR(255)
);
INSERT INTO application_config (config_key, config_value) VALUES
('app_title', 'Corporate ERP System'),
('api_admin_key', '*2470C0C06DEE42FD1618BB99005ADCA2EC9D1E19');

-- Tabel Target: backup_users
-- SHA-512 Crypt ($6$) dari "Company2026!" dengan salt "salttest"
CREATE TABLE IF NOT EXISTS backup_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50),
    email VARCHAR(100),
    password_hash VARCHAR(255)
);
INSERT INTO backup_users (username, email, password_hash) VALUES
('administrator', 'admin@company.local', '$6$salttest$a1M4aG.z1kC6wN3S8T2X8Y7Z6W5V4U3T2S1R0Q9P8O7N6M5L4K3J2I1H0G9F8E7D6C5B4A3/'),
('service_account', 'svc@company.local', '$6$salttest$p9O8N7M6L5K4J3I2H1G0F9E8D7C6B5A4321098765432109876543210987654321');
EOF

# 3. Wordlist
cat << 'EOF' > "$TARGET_DIR/wordlists/corporate_keywords.txt"
company
Company
company2026
Company2026
enterprise
admin2026
EOF

# 4. Membikin file terenkripsi untuk Challenge 8
mkdir -p /var/backups
echo "FLAG{ADMIN_BACKUP_DECRYPTED_SUCCESSFULLY}" | openssl enc -aes-256-cbc -pbkdf2 -out /var/backups/admin_data.enc -k "Company2026!" 2>/dev/null

# Set hak milik dan akses direktori
chown -R student:student /home/student
chmod -R 755 "$TARGET_DIR"

echo "==================================================================="
echo "[+] Setup Lab VM-02 di Ubuntu 24 Selesai!"
echo "==================================================================="
