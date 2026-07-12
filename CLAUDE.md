# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

KubeFoundry 是一个用于自动化部署 Kubernetes 的项目，提供一键安装工具。

## 项目架构

- **技术栈：** 纯 Bash 脚本
- **配置管理：** YAML 格式（使用 yq 工具解析）
- **执行方式：** 管理节点通过 SSH/SCP 向各节点分发命令和文件
- **设计模式：** 模块化脚本，每个步骤独立

## 项目结构

```
KubeFoundry/
├── scripts/                    # 脚本目录
│   ├── main.sh               # 主入口脚本
│   ├── lib/                  # 公共函数库
│   │   ├── tools.sh          # 工具检查与安装（yq/helm）
│   │   ├── logger.sh        # 日志函数
│   │   ├── config.sh        # 配置解析
│   │   ├── ssh.sh          # SSH/SCP 操作
│   │   ├── exec.sh          # 批量执行（命令）
│   │   ├── exec_script.sh   # 批量执行（脚本）
│   │   ├── rollback.sh     # 回滚操作
│   │   └── validator.sh     # 验证函数
│   ├── steps/               # 各步骤脚本
│   └── verify/              # 验证脚本
├── config/                    # 配置文件
│   └── cluster.yaml         # 集群配置
├── templates/                 # 模板文件
└── doc/                      # 文档目录
    ├── cmdlist.md           # 原始命令清单
    ├── design.md            # 设计文档
    └── api.md               # 接口文档
```

## 开发规范

### 文件格式规范

**重要：所有生成的文件必须使用 Linux LF 换行符格式**

#### 1. 文件换行符格式

- **要求：** 所有文本文件（脚本、配置文件、文档）必须使用 LF（`\n`）换行符
- **禁止：** 使用 Windows CRLF（`\r\n`）换行符
- **适用文件类型：**
  - `.sh` - Bash 脚本文件
  - `.yaml` / `.yml` - YAML 配置文件
  - `.md` - Markdown 文档文件
  - `.toml` - TOML 配置文件
  - `.conf` - 系统配置文件

#### 2. 写入文件时指定 LF 格式

**正确方式（使用 Write 工具时）：**

```bash
# Write 工具会自动使用 LF 格式，无需额外处理
Write("path/to/file.sh", content_with_lf)
```


#### 3. 验证文件格式

**使用 file 命令验证：**
```bash
file script.sh
# 输出示例：script.sh: ASCII text, with no line terminators (或 LF)
```

**检查换行符类型：**
```bash
# 查看文件的十六进制
hexdump -C file.sh | head -5
# LF: 0a
# CRLF: 0d 0a

# 或使用 cat -A
cat -A file.sh
# LF: 行尾显示 $
# CRLF: 行尾显示 ^M$
```

### 依赖选择原则

为了提升离线部署、老旧 Linux 发行版和多架构环境的兼容性，代码实现应优先采用最小依赖策略：

- 优先使用标准库、系统内置工具和项目已有依赖。
- 新增第三方依赖前必须评估是否必要，避免为了简单功能引入大型依赖。
- 避免引入原生扩展依赖、平台相关二进制包或需要编译步骤的依赖。
- 如必须新增依赖，应优先选择纯 Bash、纯 Python 或其他跨平台稳定的实现。
- 新增依赖后必须同步更新打包脚本、测试和文档，并验证离线部署包可用。

### 代码规范

#### 1. 脚本规范

**文件头注释：**
```bash
#!/bin/bash

#===============================================================================
# 脚本名称：xxx.sh
# 功能：xxxx
# 作者：KubeFoundry Team
# 版本：1.0.0
#===============================================================================
```

**函数命名：**
- 私有函数：使用下划线前缀（`_private_func`）
- 公共函数：使用描述性名称（`exec_on_workers`）

**变量命名：**
- 全局变量：大写下划线（`GLOBAL_VAR`）
- 局部变量：小写下划线（`local_var`）
- 常量：大写（`MAX_RETRIES`）

**日志输出：**
- 使用统一的日志函数：`log_info`, `log_success`, `log_warn`, `log_error`
- 所有日志必须同时输出到终端和日志文件

**错误处理：**
- 所有函数必须返回退出码（0 成功，非 0 失败）
- 关键操作必须检查返回值
- 失败时必须输出详细的错误信息

#### 2. 文档规范

**Markdown 格式：**
- 使用标准的 Markdown 语法
- 代码块使用三个反引号包裹
- 表格使用 Markdown 表格语法
- 标题层级清晰（最多 3 级）
- `doc/` 和 `docs/` 目录下的文档文件必须使用中文名称
- `doc/` 和 `docs/` 目录下的文档必须按版本创建独立目录归档，例如 `v0.1.0/文档名称.md`



## 文档参考

- **设计文档：** [doc/design.md](./doc/design.md) - 整体架构和流程设计
- **接口文档：** [doc/api.md](./doc/api.md) - 所有公共函数接口定义
- **命令清单：** [doc/cmdlist.md](./doc/cmdlist.md) - 手动安装命令参考

## 注意事项

1. **文件格式：** 所有文件必须使用 LF 换行符
2. **日志输出：** 使用统一的日志函数
3. **错误处理：** 必须检查命令返回值
4. **代码可读性：** 使用有意义的变量和函数名
5. **文档同步：** 代码修改后必须同步更新文档
6. **测试覆盖：** 新功能必须包含测试和验证

## 版本历史

- **v1.0.0** (2026-03-22): 初始版本，确定项目架构和开发规范
