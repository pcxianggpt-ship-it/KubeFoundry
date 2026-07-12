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
