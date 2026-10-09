package com.zyaire.identity.directory.domain.tenant.model;

import java.util.Set;

public record Tenant(long id, String name, String code, String status, long version) {
    public Tenant {
        if (id <= 0) throw new IllegalArgumentException("id must be positive");
        if (name == null || name.isBlank() || name.length() > 200)
            throw new IllegalArgumentException("invalid tenant name");
        if (code == null || code.length() > 64 || !code.matches("[a-z0-9][a-z0-9_-]*"))
            throw new IllegalArgumentException("invalid tenant code");
        if (status == null || !Set.of("PROVISIONING", "ACTIVE", "SUSPENDED", "CLOSING", "CLOSED").contains(status))
            throw new IllegalArgumentException("invalid tenant status");
        if (version < 0) throw new IllegalArgumentException("invalid version");
    }
    public static Tenant provision(long id, String name, String code) {
        return new Tenant(id, name == null ? null : name.strip(), code, "PROVISIONING", 0);
    }
}