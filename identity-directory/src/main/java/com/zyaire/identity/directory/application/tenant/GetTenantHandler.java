package com.zyaire.identity.directory.application.tenant;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.zyaire.identity.directory.domain.tenant.model.Tenant;
import com.zyaire.identity.directory.domain.tenant.repository.TenantRepository;

@Service
public class GetTenantHandler {
    private final TenantRepository repository;
    public GetTenantHandler(TenantRepository repository) { this.repository = repository; }
    @Transactional(readOnly = true)
    public Tenant handle(long id) {
        if (id <= 0) throw new IllegalArgumentException("id must be positive");
        return repository.findById(id).orElseThrow(TenantNotFound::new);
    }
}
