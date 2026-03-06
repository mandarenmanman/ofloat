# 自建 daprd Docker 镜像

## 背景

项目中 Dapr sidecar 原本使用官方镜像 `daprio/daprd:1.16.9`，但在国内环境下拉取 Docker Hub / gcr.io 镜像经常超时。
同时我们需要使用自编译的 daprd 二进制（从 Dapr 源码构建），以便调试或定制。

解决方案：将自编译的 daprd 打包成 Docker 镜像，推送到本地 registry（`localhost:15000`），Nomad Job 直接从本地拉取。

## 文件说明

```
nomad/daprd/
├── Dockerfile          # 基于 scratch，仅包含 daprd 二进制
├── build-and-push.ps1  # 构建并推送到本地 registry 的脚本
├── daprd               # 自编译的 daprd 二进制（已 gitignore，不入库）
└── README.md           # 本文档
```

## 编译 daprd

在 Linux 机器（或 WSL）上从 Dapr 源码编译，只需要 `daprd` 一个组件：

```bash
git clone https://github.com/dapr/dapr.git /tmp/dapr
cd /tmp/dapr
make build DAPR_BINARY=daprd TARGET_OS=linux TARGET_ARCH=amd64
# 产物在 /tmp/dapr/dist/linux_amd64/release/daprd
```

编译完成后将 `daprd` 二进制复制到 `nomad/daprd/` 目录下。

## 构建并推送镜像

前提：WSL 中 Docker 已运行，本地 registry（`localhost:15000`）已部署。

```powershell
# 默认使用 nomad/daprd/daprd 二进制
.\nomad\daprd\build-and-push.ps1

# 指定二进制路径
.\nomad\daprd\build-and-push.ps1 -DaprdBin "C:\path\to\daprd"

# 指定 tag
.\nomad\daprd\build-and-push.ps1 -Tag "1.16.9-custom"
```

推送成功后镜像地址为 `localhost:15000/daprd:latest`。

## 在 Nomad Job 中使用

将 sidecar task 的镜像从官方改为本地：

```hcl
# 之前
image = "daprio/daprd:1.16.9"

# 改为
image = "localhost:15000/daprd:latest"
```

## 关于 scratch 基础镜像

Dockerfile 使用 `FROM scratch`（空镜像），原因：
- daprd 是 Go 静态编译的二进制（CGO_ENABLED=0），不依赖 glibc
- 不需要 shell、包管理器等系统工具
- 镜像体积最小（仅 daprd 二进制本身约 100MB，无额外开销）

局限性：scratch 不包含 CA 证书（`/etc/ssl/certs`），如果 daprd 需要发起 HTTPS 外部请求会失败。
当前场景中 daprd 只连接本地 Redis、placement、Spin app，全部走 HTTP localhost，不受影响。

## 从 Git 历史中清除大文件

daprd 二进制约 218MB，曾误提交到 Git。清除步骤记录如下：

```bash
# 1. 暂存当前修改
git stash

# 2. 从指定 commit 范围内移除大文件
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch nomad/daprd/daprd" \
  -- <大文件首次出现的前一个commit>..HEAD

# 3. 清理引用和回收空间
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# 4. 恢复暂存
git stash pop

# 5. 推送（历史已改写，需要 force push）
git push --force-with-lease
```

`.gitignore` 中已添加 `nomad/daprd/daprd`，防止再次误提交。
