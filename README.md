# 🖥️ Ubuntu Home Lab

> **Your own server. Your own infrastructure.** 🚀

A self-hosted home lab built with Ubuntu Server for remote development, Docker applications, and personal services — accessible from anywhere through a private network using Tailscale.

Turn an ordinary PC into a personal server without paying for a VPS or keeping a monitor connected.

## ✨ Features

- 🐧 **Ubuntu Server** — A lightweight Linux server environment.
- 🐳 **Docker** — Run applications in isolated containers.
- 🏠 **CasaOS** — Manage self-hosted applications through a web interface.
- 🔐 **Tailscale** — Secure private access to your home server.
- 💻 **Remote Development** — Work with VS Code Remote SSH and compatible JetBrains tools.
- 🛠️ **Development Environment** — Support for Node.js, pnpm, Python, Java, Git, and other tools.
- ⚡ **Headless Operation** — Run without a dedicated monitor or keyboard after setup.

## 🧰 Tech Stack

| Category | Technology |
|---|---|
| Operating System | Ubuntu Server LTS |
| Remote Administration | OpenSSH |
| Private Networking | Tailscale |
| Container Runtime | Docker Engine |
| Server Management | CasaOS |
| Web Development | Node.js, pnpm |
| Programming Languages | JavaScript, TypeScript, Python, Java |
| Code Editor | VS Code Remote SSH |
| Remote IDE | JetBrains Gateway, where supported |

## 💻 Hardware Requirements

This project is designed to work on modest hardware. A high-end workstation or dedicated server is not required.

### Minimum Requirements

| Component | Specification |
|---|---|
| CPU | 2-core, 64-bit processor |
| RAM | 4 GB |
| Storage | 64 GB SSD |
| Network | Ethernet or Wi-Fi |
| Boot Mode | UEFI recommended |
| Internet | Required for installation and downloads |

### Recommended Requirements

| Component | Specification |
|---|---|
| CPU | 4 or more cores |
| RAM | 8–16 GB or more |
| Storage | 256 GB or more SSD |
| Network | Gigabit Ethernet |
| Additional Storage | Optional drive for application data |

**Note:** Minimum requirements are intended for a basic server and lightweight services. Resource requirements increase depending on the number of containers and applications running. Nextcloud, databases, and Android builds benefit from additional RAM, CPU cores, and storage.

## 🖥️ Example Deployment

The following is the hardware used for my personal home lab. It is an example configuration, not a requirement.

| Component | Specification |
|---|---|
| CPU | Intel Core i7-14700F |
| RAM | 32 GB |
| Windows Drive | 1 TB SSD |
| Ubuntu Drive | 512 GB NVMe SSD |
| Operating System | Windows + Ubuntu Server |
| Remote Access | Tailscale + SSH |

## 🏗️ Architecture

```text
   Remote Devices
   ┌─────────────────────┐
   │ Windows PC          │
   │ MacBook              │
   │ Other Devices        │
   └──────────┬──────────┘
              │
          Tailscale
        Private Network
              │
              ▼
   ┌─────────────────────┐
   │   Ubuntu Server     │
   │                     │
   │  ┌───────────────┐  │
   │  │ OpenSSH       │  │
   │  └───────────────┘  │
   │                     │
   │  ┌───────────────┐  │
   │  │ Docker Engine │  │
   │  └───────┬───────┘  │
   │          │          │
   │  ┌───────▼───────┐  │
   │  │ Applications  │  │
   │  │ CasaOS & Apps │  │
   │  └───────────────┘  │
   └─────────────────────┘
```

## 💽 Dual-Boot Disk Layout

A separate SSD is used for Ubuntu Server while preserving the existing Windows installation.

```text
PC
├── SSD 1 — 1 TB
│   └── Windows
│
└── SSD 2 — 512 GB NVMe
    └── Ubuntu Server
        ├── Docker
        ├── CasaOS
        ├── Development Tools
        └── Self-hosted Applications
```

**Installation safety:** Always verify the target disk by model, capacity, and device details before modifying partitions. Device names such as `/dev/nvme0n1` can vary between systems.

For the strongest protection, temporarily disconnect the Windows drive during Ubuntu installation. If Windows uses BitLocker or Device Encryption, save its recovery key somewhere safe before changing boot settings.

## 🚀 Installation

### 1. Install Ubuntu Server

1. Download a supported Ubuntu Server LTS image from the official website.
2. Create a bootable USB using Rufus with GPT/UEFI settings.
3. Boot from the USB installer.
4. Select the intended Ubuntu SSD and configure its partitions carefully.
5. Create a user account and enable OpenSSH during installation.
6. Complete the installation and verify that the system boots successfully.

### 2. Configure SSH

Update the system and install the SSH server if it was not selected during installation.

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install openssh-server -y
sudo systemctl enable --now ssh
```

Check the service status:

```bash
systemctl status ssh
```

Find the server's local IP address:

```bash
hostname -I
```

Connect from another device on the same network:

```bash
ssh username@server-ip
```

Replace `username` and `server-ip` with your actual account and server address.

### 3. Install Tailscale

Follow the official installation instructions for Ubuntu on the [Tailscale documentation](https://tailscale.com/kb/).

Authenticate the server, verify its connection, and test SSH access through its Tailscale IP or MagicDNS hostname.

### 4. Install Docker

Follow the official [Docker Engine installation guide for Ubuntu](https://docs.docker.com/engine/install/ubuntu/).

Verify the installation:

```bash
docker --version
docker compose version
```

### 5. Install CasaOS

Follow the current instructions on the [official CasaOS website](https://casaos.io/).

Review the installation script and its permissions before executing it. After installation, access the dashboard through an appropriate trusted network address.

### 6. Configure Development Tools

Install only the tools needed for your workflow:

- Git
- Node.js and pnpm
- Python
- Java JDK
- VS Code Remote SSH
- JetBrains Gateway, where supported

Keep development tools and application data organized so that maintenance and migration are easier.

## 🔐 Security

- Keep Ubuntu and installed packages updated.
- Use strong credentials and consider SSH key authentication.
- Restrict administrative access to trusted networks.
- Avoid exposing SSH, CasaOS, or other management interfaces directly to the public internet.
- Configure firewall rules carefully, especially when Docker is installed.
- Never commit passwords, private keys, access tokens, or recovery keys to Git.
- Maintain backups of important application data and configuration files.

## ⚡ Power Efficiency

The server is intended to operate headlessly and be accessed remotely.

- Run without a dedicated monitor after initial setup.
- Disable unnecessary services.
- Monitor CPU usage, memory consumption, temperatures, and power draw.
- Use scheduled shutdown or startup only when appropriate for the workload and supported hardware.
- Avoid sleep or hibernation if the server needs to remain reachable.

Actual power consumption depends on hardware, BIOS settings, peripherals, and server workload.

## 📚 Resources

- [Ubuntu Server Documentation](https://documentation.ubuntu.com/server/)
- [Docker Documentation](https://docs.docker.com/)
- [CasaOS](https://casaos.io/)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [VS Code Remote SSH](https://code.visualstudio.com/docs/remote/ssh)
- [JetBrains Remote Development](https://www.jetbrains.com/remote-development/gateway/)

## 📄 License

Choose a license before distributing this repository or its scripts. If you intend to make the project open source, consider adding an appropriate `LICENSE` file.

---

<p align="center">
  <b>🏠 Built at home · Powered by Ubuntu · Connected with Tailscale</b>
</p>
