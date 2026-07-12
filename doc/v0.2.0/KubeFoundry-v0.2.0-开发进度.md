# KubeFoundry v0.2.0 开发进度

## 任务 1：Java 后端骨架与健康检查

- 状态：已完成，待合并。
- Java 运行时：17。
- Spring Boot：3.3.12。
- 健康检查：`GET /api/health` 返回状态和版本信息。
- 默认配置：服务端口为 `10001`，数据目录读取 `KF_DATA_DIR`，默认值为 `data`。
- 验证：已执行健康检查定向测试与 Maven 全量测试。

## 任务 2：H2 数据库与版本迁移

- 状态：已完成。
- 持久化：使用 Spring Data JPA、Flyway 和 H2；生产环境默认将 H2 文件存储在 `${KF_DATA_DIR:data}` 下。
- 迁移：V1 创建 clusters、nodes、cluster_settings、ssh_keys、jobs、job_steps、job_step_nodes 和 events 业务表，使用 Flyway 默认历史表。
- 约束：状态字段使用 `varchar`，业务表包含创建和更新时间；日志仅保存路径，集群和任务关联使用外键级联删除。
- 验证：SchemaMigrationTest 覆盖迁移表、Flyway V1、nodes.cluster_id 外键、events.id 自增和测试不写入 data 目录。

## 任务 3：凭据加密与主密钥管理

- 状态：已完成，待合并。
- 凭据加密：使用 Java 标准库 AES-256-GCM，每条凭据使用独立的 12 字节随机 IV 和 128 位认证标签；密文与 IV 以 Base64 保存，当前格式版本为 1。
- 主密钥：首次使用时在 `${KF_DATA_DIR:data}/secrets/master.key` 创建 256 位 AES 主密钥，后续调用复用；密钥文件使用 Base64，不写入 H2。
- 权限与安全：威胁模型假设当前服务账户是 `secrets` 的唯一写者，同账户恶意进程不在 v0.2.0 防护范围。主密钥仅支持同时提供 POSIX 权限和 `SecureDirectoryStream` 的文件系统；`dataDir` 与 `secrets` 必须为当前服务账户所有、非符号链接且精确 `rwx------`。新建目录原子设置并复核 `0700`，密钥文件在写入前复核为 `rw-------`；无法验证时失败关闭。已有目录或文件权限过宽、所有者不符、符号链接、身份变化或无法提供 `fileKey` 时均拒绝加载；清理仅删除仍与创建时 `fileKey` 相同的空密钥文件。
