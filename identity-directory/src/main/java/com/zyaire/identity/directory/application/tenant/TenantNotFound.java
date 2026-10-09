package com.zyaire.identity.directory.application.tenant;

public class TenantNotFound extends RuntimeException {
    public TenantNotFound() { super("tenant not found"); }
}
