# KubeFoundry v0.2.0 开发进度

## 任务 1：Java 后端骨架与健康检查

- 状态：已完成，待合并。
- Java 运行时：17。
- Spring Boot：3.3.12。
- 健康检查：`GET /api/health` 返回状态和版本信息。
- 默认配置：服务端口为 `10001`，数据目录读取 `KF_DATA_DIR`，默认值为 `data`。
- 验证：已执行健康检查定向测试与 Maven 全量测试。
