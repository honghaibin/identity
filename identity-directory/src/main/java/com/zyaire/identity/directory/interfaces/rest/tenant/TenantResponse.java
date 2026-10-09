package com.zyaire.identity.directory.interfaces.rest.tenant;

public record TenantResponse(String id, String name, String code, String status, long version) {}
