package io.kubefoundry.api;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.beans.factory.config.YamlPropertiesFactoryBean;
import org.springframework.core.io.ClassPathResource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.Properties;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class HealthControllerTest {

    @Test
    void getHealthReturnsStatusAndVersion() throws Exception {
        Object healthController = assertDoesNotThrow(() -> {
            Class<?> controllerType = Class.forName("io.kubefoundry.api.HealthController");
            return controllerType.getDeclaredConstructor().newInstance();
        });

        MockMvc mockMvc = MockMvcBuilders.standaloneSetup(healthController).build();

        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.status").value("ok"))
                .andExpect(jsonPath("$.version").value("0.3.2"));
    }

    @Test
    void applicationConfigDefaultsPortAndDataDirectory() {
        ClassPathResource configuration = new ClassPathResource("application.yml");
        assertThat(configuration.exists()).isTrue();

        YamlPropertiesFactoryBean yaml = new YamlPropertiesFactoryBean();
        yaml.setResources(configuration);
        Properties properties = yaml.getObject();

        assertThat(properties)
                .containsEntry("server.port", "10001")
                .containsEntry("kubefoundry.data-dir", "${KF_DATA_DIR:data}");
    }
}
