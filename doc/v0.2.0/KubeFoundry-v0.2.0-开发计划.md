# KubeFoundry v0.2.0 开发计划

> **面向自动化开发代理：** 实施本计划时必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，逐任务执行并在任务间评审。所有步骤使用复选框跟踪。

**目标：** 用 Spring Boot 3、Java 17、H2 和 Apache MINA SSHD 替换 Python 后端，并交付流水线式部署 UI、Java SSH 免密、独立安装执行页及双架构离线包。

**架构：** 新建 `web/backend-java/` 模块，按集群配置、凭据、SSH、任务和安装编排划分边界；Vue 前端保持 `/api/*` 契约并拆分现有单文件页面。迁移期保留 Python 后端作为接口参考，Java 端达到契约和发布验收后，打包入口切换到 Java。

**技术栈：** Java 17、Spring Boot 3、Spring Data JPA、H2、Flyway、Apache MINA SSHD、JUnit 5、Vue 3、Element Plus、Vitest、Vite、SSE、Bash。

## 全局约束

- Java 运行版本固定为 17，Spring Boot 使用 3.x 稳定版本并锁定 Maven 依赖。
- H2 使用文件模式，v0.2.0 不迁移 v0.1.0 SQLite 数据。
- 节点密码使用 AES-256-GCM 加密，API、日志、SSE 和配置快照不得包含密码或私钥。
- SSH 使用 Apache MINA SSHD，不依赖系统 `ssh`、`scp`、`sshpass` 或 `expect`。
- 前端继续使用 Vue 3 + Element Plus，内部状态使用英文枚举，可见状态使用中文。
- 安装步骤之间默认串行，同一步骤内按节点受控并发。
- 继续复用 `scripts/steps/`，不得在 Java 中重写具体系统安装命令。
- 所有文本文件使用 LF；代码变更必须同步测试和 `doc/v0.2.0/` 文档。
- Git 提交信息使用中文。

---

## 任务 1：建立 Java 后端骨架与健康检查

**文件：**

- 创建：`web/backend-java/pom.xml`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/KubeFoundryApplication.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/api/HealthController.java`
- 创建：`web/backend-java/src/main/resources/application.yml`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/api/HealthControllerTest.java`

**产出接口：** `GET /api/health` 返回 `{"status":"ok","version":"0.2.0"}`。

- [ ] **步骤 1：先写失败的健康检查测试**

```java
@SpringBootTest
@AutoConfigureMockMvc
class HealthControllerTest {
    @Autowired MockMvc mvc;

    @Test
    void returnsVersionedHealthStatus() throws Exception {
        mvc.perform(get("/api/health"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("ok"))
            .andExpect(jsonPath("$.version").value("0.2.0"));
    }
}
```

- [ ] **步骤 2：运行测试并确认失败**

运行：`cd web/backend-java && mvn -q -Dtest=HealthControllerTest test`

预期：FAIL，应用类或控制器尚不存在。

- [ ] **步骤 3：创建最小 Spring Boot 应用和配置**

`pom.xml` 至少锁定 `spring-boot-starter-web`、`spring-boot-starter-validation`、`spring-boot-starter-test`，并通过 `<maven.compiler.release>17</maven.compiler.release>` 固定 Java 版本。`application.yml` 默认监听 `10001`，数据目录从 `KF_DATA_DIR` 读取。

- [ ] **步骤 4：实现健康检查并运行全部 Java 测试**

运行：`cd web/backend-java && mvn test`

预期：BUILD SUCCESS。

- [ ] **步骤 5：提交**

```bash
git add web/backend-java
git commit -m "后端：建立Java服务骨架与健康检查"
```

## 任务 2：建立 H2 数据库与版本迁移

**文件：**

- 修改：`web/backend-java/pom.xml`
- 修改：`web/backend-java/src/main/resources/application.yml`
- 创建：`web/backend-java/src/main/resources/db/migration/V1__initial_schema.sql`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/persistence/SchemaMigrationTest.java`

**产出接口：** H2 文件库包含 `clusters`、`nodes`、`cluster_settings`、`ssh_keys`、`jobs`、`job_steps`、`job_step_nodes`、`events` 和 Flyway 历史表。

- [ ] **步骤 1：写数据库迁移失败测试**

```java
@SpringBootTest(properties = "spring.datasource.url=jdbc:h2:mem:schema-test;MODE=PostgreSQL")
class SchemaMigrationTest {
    @Autowired JdbcTemplate jdbc;

    @Test
    void createsRequiredTables() {
        Integer count = jdbc.queryForObject(
            "select count(*) from information_schema.tables where table_name='CLUSTERS'",
            Integer.class);
        assertThat(count).isEqualTo(1);
    }
}
```

- [ ] **步骤 2：运行测试并确认缺少表**

运行：`cd web/backend-java && mvn -q -Dtest=SchemaMigrationTest test`

预期：FAIL，`CLUSTERS` 不存在。

- [ ] **步骤 3：加入 H2、JPA、Flyway 并创建 V1 迁移**

字段状态使用 `varchar` 保存稳定英文枚举；所有表包含创建和更新时间；外键按集群、任务级联删除，日志文件本身不存入数据库。

- [ ] **步骤 4：验证文件模式和内存测试模式**

运行：`cd web/backend-java && mvn test`

预期：迁移测试通过，测试结束后不在仓库产生数据库文件。

- [ ] **步骤 5：提交**

```bash
git add web/backend-java
git commit -m "存储：建立H2数据库与版本迁移"
```

## 任务 3：实现凭据加密与主密钥管理

**文件：**

- 创建：`web/backend-java/src/main/java/io/kubefoundry/credential/MasterKeyProvider.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/credential/AesGcmCredentialCipher.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/credential/EncryptedCredential.java`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/credential/AesGcmCredentialCipherTest.java`

**产出接口：**

```java
EncryptedCredential encrypt(char[] plaintext);
char[] decrypt(EncryptedCredential credential);
SecretKey loadOrCreate(Path dataDir);
```

- [ ] **步骤 1：写加密往返、随机 IV 和错误密钥测试**

```java
@Test
void encryptsWithUniqueIvAndRejectsWrongKey() {
    var first = cipher.encrypt("Kylin123".toCharArray());
    var second = cipher.encrypt("Kylin123".toCharArray());
    assertThat(first.iv()).isNotEqualTo(second.iv());
    assertThat(cipher.decrypt(first)).isEqualTo("Kylin123".toCharArray());
    assertThatThrownBy(() -> wrongKeyCipher.decrypt(first))
        .isInstanceOf(CredentialDecryptionException.class);
}
```

- [ ] **步骤 2：确认测试失败后实现 AES/GCM/NoPadding**

主密钥为 256 位；IV 为 12 字节随机值；解密后的 `char[]` 使用后立即覆盖；异常不得包含明文或密文。

- [ ] **步骤 3：实现 `data/secrets/master.key` 首次创建与权限检查**

Linux 上创建后设置仅所有者读写权限；现有文件权限过宽时拒绝启动并输出中文修复建议。

- [ ] **步骤 4：运行凭据测试和密钥文件测试**

运行：`cd web/backend-java && mvn -q -Dtest='*Credential*Test,*MasterKey*Test' test`

预期：全部 PASS。

- [ ] **步骤 5：提交**

```bash
git add web/backend-java
git commit -m "安全：实现节点凭据加密与主密钥管理"
```

## 任务 4：实现集群、节点和复制节点 API

**文件：**

- 创建：`web/backend-java/src/main/java/io/kubefoundry/cluster/Cluster.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/cluster/Node.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/cluster/ClusterRepository.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/cluster/NodeRepository.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/cluster/ClusterService.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/api/ClusterController.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/api/NodeController.java`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/api/ClusterNodeApiTest.java`

**产出接口：** 保持设计文档中的集群、节点 CRUD 和 `/nodes/copy` 路径。

- [ ] **步骤 1：写 API 契约测试**

测试创建集群、添加节点、更新节点时保留空密码、API 只返回 `hasPassword`，以及复制节点后凭据存在但指纹、免密和测试状态清空。

- [ ] **步骤 2：运行契约测试并确认 404 或 Bean 缺失**

运行：`cd web/backend-java && mvn -q -Dtest=ClusterNodeApiTest test`

- [ ] **步骤 3：实现实体、仓储、DTO 和服务**

控制器禁止直接返回 JPA 实体。复制方法固定签名：

```java
public NodeResponse copyNode(long clusterId, long sourceNodeId)
```

复制结果设置 `draft=true`、`testStatus=PENDING`，并清空主机绑定字段。

- [ ] **步骤 4：运行测试并对照 v0.1.0 前端请求格式**

运行：`cd web/backend-java && mvn test`

预期：API 测试通过，JSON 中不存在 `password`、`ciphertext`、`privateKey`。

- [ ] **步骤 5：提交**

```bash
git add web/backend-java
git commit -m "后端：实现集群与节点配置接口"
```

## 任务 5：实现 Java SSH 客户端基础能力

**文件：**

- 修改：`web/backend-java/pom.xml`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/ssh/SshClientFactory.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/ssh/SshConnectionSpec.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/ssh/SshCommandResult.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/ssh/SshService.java`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/ssh/SshServiceTest.java`

**产出接口：**

```java
SshSession connectWithPassword(SshConnectionSpec spec, char[] password);
SshSession connectWithKey(SshConnectionSpec spec, KeyPair keyPair);
SshCommandResult execute(SshSession session, String command, Duration timeout);
void upload(SshSession session, Path local, String remotePath);
```

- [ ] **步骤 1：建立测试 SSH 服务器并写密码、公钥、命令和 SFTP 测试**

测试服务只监听回环随机端口，不使用生产密码；同时验证超时和认证失败映射为稳定异常类型。

- [ ] **步骤 2：运行测试确认实现缺失**

运行：`cd web/backend-java && mvn -q -Dtest=SshServiceTest test`

- [ ] **步骤 3：加入 Apache MINA SSHD 并实现连接生命周期**

每次会话必须显式关闭；连接、认证、命令分别设置超时；标准输出和错误输出设置最大采集尺寸，超限写入日志文件。

- [ ] **步骤 4：验证项目不调用系统 SSH 工具**

运行：`rg -n "ProcessBuilder.*(ssh|scp|sshpass|expect)|Runtime.getRuntime" web/backend-java/src`

预期：无匹配。

- [ ] **步骤 5：运行全部测试并提交**

```bash
cd web/backend-java && mvn test
git add web/backend-java
git commit -m "SSH：实现Java连接命令与文件传输"
```

## 任务 6：实现主机指纹和集群 SSH 密钥

**文件：**

- 创建：`web/backend-java/src/main/java/io/kubefoundry/ssh/HostFingerprintVerifier.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/ssh/ClusterKeyService.java`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/ssh/HostFingerprintVerifierTest.java`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/ssh/ClusterKeyServiceTest.java`

**产出接口：** 首次连接记录 SHA-256 指纹，后续变化抛出 `HostFingerprintChangedException`；每集群创建并复用 Ed25519 密钥对。

- [ ] **步骤 1：写首次接受、重复接受、指纹变化拒绝测试**
- [ ] **步骤 2：写 Ed25519 密钥创建、复用和私钥不明文落库测试**
- [ ] **步骤 3：运行测试确认失败**

运行：`cd web/backend-java && mvn -q -Dtest='HostFingerprintVerifierTest,ClusterKeyServiceTest' test`

- [ ] **步骤 4：实现指纹校验和密钥服务**

指纹变化错误消息包含节点名、旧指纹、新指纹和人工确认建议，不自动覆盖旧指纹。

- [ ] **步骤 5：运行测试并提交**

```bash
cd web/backend-java && mvn test
git add web/backend-java
git commit -m "SSH：实现主机指纹与集群密钥管理"
```

## 任务 7：实现任务、步骤、事件和受控并发

**文件：**

- 创建：`web/backend-java/src/main/java/io/kubefoundry/job/JobService.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/job/JobExecutor.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/job/EventService.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/api/JobController.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/api/JobEventController.java`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/job/JobExecutorTest.java`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/api/JobEventApiTest.java`

**产出接口：** `submit(JobDefinition)` 返回任务 ID；SSE 支持最后事件 ID；应用启动时把遗留 `running` 任务改为 `interrupted`。

- [ ] **步骤 1：写并发上限、部分失败汇总和启动中断恢复测试**
- [ ] **步骤 2：写 SSE 顺序、断线续传和心跳测试**
- [ ] **步骤 3：运行测试确认失败**

运行：`cd web/backend-java && mvn -q -Dtest='JobExecutorTest,JobEventApiTest' test`

- [ ] **步骤 4：实现有界线程池和事务状态更新**

默认工作线程 5，队列容量 100；拒绝新任务时返回中文“任务队列已满，请稍后重试”，不得静默丢弃。

- [ ] **步骤 5：运行测试并提交**

```bash
cd web/backend-java && mvn test
git add web/backend-java
git commit -m "任务：实现状态机并发执行与SSE事件"
```

## 任务 8：实现“测试全部节点”免密配置

**文件：**

- 创建：`web/backend-java/src/main/java/io/kubefoundry/ssh/NodeTestService.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/ssh/AuthorizedKeysService.java`
- 修改：`web/backend-java/src/main/java/io/kubefoundry/api/NodeController.java`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/ssh/NodeTestServiceTest.java`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/api/NodeTestApiTest.java`

**产出接口：** `POST /api/clusters/{clusterId}/node-test` 和 `POST /api/nodes/{nodeId}/node-test`。

- [ ] **步骤 1：写状态序列和幂等公钥写入测试**

断言事件顺序为 `password_connecting -> key_installing -> key_verifying -> success`；重复测试不会重复写入同一公钥。

- [ ] **步骤 2：写部分失败、只重试失败节点和日志脱敏测试**
- [ ] **步骤 3：运行测试确认失败**

运行：`cd web/backend-java && mvn -q -Dtest='NodeTestServiceTest,NodeTestApiTest' test`

- [ ] **步骤 4：实现密码连接、公钥追加、私钥复连和环境探测**

环境探测返回主机名、`/etc/os-release` 和 `uname -m`；命令失败时保留具体节点和阶段，但不输出认证数据。

- [ ] **步骤 5：运行全部测试和敏感词扫描后提交**

```bash
cd web/backend-java && mvn test
bash scripts/ci/check-secrets.sh
git add web/backend-java
git commit -m "节点：实现Java免密配置与并发测试"
```

## 任务 9：迁移安装计划、预检查和 Bash 步骤执行

**文件：**

- 创建：`web/backend-java/src/main/java/io/kubefoundry/installer/InstallPlan.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/installer/InstallStep.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/installer/InstallPlanFactory.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/installer/RuntimeEnvRenderer.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/installer/RemoteStepRunner.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/installer/PrecheckService.java`
- 创建：`web/backend-java/src/main/java/io/kubefoundry/installer/InstallService.java`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/installer/InstallPlanFactoryTest.java`
- 创建：`web/backend-java/src/test/java/io/kubefoundry/installer/RemoteStepRunnerTest.java`

**产出接口：** 生成与 v0.1.0 等价的步骤顺序、节点范围和 `runtime.env`，通过 SFTP 分发并远程执行现有脚本。

- [ ] **步骤 1：把现有 Python 安装计划行为固化为 Java 测试样例**

至少覆盖 `13-install-k8s-deps`、`16-install-containerd` 并发，以及控制面初始化和控制节点加入串行。

- [ ] **步骤 2：写 Shell 安全转义和 runtime.env 渲染测试**
- [ ] **步骤 3：运行测试确认失败**

运行：`cd web/backend-java && mvn -q -Dtest='InstallPlanFactoryTest,RemoteStepRunnerTest' test`

- [ ] **步骤 4：实现最小安装闭环**

远端目录固定为 `/tmp/kubefoundry/{jobId}/`；执行命令固定采用 `bash -lc`；每节点日志写入 `data/jobs/{jobId}/logs/{stepKey}/{hostname}.log`。

- [ ] **步骤 5：用本地假 SSH 服务验证步骤分发、退出码和失败汇总**

运行：`cd web/backend-java && mvn test`

- [ ] **步骤 6：提交**

```bash
git add web/backend-java
git commit -m "安装：迁移预检查与Bash步骤编排"
```

## 任务 10：拆分前端并建立流水线布局

**文件：**

- 修改：`web/frontend/package.json`
- 修改：`web/frontend/src/App.vue`
- 创建：`web/frontend/src/router.js`
- 创建：`web/frontend/src/layouts/AppShell.vue`
- 创建：`web/frontend/src/components/deployment/DeploymentPipeline.vue`
- 创建：`web/frontend/src/views/ClusterListView.vue`
- 创建：`web/frontend/src/views/ClusterWorkspaceView.vue`
- 创建：`web/frontend/src/components/deployment/DeploymentPipeline.test.js`
- 创建：`web/frontend/src/views/ClusterListView.test.js`

**产出接口：** 首页按状态直接跳转；集群空间显示五阶段流水线；路由状态可刷新恢复。

- [ ] **步骤 1：写流水线中文阶段和状态入口测试**

测试 `配置未完成 -> 继续配置`、`预检查通过 -> 开始安装`、`正在安装 -> 查看进度`、`失败 -> 查看失败原因`、`成功 -> 查看集群`。

- [ ] **步骤 2：运行 Vitest 确认组件不存在**

运行：`cd web/frontend && npm test -- DeploymentPipeline.test.js ClusterListView.test.js`

- [ ] **步骤 3：引入 Vue Router 并实现应用框架和流水线组件**

流水线阶段固定使用 `cluster-info`、`nodes`、`settings`、`precheck`、`install`；可见标题使用中文。

- [ ] **步骤 4：运行组件测试和生产构建**

```bash
cd web/frontend
npm test
npm run build
```

预期：测试与构建通过，无控制台错误。

- [ ] **步骤 5：提交**

```bash
git add web/frontend
git commit -m "前端：建立流水线部署布局与首页入口"
```

## 任务 11：实现节点配置与中文免密状态

**文件：**

- 创建：`web/frontend/src/views/NodeConfigView.vue`
- 创建：`web/frontend/src/components/nodes/NodeTable.vue`
- 创建：`web/frontend/src/components/nodes/NodeEditor.vue`
- 创建：`web/frontend/src/components/nodes/NodeTestActivity.vue`
- 修改：`web/frontend/src/api/client.js`
- 创建：`web/frontend/src/views/NodeConfigView.test.js`

**产出接口：** 节点增删改复制、加密密码占位、测试全部节点、失败重试和逐节点中文状态。

- [ ] **步骤 1：写复制密码语义和状态映射测试**

编辑已有密码时空输入不发送 `password`；复制结果显示“密码已保存”；英文枚举映射为设计文档中的中文状态。

- [ ] **步骤 2：写测试任务 SSE 更新表格状态测试**
- [ ] **步骤 3：运行测试确认失败**

运行：`cd web/frontend && npm test -- NodeConfigView.test.js`

- [ ] **步骤 4：实现节点页面、编辑器和活动日志**

主操作固定为“测试全部节点”；失败消息必须包含原因和“编辑节点”或“重试失败节点”入口。

- [ ] **步骤 5：运行测试和构建后提交**

```bash
cd web/frontend && npm test && npm run build
git add web/frontend
git commit -m "前端：实现节点配置与免密测试状态"
```

## 任务 12：实现预检查跳转和独立安装执行页

**文件：**

- 创建：`web/frontend/src/views/PrecheckView.vue`
- 创建：`web/frontend/src/views/InstallConfirmView.vue`
- 创建：`web/frontend/src/views/JobExecutionView.vue`
- 创建：`web/frontend/src/components/jobs/JobStageList.vue`
- 创建：`web/frontend/src/components/jobs/NodeExecutionTable.vue`
- 创建：`web/frontend/src/components/jobs/LiveLogViewer.vue`
- 修改：`web/frontend/src/router.js`
- 创建：`web/frontend/src/views/InstallFlow.test.js`

**产出接口：** 预检查成功自动跳转，安装必须人工确认；执行页支持快照加载、SSE 更新和刷新恢复。

- [ ] **步骤 1：写预检查成功跳转但不调用安装 API 的测试**
- [ ] **步骤 2：写点击“开始安装”后进入 `/jobs/{jobId}/execution` 的测试**
- [ ] **步骤 3：写刷新时先读快照再订阅 SSE 的测试**
- [ ] **步骤 4：运行测试确认失败**

运行：`cd web/frontend && npm test -- InstallFlow.test.js`

- [ ] **步骤 5：实现确认页、执行页、节点状态和日志过滤**
- [ ] **步骤 6：运行全部前端测试和构建**

运行：`cd web/frontend && npm test && npm run build`

- [ ] **步骤 7：提交**

```bash
git add web/frontend
git commit -m "前端：实现预检查跳转与安装执行页"
```

## 任务 13：完成 Java API 契约和端到端验收

**文件：**

- 创建：`web/backend-java/src/test/java/io/kubefoundry/api/ApiContractTest.java`
- 创建：`web/frontend/src/api/client.contract.test.js`
- 创建：`scripts/tests/test_java_web_smoke.sh`
- 修改：`doc/api.md`
- 创建：`doc/v0.2.0/KubeFoundry-v0.2.0-验收清单.md`

**产出接口：** 前端不再依赖 Python 专有响应；健康、集群、节点、任务、SSE 和日志接口通过契约与冒烟测试。

- [ ] **步骤 1：列出前端使用的全部 API 并写契约测试**
- [ ] **步骤 2：启动 Java 后端和 Vite 代理执行冒烟测试**

运行：

```bash
cd web/backend-java && mvn spring-boot:run
cd web/frontend && npm run dev
bash scripts/tests/test_java_web_smoke.sh
```

预期：健康检查、创建集群、添加节点、任务查询和 SSE 均返回预期状态码。

- [ ] **步骤 3：更新 API 文档和 v0.2.0 验收清单**
- [ ] **步骤 4：运行 Java、前端和 Bash 测试**

```bash
cd web/backend-java && mvn test
cd web/frontend && npm test && npm run build
bash scripts/tests/test_cli_routing.sh
bash scripts/ci/check-lf.sh
bash scripts/ci/check-secrets.sh
```

- [ ] **步骤 5：提交**

```bash
git add web/backend-java web/frontend scripts/tests doc/api.md doc/v0.2.0
git commit -m "测试：完成Java接口契约与Web闭环验收"
```

## 任务 14：切换双架构离线打包与部署

**文件：**

- 修改：`package.sh`
- 修改：`deploy.sh`
- 修改：`scripts/tests/test_web_package_deploy.sh`
- 创建：`scripts/build/build-jre.sh`
- 创建：`doc/v0.2.0/KubeFoundry-v0.2.0-部署手册.md`
- 修改：`README.md`

**产出接口：** `dist/kubefoundry-web-v0.2.0-{x86_64|aarch64}.tar.gz`，包含精简 JRE、Java JAR、前端、脚本和校验文件。

- [ ] **步骤 1：先修改打包测试声明目标结构**

归档必须包含：

```text
runtime/bin/java
app/kubefoundry.jar
web/index.html
scripts/steps/
deploy.sh
VERSION
SHA256SUMS
```

- [ ] **步骤 2：运行测试确认仍输出 Python 包结构**

运行：`KF_PACKAGE_TEST_MODE=1 bash package.sh`

预期：FAIL，缺少 Java 运行时和 JAR。

- [ ] **步骤 3：实现 Maven 构建、前端构建、jlink 和按架构归档**

构建机显式指定 `KF_TARGET_ARCH=x86_64` 或 `KF_TARGET_ARCH=aarch64`；禁止将一个架构的 JRE 标记成另一个架构。

- [ ] **步骤 4：修改部署脚本和 systemd 服务**

`ExecStart` 使用 `${APP_DIR}/runtime/bin/java -jar ${APP_DIR}/app/kubefoundry.jar`；环境变量至少包含 `KF_DATA_DIR`、`KF_LOG_DIR` 和监听端口；移除 Python 和 Gunicorn 检查。

- [ ] **步骤 5：运行测试模式打包和部署测试**

```bash
KF_PACKAGE_TEST_MODE=1 KF_TARGET_ARCH=x86_64 bash package.sh
bash scripts/tests/test_web_package_deploy.sh
```

- [ ] **步骤 6：在 x86_64 和 ARM64 真实环境分别验证**

每个架构执行部署、`GET /api/health`、H2 文件创建、SSH 测试服务器连接、前端加载和服务重启恢复。结果记录到验收清单，不用一个架构的结果代替另一个架构。

- [ ] **步骤 7：更新部署文档并运行最终检查**

```bash
cd web/backend-java && mvn clean test package
cd web/frontend && npm test && npm run build
bash scripts/ci/check-lf.sh
bash scripts/ci/check-secrets.sh
git diff --check
```

- [ ] **步骤 8：提交**

```bash
git add package.sh deploy.sh scripts README.md doc/v0.2.0
git commit -m "发布：切换v0.2.0 Java双架构离线包"
```

## 里程碑与执行顺序

1. **M1 Java 基础可运行：** 完成任务 1 至 4，具备 H2、加密和配置 API。
2. **M2 Java SSH 闭环：** 完成任务 5 至 8，不依赖 `sshpass` 完成免密配置。
3. **M3 安装编排闭环：** 完成任务 9，Java 可执行核心 Bash 步骤。
4. **M4 新 UI 闭环：** 完成任务 10 至 12，流水线、首页直达和独立安装页可用。
5. **M5 发布验收：** 完成任务 13 至 14，切换 Java 发布包并完成双架构验证。

每个里程碑完成后运行该阶段全部测试并进行代码评审。M5 验收通过前保留 `web/backend/`，但 `package.sh` 在 M5 完成后只打包 Java 后端。
