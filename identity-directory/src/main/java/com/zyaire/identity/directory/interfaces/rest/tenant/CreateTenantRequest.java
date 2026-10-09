package com.zyaire.identity.directory.interfaces.rest.tenant;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record CreateTenantRequest(
    @NotBlank @Size(max = 200) String name,
    @NotBlank @Size(max = 64) @Pattern(regexp = "[a-z0-9][a-z0-9_-]*") String code
) {}
