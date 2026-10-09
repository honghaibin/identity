-- 本地学习阶段使用的持久发号序列
CREATE SEQUENCE platform_meta.learning_id_seq
START WITH 100000;

-- 允许运行账号通过 platform_runtime 使用序列
GRANT USAGE, SELECT
    ON SEQUENCE platform_meta.learning_id_seq
TO platform_runtime;