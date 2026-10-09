package com.zyaire.identity.directory.interfaces.rest.error;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.TypeMismatchException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.ErrorResponse;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import com.zyaire.identity.directory.application.tenant.TenantNotFound;
import com.zyaire.identity.directory.domain.tenant.model.TenantCodeConflict;

@RestControllerAdvice
public class ApiExceptionHandler {
    @ExceptionHandler(TenantNotFound.class)
    public ResponseEntity<ApiError> missing(TenantNotFound error) {
        return response(HttpStatus.NOT_FOUND, "TENANT_NOT_FOUND", "企业不存在", Map.of());
    }

    @ExceptionHandler(TenantCodeConflict.class)
    public ResponseEntity<ApiError> duplicate(TenantCodeConflict error) {
        return response(HttpStatus.CONFLICT, "TENANT_CODE_CONFLICT", "企业编码已存在", Map.of());
    }

    @ExceptionHandler({IllegalArgumentException.class, TypeMismatchException.class,
        HttpMessageNotReadableException.class})
    public ResponseEntity<ApiError> invalid(Exception error) {
        return response(HttpStatus.BAD_REQUEST, "INVALID_ARGUMENT", "参数不合法", Map.of());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiError> validation(MethodArgumentNotValidException error) {
        Map<String, String> fields = new LinkedHashMap<>();
        error.getBindingResult().getFieldErrors()
            .forEach(e -> fields.putIfAbsent(e.getField(), "字段不符合要求"));
        return response(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "请检查输入", fields);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiError> unexpected(Exception error) {
        // 保留框架自身的 4xx（例如 405、415），不把客户端错误误报成 500。
        // 不使用异常 message 或 ProblemDetail，它们可能包含原始输入或内部细节。
        if (error instanceof ErrorResponse frameworkError
            && frameworkError.getStatusCode().is4xxClientError()) {
            HttpStatus status = HttpStatus.resolve(frameworkError.getStatusCode().value());
            if (status != null) {
                ResponseEntity<ApiError> result = response(status, "HTTP_" + status.value(), "请求无法处理", Map.of());
                return ResponseEntity.status(status)
                    .headers(frameworkError.getHeaders())
                    .headers(result.getHeaders())
                    .body(result.getBody());
            }
        }
        return response(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "服务暂时不可用，请稍后重试", Map.of());
    }

    private ResponseEntity<ApiError> response(HttpStatus status, String code, String message,
                                             Map<String, String> fields) {
        // 步骤 054 将统一到请求过滤器；本步先保证错误编号由服务端生成。
        String requestId = UUID.randomUUID().toString();
        return ResponseEntity.status(status)
            .header("X-Request-ID", requestId)
            .body(new ApiError(code, message, requestId, fields));
    }
}
