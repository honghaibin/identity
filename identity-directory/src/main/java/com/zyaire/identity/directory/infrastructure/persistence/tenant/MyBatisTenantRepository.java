package com.zyaire.identity.directory.infrastructure.persistence.tenant;

import java.sql.SQLException;
import java.util.Optional;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Repository;
import com.zyaire.identity.directory.domain.tenant.model.Tenant;
import com.zyaire.identity.directory.domain.tenant.model.TenantCodeConflict;
import com.zyaire.identity.directory.domain.tenant.repository.TenantRepository;

@Repository
public class MyBatisTenantRepository implements TenantRepository {
    private final TenantMapper mapper;
    public MyBatisTenantRepository(TenantMapper mapper) { this.mapper = mapper; }
    @Override
    public void saveNew(Tenant tenant) {
        try {
            mapper.insert(new TenantRow(tenant.id(), tenant.name(), tenant.code(), tenant.status(), tenant.version()));
        } catch (DuplicateKeyException failure) {
            for (Throwable cause = failure; cause != null; cause = cause.getCause()) {
                if (cause instanceof SQLException sql && "23505".equals(sql.getSQLState())
                        && sql.getMessage() != null && sql.getMessage().contains("uq_tenant_code")) {
                    throw new TenantCodeConflict();
                }
            }
            throw failure;
        }
    }
    @Override
    public Optional<Tenant> findById(long id) {
        TenantRow row = mapper.findById(id);
        return Optional.ofNullable(row)
            .map(r -> new Tenant(r.id(), r.name(), r.code(), r.status(), r.version()));
    }
}
