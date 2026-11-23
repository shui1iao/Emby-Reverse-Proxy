# Emby Reverse Proxy

[English](README.en.md) | 简体中文

**一个用于快速反代 Emby/Jellyfin 服务的一键脚本。**

适合把别人的 Emby 地址、自己的 Emby 后端，或内网 Emby 服务，通过你自己的域名反代出去。脚本会自动识别服务器已有的 Web 服务：有 Caddy 就用 Caddy，有 Nginx 就用 Nginx；如果都没有，则自动安装 Caddy。

---

## ✨ 功能特点

- 自动配置 Emby 反向代理
- 支持自定义域名和上游 Emby 地址
- 自动检测 Caddy / Nginx
- 优先使用服务器已有的 Caddy 或 Nginx
- 没有 Web 服务时自动安装 Caddy
- Caddy 模式自动申请 HTTPS 证书
- Nginx 模式自动生成反代配置
- 自动备份原配置文件
- 尝试自动放行 80/443 端口

---

## 🚀 一键安装

```bash
bash <(curl -Ls https://raw.githubusercontent.com/shui1iao/Emby-Reverse-Proxy/main/install.sh)
```

运行后按提示输入：

- 你的域名，例如 `emby.example.com`
- 要反代的 Emby 地址，例如 `https://origin.example.com:443`

也可以非交互运行：

```bash
DOMAIN=emby.example.com UPSTREAM=https://origin.example.com:443 bash <(curl -Ls https://raw.githubusercontent.com/shui1iao/Emby-Reverse-Proxy/main/install.sh)
```

---

## 📌 使用前准备

请先把你的域名解析到运行脚本的服务器 IP：

```text
emby.example.com  A  你的服务器 IPv4
```

如果使用 Cloudflare，建议保持 **DNS only / 灰云**。视频流量不建议走橙云代理。

服务器需要开放：

- `80/tcp`
- `443/tcp`

---

## 🧩 反代逻辑

脚本会按顺序选择反代服务：

1. 检测到 Caddy：使用 Caddy
2. 没有 Caddy，但检测到 Nginx：使用 Nginx
3. Caddy / Nginx 都没有：自动安装 Caddy 并使用 Caddy

### Caddy 模式

会写入类似配置：

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

Caddy 会自动申请 HTTPS 证书。

### Nginx 模式

会写入类似配置：

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

Nginx 模式默认只写 HTTP 反代。如需 HTTPS，可以使用你已有的证书方案，或运行：

```bash
certbot --nginx -d emby.example.com
```

---

## ⚙️ 环境变量

| 变量 | 说明 | 示例 |
| --- | --- | --- |
| `DOMAIN` | 你的访问域名 | `emby.example.com` |
| `UPSTREAM` | 上游 Emby 地址 | `https://origin.example.com:443` |
| `PROXY_ENGINE` | 指定反代服务，可选 `auto` / `caddy` / `nginx` | `caddy` |

示例：

```bash
DOMAIN=emby.example.com \
UPSTREAM=https://origin.example.com:443 \
PROXY_ENGINE=caddy \
bash <(curl -Ls https://raw.githubusercontent.com/shui1iao/Emby-Reverse-Proxy/main/install.sh)
```

---

## 🔍 注意事项

- 独立子域名比路径反代更稳，不建议使用 `/emby` 这类路径反代。
- 如果上游 Emby 有 IP 白名单，需要把你的服务器出口 IP 加入白名单。
- 如果服务器上用 `curl` 测试返回 403，但浏览器能正常打开，可能是上游 WAF 拦截命令行请求，不一定代表反代失败。
- 反代视频会消耗你的服务器流量和带宽。

---

## 📄 License

MIT
