# Anytype Self-Hosting Guide (No Docker)

A step-by-step plan for setting up an Anytype self-hosted sync server on a VPS using the `any-sync-bundle` binary, without Docker.

---

## Prerequisites

- A VPS running Ubuntu 22.04 or Debian 12 (minimum 1GB RAM recommended)
- A public IP address or domain name pointing to the VPS
- Root or sudo access
- Ports available: `33010/tcp`, `33020/udp`, `33030/tcp`, `33060/tcp`, `33080/tcp`

---

## Step 1 — Update the System

```bash
sudo apt update && sudo apt upgrade -y
```

---

## Step 2 — Install MongoDB

Anytype uses MongoDB as its primary data store.

```bash
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
  sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg

echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] \
  https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
  sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

sudo apt update
sudo apt install -y mongodb-org
sudo systemctl enable --now mongod
```

Verify it is running:

```bash
sudo systemctl status mongod
```

---

## Step 3 — Install Redis

Redis is used for caching and coordination between sync components.

```bash
sudo apt install -y redis-server
sudo systemctl enable --now redis-server
```

Redis will listen on `127.0.0.1:6379` by default, which is exactly what the bundle expects.

---

## Step 4 — Download the any-sync-bundle Binary

`any-sync-bundle` is a community-maintained single Go binary that merges all official Anytype sync services (coordinator, consensus, file node, sync node) into one executable. It also replaces the heavy MinIO S3 component with a lighter local storage solution.

Check the [releases page](https://github.com/grishy/any-sync-bundle/releases) for the latest version, then download:

```bash
VERSION="1.3.0-2026-01-31"   # Replace with the latest release tag
curl -LO "https://github.com/grishy/any-sync-bundle/releases/download/${VERSION}/any-sync-bundle_linux_amd64.tar.gz"
tar -xzf any-sync-bundle_linux_amd64.tar.gz
sudo mv any-sync-bundle /usr/local/bin/
sudo chmod +x /usr/local/bin/any-sync-bundle
```

Confirm the binary works:

```bash
any-sync-bundle --help
```

---

## Step 5 — Create a Dedicated System User and Data Directory

Running the service as a dedicated non-root user is a security best practice.

```bash
sudo useradd --system --no-create-home --shell /bin/false anytype
sudo mkdir -p /var/lib/anytype/data
sudo chown -R anytype:anytype /var/lib/anytype
```

---

## Step 6 — First Run (Initialization)

The `--initial-*` flags are only processed on the very first run to generate the configuration files. Subsequent starts will read from the persisted config.

Replace `YOUR_PUBLIC_IP` with your server's actual public IP address or domain name:

```bash
sudo -u anytype any-sync-bundle start-bundle \
  --initial-external-addrs "YOUR_PUBLIC_IP" \
  --initial-mongo-uri "mongodb://127.0.0.1:27017/" \
  --initial-redis-uri "redis://127.0.0.1:6379/" \
  --config-save-path /var/lib/anytype/bundle-config.yml \
  --client-config-path /var/lib/anytype/data/client-config.yml \
  --initial-storage /var/lib/anytype/data/storage
```

Let it run until you see it is active (a few seconds), then stop it with `Ctrl+C`. This creates two important files:

- `/var/lib/anytype/bundle-config.yml` — server configuration
- `/var/lib/anytype/data/client-config.yml` — client configuration to import into the Anytype app

---

## Step 7 — Set Up as a systemd Service

Create the service unit file:

```bash
sudo nano /etc/systemd/system/anytype.service
```

Paste the following content:

```ini
[Unit]
Description=Anytype Self-Hosted Sync Server
After=network.target mongod.service redis-server.service
Requires=mongod.service redis-server.service

[Service]
Type=simple
User=anytype
Group=anytype
ExecStart=/usr/local/bin/any-sync-bundle start-bundle \
  --config-path /var/lib/anytype/bundle-config.yml \
  --client-config-path /var/lib/anytype/data/client-config.yml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now anytype
sudo systemctl status anytype
```

---

## Step 8 — Open Firewall Ports

Allow the required ports through the firewall:

```bash
sudo ufw allow 33010/tcp    # any-sync-node
sudo ufw allow 33020/udp    # any-sync-node (QUIC protocol)
sudo ufw allow 33030/tcp    # any-sync-filenode
sudo ufw allow 33060/tcp    # any-sync-coordinator
sudo ufw allow 33080/tcp    # any-sync-consensusnode
sudo ufw reload
```

---

## Step 9 — Connect the Anytype Client

The initialization step generated a `client-config.yml` file that the Anytype app needs. Copy it from your server to your local machine:

```bash
scp user@YOUR_PUBLIC_IP:/var/lib/anytype/data/client-config.yml ~/client-config.yml
```

Then in the Anytype app:

1. Open Anytype and go to the onboarding screen (log out if already logged in)
2. Click the **gear icon** in the top right corner
3. Go to **Networks → Self-hosted**
4. Click **"Tap to provide your network configuration"**
5. Upload the `client-config.yml` file
6. Click **Save**

---

## Maintenance

### View Logs

```bash
sudo journalctl -u anytype -f
```

### Check Service Status

```bash
sudo systemctl status anytype
sudo systemctl status mongod
sudo systemctl status redis-server
```

### Update the Binary

```bash
sudo systemctl stop anytype
# Download new binary (repeat Step 4 with updated VERSION)
sudo systemctl start anytype
```

> **Always back up your data before updating.**

### Backup

Back up the data directory and MongoDB regularly:

```bash
# File storage backup
sudo tar -czf anytype-backup-$(date +%F).tar.gz /var/lib/anytype/data/storage

# MongoDB dump
mongodump --out /var/lib/anytype/backup/mongo-$(date +%F)
```

---

## Port Reference

| Port       | Protocol | Component               |
|------------|----------|-------------------------|
| 33010      | TCP      | any-sync-node           |
| 33020      | UDP      | any-sync-node (QUIC)    |
| 33030      | TCP      | any-sync-filenode       |
| 33060      | TCP      | any-sync-coordinator    |
| 33080      | TCP      | any-sync-consensusnode  |

---

## Notes

- **Domain + TLS:** If you use a domain name instead of an IP, update `--initial-external-addrs` accordingly during initialization. TLS termination is not handled by the bundle itself — you would need a reverse proxy like Caddy or Nginx for that.
- **RAM usage:** The full stack (bundle + MongoDB + Redis) typically uses under 200MB of RAM at idle, making this well-suited to small VPS instances.
- **ARM support:** Replace `amd64` with `arm64` in the download URL if your VPS uses an ARM processor (e.g. Ampere-based instances).
- **Official docs:** [doc.anytype.io](https://doc.anytype.io) | [github.com/grishy/any-sync-bundle](https://github.com/grishy/any-sync-bundle)
