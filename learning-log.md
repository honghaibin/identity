# 学习记录

| 步骤编号 | 日期         | 执行命令 | 实际结果 | 疑问 | 
|------|------------|------|------|------|
| 007  | 2025-10-06 | `git init` | 成功初始化了一个新的 Git 仓库 | 无 |
| 047 | 2026-10-07 | `./mvnw -o compile`；临时 Spring 集成验证 | 编译通过；仅扫描 TenantMapper；XML namespace、方法绑定和 record 映射通过；identity_app 完成序列取号、插入读取、空结果及重复编码异常转换验证；测试行已回滚，共消耗 3 个序列号 | 发现并修复 nextval 的 MyBatis 一级缓存问题：取号语句设置 flushCache=true、useCache=false；已同步代码册。验证关闭 Flyway，不执行迁移。 |
| 048 | 2026-10-07 | `./mvnw -o compile`；临时端口 local HTTP 集成验证 | 编译通过；POST 201 + Location、字符串 ID、GET 200；重复编码 409、参数校验 400、租户不存在 404；验证创建事务提交及回滚；domain 无 HTTP 类型，Controller 不调用 Mapper | 使用 identity_app，关闭 Flyway；本次唯一随机编码测试行已清理，序列共消耗 4 个号码；测试应用已关闭。 |
| 051 | 2026-10-09 | `cd services/identity && ./mvnw -o test` | PASS：10 项 MockMvc 契约测试全部通过；统一四字段 ApiError；400/404/409/500 使用真实 HTTP 状态和稳定 code；异常中合成 SQL、表名、密码、堆栈信息未出现在响应中；错误 requestId 为服务端 UUID 且与 X-Request-ID 一致；405/415 及 Allow 头保持正确 | 测试模拟用例层与数据库异常，不连接数据库；完整请求过滤器和 MDC 关联留到 054。报告：identity-start/target/surefire-reports/com.zyaire.identity.directory.interfaces.rest.error.ApiErrorContractTest.txt。 |
