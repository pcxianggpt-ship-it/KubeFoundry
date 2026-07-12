package io.kubefoundry.credential;

import java.nio.file.Path;
import javax.crypto.SecretKey;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Lazy;

@Configuration
public class CredentialConfiguration {

    @Bean
    @Lazy
    public AesGcmCredentialCipher credentialCipher(
            @Value("${kubefoundry.data-dir:data}") String dataDirectory) {
        SecretKey masterKey = new MasterKeyProvider().loadOrCreate(Path.of(dataDirectory));
        return new AesGcmCredentialCipher(masterKey);
    }
}
