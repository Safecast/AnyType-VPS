# Anytype Self-Hosted Server Setup - Complete

**Server:** simplemap.safecast.org (65.108.24.131)  
**Date:** February 19, 2026  
**Status:** ✅ Complete - Awaiting firewall configuration

---

## Summary

Successfully set up an Anytype self-hosted sync server on Ubuntu 24.04 VPS using:
- **any-sync-bundle** v1.3.1-2026-02-16
- **MongoDB** 7.0 (with replica set)
- **RedisStack** 7.4 (with Bloom filter module)

---

## Prerequisites

- VPS: Ubuntu 24.04.4 LTS (x86_64)
- SSH access: `ssh root@simplemap.safecast.org`
- Domain: simplemap.safecast.org → 65.108.24.131

---

## Step-by-Step Commands Executed

### Step 1: System Update

```bash
ssh root@simplemap.safecast.org "sudo apt update && sudo apt upgrade -y"
```

---

### Step 2: Install MongoDB

```bash
# Add MongoDB GPG key
ssh root@simplemap.safecast.org "curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg"

# Add MongoDB repository
ssh root@simplemap.safecast.org "echo 'deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse' | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list"

# Install MongoDB
ssh root@simplemap.safecast.org "sudo apt update && sudo apt install -y mongodb-org"

# Enable and start MongoDB
ssh root@simplemap.safecast.org "sudo systemctl enable --now mongod"
```

---

### Step 3: Configure MongoDB Replica Set

```bash
# Stop MongoDB
ssh root@simplemap.safecast.org "sudo systemctl stop mongod"

# Start MongoDB with replica set mode
ssh root@simplemap.safecast.org "sudo mongod --replSet rs0 --bind_ip 127.0.0.1 --dbpath /var/lib/mongodb --fork --logpath /var/log/mongodb/mongod.log"

# Initialize replica set
ssh root@simplemap.safecast.org "mongosh --eval 'rs.initiate({_id: \"rs0\", members: [{_id: 0, host: \"127.0.0.1:27017\"}]})'"

# Add replication config to MongoDB
ssh root@simplemap.safecast.org "sudo bash -c 'echo -e \"\\n# Replication\\nreplication:\\n  replSetName: rs0\" >> /etc/mongod.conf'"

# Fix permissions and restart
ssh root@simplemap.safecast.org "sudo chown -R mongodb:mongodb /var/lib/mongodb && sudo chown -R mongodb:mongodb /var/log/mongodb && sudo systemctl start mongod"
```

---

### Step 4: Install RedisStack (with Bloom Filter)

```bash
# Add Redis official repository
ssh root@simplemap.safecast.org "curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg"
ssh root@simplemap.safecast.org "echo 'deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb bullseye main' | sudo tee /etc/apt/sources.list.d/redis.list"

# Install RedisStack
ssh root@simplemap.safecast.org "sudo apt update && sudo apt install -y redis-stack-server"

# Install libssl1.1 dependency (required for RedisStack)
ssh root@simplemap.safecast.org "wget http://nz2.archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb && sudo dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb"

# Enable and start RedisStack
ssh root@simplemap.safecast.org "sudo systemctl enable --now redis-stack-server"

# Verify Bloom filter module is loaded
ssh root@simplemap.safecast.org "redis-cli MODULE LIST"
```

---

### Step 5: Download and Install any-sync-bundle

```bash
# Download latest version
ssh root@simplemap.safecast.org "curl -LO https://github.com/grishy/any-sync-bundle/releases/download/v1.3.1-2026-02-16/any-sync-bundle_1.3.1-2026-02-16_linux_amd64.tar.gz"

# Extract and install
ssh root@simplemap.safecast.org "tar -xzf any-sync-bundle_1.3.1-2026-02-16_linux_amd64.tar.gz"
ssh root@simplemap.safecast.org "sudo mv any-sync-bundle /usr/local/bin/"
ssh root@simplemap.safecast.org "sudo chmod +x /usr/local/bin/any-sync-bundle"

# Verify installation
ssh root@simplemap.safecast.org "any-sync-bundle --help"
```

---

### Step 6: Create System User and Directories

```bash
ssh root@simplemap.safecast.org "sudo useradd --system --no-create-home --shell /bin/false anytype"
ssh root@simplemap.safecast.org "sudo mkdir -p /var/lib/anytype/data"
ssh root@simplemap.safecast.org "sudo chown -R anytype:anytype /var/lib/anytype"
```

---

### Step 7: Initialize any-sync-bundle

```bash
# Clean up any old configs
ssh root@simplemap.safecast.org "sudo rm -f /var/lib/anytype/bundle-config.yml /var/lib/anytype/data/client-config.yml"
ssh root@simplemap.safecast.org "sudo rm -rf /var/lib/anytype/data/storage"

# Run initialization (generates config files)
ssh root@simplemap.safecast.org "sudo -u anytype any-sync-bundle start-bundle --bundle-config /var/lib/anytype/bundle-config.yml --client-config /var/lib/anytype/data/client-config.yml --initial-storage /var/lib/anytype/data/storage --initial-external-addrs \"simplemap.safecast.org\" --initial-mongo-uri \"mongodb://127.0.0.1:27017/?replicaSet=rs0\" --initial-redis-uri \"redis://127.0.0.1:6379/\""
```

---

### Step 8: Create systemd Service

```bash
ssh root@simplemap.safecast.org "sudo tee /etc/systemd/system/anytype.service > /dev/null << 'ENDOFFILE'
[Unit]
Description=Anytype Self-Hosted Sync Server
After=network.target mongod.service redis-stack-server.service
Requires=mongod.service redis-stack-server.service

[Service]
Type=simple
User=anytype
Group=anytype
ExecStart=/usr/local/bin/any-sync-bundle start-bundle --bundle-config /var/lib/anytype/bundle-config.yml --client-config /var/lib/anytype/data/client-config.yml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
ENDOFFILE"

# Reload and enable service
ssh root@simplemap.safecast.org "sudo systemctl daemon-reload"
ssh root@simplemap.safecast.org "sudo systemctl enable --now anytype"
```

---

### Step 9: Verify Services

```bash
# Check all services
ssh root@simplemap.safecast.org "echo '=== MongoDB ===' && sudo systemctl status mongod --no-pager | grep -E 'Active|Loaded' && echo '=== RedisStack ===' && sudo systemctl status redis-stack-server --no-pager | grep -E 'Active|Loaded' && echo '=== Anytype ===' && sudo systemctl status anytype --no-pager | grep -E 'Active|Loaded'"
```

---

### Step 10: Copy Client Configuration

```bash
# Copy client config to local machine
scp root@simplemap.safecast.org:/var/lib/anytype/data/client-config.yml ~/anytype-client-config.yml

# View configuration
cat ~/anytype-client-config.yml
```

---

## Client Configuration File

**Location:** `~/anytype-client-config.yml`

```yaml
id: 6996edc574db9dd37420fdf2
networkId: N4fmB1wEwuUffXQSihAxcEhCbQw4H3mwdwU97EctS6yH3doK
nodes:
    - peerId: 12D3KooWR4wYLUNahA4ifVxFi8Z1e2qMLYzSXmQVzefc763iaiZp
      addresses:
        - quic://simplemap.safecast.org:33020
        - simplemap.safecast.org:33010
      types:
        - coordinator
        - consensus
        - tree
        - file
creationTime: 2026-02-19T11:04:03.643442801Z
```

---

## Required Firewall Ports

**IMPORTANT:** These ports must be opened in the Hetzner Cloud Firewall:

| Port | Protocol | Component | Status |
|------|----------|-----------|--------|
| 33010 | TCP | any-sync-node | ⚠️ Requires firewall config |
| 33020 | UDP | any-sync-node (QUIC) | ⚠️ Requires firewall config |
| 33030 | TCP | any-sync-filenode | ⚠️ Requires firewall config |
| 33060 | TCP | any-sync-coordinator | ⚠️ Requires firewall config |
| 33080 | TCP | any-sync-consensusnode | ⚠️ Requires firewall config |

### Hetzner Firewall Rules (Incoming)

Add these rules in the Hetzner Cloud Console → Security → Firewalls:

| Name | Protocol | Source IP | Destination Port | Action |
|------|----------|-----------|------------------|--------|
| anytype-sync | TCP | 0.0.0.0/0 | 33010 | Accept |
| anytype-quic | UDP | 0.0.0.0/0 | 33020 | Accept |
| anytype-filenode | TCP | 0.0.0.0/0 | 33030 | Accept |
| anytype-coordinator | TCP | 0.0.0.0/0 | 33060 | Accept |
| anytype-consensus | TCP | 0.0.0.0/0 | 33080 | Accept |

---

## Connecting the Anytype Client

1. Open Anytype app
2. Log out if already logged in (go to onboarding screen)
3. Click the **gear icon** in the top right corner
4. Go to **Networks → Self-hosted**
5. Click **"Tap to provide your network configuration"**
6. Upload `~/anytype-client-config.yml`
7. Click **Save**
8. Log in with your Anytype account

---

## Maintenance Commands

### View Logs

```bash
# Anytype logs
ssh root@simplemap.safecast.org "sudo journalctl -u anytype -f"

# MongoDB logs
ssh root@simplemap.safecast.org "sudo journalctl -u mongod -f"

# RedisStack logs
ssh root@simplemap.safecast.org "sudo journalctl -u redis-stack-server -f"
```

### Check Service Status

```bash
ssh root@simplemap.safecast.org "sudo systemctl status anytype mongod redis-stack-server"
```

### Restart Services

```bash
# Restart Anytype
ssh root@simplemap.safecast.org "sudo systemctl restart anytype"

# Restart MongoDB
ssh root@simplemap.safecast.org "sudo systemctl restart mongod"

# Restart RedisStack
ssh root@simplemap.safecast.org "sudo systemctl restart redis-stack-server"
```

### Backup

```bash
# File storage backup
ssh root@simplemap.safecast.org "sudo tar -czf anytype-backup-$(date +%F).tar.gz /var/lib/anytype/data/storage"

# MongoDB dump
ssh root@simplemap.safecast.org "mongodump --out /var/lib/anytype/backup/mongo-$(date +%F)"
```

### Update any-sync-bundle

```bash
# Stop service
ssh root@simplemap.safecast.org "sudo systemctl stop anytype"

# Download new version (update VERSION as needed)
ssh root@simplemap.safecast.org "curl -LO https://github.com/grishy/any-sync-bundle/releases/download/v1.3.1-2026-02-16/any-sync-bundle_1.3.1-2026-02-16_linux_amd64.tar.gz"
ssh root@simplemap.safecast.org "tar -xzf any-sync-bundle_1.3.1-2026-02-16_linux_amd64.tar.gz"
ssh root@simplemap.safecast.org "sudo mv any-sync-bundle /usr/local/bin/"

# Start service
ssh root@simplemap.safecast.org "sudo systemctl start anytype"
```

---

## Troubleshooting

### Test Port Connectivity

```bash
# From local machine
nc -zv 65.108.24.131 33010
nc -zuv 65.108.24.131 33020
```

### Check Listening Ports

```bash
ssh root@simplemap.safecast.org "ss -tlnp | grep -E '33010|33030|33060|33080'"
ssh root@simplemap.safecast.org "ss -ulnp | grep 33020"
```

### Verify MongoDB Replica Set

```bash
ssh root@simplemap.safecast.org "mongosh --eval 'rs.status().ok'"
```

### Verify Redis Modules

```bash
ssh root@simplemap.safecast.org "redis-cli MODULE LIST"
```

---

## Resource Usage

- **MongoDB:** ~180MB RAM
- **RedisStack:** ~50MB RAM
- **any-sync-bundle:** ~25MB RAM
- **Total:** ~250-300MB RAM at idle

---

## References

- [Anytype Documentation](https://doc.anytype.io)
- [any-sync-bundle GitHub](https://github.com/grishy/any-sync-bundle)
- [RedisStack Documentation](https://redis.io/docs/stack/)
- [MongoDB Documentation](https://docs.mongodb.org/manual)

---

## Notes

- The server is configured to use the domain `simplemap.safecast.org` instead of IP
- MongoDB is configured as a single-node replica set (required for change streams)
- RedisStack includes the Bloom filter module required by any-sync-bundle
- All services are set to auto-start on boot
- Configuration files are stored in `/var/lib/anytype/`
