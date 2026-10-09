package com.zyaire.identity.directory.interfaces.rest.error;

import java.util.Map;

/**
 * REST 错误契约：code 是稳定机器码，message 是可调整的安全展示文案。
 * requestId 由服务端生成；fieldErrors 只包含字段名和安全提示，不包含原始输入。
 * HTTP 400：INVALID_ARGUMENT / VALIDATION_FAILED；404：TENANT_NOT_FOUND；
 * 409：TENANT_CODE_CONFLICT；500：INTERNAL_ERROR。
 * 错误必须使用对应 HTTP 状态，禁止以 200 + success=false 代替。
 */
public record ApiError(
    String code,
    String message,
    String requestId,
    Map<String, String> fieldErrors
) {
    public ApiError {
        fieldErrors = fieldErrors == null ? Map.of() : Map.copyOf(fieldErrors);
    }
}
