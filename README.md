# Anytype Self-Hosted Server

A complete guide to setting up a self-hosted Anytype sync server on a VPS using [any-sync-bundle](https://github.com/grishy/any-sync-bundle).

---

## 🎯 What This Is

This repository contains documentation and configuration for running a **self-hosted Anytype sync server** - a local-first, privacy-focused alternative to Notion with your own data storage.

### Benefits of Self-Hosting

- ✅ **Full control** over your data
- ✅ **Privacy** - your data stays on your server
- ✅ **No vendor lock-in**
- ✅ **Low resource usage** (~250-300MB RAM)
- ✅ **Single binary** deployment with any-sync-bundle

---

## 📋 Prerequisites

- **VPS**: Ubuntu 24.04+ (minimum 1GB RAM recommended)
- **Domain**: A domain name pointing to your VPS (optional but recommended)
- **SSH access**: Root or sudo access to your VPS
- **Open ports**: TCP 33010, UDP 33020

---

## 🚀 Quick Start

### 1. Clone and Review Documentation

```bash
git clone <your-repo-url>
cd AnyType-VPS
cat anytype-setup-complete.md
```

### 2. Set Up the Server

Follow the complete setup guide in [`anytype-setup-complete.md`](./anytype-setup-complete.md)

### 3. Connect Your Anytype Client

1. Open Anytype app
2. Log out (if already logged in)
3. Click **⚙️ Settings → Networks → Self-hosted**
4. Upload your `client-config.yml` file
5. Click **Save** and log in

---

## 📁 Repository Structure

```
AnyType-VPS/
├── README.md                      # This file - quick overview
├── anytype-selfhosting-guide.md   # Original guide from any-sync-bundle
├── anytype-setup-complete.md      # Complete setup documentation
└── anytype-client-config.yml      # Your client config (after setup)
```

---

## 🔧 Components

| Component | Version | Purpose |
|-----------|---------|---------|
| **any-sync-bundle** | v1.3.1-2026-02-16 | Consolidated Anytype sync services |
| **MongoDB** | 7.0 | Primary data store (with replica set) |
| **RedisStack** | 7.4 | Caching and coordination (with Bloom filter) |

---

## 🔌 Network Ports

| Port | Protocol | Component | Required |
|------|----------|-----------|----------|
| 33010 | TCP | DRPC sync protocol | ✅ Yes |
| 33020 | UDP | QUIC protocol | ✅ Yes |

### Firewall Configuration

**Hetzner Cloud** (example):
1. Go to **Console → Security → Firewalls**
2. Add rules for ports 33010/tcp and 33020/udp
3. Apply to your server

**Other providers**: Open the same ports in your provider's firewall/security group.

---

## 🛠️ Maintenance

### Check Service Status

```bash
ssh root@your-server "sudo systemctl status anytype mongod redis-stack-server"
```

### View Logs

```bash
# Real-time logs
ssh root@your-server "sudo journalctl -u anytype -f"

# Last 100 lines
ssh root@your-server "sudo journalctl -u anytype -n 100 --no-pager"
```

### Restart Services

```bash
ssh root@your-server "sudo systemctl restart anytype"
```

### Backup

```bash
# Backup bundle config (contains private keys!)
scp root@your-server:/var/lib/anytype/bundle-config.yml ./backup/

# Backup storage data
ssh root@your-server "tar -czf anytype-storage-backup.tar.gz /var/lib/anytype/data/storage"

# MongoDB dump
ssh root@your-server "mongodump --out ./backup/mongo"
```

### Update

```bash
# Stop service
ssh root@your-server "sudo systemctl stop anytype"

# Download new version
ssh root@your-server "curl -LO https://github.com/grishy/any-sync-bundle/releases/download/v1.3.1-2026-02-16/any-sync-bundle_1.3.1-2026-02-16_linux_amd64.tar.gz"
ssh root@your-server "tar -xzf any-sync-bundle_1.3.1-2026-02-16_linux_amd64.tar.gz"
ssh root@your-server "sudo mv any-sync-bundle /usr/local/bin/"

# Start service
ssh root@your-server "sudo systemctl start anytype"
```

---

## 🐛 Troubleshooting

### Connection Issues

**Error: "HTTP response at 400 or 500 level, http status code: 0"**

1. **Check firewall** - Ensure ports 33010/tcp and 33020/udp are open
2. **Test connectivity**:
   ```bash
   nc -zv your-server-ip 33010
   nc -zuv your-server-ip 33020
   ```
3. **Re-import config** - Remove old network config in Anytype and re-import

### Regenerate Client Config

```bash
ssh root@your-server "sudo systemctl stop anytype"
ssh root@your-server "sudo rm -f /var/lib/anytype/bundle-config.yml /var/lib/anytype/data/client-config.yml"
ssh root@your-server "sudo -u anytype any-sync-bundle start-bundle --bundle-config /var/lib/anytype/bundle-config.yml --client-config /var/lib/anytype/data/client-config.yml --initial-storage /var/lib/anytype/data/storage --initial-external-addrs \"your-domain,your-ip\" --initial-mongo-uri \"mongodb://127.0.0.1:27017/?replicaSet=rs0\" --initial-redis-uri \"redis://127.0.0.1:6379/\""
ssh root@your-server "sudo systemctl start anytype"

# Copy new config
scp root@your-server:/var/lib/anytype/data/client-config.yml ~/anytype-client-config.yml
```

### Check Service Health

```bash
# MongoDB replica set
ssh root@your-server "mongosh --eval 'rs.status().ok'"

# Redis modules
ssh root@your-server "redis-cli MODULE LIST"

# Listening ports
ssh root@your-server "ss -tlnp | grep 33010 && ss -ulnp | grep 33020"
```

---

## 📊 Resource Usage

| Component | RAM (idle) | CPU (idle) |
|-----------|------------|------------|
| MongoDB | ~180 MB | < 1% |
| RedisStack | ~50 MB | < 1% |
| any-sync-bundle | ~25 MB | < 1% |
| **Total** | **~255 MB** | **< 5%** |

---

## 🔒 Security Considerations

1. **Use SSH keys** instead of passwords for VPS access
2. **Enable automatic security updates** on your VPS
3. **Backup your `bundle-config.yml`** - contains private keys
4. **Use a domain with TLS** if exposing to the internet (requires reverse proxy)
5. **Regular backups** of data and configuration

---

## 📚 Documentation

- [`anytype-setup-complete.md`](./anytype-setup-complete.md) - Complete setup guide with all commands
- [`anytype-selfhosting-guide.md`](./anytype-selfhosting-guide.md) - Original any-sync-bundle guide
- [Anytype Documentation](https://doc.anytype.io)
- [any-sync-bundle GitHub](https://github.com/grishy/any-sync-bundle)

---

## 🤝 Contributing

Feel free to submit issues or pull requests to improve this guide.

---

## 📄 License

This documentation is provided as-is for educational purposes.

Anytype is a trademark of Anytype Foundation.  
any-sync-bundle is licensed under MIT by Sergei G.

---

## 🎉 Success!

If your setup is working, you should see:
- ✅ All three services running (anytype, mongod, redis-stack-server)
- ✅ Ports 33010/tcp and 33020/udp accessible
- ✅ Anytype client connected to your self-hosted network
- ✅ Sync status showing as active

Enjoy your self-hosted Anytype server! 🚀
