package com.zyaire.identity.directory.application.tenant;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.zyaire.identity.directory.application.port.TenantIdGenerator;
import com.zyaire.identity.directory.domain.tenant.model.Tenant;
import com.zyaire.identity.directory.domain.tenant.repository.TenantRepository;

@Service
public class CreateTenantHandler {
    private final TenantRepository repository;
    private final TenantIdGenerator ids;
    public CreateTenantHandler(TenantRepository repository, TenantIdGenerator ids) {
        this.repository = repository;
        this.ids = ids;
    }
    @Transactional
    public Tenant handle(String name, String code) {
        Tenant tenant = Tenant.provision(ids.nextId(), name, code);
        repository.saveNew(tenant);
        return tenant;
    }
}
