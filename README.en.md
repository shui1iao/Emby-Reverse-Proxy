# Emby Reverse Proxy

English | [简体中文](README.md)

**A one-click script for reverse proxying Emby/Jellyfin with your own domain.**

It can proxy another Emby server, your own backend, or an internal Emby instance through a public domain. The script detects existing web servers automatically: Caddy first, then Nginx. If neither exists, it installs Caddy.

---

## Features

- Configure an Emby reverse proxy automatically
- Custom domain and upstream Emby URL
- Auto-detect Caddy / Nginx
- Prefer existing Caddy or Nginx installation
- Install Caddy automatically if no web server is found
- Automatic HTTPS in Caddy mode
- Generate Nginx reverse proxy config in Nginx mode
- Backup existing config files
- Try to open ports 80/443 automatically

---

## Installation

```bash
bash <(curl -Ls https://raw.githubusercontent.com/shui1iao/Emby-Reverse-Proxy/main/install.sh)
```

You will be asked to enter:

- Your domain, for example `emby.example.com`
- The upstream Emby URL, for example `https://origin.example.com:443`

Non-interactive example:

```bash
DOMAIN=emby.example.com UPSTREAM=https://origin.example.com:443 bash <(curl -Ls https://raw.githubusercontent.com/shui1iao/Emby-Reverse-Proxy/main/install.sh)
```

---

## Before You Start

Point your domain to the server that runs this script:

```text
emby.example.com  A  your-server-ipv4
```

If you use Cloudflare, DNS only mode is recommended. Proxying video traffic through the orange cloud is not recommended.

Required open ports:

- `80/tcp`
- `443/tcp`

---

## How It Works

The script chooses the proxy engine in this order:

1. Caddy if installed
2. Nginx if Caddy is not installed
3. Install and use Caddy if neither exists

### Caddy Mode

Caddy mode writes a config like this and obtains HTTPS certificates automatically:

```caddy
emby.example.com {
    encode zstd gzip

    reverse_proxy https://upstream.example.com:443 {
        header_up Host upstream.example.com
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
    }
}
```

### Nginx Mode

Nginx mode writes an HTTP reverse proxy config:

```nginx
server {
    listen 80;
    server_name emby.example.com;

    client_max_body_size 0;
    proxy_buffering off;

    location / {
        proxy_pass https://upstream.example.com:443;
        proxy_http_version 1.1;

        proxy_set_header Host upstream.example.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

For HTTPS with Nginx, use your existing certificate setup or run:

```bash
certbot --nginx -d emby.example.com
```

---

## Environment Variables

| Variable | Description | Example |
| --- | --- | --- |
| `DOMAIN` | Public domain | `emby.example.com` |
| `UPSTREAM` | Upstream Emby URL | `https://origin.example.com:443` |
| `PROXY_ENGINE` | Proxy engine: `auto`, `caddy`, or `nginx` | `caddy` |

Example:

```bash
DOMAIN=emby.example.com \
UPSTREAM=https://origin.example.com:443 \
PROXY_ENGINE=caddy \
bash <(curl -Ls https://raw.githubusercontent.com/shui1iao/Emby-Reverse-Proxy/main/install.sh)
```

---

## Notes

- A dedicated subdomain is more reliable than path-based proxying such as `/emby`.
- If the upstream Emby server has an IP whitelist, allow your proxy server IP.
- If `curl` returns 403 from the server but the browser works, the upstream WAF may be blocking command-line requests. It does not always mean the proxy is broken.
- Video proxying consumes traffic and bandwidth on your server.

---

## License

MIT
