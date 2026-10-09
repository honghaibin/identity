package com.zyaire.identity.directory.interfaces.rest.error;

import java.sql.SQLException;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import com.zyaire.identity.directory.application.tenant.CreateTenantHandler;
import com.zyaire.identity.directory.application.tenant.GetTenantHandler;
import com.zyaire.identity.directory.application.tenant.TenantNotFound;
import com.zyaire.identity.directory.domain.tenant.model.TenantCodeConflict;
import com.zyaire.identity.directory.interfaces.rest.tenant.TenantController;
import tools.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class ApiErrorContractTest {
    private MockMvc mvc;
    private CreateTenantHandler create;
    private GetTenantHandler getTenant;
    private static final String PATH = "/api/dev/tenants";
    private static final String VALID = "{\"name\":\"测试企业\",\"code\":\"example\"}";
    // 全部为合成哨兵，不能出现在客户端响应中。
    private static final String SECRET = "SELECT password FROM private_tenant_table; password=fake-secret";

    @BeforeEach
    void setUp() {
        create = mock(CreateTenantHandler.class);
        getTenant = mock(GetTenantHandler.class);
        mvc = MockMvcBuilders.standaloneSetup(new TenantController(create, getTenant))
            .setControllerAdvice(new ApiExceptionHandler()).build();
    }

    @Test
    void missingTenantReturns404() throws Exception {
        when(getTenant.handle(1L)).thenThrow(new TenantNotFound());
        check(mvc.perform(get(PATH + "/1")), 404, "TENANT_NOT_FOUND");
    }

    @Test
    void duplicateCodeReturns409() throws Exception {
        when(create.handle("测试企业", "example")).thenThrow(new TenantCodeConflict());
        check(postJson(VALID), 409, "TENANT_CODE_CONFLICT");
    }

    @Test
    void invalidArgumentDoesNotExposeExceptionMessage() throws Exception {
        when(create.handle("测试企业", "example")).thenThrow(new IllegalArgumentException(SECRET));
        check(postJson(VALID), 400, "INVALID_ARGUMENT");
    }

    @Test
    void validationIncludesSafeFieldErrors() throws Exception {
        MvcResult result = check(postJson("{\"name\":\"\",\"code\":\"fake-secret!\"}"), 400, "VALIDATION_FAILED");
        assertThat(new ObjectMapper().readTree(result.getResponse().getContentAsString())
            .get("fieldErrors").properties()).hasSize(2);
        assertThat(result.getResponse().getContentAsString()).contains("字段不符合要求");
    }

    @Test
    void malformedJsonReturns400() throws Exception {
        check(postJson("{\"name\":"), 400, "INVALID_ARGUMENT");
    }

    @Test
    void invalidPathIdReturns400() throws Exception {
        check(mvc.perform(get(PATH + "/fake-secret")), 400, "INVALID_ARGUMENT");
    }

    @Test
    void databaseFailureReturnsSafe500() throws Exception {
        when(create.handle("测试企业", "example"))
            .thenThrow(new RuntimeException(SECRET, new SQLException(SECRET)));
        check(postJson(VALID), 500, "INTERNAL_ERROR");
    }

    @Test
    void unknownIntegrityFailureIsNotMisreportedAsConflict() throws Exception {
        when(create.handle("测试企业", "example"))
            .thenThrow(new DataIntegrityViolationException(SECRET));
        check(postJson(VALID), 500, "INTERNAL_ERROR");
    }

    @Test
    void frameworkClientErrorsKeepTheirHttpStatus() throws Exception {
        MvcResult methodNotAllowed = check(mvc.perform(put(PATH)), 405, "HTTP_405");
        assertThat(methodNotAllowed.getResponse().getHeader("Allow")).contains("POST");
        check(mvc.perform(post(PATH).contentType(MediaType.TEXT_PLAIN).content(SECRET)), 415, "HTTP_415");
    }

    @Test
    void requestIdsAreGeneratedAndDoNotTrustClientHeader() throws Exception {
        when(getTenant.handle(1L)).thenThrow(new TenantNotFound());
        MvcResult first = check(mvc.perform(get(PATH + "/1").header("X-Request-ID", "fake-secret")),
            404, "TENANT_NOT_FOUND");
        MvcResult second = check(mvc.perform(get(PATH + "/1")), 404, "TENANT_NOT_FOUND");
        assertThat(first.getResponse().getHeader("X-Request-ID"))
            .isNotEqualTo(second.getResponse().getHeader("X-Request-ID"));
    }

    private ResultActions postJson(String body) throws Exception {
        return mvc.perform(post(PATH).contentType(MediaType.APPLICATION_JSON).content(body));
    }

    private MvcResult check(ResultActions action, int httpStatus, String code) throws Exception {
        MvcResult result = action.andExpect(status().is(httpStatus))
            .andExpect(jsonPath("$.length()").value(4))
            .andExpect(jsonPath("$.code").value(code))
            .andExpect(jsonPath("$.message").isNotEmpty())
            .andExpect(jsonPath("$.requestId").isNotEmpty())
            .andExpect(jsonPath("$.fieldErrors").isMap()).andReturn();
        String body = result.getResponse().getContentAsString();
        String requestId = new ObjectMapper().readTree(body).get("requestId").asString();
        assertThat(UUID.fromString(requestId).toString()).isEqualTo(requestId);
        assertThat(result.getResponse().getHeader("X-Request-ID")).isEqualTo(requestId);
        assertThat(body).doesNotContain("SELECT", "private_tenant_table", "password", "fake-secret",
            "SQLException", "RuntimeException", "stackTrace", "java.sql", "success");
        if (!code.equals("VALIDATION_FAILED")) {
            assertThat(new ObjectMapper().readTree(body).get("fieldErrors").isEmpty()).isTrue();
        }
        return result;
    }
}
