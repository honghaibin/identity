package com.zyaire.identity.directory.interfaces.rest.tenant;

import java.net.URI;
import jakarta.validation.Valid;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.zyaire.identity.directory.application.tenant.CreateTenantHandler;
import com.zyaire.identity.directory.application.tenant.GetTenantHandler;

@Profile("local")
@RestController
@RequestMapping("/api/dev/tenants")
public class TenantController {
    private final CreateTenantHandler create;
    private final GetTenantHandler get;
    public TenantController(CreateTenantHandler create, GetTenantHandler get) {
        this.create = create;
        this.get = get;
    }
    @PostMapping
    public ResponseEntity<TenantResponse> create(@Valid @RequestBody CreateTenantRequest request) {
        TenantResponse result = TenantAssembler.response(create.handle(request.name(), request.code()));
        return ResponseEntity.created(URI.create("/api/dev/tenants/" + result.id())).body(result);
    }
    @GetMapping("/{id}")
    public TenantResponse get(@PathVariable("id") long id) {
        return TenantAssembler.response(get.handle(id));
    }
}
