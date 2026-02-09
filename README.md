[English](README.md) | [中文](README_zh.md)

# Macless Haystack Installer

One-click deployment tool for Macless Haystack (FindMy network server).

## Quick Start

```bash
curl -sSL https://raw.githubusercontent.com/tinydream96/macless-haystack-installer/main/install.sh | sudo bash
```

## Features

- Auto-install Docker and dependencies
- Secure credential storage
- Smart login (auto-fill Apple ID/password, manual 2FA only)
- Fallback image sources
- Easy maintenance (re-login, full reset)

## ❓ Troubleshooting

### Getting 0 Location Reports?

If logs show success but you get 0 location reports, please check the troubleshooting guide:

👉 [Troubleshooting: No Location Data (0 reports)](troubleshooting_empty_reports_en.md)

Common causes:

1. VPS IP blocked by Apple
2. Low Apple ID Trust Score (New account)

## License

MIT
