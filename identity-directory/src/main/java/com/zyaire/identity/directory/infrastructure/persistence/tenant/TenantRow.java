package com.zyaire.identity.directory.infrastructure.persistence.tenant;

public record TenantRow(long id, String name, String code, String status, long version) {}
