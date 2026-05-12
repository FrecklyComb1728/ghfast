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
| release-assets.gh.1s.fan | release-assets.githubusercontent.com |
| github-releases.gh.1s.fan | github-releases.githubusercontent.com |

## 部署

### 前置要求

- Nginx（需编译 `ngx_http_sub_module` 模块）
- 泛域名 SSL 证书（`*.gh.1s.fan` 及 `gh.1s.fan`）
- DNS 泛解析（`*.gh.1s.fan` 指向服务器 IP）
~~骗你的，@也要解析一次~~

### 部署步骤

1. 克隆仓库

```bash
git clone https://github.com/FrecklyComb1728/ghfast.git
```

2. 替换为你的域名

```bash
sed -i 's/gh\.1s\.fan/your.domain.com/g' nginx.conf
sed -i 's/gh\.1s\.fan/your.domain.com/g' index.html
```

3. 修改配置中的实际路径

替换域名后，需同步修改以下内容：

- SSL 证书路径（`ssl_certificate` / `ssl_certificate_key`）
- 缓存目录路径（`proxy_cache_path`）
- 站点根目录路径（`map $host $doc_root` 中的路径）
- 日志文件路径（`access_log` / `error_log`）

4. 按域名目录放置本地文件

Nginx 会先查找本地文件，找不到时再回源到 GitHub。直接将文件放入上一步创建的对应域名目录即可：

```bash
/www/wwwroot/your.domain.com/your.domain.com/index.html
/www/wwwroot/your.domain.com/assets.your.domain.com/favicon.ico
/www/wwwroot/your.domain.com/docs.your.domain.com/robots.txt
```

**什么？你懒得手动一个个创建？一条命令直接搞定**
```bash
DOMAIN="your.domain.com" # 填写你的域名
mkdir -p /www/wwwroot/$DOMAIN/proxy_cache_dir/{static,dynamic} \
  /www/wwwroot/$DOMAIN/{{api,raw,camo,docs,gist,assets,avatars,objects,codeload}.$DOMAIN,ghcr.$DOMAIN,{gist-assets,user-images,release-assets,github-releases}.$DOMAIN,"$DOMAIN"}
```

目录创建完成后，将仓库中的 `index.html` 放入主域名对应的文件夹：

```bash
cp index.html /www/wwwroot/$DOMAIN/$DOMAIN/
```

这样访问 `https://$DOMAIN` 即可看到代理首页。其他子域名的本地文件同理放入对应文件夹即可。
这些目录与文件路径由 `map $host $doc_root` 和 `try_files` 控制，可以按需覆盖首页、图标、静态资源等内容。

5. 将 `nginx.conf` 内容放入 Nginx 配置并重载

```bash
nginx -t && nginx -s reload
```

## 缓存维护

通过 crontab 定时清理过期缓存文件：

```bash
crontab -e
```

```cron
# 每周日凌晨2点清理静态缓存中 180 天未访问的文件。如果服务器硬盘不是很大，可以调小清理时间。
0 2 * * 0 find /www/wwwroot/gh.1s.fan/proxy_cache_dir/static -type f -mtime +180 -delete

# 每周日凌晨3点清理动态缓存中 7 天未访问的文件
0 3 * * 0 find /www/wwwroot/gh.1s.fan/proxy_cache_dir/dynamic -type f -mtime +7 -delete
```

## 文件结构

```
.
├── nginx.conf    # Nginx 配置文件
├── index.html    # 代理首页
└── .gitignore
```

## License

[MIT](LICENSE)
