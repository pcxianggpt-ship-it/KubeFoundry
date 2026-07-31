package io.kubefoundry.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:schema-test;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.datasource.driver-class-name=org.h2.Driver"
})
class SchemaMigrationTest {

    private static final String DATABASE_URL = "jdbc:h2:mem:schema-test;MODE=PostgreSQL;DB_CLOSE_DELAY=-1";
    private static final List<String> BUSINESS_TABLES = List.of(
            "clusters",
            "nodes",
            "cluster_settings",
            "app_settings",
            "ssh_keys",
            "jobs",
            "job_steps",
            "job_step_nodes",
            "precheck_results",
            "events",
            "node_roles",
            "cluster_components",
            "installation_snapshots");
    private static List<String> h2FilesBeforeTest;

    @BeforeAll
    static void recordDataDirectoryState() throws IOException {
        h2FilesBeforeTest = findH2Files();
    }

    @AfterAll
    static void verifyTestDidNotCreateH2FilesInDataDirectory() throws IOException {
        assertThat(findH2Files()).containsExactlyElementsOf(h2FilesBeforeTest);
    }

    @Test
    void createsAllBusinessTables() throws SQLException {
        try (Connection connection = openConnection()) {
            DatabaseMetaData metadata = connection.getMetaData();

            for (String table : BUSINESS_TABLES) {
                assertThat(tableExists(metadata, table))
                        .as("业务表 %s 应由迁移创建", table)
                        .isTrue();
            }
        }
    }

    @Test
    void recordsSuccessfulV1MigrationInFlywayHistory() throws SQLException {
        try (Connection connection = openConnection()) {
            assertThat(tableExists(connection.getMetaData(), "flyway_schema_history")).isTrue();

            try (var statement = connection.prepareStatement(
                    "SELECT \"success\" FROM \"flyway_schema_history\" WHERE \"version\" = '1'")) {
                try (ResultSet result = statement.executeQuery()) {
                    assertThat(result.next()).isTrue();
                    assertThat(result.getBoolean("success")).isTrue();
                }
            }
        }
    }

    @Test
    void createsForeignKeyFromNodesToClusters() throws SQLException {
        try (Connection connection = openConnection()) {
            try (ResultSet foreignKeys = connection.getMetaData()
                    .getImportedKeys(null, null, "NODES")) {
                boolean clusterForeignKeyExists = false;
                while (foreignKeys.next()) {
                    if ("CLUSTER_ID".equalsIgnoreCase(foreignKeys.getString("FKCOLUMN_NAME"))
                            && "CLUSTERS".equalsIgnoreCase(foreignKeys.getString("PKTABLE_NAME"))) {
                        clusterForeignKeyExists = true;
                        break;
                    }
                }

                assertThat(clusterForeignKeyExists).isTrue();
            }
        }
    }

    @Test
    void makesEventIdAutoIncrementing() throws SQLException {
        try (Connection connection = openConnection()) {
            try (ResultSet columns = connection.getMetaData()
                    .getColumns(null, null, "EVENTS", "ID")) {
                assertThat(columns.next()).isTrue();
                assertThat(columns.getString("IS_AUTOINCREMENT")).isEqualTo("YES");
            }
        }
    }

    @Test
    void addsStableNodeExecutionDiagnosticsInV3() throws SQLException {
        try (Connection connection = openConnection()) {
            DatabaseMetaData metadata = connection.getMetaData();
            assertThat(columnExists(metadata, "JOB_STEP_NODES", "LOG_PATH")).isTrue();
            assertThat(columnExists(metadata, "JOB_STEP_NODES", "EXIT_CODE")).isTrue();
            assertThat(columnExists(metadata, "JOB_STEP_NODES", "MESSAGE")).isTrue();
            try (var statement = connection.prepareStatement(
                    "SELECT \"success\" FROM \"flyway_schema_history\" WHERE \"version\" = '3'")) {
                try (ResultSet result = statement.executeQuery()) {
                    assertThat(result.next()).isTrue();
                    assertThat(result.getBoolean("success")).isTrue();
                }
            }
        }
    }

    @Test
    void createsStructuredPrecheckResultsAndInstallerIndexesInV4AndV5() throws SQLException {
        try (Connection connection = openConnection()) {
            DatabaseMetaData metadata = connection.getMetaData();
            assertThat(columnExists(metadata, "PRECHECK_RESULTS", "CHECK_KEY")).isTrue();
            assertThat(columnExists(metadata, "PRECHECK_RESULTS", "SEVERITY")).isTrue();
            assertThat(columnExists(metadata, "PRECHECK_RESULTS", "STATUS")).isTrue();
            assertThat(successfulMigration(connection, "4")).isTrue();
            assertThat(successfulMigration(connection, "5")).isTrue();
        }
    }

    @Test
    void createsPersistentApplicationSettingsInV6() throws SQLException {
        try (Connection connection = openConnection()) {
            assertThat(successfulMigration(connection, "6")).isTrue();
            assertThat(columnExists(connection.getMetaData(), "APP_SETTINGS", "SETTING_KEY")).isTrue();
            assertThat(columnExists(connection.getMetaData(), "APP_SETTINGS", "SETTING_VALUE")).isTrue();
        }
    }

    @Test
    void createsClusterConfigurationStructuresInV8() throws SQLException {
        try (Connection connection = openConnection()) {
            DatabaseMetaData metadata = connection.getMetaData();
            assertThat(successfulMigration(connection, "8")).isTrue();
            assertThat(columnExists(metadata, "CLUSTERS", "KUBERNETES_WORK_DIR")).isTrue();
            assertThat(columnExists(metadata, "CLUSTERS", "IMAGE_REGISTRY_TYPE")).isTrue();
            assertThat(columnExists(metadata, "NODE_ROLES", "NODE_ID")).isTrue();
            assertThat(columnExists(metadata, "CLUSTER_COMPONENTS", "COMPONENT_KEY")).isTrue();
            assertThat(columnExists(metadata, "INSTALLATION_SNAPSHOTS", "SNAPSHOT_JSON")).isTrue();
        }
    }

    @Test
    void upgradesAnExistingV7DatabaseAndDerivesRegistryRolesSafely() throws SQLException {
        String databaseUrl = "jdbc:h2:mem:schema-v7-incremental;MODE=PostgreSQL;DB_CLOSE_DELAY=-1";
        Flyway.configure()
                .dataSource(databaseUrl, "sa", "")
                .target("7")
                .load()
                .migrate();

        try (Connection connection = DriverManager.getConnection(databaseUrl, "sa", "")) {
            long matchedCluster = insertCluster(connection, "matched", "10.0.0.10", true);
            long unmatchedCluster = insertCluster(connection, "unmatched", "10.0.0.99", true);
            long installedCluster = insertCluster(connection, "installed", "", true);
            insertNode(connection, matchedCluster, "registry-node", "10.0.0.10");
            insertNode(connection, unmatchedCluster, "worker-node", "10.0.0.10");
            insertInstallJob(connection, installedCluster, "success");
        }

        Flyway.configure().dataSource(databaseUrl, "sa", "").load().migrate();

        try (Connection connection = DriverManager.getConnection(databaseUrl, "sa", "")) {
            assertThat(successfulMigration(connection, "8")).isTrue();
            assertThat(countRows(connection, "SELECT COUNT(*) FROM node_roles WHERE role = 'registry'"))
                    .isEqualTo(1);
            assertThat(countRows(connection, "SELECT COUNT(*) FROM node_roles WHERE role = 'registry' "
                    + "AND node_id = (SELECT id FROM nodes WHERE name = 'registry-node')")).isEqualTo(1);
            assertThat(countRows(connection, "SELECT COUNT(*) FROM node_roles WHERE role = 'registry' "
                    + "AND node_id = (SELECT id FROM nodes WHERE name = 'worker-node')")).isZero();
            assertThat(booleanValue(connection, "SELECT installation_locked FROM clusters WHERE name = 'matched'"))
                    .isFalse();
            assertThat(booleanValue(connection, "SELECT installation_locked FROM clusters WHERE name = 'unmatched'"))
                    .isFalse();
            assertThat(booleanValue(connection, "SELECT installation_locked FROM clusters WHERE name = 'installed'"))
                    .isTrue();
        }
    }

    private static long insertCluster(Connection connection, String name, String registryIp, boolean locked)
            throws SQLException {
        try (var statement = connection.prepareStatement(
                "INSERT INTO clusters (name, status, registry_ip, installation_locked) VALUES (?, 'draft', ?, ?)",
                java.sql.Statement.RETURN_GENERATED_KEYS)) {
            statement.setString(1, name);
            statement.setString(2, registryIp);
            statement.setBoolean(3, locked);
            statement.executeUpdate();
            try (ResultSet keys = statement.getGeneratedKeys()) {
                keys.next();
                return keys.getLong(1);
            }
        }
    }

    private static void insertNode(Connection connection, long clusterId, String name, String host)
            throws SQLException {
        try (var statement = connection.prepareStatement(
                "INSERT INTO nodes (cluster_id, name, host, username, node_role, status) "
                        + "VALUES (?, ?, ?, 'root', 'worker', 'draft')")) {
            statement.setLong(1, clusterId);
            statement.setString(2, name);
            statement.setString(3, host);
            statement.executeUpdate();
        }
    }

    private static void insertInstallJob(Connection connection, long clusterId, String status) throws SQLException {
        try (var statement = connection.prepareStatement(
                "INSERT INTO jobs (cluster_id, job_type, status) VALUES (?, 'install', ?)")) {
            statement.setLong(1, clusterId);
            statement.setString(2, status);
            statement.executeUpdate();
        }
    }

    private static long countRows(Connection connection, String sql) throws SQLException {
        try (var statement = connection.prepareStatement(sql); ResultSet result = statement.executeQuery()) {
            result.next();
            return result.getLong(1);
        }
    }

    private static boolean booleanValue(Connection connection, String sql) throws SQLException {
        try (var statement = connection.prepareStatement(sql); ResultSet result = statement.executeQuery()) {
            result.next();
            return result.getBoolean(1);
        }
    }

    private static boolean tableExists(DatabaseMetaData metadata, String table) throws SQLException {
        for (String tableName : List.of(table, table.toUpperCase(), table.toLowerCase())) {
            try (ResultSet tables = metadata.getTables(null, null, tableName, new String[] {"TABLE"})) {
                if (tables.next()) {
                    return true;
                }
            }
        }

        return false;
    }

    private static boolean columnExists(
            DatabaseMetaData metadata, String table, String column) throws SQLException {
        try (ResultSet columns = metadata.getColumns(null, null, table, column)) {
            return columns.next();
        }
    }

    private static Connection openConnection() throws SQLException {
        return DriverManager.getConnection(DATABASE_URL, "sa", "");
    }

    private static boolean successfulMigration(Connection connection, String version) throws SQLException {
        try (var statement = connection.prepareStatement(
                "SELECT \"success\" FROM \"flyway_schema_history\" WHERE \"version\" = ?")) {
            statement.setString(1, version);
            try (ResultSet result = statement.executeQuery()) {
                return result.next() && result.getBoolean("success");
            }
        }
    }

    private static List<String> findH2Files() throws IOException {
        Path dataDirectory = Path.of("data");
        if (Files.notExists(dataDirectory)) {
            return List.of();
        }

        try (var files = Files.list(dataDirectory)) {
            return files
                    .filter(Files::isRegularFile)
                    .map(Path::getFileName)
                    .map(Path::toString)
                    .filter(file -> file.endsWith(".mv.db") || file.endsWith(".trace.db"))
                    .sorted()
                    .toList();
        }
    }
}
