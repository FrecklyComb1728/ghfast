# ghfast

基于 Nginx 的 GitHub 全站反向代理配置，覆盖 GitHub 15 个域名，实现全站加速访问。

## 特性

- **全站反代** - 覆盖 GitHub 主站、API、Raw、Gist、GHCR 等 15 个域名
- **URL 智能跳转** - 访问 `gh.1s.fan/https://gist.github.com/user/id` 自动 301 到 `gist.gh.1s.fan/user/id`
- **分区缓存** - 静态资源（Raw、Avatars、Assets 等）与动态内容（API、Docs 等）独立缓存区
- **安全拦截** - 屏蔽 `.git`、`login`、`signup` 等敏感路径，防止滥用
- **API 鉴权透传** - `api` 和 `ghcr` 域名支持 Authorization / Cookie 透传
- **CSP 策略替换** - 自动替换 Content-Security-Policy，避免浏览器拦截
- **sub_filter 全文替换** - HTML / CSS / JS / JSON 中的 GitHub 域名自动替换为代理域名
- **一键部署** - 交互式脚本自动完成域名替换、目录创建、SSL 配置、crontab 设置
- **No if** - 整个配置文件完全没有 if 语句，充分利用 nginx 从上到下的执行顺序

## 域名映射

以 `gh.1s.fan` 为示例域名：

| 代理域名 | 源站 |
|---------|------|
| gh.1s.fan | github.com |
| api.gh.1s.fan | api.github.com |
| raw.gh.1s.fan | raw.githubusercontent.com |
| camo.gh.1s.fan | camo.githubusercontent.com |
| docs.gh.1s.fan | docs.github.com |
| ghcr.gh.1s.fan | ghcr.io |
| gist.gh.1s.fan | gist.github.com |
| assets.gh.1s.fan | github.githubassets.com |
| avatars.gh.1s.fan | avatars.githubusercontent.com |
| objects.gh.1s.fan | objects.githubusercontent.com |
| codeload.gh.1s.fan | codeload.github.com |
| gist-assets.gh.1s.fan | gist-assets.githubusercontent.com |
| user-images.gh.1s.fan | user-images.githubusercontent.com |
| private-user-images.gh.1s.fan | private-user-images.githubusercontent.com |
| release-assets.gh.1s.fan | release-assets.githubusercontent.com |
| github-releases.gh.1s.fan | github-releases.githubusercontent.com |

## 快速部署

### 前置要求

- Nginx（需编译 `ngx_http_sub_module` 模块）
- 泛域名 SSL 证书（`*.your.domain` 及 `your.domain`，不配置则仅 HTTP）
- DNS 泛解析（`*.your.domain` 和 `your.domain` 均指向服务器 IP）

### 一键部署

```bash
git clone https://github.com/FrecklyComb1728/ghfast.git
cd ghfast
sudo chmod +x deploy.sh && sudo ./deploy.sh
```

脚本会依次询问以下配置，全部交互式完成：

| 步骤 | 询问内容 | 默认值 |
|------|----------|--------|
| 1 | 代理主域名 | 必填 |
| 2 | SSL 证书 + 私钥路径 | 留空则仅 HTTP |
| 3 | 是否安装 crontab 缓存清理 | 否 |
| 4 | 静态/动态缓存保留天数 | 180 / 7 |
| 5 | Web 根目录 | `/www/wwwroot/$DOMAIN` |
| 6 | Nginx 配置目录 | 必填 |
| 7 | 日志目录 | `/www/wwwlogs` |

脚本会自动完成：域名替换、路径替换、SSL 开关、目录创建、文件复制、CA 证书检测、crontab 配置、nginx -t 验证。

> 源文件不会被修改，脚本在临时目录操作副本，支持重复运行。

### 手动部署

如果不想使用一键脚本，可以手动执行以下步骤：

1. 替换域名

```bash
sed -i 's/gh\.1s\.fan/your.domain.com/g' nginx.conf
sed -i 's/gh\.1s\.fan/your.domain.com/g' index.html
```

2. 修改配置中的实际路径

替换域名后，还需修改以下内容：

- SSL 证书路径（`ssl_certificate` / `ssl_certificate_key`）
- 缓存目录路径（`proxy_cache_path`）
- 站点根目录路径（`map $host $doc_root` 中的路径）
- 日志文件路径（`access_log` / `error_log`）
- CA 证书路径（`proxy_ssl_trusted_certificate`，Debian/Ubuntu 为 `/etc/ssl/certs/ca-certificates.crt`）

3. 创建所有目录

```bash
DOMAIN="your.domain.com"
mkdir -p /www/wwwroot/$DOMAIN/proxy_cache_dir/{static,dynamic} \
  /www/wwwroot/$DOMAIN/{{api,raw,camo,docs,gist,assets,avatars,objects,codeload}.$DOMAIN,ghcr.$DOMAIN,{gist-assets,user-images,release-assets,github-releases}.$DOMAIN,"$DOMAIN"}
```

4. 放置首页文件

将 `index.html` 放入主域名文件夹，访问根域名时即可看到代理首页：

```bash
cp index.html /www/wwwroot/$DOMAIN/$DOMAIN/
```

其他子域名的本地文件同理放入对应文件夹，Nginx 会优先返回本地文件，找不到时再回源 GitHub。

5. 部署配置并重载

```bash
cp nginx.conf /etc/nginx/conf.d/ghfast.conf
nginx -t && nginx -s reload
```

## 缓存维护

通过 crontab 定时清理过期缓存文件：

> 服务器硬盘可用空间太小的话（<= 10G），就不建议开缓存了，因为缓存文件占用的空间会非常大。

```bash
crontab -e
```

```cron
# 每周日凌晨2点清理静态缓存中 180 天未访问的文件
0 2 * * 0 find /www/wwwroot/your.domain.com/proxy_cache_dir/static -type f -mtime +180 -delete

# 每周日凌晨3点清理动态缓存中 7 天未访问的文件
0 3 * * 0 find /www/wwwroot/your.domain.com/proxy_cache_dir/dynamic -type f -mtime +7 -delete
```

## 文件结构

```
.
├── deploy.sh     # 一键部署脚本
├── nginx.conf    # Nginx 配置文件
├── index.html    # 代理首页
├── LICENSE
└── .gitignore
```

## License

[MIT](LICENSE)
