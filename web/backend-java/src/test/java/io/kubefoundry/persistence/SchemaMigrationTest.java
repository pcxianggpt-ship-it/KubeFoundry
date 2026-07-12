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
            "ssh_keys",
            "jobs",
            "job_steps",
            "job_step_nodes",
            "events");
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

    private static Connection openConnection() throws SQLException {
        return DriverManager.getConnection(DATABASE_URL, "sa", "");
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
