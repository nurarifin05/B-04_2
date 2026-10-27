#!/usr/bin/env bash
# CTF VM-04: Incident Recovery Vault (Ubuntu 22.04 / 24.04)
set -Eeuo pipefail

LAB_USER=student
BASE=/home/student/evidence
DB_DIR="$BASE/archive"
DB_FILE="$DB_DIR/incident_vault.db"

if [[ ${EUID} -ne 0 ]]; then
  echo '[!] Jalankan: sudo bash setup.sh' >&2
  exit 1
fi

status() {
  echo '=== STATUS VM-04 ==='
  for x in sqlite3 hashcat openssl; do command -v "$x" >/dev/null && echo "[OK] $x" || echo "[MISSING] $x"; done
  [[ -f "$DB_FILE" ]] && echo "[OK] Database: $DB_FILE" || echo '[MISSING] Database'
  [[ -f "$BASE/recovery_bundle.enc" ]] && echo '[OK] Encrypted bundle' || echo '[MISSING] Encrypted bundle'
  if [[ -f "$DB_FILE" ]]; then
    echo "[INFO] Tables: $(sqlite3 "$DB_FILE" '.tables')"
  fi
}
if [[ ${1:-} == --status ]]; then status; exit 0; fi
if [[ $# -gt 0 && ${1:-} != --install ]]; then echo 'Usage: sudo bash setup.sh [--install|--status]' >&2; exit 2; fi

echo '[+] Memasang sqlite3, hashcat, openssl, zip, unzip...'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq sqlite3 hashcat openssl zip unzip ca-certificates >/dev/null
if ! id "$LAB_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$LAB_USER"
  echo 'student:student123' | chpasswd
fi
install -d -m 0755 "$DB_DIR"

cat > "$BASE/README.txt" <<'EOF'
=================================================================
CTF VM-04 — INCIDENT RECOVERY VAULT
=================================================================
Tim SOC menemukan cadangan aplikasi Incident Recovery milik perusahaan
fiktif Cakra Data. Arsip aplikasi tersimpan dalam database SQLite.
Sebuah paket recovery terenkripsi turut ditemukan tetapi kata sandi
pembukanya tidak didokumentasikan secara langsung.

Tugas peserta:
1. Inventarisasi arsip dan tabel SQLite.
2. Temukan akun service pemilik paket recovery.
3. Identifikasi jenis hash dan pulihkan password dengan mask terarah.
4. Buka paket terenkripsi untuk mendapatkan bukti insiden.
5. Investigasi akun legacy dan verifikasi integritas manifest.

Kerjakan hanya pada data simulasi di folder /home/student/evidence.
EOF

cat > "$BASE/password_policy.txt" <<'EOF'
Kebijakan khusus akun service recovery:
- Password terdiri dari prefix tetap "Vault" (V besar) dan 4 digit angka.
- Contoh pola: Vault0000 (hanya contoh, BUKAN password sebenarnya).
- Akun service_accounts memakai SHA-256 raw (tanpa salt).
- Sistem lama menggunakan MD5 untuk akun arsip legacy.
- Password akun legacy berpola prefix tetap "Log" + 2 digit angka.
Catatan: hashing password SHA-256/MD5 tanpa salt ini sengaja LEMAH
untuk pendidikan. Sistem nyata wajib memakai Argon2id/bcrypt/scrypt.
EOF

# Deterministic passwords keep instructor validation reproducible.
SERVICE_PASS='Vault4821'
LEGACY_PASS='Log73'
SERVICE_HASH=$(printf '%s' "$SERVICE_PASS" | sha256sum | awk '{print $1}')
LEGACY_HASH=$(printf '%s' "$LEGACY_PASS" | md5sum | awk '{print $1}')

rm -f "$DB_FILE"
sqlite3 "$DB_FILE" <<SQL
CREATE TABLE personnel (id INTEGER PRIMARY KEY, full_name TEXT, team TEXT);
INSERT INTO personnel VALUES (1,'Rina Pratama','SOC'),(2,'Dimas Putra','Infrastructure');
CREATE TABLE service_accounts (
 id INTEGER PRIMARY KEY, account_name TEXT UNIQUE, role TEXT,
 password_hash TEXT, status TEXT
);
INSERT INTO service_accounts VALUES
 (1,'svc_recovery','RECOVERY_ADMIN','$SERVICE_HASH','ACTIVE'),
 (2,'svc_monitor','MONITOR','$(printf '%s' 'Monitor1' | sha256sum | awk '{print $1}')','DISABLED');
CREATE TABLE legacy_accounts (id INTEGER PRIMARY KEY, username TEXT, legacy_md5 TEXT);
INSERT INTO legacy_accounts VALUES (1,'archive_bot','$LEGACY_HASH');
CREATE TABLE audit_events (event_id INTEGER PRIMARY KEY, actor TEXT, action TEXT, occurred_at TEXT);
INSERT INTO audit_events VALUES
 (401,'svc_recovery','RECOVERY_BUNDLE_CREATED','2026-09-17 08:30:00'),
 (402,'archive_bot','LEGACY_EXPORT_CHECK','2026-09-17 08:35:00');
CREATE TABLE recovery_manifest (artifact TEXT PRIMARY KEY, sha256 TEXT);
SQL

# Bundle contains a real flag after decryption, plus a report whose checksum
# is stored in the SQLite manifest (independent integrity task).
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
cat > "$TMP_DIR/incident_report.txt" <<'EOF'
INCIDENT REPORT IR-2026-041
Company: Cakra Data (simulated)
Summary: An internal service account was reviewed after an unexpected backup.
Finding: The archive uses an unsuitable fast password hash.
Recommendation: Rotate credentials and use a slow salted password KDF.
EOF
printf '%s\n' 'FLAG{RECOVERY_BUNDLE_OPENED_2026}' > "$TMP_DIR/recovery_token.txt"
REPORT_HASH=$(sha256sum "$TMP_DIR/incident_report.txt" | awk '{print $1}')
sqlite3 "$DB_FILE" "INSERT INTO recovery_manifest VALUES ('incident_report.txt','$REPORT_HASH');"
( cd "$TMP_DIR" && zip -q "$BASE/recovery_bundle.zip" incident_report.txt recovery_token.txt )
# Encrypt ZIP using modern password derivation and AES-256-CBC.
openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt \
  -in "$BASE/recovery_bundle.zip" -out "$BASE/recovery_bundle.enc" \
  -pass "pass:$SERVICE_PASS"
rm -f "$BASE/recovery_bundle.zip"

cat > "$BASE/INSTRUCTIONS.txt" <<'EOF'
Peserta: baca README.txt dan password_policy.txt.
Seluruh hash dan data adalah simulasi CTF.
Gunakan hashcat mode 1400 untuk SHA-256 raw, mode 0 untuk MD5 raw.
Paket terenkripsi berisi ZIP; dekripsi dahulu lalu lakukan unzip.
Dilarang menggunakan akun dan kata sandi hasil latihan pada sistem nyata.
EOF

chown -R "$LAB_USER:$LAB_USER" "$BASE"
find "$BASE" -type d -exec chmod 0755 {} +
find "$BASE" -type f -exec chmod 0644 {} +
echo '[+] Setup VM-04 selesai. Akun student tersedia.'
status
