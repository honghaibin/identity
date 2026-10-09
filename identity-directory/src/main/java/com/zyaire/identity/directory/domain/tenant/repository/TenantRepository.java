package com.zyaire.identity.directory.domain.tenant.repository;

import java.util.Optional;
import com.zyaire.identity.directory.domain.tenant.model.Tenant;

public interface TenantRepository {
    void saveNew(Tenant tenant);
    Optional<Tenant> findById(long id);
}
