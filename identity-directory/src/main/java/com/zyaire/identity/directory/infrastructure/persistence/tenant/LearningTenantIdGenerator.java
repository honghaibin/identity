package com.zyaire.identity.directory.infrastructure.persistence.tenant;

import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import com.zyaire.identity.directory.application.port.TenantIdGenerator;

@Profile("local")
@Component
public class LearningTenantIdGenerator implements TenantIdGenerator {
    private final TenantMapper mapper;
    public LearningTenantIdGenerator(TenantMapper mapper) { this.mapper = mapper; }
    @Override
    public Long nextId() { return mapper.nextLearningId(); }
}
