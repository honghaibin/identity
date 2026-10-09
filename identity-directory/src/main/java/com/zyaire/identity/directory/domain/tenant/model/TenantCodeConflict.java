package com.zyaire.identity.directory.domain.tenant.model;

public class TenantCodeConflict extends RuntimeException {
    public TenantCodeConflict() { super("tenant code conflict"); }
}
