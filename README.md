[English](README.md) | [中文](README_zh.md)

# Macless Haystack Installer

🍎 Quickly deploy a FindMy network server, allowing you to locate your DIY trackers using Apple's FindMy network without needing a Mac.

## ✨ Features

- 🚀 **One-Click Install** - Automatically installs Docker and all dependencies.
- 🔐 **Secure Credentials** - Apple ID and password are stored securely, only need to be entered once.
- ⚡ **Smart Login** - Auto-fills credentials, you only need to manually enter the 2FA code.
- 🔄 **Fallback Images** - Automatically switches to backup sources if primary Docker images are unavailable.
- 🛠️ **Easy Maintenance** - Supports re-login, full reset, and other maintenance operations.

## 📦 Quick Start

### One-Click Installation

```bash
curl -sSL https://raw.githubusercontent.com/tinydream96/macless-haystack-installer/main/install.sh -o install.sh && chmod +x install.sh && sudo ./install.sh
```

Or using wget:

```bash
wget -qO install.sh https://raw.githubusercontent.com/tinydream96/macless-haystack-installer/main/install.sh && chmod +x install.sh && sudo ./install.sh
```

### Manual Installation

1. Clone the repository

```bash
git clone https://github.com/tinydream96/macless-haystack-installer.git
cd macless-haystack-installer
```

1. Run the installation script

```bash
sudo ./install.sh
```

## 🎯 Usage Guide

After running the script, an interactive menu will appear:

```
╔═══════════════════════════════════════════════════════════╗
║   🍎 Macless Haystack Installer v1.0.0                      ║
╚═══════════════════════════════════════════════════════════╝

Select an option:

  1. 🚀 Clean Install
  2. 🔑 Re-login (Keep Data)
  3. 🔄 Full Reset (Delete All Data)
  4. 📊 Check Status
  5. 🛑 Stop All Services
  6. ❌ Exit
```

### First Time Installation

1. Select `1. Clean Install`
2. Enter your Apple ID (Phone number or Email)
3. Enter your Password
4. The script will auto-fill your credentials
5. Wait for the 2FA code to arrive on your device, then enter it manually
6. Done!

### Re-login

If authentication expires, select `2. Re-login`, and you simply need to enter the 2FA code again.

## ⚠️ Security Notice

> 🔒 **Strongly recommended to use a burner Apple ID**, to avoid risk to your main account.

Credentials storage location: `~/.mh-credentials` (Permission 600, root readable only)

## 🔧 System Requirements

- Linux Server (Ubuntu/Debian/CentOS/Alpine)
- Root Privileges
- Network Connection

## 📋 Components

This tool deploys the following services:

| Service | Port | Description |
|------|------|------|
| Macless Haystack | 6176 | FindMy data retrieval service |
| Anisette Server | 6969 | Apple 2FA handling service |

## 🙏 Acknowledgements

- [macless-haystack](https://github.com/dchristl/macless-haystack) - Core FindMy service
- [anisette-v3-server](https://github.com/Dadoum/anisette-v3-server) - Anisette authentication service

## ❓ Troubleshooting

### Getting 0 Location Reports?

If logs show success but you get 0 location reports, please check the troubleshooting guide:

👉 [Troubleshooting: No Location Data (0 reports)](troubleshooting_empty_reports_en.md)

Common causes:

1. VPS IP blocked by Apple
2. Low Apple ID Trust Score (New account)

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.
