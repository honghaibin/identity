package com.zyaire.identity.directory.interfaces.rest.tenant;

import com.zyaire.identity.directory.domain.tenant.model.Tenant;

public final class TenantAssembler {
    private TenantAssembler() {}
    public static TenantResponse response(Tenant t) {
        return new TenantResponse(Long.toString(t.id()), t.name(), t.code(), t.status(), t.version());
    }
}
