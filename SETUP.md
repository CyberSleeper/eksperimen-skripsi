# Setup Guide

Panduan lengkap untuk setup environment testing cache performance.

## 1. Setup K6 VM (Load Testing Machine)

### Install K6

```bash
# Add K6 repository
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69

echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
  sudo tee /etc/apt/sources.list.d/k6.list

# Install K6
sudo apt-get update
sudo apt-get install k6
```

### Verify Installation

```bash
k6 version
# Expected output: k6 v0.x.x
```

### Clone Repository

```bash
git clone <repository-url>
cd skripsi_gilang_eksperimen
chmod +x *.sh
```

### Configure SSH Access

```bash
# Generate SSH key if not exists
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy public key to target VMs
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@<vm-no-cache-ip>
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@<vm-cache-ip>
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@<vm-backup-ip>
```

## 2. Setup Target VMs (Application Servers)

### VM 1: No Cache Configuration

```bash
# Install nginx if not installed
sudo apt-get update
sudo apt-get install nginx

# Configure nginx WITHOUT cache
sudo nano /etc/nginx/sites-available/hightide

# Basic configuration (no proxy_cache directives)
# Example:
server {
    listen 80;
    server_name hightide-no-cache.sple.my.id;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

sudo nginx -t
sudo systemctl reload nginx
```

### VM 2 & 3: Cache Configuration

```bash
# Configure nginx WITH cache
sudo nano /etc/nginx/nginx.conf

# Add cache configuration
http {
    # Cache configuration
    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=my_cache:10m 
                     max_size=1g inactive=60m use_temp_path=off;
    
    # Cache key configuration
    proxy_cache_key "$scheme$request_method$host$request_uri";
}

# Site configuration
sudo nano /etc/nginx/sites-available/hightide

server {
    listen 80;
    server_name hightide-cache.sple.my.id;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_cache my_cache;
        proxy_cache_valid 200 60m;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_background_update on;
        proxy_cache_lock on;
        
        # Add cache status header
        add_header X-Cache-Status $upstream_cache_status;
        
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

# Create cache directory
sudo mkdir -p /var/cache/nginx
sudo chown www-data:www-data /var/cache/nginx

sudo nginx -t
sudo systemctl reload nginx
```

### Install PostgreSQL (All VMs)

```bash
# Install PostgreSQL
sudo apt-get update
sudo apt-get install postgresql postgresql-contrib

# Configure PostgreSQL for remote connections (if needed)
sudo nano /etc/postgresql/14/main/postgresql.conf
# Set: listen_addresses = '*'

sudo nano /etc/postgresql/14/main/pg_hba.conf
# Add: host all all 0.0.0.0/0 md5

sudo systemctl restart postgresql
```

### Create Database

```bash
sudo -u postgres psql

CREATE DATABASE aisco_product_hightide;
\c aisco_product_hightide

-- Create tables (import your schema here)
\q
```

### Install Application

```bash
# Example for Java Spring Boot application
sudo apt-get install openjdk-17-jdk

# Deploy application jar
sudo mkdir -p /opt/hightide
sudo cp hightide-app.jar /opt/hightide/

# Create systemd service
sudo nano /etc/systemd/system/hightide.service

[Unit]
Description=High Tide Application
After=network.target postgresql.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/hightide
ExecStart=/usr/bin/java -jar /opt/hightide/hightide-app.jar
Restart=always

[Install]
WantedBy=multi-user.target

# Start service
sudo systemctl daemon-reload
sudo systemctl enable hightide
sudo systemctl start hightide
```

## 3. Generate Seed Data

```bash
# On K6 VM
cd skripsi_gilang_eksperimen

# Generate seed files for different payload sizes
for size in 10 100 500 1000 2000 4000 8000 16000 32000; do
    echo $size | python gen_income.py
done

# Verify seed files
ls -lh seeds/
```

## 4. Configure Testing Framework

```bash
# Copy example config
cp config.env.example config.env

# Edit configuration
nano config.env

# Set your VM IPs and credentials
VM_NO_CACHE="13.214.170.49"
VM_CACHE="18.141.211.240"
VM_CACHE_BACKUP="52.77.228.157"
SSH_KEY="~/.ssh/id_ed25519"
SSH_USER="ubuntu"
```

## 5. Test Connectivity

```bash
# Test SSH access to all VMs
ssh -i ~/.ssh/id_ed25519 ubuntu@<vm-no-cache-ip> "echo 'Connection OK'"
ssh -i ~/.ssh/id_ed25519 ubuntu@<vm-cache-ip> "echo 'Connection OK'"
ssh -i ~/.ssh/id_ed25519 ubuntu@<vm-backup-ip> "echo 'Connection OK'"

# Test database access
ssh -i ~/.ssh/id_ed25519 ubuntu@<vm-no-cache-ip> \
  "psql -U postgres -d aisco_product_hightide -c 'SELECT 1;'"

# Test API endpoints
curl https://hightide-no-cache.sple.my.id/call/automatic-report-twolevel/list
curl https://hightide-cache.sple.my.id/call/income/list
```

## 6. Run Initial Test

```bash
# Single test run
./run_multiple_tests.sh 3 100

# Check results
ls -lh results/
```

## 7. Setup Analysis Environment (Optional)

### On Local Machine (Windows with PowerShell)

```powershell
# Install Python
# Download from https://www.python.org/downloads/

# Install Jupyter and dependencies
pip install jupyter pandas numpy matplotlib seaborn

# Copy results from K6 VM
scp -i ~/.ssh/id_ed25519 -r ubuntu@<k6-vm-ip>:~/skripsi_gilang_eksperimen/results ./

# Start Jupyter
jupyter notebook cache_performance_eda.ipynb
```

## 8. Verify Setup

### Checklist

- [ ] K6 installed and working
- [ ] SSH access configured to all VMs
- [ ] PostgreSQL installed on all VMs
- [ ] Application running on all VMs
- [ ] Nginx configured correctly (no cache vs with cache)
- [ ] Seed data generated
- [ ] config.env configured
- [ ] Test connectivity successful
- [ ] Initial test run successful

## Troubleshooting

### K6 Installation Issues

```bash
# If GPG key fails
curl -s https://dl.k6.io/key.gpg | sudo apt-key add -

# Alternative: Download binary directly
wget https://github.com/grafana/k6/releases/download/v0.47.0/k6-v0.47.0-linux-amd64.tar.gz
tar -xzf k6-v0.47.0-linux-amd64.tar.gz
sudo mv k6-v0.47.0-linux-amd64/k6 /usr/local/bin/
```

### SSH Connection Issues

```bash
# Check SSH key permissions
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

# Test with verbose output
ssh -v -i ~/.ssh/id_ed25519 ubuntu@<vm-ip>
```

### PostgreSQL Connection Issues

```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Check listening ports
sudo netstat -plnt | grep postgres

# Test local connection
sudo -u postgres psql -c "SELECT version();"
```

### Nginx Cache Not Working

```bash
# Check cache directory
ls -la /var/cache/nginx/

# Check nginx error logs
sudo tail -f /var/log/nginx/error.log

# Verify cache headers
curl -I https://hightide-cache.sple.my.id/call/income/list
# Look for: X-Cache-Status: HIT
```

## Next Steps

After setup is complete:
1. Read [README.md](README.md) for usage instructions
2. Run initial small-scale test: `./run_multiple_tests.sh 3 100`
3. Run full experiment: `./run_full_experiment.sh`
4. Analyze results using PowerShell script or Jupyter notebook
