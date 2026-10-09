-- 企业身份平台：完整目标建库 SQL（PostgreSQL 18）。
-- 本文件是逐表验收依据；只面向空数据库，不读取、不回填、不依赖历史迁移。
-- 业务 ID 由应用生成；不初始化客户、员工、管理员、登录凭据或默认密码。
-- 仅包含表/约束/索引/注释/隔离/运行权限以及内置资源类型和动作目录。
-- 跨表循环引用的少量外键在表创建完毕后统一声明。
-- 字段说明更新于 2026-10-05：每列注释包含含义与设计场景；业务行为仍需由用例实现。
-- 本次仅移动文件并补充注释，不改变字段、约束、索引、隔离、权限或种子数据。
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='platform_runtime') THEN CREATE ROLE platform_runtime NOLOGIN NOSUPERUSER NOBYPASSRLS; END IF; END $$;
SET LOCAL search_path TO public;
CREATE SCHEMA directory;
REVOKE ALL ON SCHEMA directory FROM PUBLIC;
CREATE SCHEMA identity;
REVOKE ALL ON SCHEMA identity FROM PUBLIC;
CREATE SCHEMA access;
REVOKE ALL ON SCHEMA access FROM PUBLIC;
CREATE SCHEMA application;
REVOKE ALL ON SCHEMA application FROM PUBLIC;
CREATE SCHEMA machine;
REVOKE ALL ON SCHEMA machine FROM PUBLIC;
CREATE SCHEMA audit;
REVOKE ALL ON SCHEMA audit FROM PUBLIC;
CREATE SCHEMA delivery;
REVOKE ALL ON SCHEMA delivery FROM PUBLIC;
CREATE SCHEMA protocol;
REVOKE ALL ON SCHEMA protocol FROM PUBLIC;
CREATE SCHEMA platform_meta;
REVOKE ALL ON SCHEMA platform_meta FROM PUBLIC;
CREATE SCHEMA demo;
REVOKE ALL ON SCHEMA demo FROM PUBLIC;

-- directory.account：全局账号；不保存密码、当前企业或企业角色，生命周期变更保留账号记录。
CREATE TABLE directory.account (
    -- 全局账号 ID，由应用生成雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 账号状态：ACTIVE正常、DISABLED安全冻结、CLOSED已注销、MERGED已合并；终止状态不能认证。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 非负认证撤销版本；应用只递增，安全变更后旧会话与半认证过程失效。 设计场景：作为账号权威撤销版本，改密、全局禁用或全部退出时递增；会话和半认证保存的旧版本据此失效，依赖这些证明的操作须重新核验。
    "auth_epoch" bigint DEFAULT 0 NOT NULL,
    -- 聚合乐观锁版本，由应用条件更新并递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 安全冻结时间；ACTIVE为空，DISABLED非空，注销/合并墓碑可以保留之前的冻结时间。 设计场景：区分正常账号与因安全原因冻结的账号，帮助解释冻结时间和恢复流程；业务状态仍由生命周期字段组合决定。
    "disabled_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由应用写入；数据库不会自动刷新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 注销或合并完成时间；保留账号墓碑及依法/按保留规则必须保留的引用，个人资料另行清理。 设计场景：企业关闭或账号终止后保留时间依据，供历史追溯与保留清理；不等于立即物理删除相关数据。
    "closed_at" timestamp with time zone,
    -- 合并后的目标账号；只记录最终关系，不自动迁移身份或叠加权限；应用锁定双方、防环并撤销旧凭据。 设计场景：重复账号合并后可从旧账号追溯目标账号；合并执行必须处理成员、权限和凭据冲突，不能只改这个引用。
    "merged_into_account_id" bigint,
    CONSTRAINT "ck_account_auth_epoch" CHECK (auth_epoch >= 0),
    CONSTRAINT "ck_account_closed_time" CHECK (closed_at IS NULL OR closed_at >= created_at),
    CONSTRAINT "ck_account_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_account_lifecycle" CHECK (status::text = 'ACTIVE'::text AND disabled_at IS NULL AND closed_at IS NULL AND merged_into_account_id IS NULL OR status::text = 'DISABLED'::text AND disabled_at IS NOT NULL AND closed_at IS NULL AND merged_into_account_id IS NULL OR status::text = 'CLOSED'::text AND closed_at IS NOT NULL AND merged_into_account_id IS NULL OR status::text = 'MERGED'::text AND closed_at IS NOT NULL AND merged_into_account_id IS NOT NULL AND merged_into_account_id <> id),
    CONSTRAINT "ck_account_status" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying, 'CLOSED'::character varying, 'MERGED'::character varying]::text[])),
    CONSTRAINT "ck_account_version" CHECK (version >= 0),
    CONSTRAINT "fk_account_merged_into" FOREIGN KEY (merged_into_account_id) REFERENCES directory.account(id),
    CONSTRAINT "pk_directory_account" PRIMARY KEY (id)
);
COMMENT ON TABLE directory.account IS '全局账号；不保存密码、当前企业或企业角色，生命周期变更保留账号记录。';
COMMENT ON COLUMN directory.account."id" IS '全局账号 ID，由应用生成雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.account."status" IS '账号状态：ACTIVE正常、DISABLED安全冻结、CLOSED已注销、MERGED已合并；终止状态不能认证。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.account."auth_epoch" IS '非负认证撤销版本；应用只递增，安全变更后旧会话与半认证过程失效。 设计场景：作为账号权威撤销版本，改密、全局禁用或全部退出时递增；会话和半认证保存的旧版本据此失效，依赖这些证明的操作须重新核验。';
COMMENT ON COLUMN directory.account."version" IS '聚合乐观锁版本，由应用条件更新并递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.account."disabled_at" IS '安全冻结时间；ACTIVE为空，DISABLED非空，注销/合并墓碑可以保留之前的冻结时间。 设计场景：区分正常账号与因安全原因冻结的账号，帮助解释冻结时间和恢复流程；业务状态仍由生命周期字段组合决定。';
COMMENT ON COLUMN directory.account."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.account."updated_at" IS '最近更新时间，由应用写入；数据库不会自动刷新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
COMMENT ON COLUMN directory.account."closed_at" IS '注销或合并完成时间；保留账号墓碑及依法/按保留规则必须保留的引用，个人资料另行清理。 设计场景：企业关闭或账号终止后保留时间依据，供历史追溯与保留清理；不等于立即物理删除相关数据。';
COMMENT ON COLUMN directory.account."merged_into_account_id" IS '合并后的目标账号；只记录最终关系，不自动迁移身份或叠加权限；应用锁定双方、防环并撤销旧凭据。 设计场景：重复账号合并后可从旧账号追溯目标账号；合并执行必须处理成员、权限和凭据冲突，不能只改这个引用。';
CREATE INDEX ix_account_merged_into ON directory.account USING btree (merged_into_account_id) WHERE (merged_into_account_id IS NOT NULL);

-- directory.tenant：企业租户与独立生命周期；支持开通、暂停和关闭，不因企业关闭删除个人账号。
CREATE TABLE directory.tenant (
    -- 企业 ID，由应用生成雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 企业展示名称，不承担身份唯一性。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。
    "name" character varying(200) NOT NULL,
    -- 全局唯一企业编码：小写字母或数字开头，仅含小写字母、数字、下划线和连字符。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。
    "code" character varying(64) NOT NULL,
    -- PROVISIONING 开通中、ACTIVE 有效、SUSPENDED 暂停、CLOSING 关闭中、CLOSED 已关闭。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 企业聚合乐观锁版本；组织及管理员变更还需按企业加锁。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由应用写入。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 关闭完成时间；关闭不是删除成员个人账号。 设计场景：企业关闭或账号终止后保留时间依据，供历史追溯与保留清理；不等于立即物理删除相关数据。
    "closed_at" timestamp with time zone,
    CONSTRAINT "ck_tenant_closed_at" CHECK ((status::text = 'CLOSED'::text) = (closed_at IS NOT NULL)),
    CONSTRAINT "ck_tenant_code" CHECK (code::text = lower(btrim(code::text)) AND code::text ~ '^[a-z0-9][a-z0-9_-]*$'::text),
    CONSTRAINT "ck_tenant_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_tenant_name" CHECK (btrim(name::text) <> ''::text),
    CONSTRAINT "ck_tenant_status" CHECK (status::text = ANY (ARRAY['PROVISIONING'::character varying, 'ACTIVE'::character varying, 'SUSPENDED'::character varying, 'CLOSING'::character varying, 'CLOSED'::character varying]::text[])),
    CONSTRAINT "ck_tenant_version" CHECK (version >= 0),
    CONSTRAINT "pk_directory_tenant" PRIMARY KEY (id),
    CONSTRAINT "uq_tenant_code" UNIQUE (code)
);
COMMENT ON TABLE directory.tenant IS '企业租户与独立生命周期；支持开通、暂停和关闭，不因企业关闭删除个人账号。';
COMMENT ON COLUMN directory.tenant."id" IS '企业 ID，由应用生成雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.tenant."name" IS '企业展示名称，不承担身份唯一性。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。';
COMMENT ON COLUMN directory.tenant."code" IS '全局唯一企业编码：小写字母或数字开头，仅含小写字母、数字、下划线和连字符。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。';
COMMENT ON COLUMN directory.tenant."status" IS 'PROVISIONING 开通中、ACTIVE 有效、SUSPENDED 暂停、CLOSING 关闭中、CLOSED 已关闭。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.tenant."version" IS '企业聚合乐观锁版本；组织及管理员变更还需按企业加锁。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.tenant."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.tenant."updated_at" IS '最近更新时间，由应用写入。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
COMMENT ON COLUMN directory.tenant."closed_at" IS '关闭完成时间；关闭不是删除成员个人账号。 设计场景：企业关闭或账号终止后保留时间依据，供历史追溯与保留清理；不等于立即物理删除相关数据。';

-- identity.external_connection_version：上游连接的不可变发布快照；协议适配器校验配置结构，发布事务校验状态并切换根记录，不允许编辑已发布快照。
CREATE TABLE identity.external_connection_version (
    -- 应用生成的正数雪花版本ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属上游连接；连接固定外部主体命名空间，更换外部企业/应用须迁移映射。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 连接内递增配置版本号，不能用旧配置覆盖新配置。 设计场景：让同一配置的不同快照可明确比较和引用，旧任务不能用新版本号冒充原有配置。
    "version_number" bigint NOT NULL,
    -- DRAFT待校验、VALIDATED已校验、PUBLISHED已发布、RETIRED已退役；状态推进由应用控制。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'DRAFT'::character varying NOT NULL,
    -- version=1的协议配置快照：端点白名单、issuer/entityId/service、回调、scope、claims及字段映射、LDAP目录范围；按protocol_kind验证，禁止明文凭据，不存成员/授权关系。 设计场景：同一连接可能经历多轮改配置和回退；保存不可变快照，定位某次登录使用的参数，发布时仍按协议逐项校验。
    "configuration" jsonb NOT NULL,
    -- 创建配置的管理员账号；受控系统迁移可空并须审计。 设计场景：追踪是谁建立了配置或记录，发生误配置时可定位责任来源；不表示该人永久拥有管理权。
    "created_by_account_id" bigint,
    -- 完成对应协议配置及受控联调检查时间，不等于所有生产渠道均已验收。 设计场景：记录配置完成校验的时间，发布前确认其已通过对应检查；修改后不能沿用不适用的旧校验结论。
    "validated_at" timestamp with time zone,
    -- 发布时刻；根连接仅允许指向已发布且未退役版本，跨行约束由发布事务保证。 设计场景：区分保存草稿与正式发布，便于追踪某段时间实际采用哪份规则或连接配置。
    "published_at" timestamp with time zone,
    -- 版本退役时刻；历史快照保留供审计，清理遵循保留规则。 设计场景：标明版本退出使用的时刻，历史请求仍可追溯其原配置，新请求不能继续选择该版本。
    "retired_at" timestamp with time zone,
    -- 版本创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_external_connection_version_config" CHECK (jsonb_typeof(configuration) = 'object'::text AND configuration @> '{"version": 1}'::jsonb),
    CONSTRAINT "ck_external_connection_version_state" CHECK (status::text = 'DRAFT'::text AND validated_at IS NULL AND published_at IS NULL AND retired_at IS NULL OR status::text = 'VALIDATED'::text AND validated_at IS NOT NULL AND published_at IS NULL AND retired_at IS NULL OR status::text = 'PUBLISHED'::text AND validated_at IS NOT NULL AND published_at IS NOT NULL AND retired_at IS NULL OR status::text = 'RETIRED'::text AND retired_at IS NOT NULL),
    CONSTRAINT "ck_external_connection_version_times" CHECK ((validated_at IS NULL OR validated_at >= created_at) AND (published_at IS NULL OR validated_at IS NOT NULL AND published_at >= validated_at) AND (retired_at IS NULL OR retired_at >= COALESCE(published_at, validated_at, created_at))),
    CONSTRAINT "external_connection_version_created_by_account_id_fkey" FOREIGN KEY (created_by_account_id) REFERENCES directory.account(id),
    CONSTRAINT "external_connection_version_id_check" CHECK (id > 0),
    CONSTRAINT "external_connection_version_pkey" PRIMARY KEY (id),
    CONSTRAINT "external_connection_version_status_check" CHECK (status::text = ANY (ARRAY['DRAFT'::character varying, 'VALIDATED'::character varying, 'PUBLISHED'::character varying, 'RETIRED'::character varying]::text[])),
    CONSTRAINT "external_connection_version_version_number_check" CHECK (version_number > 0),
    CONSTRAINT "uq_external_connection_version" UNIQUE (connection_id, version_number),
    CONSTRAINT "uq_external_connection_version_id" UNIQUE (connection_id, id)
);
COMMENT ON TABLE identity.external_connection_version IS '上游连接的不可变发布快照；协议适配器校验配置结构，发布事务校验状态并切换根记录，不允许编辑已发布快照。';
COMMENT ON COLUMN identity.external_connection_version."id" IS '应用生成的正数雪花版本ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.external_connection_version."connection_id" IS '所属上游连接；连接固定外部主体命名空间，更换外部企业/应用须迁移映射。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN identity.external_connection_version."version_number" IS '连接内递增配置版本号，不能用旧配置覆盖新配置。 设计场景：让同一配置的不同快照可明确比较和引用，旧任务不能用新版本号冒充原有配置。';
COMMENT ON COLUMN identity.external_connection_version."status" IS 'DRAFT待校验、VALIDATED已校验、PUBLISHED已发布、RETIRED已退役；状态推进由应用控制。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN identity.external_connection_version."configuration" IS 'version=1的协议配置快照：端点白名单、issuer/entityId/service、回调、scope、claims及字段映射、LDAP目录范围；按protocol_kind验证，禁止明文凭据，不存成员/授权关系。 设计场景：同一连接可能经历多轮改配置和回退；保存不可变快照，定位某次登录使用的参数，发布时仍按协议逐项校验。';
COMMENT ON COLUMN identity.external_connection_version."created_by_account_id" IS '创建配置的管理员账号；受控系统迁移可空并须审计。 设计场景：追踪是谁建立了配置或记录，发生误配置时可定位责任来源；不表示该人永久拥有管理权。';
COMMENT ON COLUMN identity.external_connection_version."validated_at" IS '完成对应协议配置及受控联调检查时间，不等于所有生产渠道均已验收。 设计场景：记录配置完成校验的时间，发布前确认其已通过对应检查；修改后不能沿用不适用的旧校验结论。';
COMMENT ON COLUMN identity.external_connection_version."published_at" IS '发布时刻；根连接仅允许指向已发布且未退役版本，跨行约束由发布事务保证。 设计场景：区分保存草稿与正式发布，便于追踪某段时间实际采用哪份规则或连接配置。';
COMMENT ON COLUMN identity.external_connection_version."retired_at" IS '版本退役时刻；历史快照保留供审计，清理遵循保留规则。 设计场景：标明版本退出使用的时刻，历史请求仍可追溯其原配置，新请求不能继续选择该版本。';
COMMENT ON COLUMN identity.external_connection_version."created_at" IS '版本创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_external_connection_version_creator ON identity.external_connection_version USING btree (created_by_account_id) WHERE (created_by_account_id IS NOT NULL);

-- identity.external_connection：经配置和验证的上游身份连接；连接决定外部 subject 的命名空间。
CREATE TABLE identity.external_connection (
    CONSTRAINT ck_external_connection_active_configuration CHECK(status<>'ACTIVE' OR active_version_id IS NOT NULL),
    -- 本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 上游厂商或通用身份源类型；厂商与协议分开，LDAP/AD不代表本平台提供LDAP服务端。 设计场景：区分飞书、钉钉等身份来源并选择适配器，不能将不同厂商返回的相同用户字符串认作同一人。
    "provider" character varying(32) NOT NULL,
    -- 受控配置键，全局唯一，不保存秘密值。 设计场景：环境配置可以通过稳定的键定位连接，避免随管理员改展示名而失去引用；键对应配置而非秘密值。
    "config_key" character varying(128) NOT NULL,
    -- 可选的配置归属企业，不构成企业成员关系或自动授权。 设计场景：标明连接由哪家企业管理，防止客户修改别人的身份源；拥有连接不意味着取得其中所有人的企业成员资格。
    "owner_tenant_id" bigint,
    -- 适配器验证的外部企业标识；按渠道保留原始大小写和格式。 设计场景：同一供应商服务多个客户时限定外部企业命名空间，拒绝把另一客户的扫码结果用于当前企业。
    "external_tenant_key" character varying(512),
    -- 扫码/OAuth 上游应用标识；属于外部身份命名空间，不适用的协议允许为空。 设计场景：协议交互时定位具体应用客户端，与平台账号和企业应用 ID 分开；公开标识本身不能证明客户端身份。
    "client_id" character varying(512),
    -- 外部签发方标识，须与配置和协议验证结果精确匹配。 设计场景：验证外部签发者与登记配置一致，防止其他认证中心签发的合法凭证被误用于本连接。
    "issuer" character varying(1024),
    -- 连接默认客户端认证秘密的受控引用；不需要时可空，发布版本的轮换材料由 external_connection_key 管理。 设计场景：通过受控引用读取密钥材料，支持轮换和访问审计，避免把明文秘密放进普通配置与日志。
    "secret_ref" text,
    -- 对象状态，允许值及字段组合见本表 CHECK 约束。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'DISABLED'::character varying NOT NULL,
    -- 连接配置并发版本；密钥轮换可递增，更换应用/issuer/外部企业须新建连接或显式迁移。 设计场景：管理员同时修改连接或任务继续使用旧配置时识别版本变化；改变主体命名空间仍需迁移映射。
    "config_version" bigint DEFAULT 0 NOT NULL,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 上游认证协议；仅用于本平台接收外部认证或目录连接，不登记下游应用；SCIM仅上游目录供应命名空间。 设计场景：同一厂商可能提供登录与目录能力，按协议类型选择验证流程，避免把目录供应当作用户认证。
    "protocol_kind" character varying(16) DEFAULT 'OAUTH2'::character varying NOT NULL,
    -- INTERNAL企业内部应用、PROVIDER服务商应用、PERSONAL个人微信、GENERIC通用身份源。 设计场景：企业自建、服务商和个人应用的授权范围及用户标识不同，接入时据此采用匹配的配置与身份作用域。
    "application_type" character varying(16) DEFAULT 'INTERNAL'::character varying NOT NULL,
    -- 当前启用的已验证连接版本；禁用连接可暂未配置，启用时必须指向本连接已发布版本。 设计场景：将草稿编辑与在线配置分开，完成校验发布后再原子切换，避免请求读取半修改的配置。
    "active_version_id" bigint,
    -- 是否允许此连接作为登录入口；SCIM仅传递目录记录必须为false，不把目录供应凭据当用户登录。 设计场景：同一连接可仅用于同步人员；只有显式允许登录才进入认证流程，持有同步接口权限不等于可登录为员工。
    "authentication_enabled" boolean DEFAULT true NOT NULL,
    CONSTRAINT "ck_external_connection_application_type" CHECK (application_type::text = ANY (ARRAY['INTERNAL'::character varying, 'PROVIDER'::character varying, 'PERSONAL'::character varying, 'GENERIC'::character varying]::text[])),
    CONSTRAINT "ck_external_connection_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_external_connection_optional_credentials" CHECK (btrim(config_key::text) <> ''::text AND (external_tenant_key IS NULL OR btrim(external_tenant_key::text) <> ''::text) AND (issuer IS NULL OR btrim(issuer::text) <> ''::text) AND (client_id IS NULL OR btrim(client_id::text) <> ''::text) AND (secret_ref IS NULL OR btrim(secret_ref) <> ''::text)),
    CONSTRAINT "ck_external_connection_protocol" CHECK (protocol_kind::text = ANY (ARRAY['OAUTH2'::character varying, 'OIDC'::character varying, 'SAML'::character varying, 'CAS'::character varying, 'LDAP'::character varying, 'SCIM'::character varying]::text[])),
    CONSTRAINT "ck_external_connection_protocol_match" CHECK ((provider::text = ANY (ARRAY['WECHAT'::character varying, 'WECOM'::character varying, 'DINGTALK'::character varying, 'FEISHU'::character varying]::text[])) AND (protocol_kind::text = ANY (ARRAY['OAUTH2'::character varying, 'OIDC'::character varying]::text[])) OR provider::text = 'GENERIC_OIDC'::text AND protocol_kind::text = 'OIDC'::text OR provider::text = 'GENERIC_SAML'::text AND protocol_kind::text = 'SAML'::text OR provider::text = 'GENERIC_CAS'::text AND protocol_kind::text = 'CAS'::text OR (provider::text = ANY (ARRAY['LDAP'::character varying, 'AD'::character varying]::text[])) AND protocol_kind::text = 'LDAP'::text OR provider::text = 'SCIM'::text AND protocol_kind::text = 'SCIM'::text AND NOT authentication_enabled),
    CONSTRAINT "ck_external_connection_provider" CHECK (provider::text = ANY (ARRAY['WECHAT'::character varying, 'WECOM'::character varying, 'DINGTALK'::character varying, 'FEISHU'::character varying, 'GENERIC_OIDC'::character varying, 'GENERIC_SAML'::character varying, 'GENERIC_CAS'::character varying, 'LDAP'::character varying, 'AD'::character varying, 'SCIM'::character varying]::text[])),
    CONSTRAINT "ck_external_connection_status" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying]::text[])),
    CONSTRAINT "ck_external_connection_updated" CHECK (updated_at >= created_at),
    CONSTRAINT "ck_external_connection_version" CHECK (config_version >= 0),
    CONSTRAINT "external_connection_pkey" PRIMARY KEY (id),
    CONSTRAINT "fk_external_connection_active_version" FOREIGN KEY (id, active_version_id) REFERENCES identity.external_connection_version(connection_id, id),
    CONSTRAINT "fk_external_connection_owner" FOREIGN KEY (owner_tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "uq_external_connection_config_key" UNIQUE (config_key),
    CONSTRAINT "uq_external_connection_provider_id" UNIQUE (provider, id),
    CONSTRAINT "uq_external_connection_tenant_id" UNIQUE (owner_tenant_id, id)
);
COMMENT ON TABLE identity.external_connection IS '经配置和验证的上游身份连接；连接决定外部 subject 的命名空间。';
COMMENT ON COLUMN identity.external_connection."id" IS '本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.external_connection."provider" IS '上游厂商或通用身份源类型；厂商与协议分开，LDAP/AD不代表本平台提供LDAP服务端。 设计场景：区分飞书、钉钉等身份来源并选择适配器，不能将不同厂商返回的相同用户字符串认作同一人。';
COMMENT ON COLUMN identity.external_connection."config_key" IS '受控配置键，全局唯一，不保存秘密值。 设计场景：环境配置可以通过稳定的键定位连接，避免随管理员改展示名而失去引用；键对应配置而非秘密值。';
COMMENT ON COLUMN identity.external_connection."owner_tenant_id" IS '可选的配置归属企业，不构成企业成员关系或自动授权。 设计场景：标明连接由哪家企业管理，防止客户修改别人的身份源；拥有连接不意味着取得其中所有人的企业成员资格。';
COMMENT ON COLUMN identity.external_connection."external_tenant_key" IS '适配器验证的外部企业标识；按渠道保留原始大小写和格式。 设计场景：同一供应商服务多个客户时限定外部企业命名空间，拒绝把另一客户的扫码结果用于当前企业。';
COMMENT ON COLUMN identity.external_connection."client_id" IS '扫码/OAuth 上游应用标识；属于外部身份命名空间，不适用的协议允许为空。 设计场景：协议交互时定位具体应用客户端，与平台账号和企业应用 ID 分开；公开标识本身不能证明客户端身份。';
COMMENT ON COLUMN identity.external_connection."issuer" IS '外部签发方标识，须与配置和协议验证结果精确匹配。 设计场景：验证外部签发者与登记配置一致，防止其他认证中心签发的合法凭证被误用于本连接。';
COMMENT ON COLUMN identity.external_connection."secret_ref" IS '连接默认客户端认证秘密的受控引用；不需要时可空，发布版本的轮换材料由 external_connection_key 管理。 设计场景：通过受控引用读取密钥材料，支持轮换和访问审计，避免把明文秘密放进普通配置与日志。';
COMMENT ON COLUMN identity.external_connection."status" IS '对象状态，允许值及字段组合见本表 CHECK 约束。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN identity.external_connection."config_version" IS '连接配置并发版本；密钥轮换可递增，更换应用/issuer/外部企业须新建连接或显式迁移。 设计场景：管理员同时修改连接或任务继续使用旧配置时识别版本变化；改变主体命名空间仍需迁移映射。';
COMMENT ON COLUMN identity.external_connection."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.external_connection."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
COMMENT ON COLUMN identity.external_connection."protocol_kind" IS '上游认证协议；仅用于本平台接收外部认证或目录连接，不登记下游应用；SCIM仅上游目录供应命名空间。 设计场景：同一厂商可能提供登录与目录能力，按协议类型选择验证流程，避免把目录供应当作用户认证。';
COMMENT ON COLUMN identity.external_connection."application_type" IS 'INTERNAL企业内部应用、PROVIDER服务商应用、PERSONAL个人微信、GENERIC通用身份源。 设计场景：企业自建、服务商和个人应用的授权范围及用户标识不同，接入时据此采用匹配的配置与身份作用域。';
COMMENT ON COLUMN identity.external_connection."active_version_id" IS '当前启用的已验证连接版本；禁用连接可暂未配置，启用时必须指向本连接已发布版本。 设计场景：将草稿编辑与在线配置分开，完成校验发布后再原子切换，避免请求读取半修改的配置。';
COMMENT ON COLUMN identity.external_connection."authentication_enabled" IS '是否允许此连接作为登录入口；SCIM仅传递目录记录必须为false，不把目录供应凭据当用户登录。 设计场景：同一连接可仅用于同步人员；只有显式允许登录才进入认证流程，持有同步接口权限不等于可登录为员工。';
CREATE INDEX ix_external_connection_active_version ON identity.external_connection USING btree (active_version_id) WHERE (active_version_id IS NOT NULL);
CREATE INDEX ix_external_connection_owner ON identity.external_connection USING btree (owner_tenant_id);

-- directory.sync_connection：企业通讯录连接；复用上游身份连接的命名空间，独立记录目录权限和同步范围。
CREATE TABLE directory.sync_connection (
    -- 对应 identity.external_connection.id，不创建第二个外部身份命名空间。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 目录接口类型；与登录协议区分。 设计场景：按获授权的通讯录协议选择同步方式；即使登录渠道相同，也不能假定已经拥有目录读取权限。
    "directory_protocol" character varying(16) NOT NULL,
    -- 启停状态；错误不代表全员离职。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'DISABLED'::character varying NOT NULL,
    -- 版本化授权可见范围和筛选条件；不含连接密钥。 设计场景：记录客户实际授权可见的部门和人员范围，避免把无权读取的人员当成已经离职。
    "scope_config" jsonb DEFAULT '{}'::jsonb NOT NULL,
    -- 范围版本；不同版本的全量结果不得直接比较删除。 设计场景：客户缩小目录可见范围后，旧全量与新全量不能直接做删除差集，需按范围变更重新判断。
    "scope_version" bigint DEFAULT 1 NOT NULL,
    -- 定期全量对账间隔。 设计场景：增量回调可能遗漏或乱序，通过定期全量对账发现本地与来源不一致。
    "reconcile_interval_seconds" integer DEFAULT 86400 NOT NULL,
    -- 单批停用达到此人数进入人工复核；比例阈值由策略补充。 设计场景：一次同步拟停用大量成员时进入人工复核，防止来源故障或范围配置错误造成批量误撤权。
    "mass_change_threshold" integer DEFAULT 20 NOT NULL,
    -- 最近完整成功时间。 设计场景：区分最近一次尝试与最近一次完整成功，连续失败时仍能定位可用数据的时间边界。
    "last_success_at" timestamp with time zone,
    -- 下次应调度时间。 设计场景：持久化下一次计划时间，进程重启后仍可安排同步；任务执行结果另行记录。
    "next_run_at" timestamp with time zone,
    -- 乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "sync_connection_directory_protocol_check" CHECK (directory_protocol::text = ANY (ARRAY['WECOM'::character varying, 'DINGTALK'::character varying, 'FEISHU'::character varying, 'LDAP'::character varying, 'SCIM'::character varying]::text[])),
    CONSTRAINT "sync_connection_id_check" CHECK (id > 0),
    CONSTRAINT "sync_connection_mass_change_threshold_check" CHECK (mass_change_threshold > 0),
    CONSTRAINT "sync_connection_pkey" PRIMARY KEY (id),
    CONSTRAINT "sync_connection_reconcile_interval_seconds_check" CHECK (reconcile_interval_seconds >= 60),
    CONSTRAINT "sync_connection_scope_config_check" CHECK (jsonb_typeof(scope_config) = 'object'::text),
    CONSTRAINT "sync_connection_scope_version_check" CHECK (scope_version > 0),
    CONSTRAINT "sync_connection_status_check" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying, 'ERROR'::character varying]::text[])),
    CONSTRAINT "sync_connection_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "sync_connection_tenant_id_id_fkey" FOREIGN KEY (tenant_id, id) REFERENCES identity.external_connection(owner_tenant_id, id),
    CONSTRAINT "sync_connection_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "sync_connection_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE directory.sync_connection IS '企业通讯录连接；复用上游身份连接的命名空间，独立记录目录权限和同步范围。';
COMMENT ON COLUMN directory.sync_connection."id" IS '对应 identity.external_connection.id，不创建第二个外部身份命名空间。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.sync_connection."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.sync_connection."directory_protocol" IS '目录接口类型；与登录协议区分。 设计场景：按获授权的通讯录协议选择同步方式；即使登录渠道相同，也不能假定已经拥有目录读取权限。';
COMMENT ON COLUMN directory.sync_connection."status" IS '启停状态；错误不代表全员离职。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.sync_connection."scope_config" IS '版本化授权可见范围和筛选条件；不含连接密钥。 设计场景：记录客户实际授权可见的部门和人员范围，避免把无权读取的人员当成已经离职。';
COMMENT ON COLUMN directory.sync_connection."scope_version" IS '范围版本；不同版本的全量结果不得直接比较删除。 设计场景：客户缩小目录可见范围后，旧全量与新全量不能直接做删除差集，需按范围变更重新判断。';
COMMENT ON COLUMN directory.sync_connection."reconcile_interval_seconds" IS '定期全量对账间隔。 设计场景：增量回调可能遗漏或乱序，通过定期全量对账发现本地与来源不一致。';
COMMENT ON COLUMN directory.sync_connection."mass_change_threshold" IS '单批停用达到此人数进入人工复核；比例阈值由策略补充。 设计场景：一次同步拟停用大量成员时进入人工复核，防止来源故障或范围配置错误造成批量误撤权。';
COMMENT ON COLUMN directory.sync_connection."last_success_at" IS '最近完整成功时间。 设计场景：区分最近一次尝试与最近一次完整成功，连续失败时仍能定位可用数据的时间边界。';
COMMENT ON COLUMN directory.sync_connection."next_run_at" IS '下次应调度时间。 设计场景：持久化下一次计划时间，进程重启后仍可安排同步；任务执行结果另行记录。';
COMMENT ON COLUMN directory.sync_connection."version" IS '乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.sync_connection."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.sync_connection."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_sync_connection_due ON directory.sync_connection USING btree (status, next_run_at);

-- directory.sync_run：一次全量、增量或手工导入执行；只有完整同范围结果可以用于缺失项对账。
CREATE TABLE directory.sync_run (
    -- 应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 外部来源连接；本地 CSV 导入可空。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint,
    -- 执行类型。 设计场景：区分全量、增量和人工导入；只有满足完整性与范围条件的全量结果可用于缺失判断，导入不能冒充完整来源快照。
    "kind" character varying(16) NOT NULL,
    -- 企业内提交幂等键。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。
    "idempotency_key" character varying(128) NOT NULL,
    -- 执行时来源范围版本；IMPORT 可空。 设计场景：客户缩小目录可见范围后，旧全量与新全量不能直接做删除差集，需按范围变更重新判断。
    "scope_version" bigint,
    -- 运行状态；人工复核前不应用大批停用。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'READY'::character varying NOT NULL,
    -- 来源游标加密值，可能包含敏感接口参数。 设计场景：分页或断点续传时恢复读取进度；游标可能携带敏感参数，应加密并限定对应批次使用。
    "cursor_ciphertext" bytea,
    -- 游标密文密钥版本。 设计场景：任务跨越密钥轮换窗口继续执行时，仍能解开旧批次保存的游标。
    "cursor_key_version" integer,
    -- 完整拉取所有分页并确认授权范围后置 true。 设计场景：只有全部分页及授权范围均确认完整后，才允许把未出现的人作为缺失候选；中途失败不能触发批量离职。
    "snapshot_complete" boolean DEFAULT false NOT NULL,
    -- 拉取或导入条目数。 设计场景：对照来源条目量和实际处理量识别漏页、规模突变及中途终止，不以计数代替完整快照标记。
    "fetched_count" bigint DEFAULT 0 NOT NULL,
    -- 已成功应用数。 设计场景：区分收到的数据和已经成功改变本地状态的数据，便于恢复只完成一部分的同步批次。
    "applied_count" bigint DEFAULT 0 NOT NULL,
    -- 失败记录数。 设计场景：展示逐项失败规模并决定是否需要复核或重试；不能因为批次大部分成功就隐藏失败记录。
    "error_count" bigint DEFAULT 0 NOT NULL,
    -- 运行租约持有者。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。
    "lease_owner" character varying(128),
    -- 租约到期。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。
    "lease_until" timestamp with time zone,
    -- 执行开始。 设计场景：记录一次执行真正开始的时刻，用于识别排队与执行耗时、定位长期运行任务。
    "started_at" timestamp with time zone,
    -- 执行结束。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。
    "finished_at" timestamp with time zone,
    -- 手动请求人；后台任务可空。 设计场景：区分人工发起和允许的后台操作，追溯请求来源；保存账号不替代执行时的权限复核。
    "requested_by_account_id" bigint,
    -- 脱敏失败原因。 设计场景：用稳定且脱敏的分类定位失败和选择补偿方式；不把凭据、完整响应或个人资料写入错误字段。
    "error_code" character varying(64),
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "sync_run_applied_count_check" CHECK (applied_count >= 0),
    CONSTRAINT "sync_run_check" CHECK (kind::text = 'IMPORT'::text OR connection_id IS NOT NULL AND scope_version IS NOT NULL),
    CONSTRAINT "sync_run_check1" CHECK ((cursor_ciphertext IS NULL) = (cursor_key_version IS NULL)),
    CONSTRAINT "sync_run_check2" CHECK ((status::text = 'RUNNING'::text) = (lease_owner IS NOT NULL AND lease_until IS NOT NULL)),
    CONSTRAINT "sync_run_check3" CHECK ((lease_owner IS NULL) = (lease_until IS NULL)),
    CONSTRAINT "sync_run_check4" CHECK ((status::text <> ALL (ARRAY['SUCCEEDED'::character varying, 'FAILED'::character varying, 'CANCELLED'::character varying]::text[])) OR finished_at IS NOT NULL),
    CONSTRAINT "sync_run_check5" CHECK (kind::text <> 'FULL'::text OR status::text <> 'SUCCEEDED'::text OR snapshot_complete),
    CONSTRAINT "sync_run_check6" CHECK (finished_at IS NULL OR finished_at >= created_at AND (started_at IS NULL OR finished_at >= started_at)),
    CONSTRAINT "sync_run_check7" CHECK ((status::text <> ALL (ARRAY['RUNNING'::character varying, 'SUCCEEDED'::character varying]::text[])) OR started_at IS NOT NULL),
    CONSTRAINT "sync_run_cursor_key_version_check" CHECK (cursor_key_version > 0),
    CONSTRAINT "sync_run_error_count_check" CHECK (error_count >= 0),
    CONSTRAINT "sync_run_fetched_count_check" CHECK (fetched_count >= 0),
    CONSTRAINT "sync_run_id_check" CHECK (id > 0),
    CONSTRAINT "sync_run_kind_check" CHECK (kind::text = ANY (ARRAY['FULL'::character varying, 'INCREMENTAL'::character varying, 'IMPORT'::character varying]::text[])),
    CONSTRAINT "sync_run_pkey" PRIMARY KEY (id),
    CONSTRAINT "sync_run_requested_by_account_id_fkey" FOREIGN KEY (requested_by_account_id) REFERENCES directory.account(id),
    CONSTRAINT "sync_run_scope_version_check" CHECK (scope_version > 0),
    CONSTRAINT "sync_run_status_check" CHECK (status::text = ANY (ARRAY['READY'::character varying, 'RUNNING'::character varying, 'REVIEW'::character varying, 'SUCCEEDED'::character varying, 'FAILED'::character varying, 'CANCELLED'::character varying]::text[])),
    CONSTRAINT "sync_run_tenant_id_connection_id_fkey" FOREIGN KEY (tenant_id, connection_id) REFERENCES directory.sync_connection(tenant_id, id),
    CONSTRAINT "sync_run_tenant_id_connection_id_id_key" UNIQUE (tenant_id, connection_id, id),
    CONSTRAINT "sync_run_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "sync_run_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "sync_run_tenant_id_idempotency_key_key" UNIQUE (tenant_id, idempotency_key)
);
COMMENT ON TABLE directory.sync_run IS '一次全量、增量或手工导入执行；只有完整同范围结果可以用于缺失项对账。';
COMMENT ON COLUMN directory.sync_run."id" IS '应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.sync_run."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.sync_run."connection_id" IS '外部来源连接；本地 CSV 导入可空。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN directory.sync_run."kind" IS '执行类型。 设计场景：区分全量、增量和人工导入；只有满足完整性与范围条件的全量结果可用于缺失判断，导入不能冒充完整来源快照。';
COMMENT ON COLUMN directory.sync_run."idempotency_key" IS '企业内提交幂等键。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。';
COMMENT ON COLUMN directory.sync_run."scope_version" IS '执行时来源范围版本；IMPORT 可空。 设计场景：客户缩小目录可见范围后，旧全量与新全量不能直接做删除差集，需按范围变更重新判断。';
COMMENT ON COLUMN directory.sync_run."status" IS '运行状态；人工复核前不应用大批停用。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.sync_run."cursor_ciphertext" IS '来源游标加密值，可能包含敏感接口参数。 设计场景：分页或断点续传时恢复读取进度；游标可能携带敏感参数，应加密并限定对应批次使用。';
COMMENT ON COLUMN directory.sync_run."cursor_key_version" IS '游标密文密钥版本。 设计场景：任务跨越密钥轮换窗口继续执行时，仍能解开旧批次保存的游标。';
COMMENT ON COLUMN directory.sync_run."snapshot_complete" IS '完整拉取所有分页并确认授权范围后置 true。 设计场景：只有全部分页及授权范围均确认完整后，才允许把未出现的人作为缺失候选；中途失败不能触发批量离职。';
COMMENT ON COLUMN directory.sync_run."fetched_count" IS '拉取或导入条目数。 设计场景：对照来源条目量和实际处理量识别漏页、规模突变及中途终止，不以计数代替完整快照标记。';
COMMENT ON COLUMN directory.sync_run."applied_count" IS '已成功应用数。 设计场景：区分收到的数据和已经成功改变本地状态的数据，便于恢复只完成一部分的同步批次。';
COMMENT ON COLUMN directory.sync_run."error_count" IS '失败记录数。 设计场景：展示逐项失败规模并决定是否需要复核或重试；不能因为批次大部分成功就隐藏失败记录。';
COMMENT ON COLUMN directory.sync_run."lease_owner" IS '运行租约持有者。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。';
COMMENT ON COLUMN directory.sync_run."lease_until" IS '租约到期。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。';
COMMENT ON COLUMN directory.sync_run."started_at" IS '执行开始。 设计场景：记录一次执行真正开始的时刻，用于识别排队与执行耗时、定位长期运行任务。';
COMMENT ON COLUMN directory.sync_run."finished_at" IS '执行结束。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。';
COMMENT ON COLUMN directory.sync_run."requested_by_account_id" IS '手动请求人；后台任务可空。 设计场景：区分人工发起和允许的后台操作，追溯请求来源；保存账号不替代执行时的权限复核。';
COMMENT ON COLUMN directory.sync_run."error_code" IS '脱敏失败原因。 设计场景：用稳定且脱敏的分类定位失败和选择补偿方式；不把凭据、完整响应或个人资料写入错误字段。';
COMMENT ON COLUMN directory.sync_run."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.sync_run."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_sync_run_connection ON directory.sync_run USING btree (tenant_id, connection_id, created_at DESC);
CREATE INDEX ix_sync_run_status ON directory.sync_run USING btree (tenant_id, status, created_at);

-- directory.source_member：外部员工到稳定企业成员的映射；可关联 PENDING 无账号成员。手机号和邮箱不参与唯一匹配。
CREATE TABLE directory.source_member (
    -- 应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 所属同步连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 来源用户标识类型，区分 user_id/open_id 等作用域。 设计场景：同一厂商可能同时提供 user_id、open_id 等不同范围标识，避免把相同字符串跨标识类型混用。
    "external_id_type" character varying(32) NOT NULL,
    -- 外部主体标识，区分大小写，不做邮箱式规范化。 设计场景：缺少邮箱、手机的员工也能通过来源内稳定标识匹配；必须同时使用连接及标识类型限定作用域。
    "external_subject" character varying(512) COLLATE "C" NOT NULL,
    -- 预登记或已激活的稳定成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 来源明确状态；读取失败不写为 LEFT。 设计场景：区分来源明确离职与读取失败、不可见等情况，只有可靠的状态变化才能进入撤权流程。
    "source_status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 来源版本；无可比较版本时回查来源，禁止字符串盲目排序。 设计场景：同一外部员工事件乱序到达时避免旧状态覆盖新状态；来源未提供可比较版本时回查最新资料，不能比较任意版本字符串。
    "source_version" character varying(200),
    -- 最近在完整或增量同步中确认存在的运行。 设计场景：全量对账时知道对象在哪个批次被确认存在，避免拿旧批次的可见性判断本次删除。
    "last_seen_run_id" bigint,
    -- 最近应用来源变更时间。 设计场景：显示来源数据的最近落地时间，识别资料陈旧或同步中断；不能据此推断当前快照完整。
    "last_synced_at" timestamp with time zone,
    -- 关联已有成员的管理员审核或本人证明时间；同步新建只建立来源对象归属。 设计场景：关联已有本地员工前记录经过核验的时间，避免同步过程仅凭同名或同手机号接管成员记录。
    "binding_verified_at" timestamp with time zone,
    -- 明确关联的受控核验引用。 设计场景：遇到人员关联争议时追溯管理员审核或本人证明，区别有证据的关联与猜测匹配。
    "binding_evidence_ref" character varying(200),
    -- 乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "source_member_check" CHECK ((binding_verified_at IS NULL) = (binding_evidence_ref IS NULL)),
    CONSTRAINT "source_member_connection_id_external_id_type_external_subje_key" UNIQUE (connection_id, external_id_type, external_subject),
    CONSTRAINT "source_member_external_id_type_check" CHECK (btrim(external_id_type::text) <> ''::text),
    CONSTRAINT "source_member_external_subject_check" CHECK (btrim(external_subject::text) <> ''::text),
    CONSTRAINT "source_member_id_check" CHECK (id > 0),
    CONSTRAINT "source_member_pkey" PRIMARY KEY (id),
    CONSTRAINT "source_member_source_status_check" CHECK (source_status::text = ANY (ARRAY['ACTIVE'::character varying, 'SUSPENDED'::character varying, 'LEFT'::character varying, 'OUT_OF_SCOPE'::character varying]::text[])),
    CONSTRAINT "source_member_tenant_id_connection_id_fkey" FOREIGN KEY (tenant_id, connection_id) REFERENCES directory.sync_connection(tenant_id, id),
    CONSTRAINT "source_member_tenant_id_connection_id_id_key" UNIQUE (tenant_id, connection_id, id),
    CONSTRAINT "source_member_tenant_id_connection_id_last_seen_run_id_fkey" FOREIGN KEY (tenant_id, connection_id, last_seen_run_id) REFERENCES directory.sync_run(tenant_id, connection_id, id),
    CONSTRAINT "source_member_tenant_id_connection_id_member_id_key" UNIQUE (tenant_id, connection_id, member_id),
    CONSTRAINT "source_member_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "source_member_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "source_member_tenant_id_id_member_id_key" UNIQUE (tenant_id, id, member_id),
    CONSTRAINT "source_member_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE directory.source_member IS '外部员工到稳定企业成员的映射；可关联 PENDING 无账号成员。手机号和邮箱不参与唯一匹配。';
COMMENT ON COLUMN directory.source_member."id" IS '应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.source_member."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.source_member."connection_id" IS '所属同步连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN directory.source_member."external_id_type" IS '来源用户标识类型，区分 user_id/open_id 等作用域。 设计场景：同一厂商可能同时提供 user_id、open_id 等不同范围标识，避免把相同字符串跨标识类型混用。';
COMMENT ON COLUMN directory.source_member."external_subject" IS '外部主体标识，区分大小写，不做邮箱式规范化。 设计场景：缺少邮箱、手机的员工也能通过来源内稳定标识匹配；必须同时使用连接及标识类型限定作用域。';
COMMENT ON COLUMN directory.source_member."member_id" IS '预登记或已激活的稳定成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN directory.source_member."source_status" IS '来源明确状态；读取失败不写为 LEFT。 设计场景：区分来源明确离职与读取失败、不可见等情况，只有可靠的状态变化才能进入撤权流程。';
COMMENT ON COLUMN directory.source_member."source_version" IS '来源版本；无可比较版本时回查来源，禁止字符串盲目排序。 设计场景：同一外部员工事件乱序到达时避免旧状态覆盖新状态；来源未提供可比较版本时回查最新资料，不能比较任意版本字符串。';
COMMENT ON COLUMN directory.source_member."last_seen_run_id" IS '最近在完整或增量同步中确认存在的运行。 设计场景：全量对账时知道对象在哪个批次被确认存在，避免拿旧批次的可见性判断本次删除。';
COMMENT ON COLUMN directory.source_member."last_synced_at" IS '最近应用来源变更时间。 设计场景：显示来源数据的最近落地时间，识别资料陈旧或同步中断；不能据此推断当前快照完整。';
COMMENT ON COLUMN directory.source_member."binding_verified_at" IS '关联已有成员的管理员审核或本人证明时间；同步新建只建立来源对象归属。 设计场景：关联已有本地员工前记录经过核验的时间，避免同步过程仅凭同名或同手机号接管成员记录。';
COMMENT ON COLUMN directory.source_member."binding_evidence_ref" IS '明确关联的受控核验引用。 设计场景：遇到人员关联争议时追溯管理员审核或本人证明，区别有证据的关联与猜测匹配。';
COMMENT ON COLUMN directory.source_member."version" IS '乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.source_member."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.source_member."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_source_member_member ON directory.source_member USING btree (tenant_id, member_id);

-- directory.membership：企业员工与成员记录；PENDING 可无账号。完成本人证明后关联账号；ACTIVE/SUSPENDED 必须有关联。租户内已关联账号唯一。
CREATE TABLE directory.membership (
    -- 企业成员 ID，由应用生成雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 成员所属企业，与账号构成唯一成员身份。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 关联的平台账号；待激活或未激活即移除时可空；不能依据未经验证的企业联系方式填写。 设计场景：企业先同步到员工但员工尚未激活时允许为空；完成本人核验后再关联平台账号，ACTIVE/SUSPENDED 不能保持空账号，不能凭同名或工作邮箱自动填充。
    "account_id" bigint,
    -- PENDING 待激活、ACTIVE 有效、SUSPENDED 暂停、REMOVED 已移除；只有 ACTIVE 可取得业务访问。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    -- 可选的企业内显示名称，不修改全局账号标识。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。
    "display_name" character varying(200),
    -- 本次加入企业的时间；恢复成员时重设。 设计场景：成员离职后重新入职时表示当前这一轮加入时间，历史轮次由审计保留，不能恢复旧授权作为默认权限。
    "joined_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 本次移除时间；仅 REMOVED 状态非空，恢复成员时清空。 设计场景：表示当前成员关系已移除及其时间；恢复关系时按业务规则清空并重新核定权限。
    "removed_at" timestamp with time zone,
    -- 成员状态及整个成员授权集合共用的并发版本，由 Directory 协调用例推进。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 该成员身份首次创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由应用写入。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 首次关联并完成激活的时间；不是单凭同步即视作本人已验证。 设计场景：区分预登记员工与已经完成本人核验的成员，同步进来的人不会仅因有记录就获得登录资格。
    "activated_at" timestamp with time zone,
    -- 当前资料维护权：LOCAL 本地，EXTERNAL 外部连接；接管需显式确认并保存来源映射。 设计场景：手工维护和外部同步共存时决定谁可以更新资料，避免同步覆盖明确由管理员维护的字段。
    "maintenance_mode" character varying(16) DEFAULT 'LOCAL'::character varying NOT NULL,
    -- 当前资料维护连接；LOCAL 必须为空，EXTERNAL 必须有同企业连接。维护权转移不改变对象 ID。 设计场景：多个目录来源存在时明确当前负责维护的连接，接管来源时保持成员或部门的本地 ID 不变。
    "managed_connection_id" bigint,
    CONSTRAINT "ck_membership_activation" CHECK ((status::text = ANY (ARRAY['PENDING'::character varying, 'REMOVED'::character varying]::text[])) OR account_id IS NOT NULL AND activated_at IS NOT NULL),
    CONSTRAINT "ck_membership_display_name" CHECK (display_name IS NULL OR btrim(display_name::text) <> ''::text),
    CONSTRAINT "ck_membership_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_membership_maintainer" CHECK ((maintenance_mode::text = 'EXTERNAL'::text) = (managed_connection_id IS NOT NULL)),
    CONSTRAINT "ck_membership_removed_at" CHECK (status::text = 'REMOVED'::text AND removed_at IS NOT NULL AND removed_at >= joined_at OR status::text <> 'REMOVED'::text AND removed_at IS NULL),
    CONSTRAINT "ck_membership_status" CHECK (status::text = ANY (ARRAY['PENDING'::character varying, 'ACTIVE'::character varying, 'SUSPENDED'::character varying, 'REMOVED'::character varying]::text[])),
    CONSTRAINT "ck_membership_version" CHECK (version >= 0),
    CONSTRAINT "fk_membership_account" FOREIGN KEY (account_id) REFERENCES directory.account(id) ON DELETE RESTRICT,
    CONSTRAINT "fk_membership_maintainer" FOREIGN KEY (tenant_id, managed_connection_id) REFERENCES directory.sync_connection(tenant_id, id),
    CONSTRAINT "fk_membership_source_owner" FOREIGN KEY (tenant_id, managed_connection_id, id) REFERENCES directory.source_member(tenant_id, connection_id, member_id) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT "fk_membership_tenant" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "membership_maintenance_mode_check" CHECK (maintenance_mode::text = ANY (ARRAY['LOCAL'::character varying, 'EXTERNAL'::character varying]::text[])),
    CONSTRAINT "pk_directory_membership" PRIMARY KEY (id),
    CONSTRAINT "uq_membership_tenant_account" UNIQUE (tenant_id, account_id),
    CONSTRAINT "uq_membership_tenant_id" UNIQUE (tenant_id, id),
    CONSTRAINT "uq_membership_tenant_id_account" UNIQUE (tenant_id, id, account_id)
);
COMMENT ON TABLE directory.membership IS '企业员工与成员记录；PENDING 可无账号。完成本人证明后关联账号；ACTIVE/SUSPENDED 必须有关联。租户内已关联账号唯一。';
COMMENT ON COLUMN directory.membership."id" IS '企业成员 ID，由应用生成雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.membership."tenant_id" IS '成员所属企业，与账号构成唯一成员身份。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.membership."account_id" IS '关联的平台账号；待激活或未激活即移除时可空；不能依据未经验证的企业联系方式填写。 设计场景：企业先同步到员工但员工尚未激活时允许为空；完成本人核验后再关联平台账号，ACTIVE/SUSPENDED 不能保持空账号，不能凭同名或工作邮箱自动填充。';
COMMENT ON COLUMN directory.membership."status" IS 'PENDING 待激活、ACTIVE 有效、SUSPENDED 暂停、REMOVED 已移除；只有 ACTIVE 可取得业务访问。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.membership."display_name" IS '可选的企业内显示名称，不修改全局账号标识。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。';
COMMENT ON COLUMN directory.membership."joined_at" IS '本次加入企业的时间；恢复成员时重设。 设计场景：成员离职后重新入职时表示当前这一轮加入时间，历史轮次由审计保留，不能恢复旧授权作为默认权限。';
COMMENT ON COLUMN directory.membership."removed_at" IS '本次移除时间；仅 REMOVED 状态非空，恢复成员时清空。 设计场景：表示当前成员关系已移除及其时间；恢复关系时按业务规则清空并重新核定权限。';
COMMENT ON COLUMN directory.membership."version" IS '成员状态及整个成员授权集合共用的并发版本，由 Directory 协调用例推进。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.membership."created_at" IS '该成员身份首次创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.membership."updated_at" IS '最近更新时间，由应用写入。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
COMMENT ON COLUMN directory.membership."activated_at" IS '首次关联并完成激活的时间；不是单凭同步即视作本人已验证。 设计场景：区分预登记员工与已经完成本人核验的成员，同步进来的人不会仅因有记录就获得登录资格。';
COMMENT ON COLUMN directory.membership."maintenance_mode" IS '当前资料维护权：LOCAL 本地，EXTERNAL 外部连接；接管需显式确认并保存来源映射。 设计场景：手工维护和外部同步共存时决定谁可以更新资料，避免同步覆盖明确由管理员维护的字段。';
COMMENT ON COLUMN directory.membership."managed_connection_id" IS '当前资料维护连接；LOCAL 必须为空，EXTERNAL 必须有同企业连接。维护权转移不改变对象 ID。 设计场景：多个目录来源存在时明确当前负责维护的连接，接管来源时保持成员或部门的本地 ID 不变。';
CREATE INDEX ix_membership_account_status_tenant ON directory.membership USING btree (account_id, status, tenant_id);
CREATE INDEX ix_membership_maintainer ON directory.membership USING btree (tenant_id, managed_connection_id);
CREATE INDEX ix_membership_tenant_status_created ON directory.membership USING btree (tenant_id, status, created_at, id);

-- access.role：每个企业独立的角色实例；角色变更影响所有现有授权
CREATE TABLE access.role (
    -- 本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 企业内唯一角色代码；TENANT_ADMIN 专供内置企业管理员。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。
    "code" character varying(64) NOT NULL,
    -- 面向用户展示的名称，不作为身份关联键。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。
    "name" character varying(100) NOT NULL,
    -- BUILTIN 仅对应 TENANT_ADMIN，其他角色为 CUSTOM；检查不替代接口变更限制。 设计场景：区分内置租户管理员角色与客户自定义角色，避免普通角色编辑接口修改系统管理职责或绕过最后管理员保护。
    "kind" character varying(16) NOT NULL,
    -- 请求使用 ACTIVE 角色；内置管理员角色不得由普通企业接口停用。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 角色与角色动作集合共同的乐观锁版本，更新需原子递增并审计。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_role_builtin_code" CHECK (kind::text = 'BUILTIN'::text AND code::text = 'TENANT_ADMIN'::text OR kind::text = 'CUSTOM'::text AND code::text <> 'TENANT_ADMIN'::text),
    CONSTRAINT "ck_role_code" CHECK (code::text = btrim(code::text) AND code::text <> ''::text),
    CONSTRAINT "ck_role_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_role_kind" CHECK (kind::text = ANY (ARRAY['BUILTIN'::character varying, 'CUSTOM'::character varying]::text[])),
    CONSTRAINT "ck_role_name" CHECK (btrim(name::text) <> ''::text),
    CONSTRAINT "ck_role_status" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying]::text[])),
    CONSTRAINT "ck_role_times" CHECK (updated_at >= created_at),
    CONSTRAINT "ck_role_version" CHECK (version >= 0),
    CONSTRAINT "fk_role_tenant" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "pk_role" PRIMARY KEY (id),
    CONSTRAINT "uq_role_tenant_code" UNIQUE (tenant_id, code),
    CONSTRAINT "uq_role_tenant_id" UNIQUE (tenant_id, id)
);
COMMENT ON TABLE access.role IS '每个企业独立的角色实例；角色变更影响所有现有授权';
COMMENT ON COLUMN access.role."id" IS '本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.role."tenant_id" IS '所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.role."code" IS '企业内唯一角色代码；TENANT_ADMIN 专供内置企业管理员。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。';
COMMENT ON COLUMN access.role."name" IS '面向用户展示的名称，不作为身份关联键。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。';
COMMENT ON COLUMN access.role."kind" IS 'BUILTIN 仅对应 TENANT_ADMIN，其他角色为 CUSTOM；检查不替代接口变更限制。 设计场景：区分内置租户管理员角色与客户自定义角色，避免普通角色编辑接口修改系统管理职责或绕过最后管理员保护。';
COMMENT ON COLUMN access.role."status" IS '请求使用 ACTIVE 角色；内置管理员角色不得由普通企业接口停用。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN access.role."version" IS '角色与角色动作集合共同的乐观锁版本，更新需原子递增并审计。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN access.role."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.role."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_role_tenant_status ON access.role USING btree (tenant_id, status, id);

-- access.authorization_request：临时或长期业务角色申请与审批状态；批准后仍须重新核对角色版本、发起人及资源资格
CREATE TABLE access.authorization_request (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 申请发起者。 设计场景：支持本人申请或代他人申请，审批时防止发起者自批。
    "requester_member_id" bigint NOT NULL,
    -- 权限接收成员。 设计场景：将权限最终获得者与申请人分开，代申请时仍检查受益人的企业资格并禁止受益人自批。
    "beneficiary_member_id" bigint NOT NULL,
    -- 申请的业务角色。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。
    "role_id" bigint NOT NULL,
    -- 申请时角色版本；版本变化必须重审。 设计场景：等待审批或邀请接受期间角色权限可能扩大；对比原版本决定重新确认，避免旧同意无意包含新权限。
    "role_version_snapshot" bigint NOT NULL,
    -- 申请的范围模式。 设计场景：显式区分全企业、指定店铺或指定资源等范围；空的明细集合不能被解释为全部权限。
    "scope_mode" character varying(24) NOT NULL,
    -- 申请原因，不得含秘密。 设计场景：让审批、撤销或变更决定有可追溯的理由，便于申诉和审计；不能用自由文本代替结构化状态。
    "reason" character varying(1000) NOT NULL,
    -- 申请生命周期；批准不等于已落地授权。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    -- 所需独立审批人数。 设计场景：需要多人复核的授权必须获得足够的独立决定，防止一个人重复点击凑足票数。
    "required_approvals" smallint DEFAULT 1 NOT NULL,
    -- 申请授权开始时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。
    "valid_from" timestamp with time zone NOT NULL,
    -- 申请授权到期时间；为空表示长期。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。
    "valid_until" timestamp with time zone,
    -- 审批截止时间。 设计场景：过期未审批的申请不能无限期等待后再生效，截止后需按业务规则重新申请。
    "decision_due_at" timestamp with time zone NOT NULL,
    -- 并发版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "authorization_request_check" CHECK (updated_at >= created_at),
    CONSTRAINT "authorization_request_check1" CHECK (valid_until IS NULL OR valid_until > valid_from),
    CONSTRAINT "authorization_request_check2" CHECK (decision_due_at > created_at),
    CONSTRAINT "authorization_request_id_check" CHECK (id > 0),
    CONSTRAINT "authorization_request_pkey" PRIMARY KEY (id),
    CONSTRAINT "authorization_request_reason_check" CHECK (btrim(reason::text) <> ''::text),
    CONSTRAINT "authorization_request_required_approvals_check" CHECK (required_approvals > 0),
    CONSTRAINT "authorization_request_role_version_snapshot_check" CHECK (role_version_snapshot >= 0),
    CONSTRAINT "authorization_request_scope_mode_check" CHECK (scope_mode::text = ANY (ARRAY['ALL_TENANT'::character varying, 'SELECTED_STORES'::character varying, 'SELECTED_RESOURCES'::character varying]::text[])),
    CONSTRAINT "authorization_request_status_check" CHECK (status::text = ANY (ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying, 'EXPIRED'::character varying, 'FULFILLED'::character varying]::text[])),
    CONSTRAINT "authorization_request_tenant_id_beneficiary_member_id_fkey" FOREIGN KEY (tenant_id, beneficiary_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "authorization_request_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "authorization_request_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "authorization_request_tenant_id_id_requester_member_id_bene_key" UNIQUE (tenant_id, id, requester_member_id, beneficiary_member_id),
    CONSTRAINT "authorization_request_tenant_id_requester_member_id_fkey" FOREIGN KEY (tenant_id, requester_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "authorization_request_tenant_id_role_id_fkey" FOREIGN KEY (tenant_id, role_id) REFERENCES access.role(tenant_id, id),
    CONSTRAINT "authorization_request_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE access.authorization_request IS '临时或长期业务角色申请与审批状态；批准后仍须重新核对角色版本、发起人及资源资格';
COMMENT ON COLUMN access.authorization_request."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.authorization_request."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.authorization_request."requester_member_id" IS '申请发起者。 设计场景：支持本人申请或代他人申请，审批时防止发起者自批。';
COMMENT ON COLUMN access.authorization_request."beneficiary_member_id" IS '权限接收成员。 设计场景：将权限最终获得者与申请人分开，代申请时仍检查受益人的企业资格并禁止受益人自批。';
COMMENT ON COLUMN access.authorization_request."role_id" IS '申请的业务角色。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。';
COMMENT ON COLUMN access.authorization_request."role_version_snapshot" IS '申请时角色版本；版本变化必须重审。 设计场景：等待审批或邀请接受期间角色权限可能扩大；对比原版本决定重新确认，避免旧同意无意包含新权限。';
COMMENT ON COLUMN access.authorization_request."scope_mode" IS '申请的范围模式。 设计场景：显式区分全企业、指定店铺或指定资源等范围；空的明细集合不能被解释为全部权限。';
COMMENT ON COLUMN access.authorization_request."reason" IS '申请原因，不得含秘密。 设计场景：让审批、撤销或变更决定有可追溯的理由，便于申诉和审计；不能用自由文本代替结构化状态。';
COMMENT ON COLUMN access.authorization_request."status" IS '申请生命周期；批准不等于已落地授权。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN access.authorization_request."required_approvals" IS '所需独立审批人数。 设计场景：需要多人复核的授权必须获得足够的独立决定，防止一个人重复点击凑足票数。';
COMMENT ON COLUMN access.authorization_request."valid_from" IS '申请授权开始时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。';
COMMENT ON COLUMN access.authorization_request."valid_until" IS '申请授权到期时间；为空表示长期。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。';
COMMENT ON COLUMN access.authorization_request."decision_due_at" IS '审批截止时间。 设计场景：过期未审批的申请不能无限期等待后再生效，截止后需按业务规则重新申请。';
COMMENT ON COLUMN access.authorization_request."version" IS '并发版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN access.authorization_request."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.authorization_request."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_access_authorization_request_beneficiary ON access.authorization_request USING btree (tenant_id, beneficiary_member_id);
CREATE INDEX ix_access_authorization_request_pending ON access.authorization_request USING btree (tenant_id, status, decision_due_at);
CREATE INDEX ix_access_authorization_request_requester ON access.authorization_request USING btree (tenant_id, requester_member_id);
CREATE INDEX ix_access_authorization_request_role ON access.authorization_request USING btree (tenant_id, role_id);

-- access.approval_decision：审批人对一次申请的不可变决定；发起者和受益人均不能自批
CREATE TABLE access.approval_decision (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 授权申请。 设计场景：一条决定只对应一份授权申请，同一审批人不能重复计票，且须禁止申请人和受益人自批。
    "request_id" bigint NOT NULL,
    -- 与申请一致的发起成员，用于数据库防自批。 设计场景：支持本人申请或代他人申请，审批时防止发起者自批。
    "requester_member_id" bigint NOT NULL,
    -- 与申请一致的受益成员，用于数据库防自批。 设计场景：将权限最终获得者与申请人分开，代申请时仍检查受益人的企业资格并禁止受益人自批。
    "beneficiary_member_id" bigint NOT NULL,
    -- 审批成员。 设计场景：限定由目标企业中有审批资格的人作决定，并检查其与申请人、受益人的职责分离。
    "reviewer_member_id" bigint NOT NULL,
    -- 审批决定。 设计场景：保存明确的处理决定供后续执行与追溯；决定本身和实际执行完成分别验证。
    "decision" character varying(16) NOT NULL,
    -- 审批原因。 设计场景：让审批、撤销或变更决定有可追溯的理由，便于申诉和审计；不能用自由文本代替结构化状态。
    "reason" character varying(1000) NOT NULL,
    -- 审批时间。 设计场景：记录批准、拒绝或复核决定的时间，便于判断是否在截止期内作出及追踪审批顺序。
    "decided_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "approval_decision_check" CHECK (updated_at >= created_at),
    CONSTRAINT "approval_decision_check1" CHECK (reviewer_member_id <> requester_member_id AND reviewer_member_id <> beneficiary_member_id),
    CONSTRAINT "approval_decision_decision_check" CHECK (decision::text = ANY (ARRAY['APPROVE'::character varying, 'REJECT'::character varying]::text[])),
    CONSTRAINT "approval_decision_id_check" CHECK (id > 0),
    CONSTRAINT "approval_decision_pkey" PRIMARY KEY (id),
    CONSTRAINT "approval_decision_reason_check" CHECK (btrim(reason::text) <> ''::text),
    CONSTRAINT "approval_decision_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "approval_decision_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "approval_decision_tenant_id_request_id_requester_member_id_fkey" FOREIGN KEY (tenant_id, request_id, requester_member_id, beneficiary_member_id) REFERENCES access.authorization_request(tenant_id, id, requester_member_id, beneficiary_member_id),
    CONSTRAINT "approval_decision_tenant_id_request_id_reviewer_member_id_key" UNIQUE (tenant_id, request_id, reviewer_member_id),
    CONSTRAINT "approval_decision_tenant_id_reviewer_member_id_fkey" FOREIGN KEY (tenant_id, reviewer_member_id) REFERENCES directory.membership(tenant_id, id)
);
COMMENT ON TABLE access.approval_decision IS '审批人对一次申请的不可变决定；发起者和受益人均不能自批';
COMMENT ON COLUMN access.approval_decision."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.approval_decision."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.approval_decision."request_id" IS '授权申请。 设计场景：一条决定只对应一份授权申请，同一审批人不能重复计票，且须禁止申请人和受益人自批。';
COMMENT ON COLUMN access.approval_decision."requester_member_id" IS '与申请一致的发起成员，用于数据库防自批。 设计场景：支持本人申请或代他人申请，审批时防止发起者自批。';
COMMENT ON COLUMN access.approval_decision."beneficiary_member_id" IS '与申请一致的受益成员，用于数据库防自批。 设计场景：将权限最终获得者与申请人分开，代申请时仍检查受益人的企业资格并禁止受益人自批。';
COMMENT ON COLUMN access.approval_decision."reviewer_member_id" IS '审批成员。 设计场景：限定由目标企业中有审批资格的人作决定，并检查其与申请人、受益人的职责分离。';
COMMENT ON COLUMN access.approval_decision."decision" IS '审批决定。 设计场景：保存明确的处理决定供后续执行与追溯；决定本身和实际执行完成分别验证。';
COMMENT ON COLUMN access.approval_decision."reason" IS '审批原因。 设计场景：让审批、撤销或变更决定有可追溯的理由，便于申诉和审计；不能用自由文本代替结构化状态。';
COMMENT ON COLUMN access.approval_decision."decided_at" IS '审批时间。 设计场景：记录批准、拒绝或复核决定的时间，便于判断是否在截止期内作出及追踪审批顺序。';
COMMENT ON COLUMN access.approval_decision."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.approval_decision."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_access_approval_decision_reviewer ON access.approval_decision USING btree (tenant_id, reviewer_member_id);

-- access.policy：版本化授权或组织自动分配规则；每个发布版本独立保留，关系和动作不藏入条件 JSON
CREATE TABLE access.policy (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 企业内稳定策略代码。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。
    "code" character varying(64) NOT NULL,
    -- 策略版本号。 设计场景：同一个策略或预批准保留多个业务版本，已执行结果能引用当时版本；与记录乐观锁 version 分工不同。
    "revision" integer NOT NULL,
    -- 显式授权规则或组织自动分配规则。 设计场景：区别显式访问规则和组织自动分配规则，执行器按类型处理，不能把分配规则直接当作所有请求的放行条件。
    "kind" character varying(24) NOT NULL,
    -- 允许或拒绝；适用的拒绝先于允许。 设计场景：显式拒绝与允许并存时优先拒绝，避免通过另一条角色授权绕过限制。
    "effect" character varying(8) NOT NULL,
    -- 草稿、已发布、已退役；已发布内容修改须新建版本。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'DRAFT'::character varying NOT NULL,
    -- 自动分配或角色条件所引用的同企业角色。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。
    "role_id" bigint,
    -- 受控属性条件表达式的结构版本。 设计场景：规则表达式升级后仍能按对应结构解释旧配置，未知版本拒绝执行而非随意猜测字段含义。
    "condition_schema_version" integer DEFAULT 1 NOT NULL,
    -- 仅保存白名单属性、运算符与值组成的条件树；不得保存账号、角色或资源关系、代码和秘密。 设计场景：用受控条件树表达属性规则，便于校验和审查；不能执行任意脚本或把正式关系藏进 JSON 绕过约束。
    "conditions" jsonb DEFAULT '{}'::jsonb NOT NULL,
    -- 规则最早生效时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。
    "valid_from" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 规则失效时间；为空表示无预设到期。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。
    "valid_until" timestamp with time zone,
    -- 发布时间。 设计场景：区分保存草稿与正式发布，便于追踪某段时间实际采用哪份规则或连接配置。
    "published_at" timestamp with time zone,
    -- 发布者企业成员。 设计场景：追溯哪位企业管理员使策略正式生效，发布时校验资格及职责互斥。
    "published_by_member_id" bigint,
    -- 并发更新版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "policy_check" CHECK (updated_at >= created_at),
    CONSTRAINT "policy_check1" CHECK (valid_until IS NULL OR valid_until > valid_from),
    CONSTRAINT "policy_check2" CHECK (status::text = 'DRAFT'::text AND published_at IS NULL AND published_by_member_id IS NULL OR (status::text = ANY (ARRAY['PUBLISHED'::character varying, 'RETIRED'::character varying]::text[])) AND published_at IS NOT NULL AND published_by_member_id IS NOT NULL),
    CONSTRAINT "policy_check3" CHECK (kind::text <> 'AUTO_ASSIGNMENT'::text OR effect::text = 'ALLOW'::text AND role_id IS NOT NULL),
    CONSTRAINT "policy_code_check" CHECK (btrim(code::text) <> ''::text),
    CONSTRAINT "policy_condition_schema_version_check" CHECK (condition_schema_version > 0),
    CONSTRAINT "policy_conditions_check" CHECK (jsonb_typeof(conditions) = 'object'::text),
    CONSTRAINT "policy_effect_check" CHECK (effect::text = ANY (ARRAY['ALLOW'::character varying, 'DENY'::character varying]::text[])),
    CONSTRAINT "policy_id_check" CHECK (id > 0),
    CONSTRAINT "policy_kind_check" CHECK (kind::text = ANY (ARRAY['AUTHORIZATION'::character varying, 'AUTO_ASSIGNMENT'::character varying]::text[])),
    CONSTRAINT "policy_pkey" PRIMARY KEY (id),
    CONSTRAINT "policy_revision_check" CHECK (revision > 0),
    CONSTRAINT "policy_status_check" CHECK (status::text = ANY (ARRAY['DRAFT'::character varying, 'PUBLISHED'::character varying, 'RETIRED'::character varying]::text[])),
    CONSTRAINT "policy_tenant_id_code_revision_key" UNIQUE (tenant_id, code, revision),
    CONSTRAINT "policy_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "policy_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "policy_tenant_id_published_by_member_id_fkey" FOREIGN KEY (tenant_id, published_by_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "policy_tenant_id_role_id_fkey" FOREIGN KEY (tenant_id, role_id) REFERENCES access.role(tenant_id, id),
    CONSTRAINT "policy_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE access.policy IS '版本化授权或组织自动分配规则；每个发布版本独立保留，关系和动作不藏入条件 JSON';
COMMENT ON COLUMN access.policy."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.policy."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.policy."code" IS '企业内稳定策略代码。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。';
COMMENT ON COLUMN access.policy."revision" IS '策略版本号。 设计场景：同一个策略或预批准保留多个业务版本，已执行结果能引用当时版本；与记录乐观锁 version 分工不同。';
COMMENT ON COLUMN access.policy."kind" IS '显式授权规则或组织自动分配规则。 设计场景：区别显式访问规则和组织自动分配规则，执行器按类型处理，不能把分配规则直接当作所有请求的放行条件。';
COMMENT ON COLUMN access.policy."effect" IS '允许或拒绝；适用的拒绝先于允许。 设计场景：显式拒绝与允许并存时优先拒绝，避免通过另一条角色授权绕过限制。';
COMMENT ON COLUMN access.policy."status" IS '草稿、已发布、已退役；已发布内容修改须新建版本。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN access.policy."role_id" IS '自动分配或角色条件所引用的同企业角色。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。';
COMMENT ON COLUMN access.policy."condition_schema_version" IS '受控属性条件表达式的结构版本。 设计场景：规则表达式升级后仍能按对应结构解释旧配置，未知版本拒绝执行而非随意猜测字段含义。';
COMMENT ON COLUMN access.policy."conditions" IS '仅保存白名单属性、运算符与值组成的条件树；不得保存账号、角色或资源关系、代码和秘密。 设计场景：用受控条件树表达属性规则，便于校验和审查；不能执行任意脚本或把正式关系藏进 JSON 绕过约束。';
COMMENT ON COLUMN access.policy."valid_from" IS '规则最早生效时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。';
COMMENT ON COLUMN access.policy."valid_until" IS '规则失效时间；为空表示无预设到期。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。';
COMMENT ON COLUMN access.policy."published_at" IS '发布时间。 设计场景：区分保存草稿与正式发布，便于追踪某段时间实际采用哪份规则或连接配置。';
COMMENT ON COLUMN access.policy."published_by_member_id" IS '发布者企业成员。 设计场景：追溯哪位企业管理员使策略正式生效，发布时校验资格及职责互斥。';
COMMENT ON COLUMN access.policy."version" IS '并发更新版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN access.policy."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.policy."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_access_policy_active ON access.policy USING btree (tenant_id, status, valid_until);
CREATE INDEX ix_access_policy_publisher ON access.policy USING btree (tenant_id, published_by_member_id);
CREATE INDEX ix_access_policy_role ON access.policy USING btree (tenant_id, role_id);
CREATE UNIQUE INDEX uq_policy_published_code ON access.policy USING btree (tenant_id, code) WHERE ((status)::text = 'PUBLISHED'::text);

-- access.member_grant：当前成员授权；角色动作和资源范围必须在同一条 grant 内匹配
CREATE TABLE access.member_grant (
    -- 本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 当前企业内的成员 ID。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 同企业角色 ID。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。
    "role_id" bigint NOT NULL,
    -- ALL_TENANT 为当前企业相应资源；指定店铺/其他资源必须有非空范围，不跨授权拼接动作和范围。 设计场景：显式区分全企业、指定店铺或指定资源等范围；空的明细集合不能被解释为全部权限。
    "scope_mode" character varying(24) NOT NULL,
    -- 授予授权的账号；其当前授权资格由事务用例检查，不由此外键保证。 设计场景：保留授权责任人，追踪权限来源；授权时必须另外验证授予人的当前可授予范围。
    "granted_by_account_id" bigint NOT NULL,
    -- 当前授权授予时间；历史变更另外写入审计。 设计场景：用于说明这项授权何时建立，判断来源及后续复核范围；实际有效期由起止时间另行控制。
    "granted_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 由应用维护；成员授权集合并发控制使用 membership.version。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 授权来源类型；直接、组织策略、审批、管理委派或内部工作身份。 设计场景：区分手工、策略、审批或委派等来源，撤销某个来源时不误删独立获得的其他资格。
    "source_kind" character varying(24) DEFAULT 'DIRECT'::character varying NOT NULL,
    -- 来源的具体策略版本；撤销规则时仅撤销依赖授权。 设计场景：策略停用或变更时只处理依赖该版本形成的关系，便于解释自动授权从何而来。
    "source_policy_id" bigint,
    -- 来源的审批申请；仅批准且仍有效的申请可形成授权。 设计场景：将最终授权追溯到批准申请，执行前复核申请、角色版本和资源仍有效。
    "source_request_id" bigint,
    -- 来源管理委派；使用时检查委派与上游授权仍有效。 设计场景：上游管理委派失效时找出依赖它授出的权限，防止下级授权脱离来源永久存活。
    "source_delegation_id" bigint,
    -- 工作身份所在企业；这是显式跨企业依赖，不是自动互信。 设计场景：内部员工为客户工作时显式记录其来源企业，离职只级联工作依赖而不影响独立客户身份。
    "source_member_tenant_id" bigint,
    -- 工作身份成员；仅撤销依赖此身份的工作授权。 设计场景：内部员工负责客户工作时记录授权依赖的内部成员；该成员离职只撤销依赖它的工作授权，不删除独立取得的客户资格。
    "source_member_id" bigint,
    -- 授权最早有效时间；授权计算必须检查开始时间与截止时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。
    "valid_from" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 授权结束时间；每次使用实时检查，不能等待清理任务。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。
    "valid_until" timestamp with time zone,
    -- 当前授权有效或已撤销；历史记录不能重新自动激活。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 授权撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 脱敏授予或撤销原因。 设计场景：让审批、撤销或变更决定有可追溯的理由，便于申诉和审计；不能用自由文本代替结构化状态。
    "reason" character varying(500),
    CONSTRAINT "ck_member_grant_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_member_grant_kind" CHECK (source_kind::text = ANY (ARRAY['DIRECT'::character varying, 'POLICY'::character varying, 'APPROVAL'::character varying, 'DELEGATION'::character varying, 'WORK_ASSIGNMENT'::character varying]::text[])),
    CONSTRAINT "ck_member_grant_lifetime" CHECK (valid_until IS NULL OR valid_until > valid_from),
    CONSTRAINT "ck_member_grant_origin" CHECK (source_kind::text = 'DIRECT'::text AND num_nonnulls(source_policy_id, source_request_id, source_delegation_id, source_member_tenant_id, source_member_id) = 0 OR source_kind::text = 'POLICY'::text AND source_policy_id IS NOT NULL AND num_nonnulls(source_policy_id, source_request_id, source_delegation_id, source_member_tenant_id, source_member_id) = 1 OR source_kind::text = 'APPROVAL'::text AND source_request_id IS NOT NULL AND num_nonnulls(source_policy_id, source_request_id, source_delegation_id, source_member_tenant_id, source_member_id) = 1 OR source_kind::text = 'DELEGATION'::text AND source_delegation_id IS NOT NULL AND num_nonnulls(source_policy_id, source_request_id, source_delegation_id, source_member_tenant_id, source_member_id) = 1 OR source_kind::text = 'WORK_ASSIGNMENT'::text AND source_member_tenant_id IS NOT NULL AND source_member_id IS NOT NULL AND num_nonnulls(source_policy_id, source_request_id, source_delegation_id, source_member_tenant_id, source_member_id) = 2),
    CONSTRAINT "ck_member_grant_scope" CHECK (scope_mode::text = ANY (ARRAY['ALL_TENANT'::character varying, 'SELECTED_STORES'::character varying, 'SELECTED_RESOURCES'::character varying]::text[])),
    CONSTRAINT "ck_member_grant_status" CHECK (status::text = 'ACTIVE'::text AND revoked_at IS NULL OR status::text = 'REVOKED'::text AND revoked_at IS NOT NULL),
    CONSTRAINT "ck_member_grant_times" CHECK (updated_at >= created_at),
    CONSTRAINT "fk_member_grant_granted_by" FOREIGN KEY (granted_by_account_id) REFERENCES directory.account(id) ON DELETE RESTRICT,
    CONSTRAINT "fk_member_grant_member" FOREIGN KEY (tenant_id, member_id) REFERENCES directory.membership(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "fk_member_grant_policy" FOREIGN KEY (tenant_id, source_policy_id) REFERENCES access.policy(tenant_id, id),
    CONSTRAINT "fk_member_grant_request" FOREIGN KEY (tenant_id, source_request_id) REFERENCES access.authorization_request(tenant_id, id),
    CONSTRAINT "fk_member_grant_role" FOREIGN KEY (tenant_id, role_id) REFERENCES access.role(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "fk_member_grant_source_member" FOREIGN KEY (source_member_tenant_id, source_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "pk_member_grant" PRIMARY KEY (id),
    CONSTRAINT "uq_member_grant_member_id" UNIQUE (tenant_id, id, member_id),
    CONSTRAINT "uq_member_grant_tenant_id" UNIQUE (tenant_id, id)
);
COMMENT ON TABLE access.member_grant IS '当前成员授权；角色动作和资源范围必须在同一条 grant 内匹配';
COMMENT ON COLUMN access.member_grant."id" IS '本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.member_grant."tenant_id" IS '所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.member_grant."member_id" IS '当前企业内的成员 ID。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN access.member_grant."role_id" IS '同企业角色 ID。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。';
COMMENT ON COLUMN access.member_grant."scope_mode" IS 'ALL_TENANT 为当前企业相应资源；指定店铺/其他资源必须有非空范围，不跨授权拼接动作和范围。 设计场景：显式区分全企业、指定店铺或指定资源等范围；空的明细集合不能被解释为全部权限。';
COMMENT ON COLUMN access.member_grant."granted_by_account_id" IS '授予授权的账号；其当前授权资格由事务用例检查，不由此外键保证。 设计场景：保留授权责任人，追踪权限来源；授权时必须另外验证授予人的当前可授予范围。';
COMMENT ON COLUMN access.member_grant."granted_at" IS '当前授权授予时间；历史变更另外写入审计。 设计场景：用于说明这项授权何时建立，判断来源及后续复核范围；实际有效期由起止时间另行控制。';
COMMENT ON COLUMN access.member_grant."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.member_grant."updated_at" IS '由应用维护；成员授权集合并发控制使用 membership.version。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
COMMENT ON COLUMN access.member_grant."source_kind" IS '授权来源类型；直接、组织策略、审批、管理委派或内部工作身份。 设计场景：区分手工、策略、审批或委派等来源，撤销某个来源时不误删独立获得的其他资格。';
COMMENT ON COLUMN access.member_grant."source_policy_id" IS '来源的具体策略版本；撤销规则时仅撤销依赖授权。 设计场景：策略停用或变更时只处理依赖该版本形成的关系，便于解释自动授权从何而来。';
COMMENT ON COLUMN access.member_grant."source_request_id" IS '来源的审批申请；仅批准且仍有效的申请可形成授权。 设计场景：将最终授权追溯到批准申请，执行前复核申请、角色版本和资源仍有效。';
COMMENT ON COLUMN access.member_grant."source_delegation_id" IS '来源管理委派；使用时检查委派与上游授权仍有效。 设计场景：上游管理委派失效时找出依赖它授出的权限，防止下级授权脱离来源永久存活。';
COMMENT ON COLUMN access.member_grant."source_member_tenant_id" IS '工作身份所在企业；这是显式跨企业依赖，不是自动互信。 设计场景：内部员工为客户工作时显式记录其来源企业，离职只级联工作依赖而不影响独立客户身份。';
COMMENT ON COLUMN access.member_grant."source_member_id" IS '工作身份成员；仅撤销依赖此身份的工作授权。 设计场景：内部员工负责客户工作时记录授权依赖的内部成员；该成员离职只撤销依赖它的工作授权，不删除独立取得的客户资格。';
COMMENT ON COLUMN access.member_grant."valid_from" IS '授权最早有效时间；授权计算必须检查开始时间与截止时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。';
COMMENT ON COLUMN access.member_grant."valid_until" IS '授权结束时间；每次使用实时检查，不能等待清理任务。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。';
COMMENT ON COLUMN access.member_grant."status" IS '当前授权有效或已撤销；历史记录不能重新自动激活。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN access.member_grant."revoked_at" IS '授权撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN access.member_grant."reason" IS '脱敏授予或撤销原因。 设计场景：让审批、撤销或变更决定有可追溯的理由，便于申诉和审计；不能用自由文本代替结构化状态。';
CREATE INDEX ix_member_grant_delegation ON access.member_grant USING btree (tenant_id, source_delegation_id) WHERE (source_delegation_id IS NOT NULL);
CREATE INDEX ix_member_grant_expiry ON access.member_grant USING btree (tenant_id, valid_until, id) WHERE ((status)::text = 'ACTIVE'::text);
CREATE INDEX ix_member_grant_granted_by ON access.member_grant USING btree (granted_by_account_id);
CREATE INDEX ix_member_grant_policy ON access.member_grant USING btree (tenant_id, source_policy_id) WHERE (source_policy_id IS NOT NULL);
CREATE INDEX ix_member_grant_request ON access.member_grant USING btree (tenant_id, source_request_id) WHERE (source_request_id IS NOT NULL);
CREATE INDEX ix_member_grant_role ON access.member_grant USING btree (tenant_id, role_id);
CREATE INDEX ix_member_grant_work_source ON access.member_grant USING btree (source_member_tenant_id, source_member_id) WHERE (source_member_id IS NOT NULL);
CREATE UNIQUE INDEX uq_member_grant_delegation_active ON access.member_grant USING btree (tenant_id, member_id, role_id, source_delegation_id) WHERE (((source_kind)::text = 'DELEGATION'::text) AND ((status)::text = 'ACTIVE'::text));
CREATE UNIQUE INDEX uq_member_grant_direct_active ON access.member_grant USING btree (tenant_id, member_id, role_id) WHERE (((source_kind)::text = 'DIRECT'::text) AND ((status)::text = 'ACTIVE'::text));
CREATE UNIQUE INDEX uq_member_grant_policy_active ON access.member_grant USING btree (tenant_id, member_id, role_id, source_policy_id) WHERE (((source_kind)::text = 'POLICY'::text) AND ((status)::text = 'ACTIVE'::text));
CREATE UNIQUE INDEX uq_member_grant_request_active ON access.member_grant USING btree (tenant_id, member_id, role_id, source_request_id) WHERE (((source_kind)::text = 'APPROVAL'::text) AND ((status)::text = 'ACTIVE'::text));
CREATE UNIQUE INDEX uq_member_grant_work_active ON access.member_grant USING btree (tenant_id, member_id, role_id, source_member_tenant_id, source_member_id) WHERE (((source_kind)::text = 'WORK_ASSIGNMENT'::text) AND ((status)::text = 'ACTIVE'::text));

-- access.management_delegation：受控管理权委派；只能在授予者有效来源授权范围内管理指定角色，不能授予平台职责
CREATE TABLE access.management_delegation (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 委派发起成员。 设计场景：指定谁在让出有限管理权，委派资格始终受其现有授权约束。
    "delegator_member_id" bigint NOT NULL,
    -- 获委派管理权的成员。 设计场景：指定可以代为管理的企业成员，不能用通用账号身份替代当前企业资格。
    "delegate_member_id" bigint NOT NULL,
    -- 发起者有效授权；引用者成员必须与发起者一致。 设计场景：把委派绑定到可追溯的有效授权，上游授权撤销或缩小时，委派不能继续沿用原权限。
    "source_grant_id" bigint NOT NULL,
    -- 允许授予和管理的角色。 设计场景：限制被委派者可以管理哪些角色，避免把一项局部管理权扩大成任意角色分配权。
    "manageable_role_id" bigint NOT NULL,
    -- 委派的最大资源边界，不能超出来源授权。 设计场景：显式区分全企业、指定店铺或指定资源等范围；空的明细集合不能被解释为全部权限。
    "scope_mode" character varying(24) NOT NULL,
    -- 是否允许继续委派；每级必须维持权限交集。 设计场景：只有明确允许才可继续向下委派，后续委派仍不得超出整个来源链的有效范围。
    "can_redelegate" boolean DEFAULT false NOT NULL,
    -- 开始时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。
    "valid_from" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 必须设置到期时间。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。
    "valid_until" timestamp with time zone NOT NULL,
    -- 撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 并发版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "management_delegation_check" CHECK (updated_at >= created_at),
    CONSTRAINT "management_delegation_check1" CHECK (delegator_member_id <> delegate_member_id),
    CONSTRAINT "management_delegation_check2" CHECK (valid_until > valid_from),
    CONSTRAINT "management_delegation_check3" CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT "management_delegation_id_check" CHECK (id > 0),
    CONSTRAINT "management_delegation_pkey" PRIMARY KEY (id),
    CONSTRAINT "management_delegation_scope_mode_check" CHECK (scope_mode::text = ANY (ARRAY['ALL_TENANT'::character varying, 'SELECTED_STORES'::character varying, 'SELECTED_RESOURCES'::character varying]::text[])),
    CONSTRAINT "management_delegation_tenant_id_delegate_member_id_fkey" FOREIGN KEY (tenant_id, delegate_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "management_delegation_tenant_id_delegator_member_id_fkey" FOREIGN KEY (tenant_id, delegator_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "management_delegation_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "management_delegation_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "management_delegation_tenant_id_manageable_role_id_fkey" FOREIGN KEY (tenant_id, manageable_role_id) REFERENCES access.role(tenant_id, id),
    CONSTRAINT "management_delegation_tenant_id_source_grant_id_delegator__fkey" FOREIGN KEY (tenant_id, source_grant_id, delegator_member_id) REFERENCES access.member_grant(tenant_id, id, member_id),
    CONSTRAINT "management_delegation_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE access.management_delegation IS '受控管理权委派；只能在授予者有效来源授权范围内管理指定角色，不能授予平台职责';
COMMENT ON COLUMN access.management_delegation."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.management_delegation."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.management_delegation."delegator_member_id" IS '委派发起成员。 设计场景：指定谁在让出有限管理权，委派资格始终受其现有授权约束。';
COMMENT ON COLUMN access.management_delegation."delegate_member_id" IS '获委派管理权的成员。 设计场景：指定可以代为管理的企业成员，不能用通用账号身份替代当前企业资格。';
COMMENT ON COLUMN access.management_delegation."source_grant_id" IS '发起者有效授权；引用者成员必须与发起者一致。 设计场景：把委派绑定到可追溯的有效授权，上游授权撤销或缩小时，委派不能继续沿用原权限。';
COMMENT ON COLUMN access.management_delegation."manageable_role_id" IS '允许授予和管理的角色。 设计场景：限制被委派者可以管理哪些角色，避免把一项局部管理权扩大成任意角色分配权。';
COMMENT ON COLUMN access.management_delegation."scope_mode" IS '委派的最大资源边界，不能超出来源授权。 设计场景：显式区分全企业、指定店铺或指定资源等范围；空的明细集合不能被解释为全部权限。';
COMMENT ON COLUMN access.management_delegation."can_redelegate" IS '是否允许继续委派；每级必须维持权限交集。 设计场景：只有明确允许才可继续向下委派，后续委派仍不得超出整个来源链的有效范围。';
COMMENT ON COLUMN access.management_delegation."valid_from" IS '开始时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。';
COMMENT ON COLUMN access.management_delegation."valid_until" IS '必须设置到期时间。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。';
COMMENT ON COLUMN access.management_delegation."revoked_at" IS '撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN access.management_delegation."version" IS '并发版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN access.management_delegation."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.management_delegation."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_access_management_delegation_delegate ON access.management_delegation USING btree (tenant_id, delegate_member_id, valid_until);
CREATE INDEX ix_access_management_delegation_delegator ON access.management_delegation USING btree (tenant_id, delegator_member_id);
CREATE INDEX ix_access_management_delegation_role ON access.management_delegation USING btree (tenant_id, manageable_role_id);
CREATE INDEX ix_access_management_delegation_source ON access.management_delegation USING btree (tenant_id, source_grant_id);

-- access.resource_type：平台维护的受控业务资源类型目录；由资源接入用例登记，企业不能随意声明类型
CREATE TABLE access.resource_type (
    -- 稳定资源类别代码。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。
    "code" character varying(64) NOT NULL,
    -- 资源类别名称。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。
    "name" character varying(100) NOT NULL,
    -- 受控资源归属及状态查询适配器代码。 设计场景：新增业务资源类型时指定受控的归属与状态查询实现，避免仅登记一个字符串就视资源真实存在。
    "adapter_key" character varying(128) NOT NULL,
    -- 登记时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "resource_type_adapter_key_check" CHECK (btrim(adapter_key::text) <> ''::text),
    CONSTRAINT "resource_type_code_check" CHECK (code::text ~ '^[A-Z][A-Z0-9_]{0,63}$'::text),
    CONSTRAINT "resource_type_name_check" CHECK (btrim(name::text) <> ''::text),
    CONSTRAINT "resource_type_pkey" PRIMARY KEY (code)
);
COMMENT ON TABLE access.resource_type IS '平台维护的受控业务资源类型目录；由资源接入用例登记，企业不能随意声明类型';
COMMENT ON COLUMN access.resource_type."code" IS '稳定资源类别代码。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。';
COMMENT ON COLUMN access.resource_type."name" IS '资源类别名称。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。';
COMMENT ON COLUMN access.resource_type."adapter_key" IS '受控资源归属及状态查询适配器代码。 设计场景：新增业务资源类型时指定受控的归属与状态查询实现，避免仅登记一个字符串就视资源真实存在。';
COMMENT ON COLUMN access.resource_type."created_at" IS '登记时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';

-- access.resource：非店铺资源的受控目录；类型和业务键确定资源，授权始终引用实际目录行，不使用无外键的任意对象 ID
CREATE TABLE access.resource (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 非企业和店铺的受控业务资源类型。 设计场景：区分不同业务对象的权限语义，防止把订单 ID 当店铺 ID 使用；类型来自受控目录。
    "resource_type" character varying(64) NOT NULL,
    -- 来源业务系统中的稳定资源键；不作为访问凭据。 设计场景：将权限资源目录映射回业务系统对象，在不同类型和企业下按约定判断唯一，不通过名称猜测归属。
    "business_key" character varying(256) NOT NULL,
    -- 资源展示名称。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。
    "display_name" character varying(200) NOT NULL,
    -- 资源负责人；必须属于同一企业。 设计场景：指定负责维护资源、机器或复核任务的企业成员，支持责任交接；负责人关系本身不赋予全部操作权限。
    "owner_member_id" bigint,
    -- 资源生命周期；停用或移除不能被允许策略重新放行。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 乐观锁版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "resource_business_key_check" CHECK (btrim(business_key::text) <> ''::text),
    CONSTRAINT "resource_check" CHECK (updated_at >= created_at),
    CONSTRAINT "resource_display_name_check" CHECK (btrim(display_name::text) <> ''::text),
    CONSTRAINT "resource_id_check" CHECK (id > 0),
    CONSTRAINT "resource_pkey" PRIMARY KEY (id),
    CONSTRAINT "resource_resource_type_check" CHECK (resource_type::text ~ '^[A-Z][A-Z0-9_]{0,63}$'::text AND (resource_type::text <> ALL (ARRAY['TENANT'::character varying, 'STORE'::character varying]::text[]))),
    CONSTRAINT "resource_resource_type_fkey" FOREIGN KEY (resource_type) REFERENCES access.resource_type(code),
    CONSTRAINT "resource_status_check" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying, 'REMOVED'::character varying]::text[])),
    CONSTRAINT "resource_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "resource_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "resource_tenant_id_owner_member_id_fkey" FOREIGN KEY (tenant_id, owner_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "resource_tenant_id_resource_type_business_key_key" UNIQUE (tenant_id, resource_type, business_key),
    CONSTRAINT "resource_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE access.resource IS '非店铺资源的受控目录；类型和业务键确定资源，授权始终引用实际目录行，不使用无外键的任意对象 ID';
COMMENT ON COLUMN access.resource."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.resource."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.resource."resource_type" IS '非企业和店铺的受控业务资源类型。 设计场景：区分不同业务对象的权限语义，防止把订单 ID 当店铺 ID 使用；类型来自受控目录。';
COMMENT ON COLUMN access.resource."business_key" IS '来源业务系统中的稳定资源键；不作为访问凭据。 设计场景：将权限资源目录映射回业务系统对象，在不同类型和企业下按约定判断唯一，不通过名称猜测归属。';
COMMENT ON COLUMN access.resource."display_name" IS '资源展示名称。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。';
COMMENT ON COLUMN access.resource."owner_member_id" IS '资源负责人；必须属于同一企业。 设计场景：指定负责维护资源、机器或复核任务的企业成员，支持责任交接；负责人关系本身不赋予全部操作权限。';
COMMENT ON COLUMN access.resource."status" IS '资源生命周期；停用或移除不能被允许策略重新放行。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN access.resource."version" IS '乐观锁版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN access.resource."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.resource."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_access_resource_owner ON access.resource USING btree (tenant_id, owner_member_id);
CREATE INDEX ix_access_resource_status ON access.resource USING btree (tenant_id, status, id);

-- demo.store：演示店铺；通过 tenant_id 与资源 ID 定位，停用后仍保留事实记录
CREATE TABLE demo.store (
    -- 应用生成的业务雪花 ID，不是访问凭证。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；授权判定必须同时匹配此租户。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 企业内唯一店铺代码，应用负责按统一规则规范化。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。
    "code" character varying(64) NOT NULL,
    -- 面向用户展示的名称，不作为身份关联键。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。
    "name" character varying(200) NOT NULL,
    -- ACTIVE 可用，DISABLED 停用；应用请求时检查当前状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 店铺资料的乐观锁版本，应用更新时比较并递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 由应用写入逻辑维护，数据库不会自动随 UPDATE 刷新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_store_code" CHECK (code::text = btrim(code::text) AND code::text <> ''::text),
    CONSTRAINT "ck_store_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_store_name" CHECK (btrim(name::text) <> ''::text),
    CONSTRAINT "ck_store_status" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying]::text[])),
    CONSTRAINT "ck_store_times" CHECK (updated_at >= created_at),
    CONSTRAINT "ck_store_version" CHECK (version >= 0),
    CONSTRAINT "fk_store_tenant" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "pk_store" PRIMARY KEY (id),
    CONSTRAINT "uq_store_tenant_code" UNIQUE (tenant_id, code),
    CONSTRAINT "uq_store_tenant_id" UNIQUE (tenant_id, id)
);
COMMENT ON TABLE demo.store IS '演示店铺；通过 tenant_id 与资源 ID 定位，停用后仍保留事实记录';
COMMENT ON COLUMN demo.store."id" IS '应用生成的业务雪花 ID，不是访问凭证。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN demo.store."tenant_id" IS '所属企业；授权判定必须同时匹配此租户。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN demo.store."code" IS '企业内唯一店铺代码，应用负责按统一规则规范化。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。';
COMMENT ON COLUMN demo.store."name" IS '面向用户展示的名称，不作为身份关联键。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。';
COMMENT ON COLUMN demo.store."status" IS 'ACTIVE 可用，DISABLED 停用；应用请求时检查当前状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN demo.store."version" IS '店铺资料的乐观锁版本，应用更新时比较并递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN demo.store."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN demo.store."updated_at" IS '由应用写入逻辑维护，数据库不会自动随 UPDATE 刷新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_store_tenant_status_created ON demo.store USING btree (tenant_id, status, created_at, id);

-- access.delegation_scope：管理委派的指定范围；空集合无授权
CREATE TABLE access.delegation_scope (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 管理委派。 设计场景：资源集合限定到具体管理委派，受委派人只能在它及上游有效授权范围内分配角色。
    "delegation_id" bigint NOT NULL,
    -- 指定店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。
    "store_id" bigint,
    -- 指定非店铺资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。
    "resource_id" bigint,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "delegation_scope_check" CHECK (updated_at >= created_at),
    CONSTRAINT "delegation_scope_check1" CHECK (num_nonnulls(store_id, resource_id) = 1),
    CONSTRAINT "delegation_scope_id_check" CHECK (id > 0),
    CONSTRAINT "delegation_scope_pkey" PRIMARY KEY (id),
    CONSTRAINT "delegation_scope_tenant_id_delegation_id_fkey" FOREIGN KEY (tenant_id, delegation_id) REFERENCES access.management_delegation(tenant_id, id),
    CONSTRAINT "delegation_scope_tenant_id_delegation_id_store_id_resource__key" UNIQUE NULLS NOT DISTINCT (tenant_id, delegation_id, store_id, resource_id),
    CONSTRAINT "delegation_scope_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "delegation_scope_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "delegation_scope_tenant_id_resource_id_fkey" FOREIGN KEY (tenant_id, resource_id) REFERENCES access.resource(tenant_id, id),
    CONSTRAINT "delegation_scope_tenant_id_store_id_fkey" FOREIGN KEY (tenant_id, store_id) REFERENCES demo.store(tenant_id, id)
);
COMMENT ON TABLE access.delegation_scope IS '管理委派的指定范围；空集合无授权';
COMMENT ON COLUMN access.delegation_scope."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.delegation_scope."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.delegation_scope."delegation_id" IS '管理委派。 设计场景：资源集合限定到具体管理委派，受委派人只能在它及上游有效授权范围内分配角色。';
COMMENT ON COLUMN access.delegation_scope."store_id" IS '指定店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。';
COMMENT ON COLUMN access.delegation_scope."resource_id" IS '指定非店铺资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。';
COMMENT ON COLUMN access.delegation_scope."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.delegation_scope."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_access_delegation_scope_resource ON access.delegation_scope USING btree (tenant_id, resource_id);
CREATE INDEX ix_access_delegation_scope_store ON access.delegation_scope USING btree (tenant_id, store_id);

-- access.grant_resource：成员授权的非店铺明确资源集合；角色和范围仍绑定同一条授权
CREATE TABLE access.grant_resource (
    -- 所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 成员授权。 设计场景：资源范围和复核决定归属某一条具体授权，不能将不同授权的动作与范围任意组合。
    "grant_id" bigint NOT NULL,
    -- 同企业受控资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。
    "resource_id" bigint NOT NULL,
    CONSTRAINT "grant_resource_pkey" PRIMARY KEY (tenant_id, grant_id, resource_id),
    CONSTRAINT "grant_resource_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "grant_resource_tenant_id_grant_id_fkey" FOREIGN KEY (tenant_id, grant_id) REFERENCES access.member_grant(tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT "grant_resource_tenant_id_resource_id_fkey" FOREIGN KEY (tenant_id, resource_id) REFERENCES access.resource(tenant_id, id)
);
COMMENT ON TABLE access.grant_resource IS '成员授权的非店铺明确资源集合；角色和范围仍绑定同一条授权';
COMMENT ON COLUMN access.grant_resource."tenant_id" IS '所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.grant_resource."grant_id" IS '成员授权。 设计场景：资源范围和复核决定归属某一条具体授权，不能将不同授权的动作与范围任意组合。';
COMMENT ON COLUMN access.grant_resource."resource_id" IS '同企业受控资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。';
CREATE INDEX ix_access_grant_resource_resource ON access.grant_resource USING btree (tenant_id, resource_id, grant_id);

-- access.grant_store：SELECTED_STORES 授权的明确店铺范围；撤销授权时可级联清除此子表
CREATE TABLE access.grant_store (
    -- 所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 绑定具体角色授权，不可将不同授权的动作和店铺集合交叉合并。 设计场景：资源范围和复核决定归属某一条具体授权，不能将不同授权的动作与范围任意组合。
    "grant_id" bigint NOT NULL,
    -- 与授权属于同一企业的店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。
    "store_id" bigint NOT NULL,
    CONSTRAINT "fk_grant_store_grant" FOREIGN KEY (tenant_id, grant_id) REFERENCES access.member_grant(tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT "fk_grant_store_store" FOREIGN KEY (tenant_id, store_id) REFERENCES demo.store(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "pk_grant_store" PRIMARY KEY (tenant_id, grant_id, store_id)
);
COMMENT ON TABLE access.grant_store IS 'SELECTED_STORES 授权的明确店铺范围；撤销授权时可级联清除此子表';
COMMENT ON COLUMN access.grant_store."tenant_id" IS '所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.grant_store."grant_id" IS '绑定具体角色授权，不可将不同授权的动作和店铺集合交叉合并。 设计场景：资源范围和复核决定归属某一条具体授权，不能将不同授权的动作与范围任意组合。';
COMMENT ON COLUMN access.grant_store."store_id" IS '与授权属于同一企业的店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。';
CREATE INDEX ix_grant_store_store ON access.grant_store USING btree (tenant_id, store_id, grant_id);

-- directory.invitation：企业邀请；按邮箱、指定账号或受控链接核验领取资格，预期授权由 Access 保存。
CREATE TABLE directory.invitation (
    -- 邀请 ID，由应用生成雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 受邀加入的企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- EMAIL 邀请联系地址；归属证明独立于个人登录邮箱，不要求更换登录邮箱。 设计场景：邀请可以发到与个人登录邮箱不同的工作邮箱，单独验证邀请地址归属，不强迫修改全局登录方式。
    "email_normalized" character varying(254),
    -- 高熵邀请令牌的 SHA-256 摘要，固定 32 字节；不保存明文令牌。 设计场景：邀请链接泄露风险通过短期高熵令牌控制，库中只留摘要，验证链接时比较摘要而不取回原始令牌。
    "token_hash" bytea NOT NULL,
    -- 邀请令牌代数，从 1 开始；重发递增并轮换摘要及到期时间，使旧链接失效。 设计场景：重发邀请后旧邮件链接必须失效；递增代数让旧证明也不能拿来接受新一轮邀请。
    "token_generation" bigint DEFAULT 1 NOT NULL,
    -- 邀请状态：PENDING 待接受，ACCEPTED 已接受，REVOKED 已撤销，EXPIRED 已过期。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    -- 当前令牌到期时间；即使仍为 PENDING，达到此时间也不可接受。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone NOT NULL,
    -- 邀请发起账号；首位管理员邀请可以由非企业成员的平台管理员发起。 设计场景：追踪邀请人并在接受时复核可授予的资格，尤其支持平台管理员开通企业首位管理员。
    "invited_by_account_id" bigint NOT NULL,
    -- 发起人的可选企业成员 ID；非空时必须同时属于本企业和发起账号。 设计场景：记录邀请人在企业里的具体身份；平台受控开通可没有该企业成员，不能伪造一个成员关系。
    "invited_by_member_id" bigint,
    -- MEMBER 普通成员邀请；FIRST_ADMIN 受控企业开通中的首位管理员邀请。 设计场景：区分普通入职和首位管理员开通，两种流程的操作者资格及最后管理员约束不同。
    "invitation_kind" character varying(16) NOT NULL,
    -- 接受邀请的已认证账号，仅 ACCEPTED 状态非空。 设计场景：防止一张邀请被不同账号重复领取，并保留最终领取者供审计。
    "accepted_by_account_id" bigint,
    -- 接受后创建或恢复的成员 ID，与接受账号和本企业通过三列外键保持一致。 设计场景：关联本次接受后创建或恢复的稳定企业成员，重试时返回同一结果而非重复创建。
    "accepted_member_id" bigint,
    -- 成功接受时间，仅 ACCEPTED 状态非空。 设计场景：确认邀请实际完成领取的时间，便于解释过期边界和重复点击的处理结果。
    "accepted_at" timestamp with time zone,
    -- 撤销时间，仅 REVOKED 状态非空。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 邀请聚合乐观锁版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由应用写入。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 邀请归属：EMAIL 验证受邀地址，ACCOUNT 已有账号，LINK 受控链接；链接本身不授予管理员职责。 设计场景：区分验证受邀邮箱、指定账号本人和受控链接领取，链接持有者不能因此自动成为企业管理员。
    "target_kind" character varying(16) DEFAULT 'EMAIL'::character varying NOT NULL,
    -- 指定受邀平台账号；接受时必须是该本人。 设计场景：指定账号邀请只允许该账号本人领取，不接受客户端把目标改成另一个当前登录账号。
    "target_account_id" bigint,
    -- 可选的待激活员工；接受时关联稳定员工记录，不能重复建成员。 设计场景：同步已经建立待激活员工时，接受邀请直接关联该员工，避免再次新增重复成员。
    "precreated_member_id" bigint,
    CONSTRAINT "ck_invitation_acceptance" CHECK (status::text = 'ACCEPTED'::text AND accepted_by_account_id IS NOT NULL AND accepted_member_id IS NOT NULL AND accepted_at IS NOT NULL AND accepted_at >= created_at AND accepted_at < expires_at OR (status::text = ANY (ARRAY['PENDING'::character varying, 'REVOKED'::character varying, 'EXPIRED'::character varying]::text[])) AND accepted_by_account_id IS NULL AND accepted_member_id IS NULL AND accepted_at IS NULL),
    CONSTRAINT "ck_invitation_email_normalized" CHECK (email_normalized::text = lower(btrim(email_normalized::text)) AND email_normalized::text ~ '^[^[:space:]@]+@[^[:space:]@]+$'::text),
    CONSTRAINT "ck_invitation_expires_at" CHECK (expires_at > created_at),
    CONSTRAINT "ck_invitation_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_invitation_kind" CHECK (invitation_kind::text = ANY (ARRAY['MEMBER'::character varying, 'FIRST_ADMIN'::character varying]::text[])),
    CONSTRAINT "ck_invitation_member_actor" CHECK (invitation_kind::text <> 'MEMBER'::text OR invited_by_member_id IS NOT NULL),
    CONSTRAINT "ck_invitation_revoked_at" CHECK (status::text = 'REVOKED'::text AND revoked_at IS NOT NULL AND revoked_at >= created_at OR (status::text = ANY (ARRAY['PENDING'::character varying, 'ACCEPTED'::character varying, 'EXPIRED'::character varying]::text[])) AND revoked_at IS NULL),
    CONSTRAINT "ck_invitation_status" CHECK (status::text = ANY (ARRAY['PENDING'::character varying, 'ACCEPTED'::character varying, 'REVOKED'::character varying, 'EXPIRED'::character varying]::text[])),
    CONSTRAINT "ck_invitation_target" CHECK (target_kind::text = 'EMAIL'::text AND email_normalized IS NOT NULL AND target_account_id IS NULL OR target_kind::text = 'ACCOUNT'::text AND target_account_id IS NOT NULL AND email_normalized IS NULL OR target_kind::text = 'LINK'::text AND email_normalized IS NULL AND target_account_id IS NULL),
    CONSTRAINT "ck_invitation_token_generation" CHECK (token_generation > 0),
    CONSTRAINT "ck_invitation_token_hash" CHECK (octet_length(token_hash) = 32),
    CONSTRAINT "ck_invitation_version" CHECK (version >= 0),
    CONSTRAINT "fk_invitation_accepted_by_account" FOREIGN KEY (accepted_by_account_id) REFERENCES directory.account(id) ON DELETE RESTRICT,
    CONSTRAINT "fk_invitation_accepted_member" FOREIGN KEY (tenant_id, accepted_member_id, accepted_by_account_id) REFERENCES directory.membership(tenant_id, id, account_id) ON DELETE RESTRICT,
    CONSTRAINT "fk_invitation_invited_by_account" FOREIGN KEY (invited_by_account_id) REFERENCES directory.account(id) ON DELETE RESTRICT,
    CONSTRAINT "fk_invitation_invited_by_member" FOREIGN KEY (tenant_id, invited_by_member_id, invited_by_account_id) REFERENCES directory.membership(tenant_id, id, account_id) ON DELETE RESTRICT,
    CONSTRAINT "fk_invitation_precreated_member" FOREIGN KEY (tenant_id, precreated_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "fk_invitation_tenant" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "invitation_target_account_id_fkey" FOREIGN KEY (target_account_id) REFERENCES directory.account(id),
    CONSTRAINT "pk_directory_invitation" PRIMARY KEY (id),
    CONSTRAINT "uq_invitation_tenant_id" UNIQUE (tenant_id, id),
    CONSTRAINT "uq_invitation_token_hash" UNIQUE (token_hash)
);
COMMENT ON TABLE directory.invitation IS '企业邀请；按邮箱、指定账号或受控链接核验领取资格，预期授权由 Access 保存。';
COMMENT ON COLUMN directory.invitation."id" IS '邀请 ID，由应用生成雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.invitation."tenant_id" IS '受邀加入的企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.invitation."email_normalized" IS 'EMAIL 邀请联系地址；归属证明独立于个人登录邮箱，不要求更换登录邮箱。 设计场景：邀请可以发到与个人登录邮箱不同的工作邮箱，单独验证邀请地址归属，不强迫修改全局登录方式。';
COMMENT ON COLUMN directory.invitation."token_hash" IS '高熵邀请令牌的 SHA-256 摘要，固定 32 字节；不保存明文令牌。 设计场景：邀请链接泄露风险通过短期高熵令牌控制，库中只留摘要，验证链接时比较摘要而不取回原始令牌。';
COMMENT ON COLUMN directory.invitation."token_generation" IS '邀请令牌代数，从 1 开始；重发递增并轮换摘要及到期时间，使旧链接失效。 设计场景：重发邀请后旧邮件链接必须失效；递增代数让旧证明也不能拿来接受新一轮邀请。';
COMMENT ON COLUMN directory.invitation."status" IS '邀请状态：PENDING 待接受，ACCEPTED 已接受，REVOKED 已撤销，EXPIRED 已过期。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.invitation."expires_at" IS '当前令牌到期时间；即使仍为 PENDING，达到此时间也不可接受。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN directory.invitation."invited_by_account_id" IS '邀请发起账号；首位管理员邀请可以由非企业成员的平台管理员发起。 设计场景：追踪邀请人并在接受时复核可授予的资格，尤其支持平台管理员开通企业首位管理员。';
COMMENT ON COLUMN directory.invitation."invited_by_member_id" IS '发起人的可选企业成员 ID；非空时必须同时属于本企业和发起账号。 设计场景：记录邀请人在企业里的具体身份；平台受控开通可没有该企业成员，不能伪造一个成员关系。';
COMMENT ON COLUMN directory.invitation."invitation_kind" IS 'MEMBER 普通成员邀请；FIRST_ADMIN 受控企业开通中的首位管理员邀请。 设计场景：区分普通入职和首位管理员开通，两种流程的操作者资格及最后管理员约束不同。';
COMMENT ON COLUMN directory.invitation."accepted_by_account_id" IS '接受邀请的已认证账号，仅 ACCEPTED 状态非空。 设计场景：防止一张邀请被不同账号重复领取，并保留最终领取者供审计。';
COMMENT ON COLUMN directory.invitation."accepted_member_id" IS '接受后创建或恢复的成员 ID，与接受账号和本企业通过三列外键保持一致。 设计场景：关联本次接受后创建或恢复的稳定企业成员，重试时返回同一结果而非重复创建。';
COMMENT ON COLUMN directory.invitation."accepted_at" IS '成功接受时间，仅 ACCEPTED 状态非空。 设计场景：确认邀请实际完成领取的时间，便于解释过期边界和重复点击的处理结果。';
COMMENT ON COLUMN directory.invitation."revoked_at" IS '撤销时间，仅 REVOKED 状态非空。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN directory.invitation."version" IS '邀请聚合乐观锁版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.invitation."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.invitation."updated_at" IS '最近更新时间，由应用写入。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
COMMENT ON COLUMN directory.invitation."target_kind" IS '邀请归属：EMAIL 验证受邀地址，ACCOUNT 已有账号，LINK 受控链接；链接本身不授予管理员职责。 设计场景：区分验证受邀邮箱、指定账号本人和受控链接领取，链接持有者不能因此自动成为企业管理员。';
COMMENT ON COLUMN directory.invitation."target_account_id" IS '指定受邀平台账号；接受时必须是该本人。 设计场景：指定账号邀请只允许该账号本人领取，不接受客户端把目标改成另一个当前登录账号。';
COMMENT ON COLUMN directory.invitation."precreated_member_id" IS '可选的待激活员工；接受时关联稳定员工记录，不能重复建成员。 设计场景：同步已经建立待激活员工时，接受邀请直接关联该员工，避免再次新增重复成员。';
CREATE INDEX ix_invitation_accepted_by_account ON directory.invitation USING btree (accepted_by_account_id) WHERE (accepted_by_account_id IS NOT NULL);
CREATE INDEX ix_invitation_accepted_member ON directory.invitation USING btree (tenant_id, accepted_member_id, accepted_by_account_id) WHERE (accepted_member_id IS NOT NULL);
CREATE INDEX ix_invitation_invited_by_account ON directory.invitation USING btree (invited_by_account_id);
CREATE INDEX ix_invitation_invited_by_member ON directory.invitation USING btree (tenant_id, invited_by_member_id, invited_by_account_id) WHERE (invited_by_member_id IS NOT NULL);
CREATE INDEX ix_invitation_pending_expires ON directory.invitation USING btree (expires_at) WHERE ((status)::text = 'PENDING'::text);
CREATE INDEX ix_invitation_tenant_status_created ON directory.invitation USING btree (tenant_id, status, created_at);
CREATE UNIQUE INDEX uq_invitation_pending_tenant_email ON directory.invitation USING btree (tenant_id, email_normalized) WHERE ((status)::text = 'PENDING'::text);

-- access.invitation_grant：邀请中的待授予方案；不参与运行时权限判断，接受后可保留用于审计解释
CREATE TABLE access.invitation_grant (
    -- 本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 同企业邀请 ID。 设计场景：将待授予权限或归属证明绑定到同一邀请，邀请被撤销、过期或重发后按规则重新核验。
    "invitation_id" bigint NOT NULL,
    -- 同企业角色 ID。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。
    "role_id" bigint NOT NULL,
    -- 生成方案时的角色版本；接受时与当前版本比较，不一致须重审或重发。 设计场景：等待审批或邀请接受期间角色权限可能扩大；对比原版本决定重新确认，避免旧同意无意包含新权限。
    "role_version_snapshot" bigint NOT NULL,
    -- 预期范围；接受邀请时重新检查角色、资源、范围及发起者当前资格。 设计场景：显式区分全企业、指定店铺或指定资源等范围；空的明细集合不能被解释为全部权限。
    "scope_mode" character varying(24) NOT NULL,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 邀请预授予开始时间；为空则接受时开始，不能绕过接受资格检查。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。
    "valid_from" timestamp with time zone,
    -- 预授予到期时间；接受时已经到期则拒绝，不能因接受邀请延长。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。
    "valid_until" timestamp with time zone,
    CONSTRAINT "ck_invitation_grant_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_invitation_grant_role_version" CHECK (role_version_snapshot >= 0),
    CONSTRAINT "ck_invitation_grant_scope" CHECK (scope_mode::text = ANY (ARRAY['ALL_TENANT'::character varying, 'SELECTED_STORES'::character varying, 'SELECTED_RESOURCES'::character varying]::text[])),
    CONSTRAINT "ck_invitation_grant_times" CHECK (updated_at >= created_at),
    CONSTRAINT "ck_invitation_grant_validity" CHECK (valid_until IS NULL OR valid_from IS NOT NULL AND valid_until > valid_from),
    CONSTRAINT "fk_invitation_grant_invitation" FOREIGN KEY (tenant_id, invitation_id) REFERENCES directory.invitation(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "fk_invitation_grant_role" FOREIGN KEY (tenant_id, role_id) REFERENCES access.role(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "pk_invitation_grant" PRIMARY KEY (id),
    CONSTRAINT "uq_invitation_grant_invitation_role" UNIQUE (tenant_id, invitation_id, role_id),
    CONSTRAINT "uq_invitation_grant_tenant_id" UNIQUE (tenant_id, id)
);
COMMENT ON TABLE access.invitation_grant IS '邀请中的待授予方案；不参与运行时权限判断，接受后可保留用于审计解释';
COMMENT ON COLUMN access.invitation_grant."id" IS '本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.invitation_grant."tenant_id" IS '所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.invitation_grant."invitation_id" IS '同企业邀请 ID。 设计场景：将待授予权限或归属证明绑定到同一邀请，邀请被撤销、过期或重发后按规则重新核验。';
COMMENT ON COLUMN access.invitation_grant."role_id" IS '同企业角色 ID。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。';
COMMENT ON COLUMN access.invitation_grant."role_version_snapshot" IS '生成方案时的角色版本；接受时与当前版本比较，不一致须重审或重发。 设计场景：等待审批或邀请接受期间角色权限可能扩大；对比原版本决定重新确认，避免旧同意无意包含新权限。';
COMMENT ON COLUMN access.invitation_grant."scope_mode" IS '预期范围；接受邀请时重新检查角色、资源、范围及发起者当前资格。 设计场景：显式区分全企业、指定店铺或指定资源等范围；空的明细集合不能被解释为全部权限。';
COMMENT ON COLUMN access.invitation_grant."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.invitation_grant."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
COMMENT ON COLUMN access.invitation_grant."valid_from" IS '邀请预授予开始时间；为空则接受时开始，不能绕过接受资格检查。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。';
COMMENT ON COLUMN access.invitation_grant."valid_until" IS '预授予到期时间；接受时已经到期则拒绝，不能因接受邀请延长。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。';
CREATE INDEX ix_invitation_grant_role ON access.invitation_grant USING btree (tenant_id, role_id);

-- access.invitation_grant_resource：邀请待授予的非店铺资源；不是有效授权
CREATE TABLE access.invitation_grant_resource (
    -- 所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 邀请预授权。 设计场景：一个邀请可能包含多个角色方案，资源范围归属具体方案，接受前这些记录不构成有效权限。
    "invitation_grant_id" bigint NOT NULL,
    -- 同企业受控资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。
    "resource_id" bigint NOT NULL,
    CONSTRAINT "invitation_grant_resource_pkey" PRIMARY KEY (tenant_id, invitation_grant_id, resource_id),
    CONSTRAINT "invitation_grant_resource_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "invitation_grant_resource_tenant_id_invitation_grant_id_fkey" FOREIGN KEY (tenant_id, invitation_grant_id) REFERENCES access.invitation_grant(tenant_id, id),
    CONSTRAINT "invitation_grant_resource_tenant_id_resource_id_fkey" FOREIGN KEY (tenant_id, resource_id) REFERENCES access.resource(tenant_id, id)
);
COMMENT ON TABLE access.invitation_grant_resource IS '邀请待授予的非店铺资源；不是有效授权';
COMMENT ON COLUMN access.invitation_grant_resource."tenant_id" IS '所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.invitation_grant_resource."invitation_grant_id" IS '邀请预授权。 设计场景：一个邀请可能包含多个角色方案，资源范围归属具体方案，接受前这些记录不构成有效权限。';
COMMENT ON COLUMN access.invitation_grant_resource."resource_id" IS '同企业受控资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。';
CREATE INDEX ix_access_invitation_grant_resource_resource ON access.invitation_grant_resource USING btree (tenant_id, resource_id);

-- access.invitation_grant_store：绑定到邀请具体预期角色的明确店铺范围；不构成有效成员授权
CREATE TABLE access.invitation_grant_store (
    -- 所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 邀请中具体角色与范围的方案 ID。 设计场景：一个邀请可能包含多个角色方案，资源范围归属具体方案，接受前这些记录不构成有效权限。
    "invitation_grant_id" bigint NOT NULL,
    -- 与邀请、预期角色处于同一企业的店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。
    "store_id" bigint NOT NULL,
    CONSTRAINT "fk_invitation_grant_store_grant" FOREIGN KEY (tenant_id, invitation_grant_id) REFERENCES access.invitation_grant(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "fk_invitation_grant_store_store" FOREIGN KEY (tenant_id, store_id) REFERENCES demo.store(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "pk_invitation_grant_store" PRIMARY KEY (tenant_id, invitation_grant_id, store_id)
);
COMMENT ON TABLE access.invitation_grant_store IS '绑定到邀请具体预期角色的明确店铺范围；不构成有效成员授权';
COMMENT ON COLUMN access.invitation_grant_store."tenant_id" IS '所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.invitation_grant_store."invitation_grant_id" IS '邀请中具体角色与范围的方案 ID。 设计场景：一个邀请可能包含多个角色方案，资源范围归属具体方案，接受前这些记录不构成有效权限。';
COMMENT ON COLUMN access.invitation_grant_store."store_id" IS '与邀请、预期角色处于同一企业的店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。';
CREATE INDEX ix_invitation_grant_store_store ON access.invitation_grant_store USING btree (tenant_id, store_id, invitation_grant_id);

-- access.permission：平台维护的全局企业权限动作目录；租户接口不得新增或修改目录
CREATE TABLE access.permission (
    -- 稳定动作代码；菜单、按钮和 OAuth scope 不能替代此权限事实。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。
    "code" character varying(120) NOT NULL,
    -- 面向用户展示的名称，不作为身份关联键。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。
    "name" character varying(100) NOT NULL,
    -- 受控资源类别代码；内置 TENANT/STORE，其他类别须经资源接入管理登记。 设计场景：区分不同业务对象的权限语义，防止把订单 ID 当店铺 ID 使用；类型来自受控目录。
    "resource_type" character varying(64) NOT NULL,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_permission_code" CHECK (code::text = btrim(code::text) AND code::text <> ''::text),
    CONSTRAINT "ck_permission_name" CHECK (btrim(name::text) <> ''::text),
    CONSTRAINT "ck_permission_resource_type" CHECK (resource_type::text ~ '^[A-Z][A-Z0-9_]{0,63}$'::text),
    CONSTRAINT "ck_permission_times" CHECK (updated_at >= created_at),
    CONSTRAINT "fk_permission_resource_type" FOREIGN KEY (resource_type) REFERENCES access.resource_type(code),
    CONSTRAINT "pk_permission" PRIMARY KEY (code)
);
COMMENT ON TABLE access.permission IS '平台维护的全局企业权限动作目录；租户接口不得新增或修改目录';
COMMENT ON COLUMN access.permission."code" IS '稳定动作代码；菜单、按钮和 OAuth scope 不能替代此权限事实。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。';
COMMENT ON COLUMN access.permission."name" IS '面向用户展示的名称，不作为身份关联键。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。';
COMMENT ON COLUMN access.permission."resource_type" IS '受控资源类别代码；内置 TENANT/STORE，其他类别须经资源接入管理登记。 设计场景：区分不同业务对象的权限语义，防止把订单 ID 当店铺 ID 使用；类型来自受控目录。';
COMMENT ON COLUMN access.permission."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.permission."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';

-- access.platform_role_assignment：平台职责记录；目标运行时还必须关联 directory.platform_operator 并检查内部企业、成员和账号有效，不隐含客户数据权限。
CREATE TABLE access.platform_role_assignment (
    -- 关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 当前仅 PLATFORM_ADMIN；职责由平台管理用例固定定义。 设计场景：平台职责使用受控编码，与企业业务角色分开；平台管理员身份不自动获得客户数据权限。
    "role_code" character varying(32) NOT NULL,
    -- 授予账号；仅受控初始引导允许为空，初始化过程须另行记录审计。 设计场景：追溯平台职责授予者，授予时验证受控管理资格；初始化空值必须有独立引导审计。
    "assigned_by_account_id" bigint,
    -- 职责授予时间。 设计场景：记录平台职责何时授予，方便核查异常提权与职责交接，当前是否有效还取决于内部成员资格。
    "assigned_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_platform_role_assignment_code" CHECK (role_code::text = 'PLATFORM_ADMIN'::text),
    CONSTRAINT "fk_platform_role_assignment_account" FOREIGN KEY (account_id) REFERENCES directory.account(id) ON DELETE RESTRICT,
    CONSTRAINT "fk_platform_role_assignment_assigned_by" FOREIGN KEY (assigned_by_account_id) REFERENCES directory.account(id) ON DELETE RESTRICT,
    CONSTRAINT "pk_platform_role_assignment" PRIMARY KEY (account_id, role_code)
);
COMMENT ON TABLE access.platform_role_assignment IS '平台职责记录；目标运行时还必须关联 directory.platform_operator 并检查内部企业、成员和账号有效，不隐含客户数据权限。';
COMMENT ON COLUMN access.platform_role_assignment."account_id" IS '关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN access.platform_role_assignment."role_code" IS '当前仅 PLATFORM_ADMIN；职责由平台管理用例固定定义。 设计场景：平台职责使用受控编码，与企业业务角色分开；平台管理员身份不自动获得客户数据权限。';
COMMENT ON COLUMN access.platform_role_assignment."assigned_by_account_id" IS '授予账号；仅受控初始引导允许为空，初始化过程须另行记录审计。 设计场景：追溯平台职责授予者，授予时验证受控管理资格；初始化空值必须有独立引导审计。';
COMMENT ON COLUMN access.platform_role_assignment."assigned_at" IS '职责授予时间。 设计场景：记录平台职责何时授予，方便核查异常提权与职责交接，当前是否有效还取决于内部成员资格。';
CREATE INDEX ix_platform_role_assignment_assigned_by ON access.platform_role_assignment USING btree (assigned_by_account_id);

-- access.policy_permission：规则包含的受控动作；不存在动作关系不表示允许所有操作
CREATE TABLE access.policy_permission (
    -- 所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 策略版本。 设计场景：主体、动作和范围绑定到同一策略版本，发布与退役后仍可还原当时规则内容。
    "policy_id" bigint NOT NULL,
    -- 受控动作代码。 设计场景：角色或策略只引用已登记业务动作，禁止通过自由字符串创造未审核的系统权限。
    "permission_code" character varying(120) NOT NULL,
    CONSTRAINT "policy_permission_permission_code_fkey" FOREIGN KEY (permission_code) REFERENCES access.permission(code),
    CONSTRAINT "policy_permission_pkey" PRIMARY KEY (tenant_id, policy_id, permission_code),
    CONSTRAINT "policy_permission_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "policy_permission_tenant_id_policy_id_fkey" FOREIGN KEY (tenant_id, policy_id) REFERENCES access.policy(tenant_id, id)
);
COMMENT ON TABLE access.policy_permission IS '规则包含的受控动作；不存在动作关系不表示允许所有操作';
COMMENT ON COLUMN access.policy_permission."tenant_id" IS '所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.policy_permission."policy_id" IS '策略版本。 设计场景：主体、动作和范围绑定到同一策略版本，发布与退役后仍可还原当时规则内容。';
COMMENT ON COLUMN access.policy_permission."permission_code" IS '受控动作代码。 设计场景：角色或策略只引用已登记业务动作，禁止通过自由字符串创造未审核的系统权限。';
CREATE INDEX ix_access_policy_permission_permission ON access.policy_permission USING btree (permission_code);

-- access.policy_resource：规则适用资源；空集合仅在策略显式声明的属性条件完整有效时计算，绝不自动视为全部
CREATE TABLE access.policy_resource (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 策略版本。 设计场景：主体、动作和范围绑定到同一策略版本，发布与退役后仍可还原当时规则内容。
    "policy_id" bigint NOT NULL,
    -- 企业全部范围或明确资源。 设计场景：明确资源范围条目的类别，便于验证对应资源列组合，避免同时填入不相容的范围。
    "scope_kind" character varying(24) NOT NULL,
    -- 明确店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。
    "store_id" bigint,
    -- 明确非店铺资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。
    "resource_id" bigint,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "policy_resource_check" CHECK (updated_at >= created_at),
    CONSTRAINT "policy_resource_check1" CHECK (scope_kind::text = 'ALL_TENANT'::text AND num_nonnulls(store_id, resource_id) = 0 OR scope_kind::text = 'STORE'::text AND store_id IS NOT NULL AND resource_id IS NULL OR scope_kind::text = 'RESOURCE'::text AND resource_id IS NOT NULL AND store_id IS NULL),
    CONSTRAINT "policy_resource_id_check" CHECK (id > 0),
    CONSTRAINT "policy_resource_pkey" PRIMARY KEY (id),
    CONSTRAINT "policy_resource_scope_kind_check" CHECK (scope_kind::text = ANY (ARRAY['ALL_TENANT'::character varying, 'STORE'::character varying, 'RESOURCE'::character varying]::text[])),
    CONSTRAINT "policy_resource_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "policy_resource_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "policy_resource_tenant_id_policy_id_fkey" FOREIGN KEY (tenant_id, policy_id) REFERENCES access.policy(tenant_id, id),
    CONSTRAINT "policy_resource_tenant_id_policy_id_scope_kind_store_id_res_key" UNIQUE NULLS NOT DISTINCT (tenant_id, policy_id, scope_kind, store_id, resource_id),
    CONSTRAINT "policy_resource_tenant_id_resource_id_fkey" FOREIGN KEY (tenant_id, resource_id) REFERENCES access.resource(tenant_id, id),
    CONSTRAINT "policy_resource_tenant_id_store_id_fkey" FOREIGN KEY (tenant_id, store_id) REFERENCES demo.store(tenant_id, id)
);
COMMENT ON TABLE access.policy_resource IS '规则适用资源；空集合仅在策略显式声明的属性条件完整有效时计算，绝不自动视为全部';
COMMENT ON COLUMN access.policy_resource."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.policy_resource."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.policy_resource."policy_id" IS '策略版本。 设计场景：主体、动作和范围绑定到同一策略版本，发布与退役后仍可还原当时规则内容。';
COMMENT ON COLUMN access.policy_resource."scope_kind" IS '企业全部范围或明确资源。 设计场景：明确资源范围条目的类别，便于验证对应资源列组合，避免同时填入不相容的范围。';
COMMENT ON COLUMN access.policy_resource."store_id" IS '明确店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。';
COMMENT ON COLUMN access.policy_resource."resource_id" IS '明确非店铺资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。';
COMMENT ON COLUMN access.policy_resource."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.policy_resource."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_access_policy_resource_resource ON access.policy_resource USING btree (tenant_id, resource_id);
CREATE INDEX ix_access_policy_resource_store ON access.policy_resource USING btree (tenant_id, store_id);

-- directory.source_department：外部部门映射；本地部门 ID 稳定，接管本地部门需要显式确认。
CREATE TABLE directory.source_department (
    -- 应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 同步连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 连接内外部部门 ID。 设计场景：缺少邮箱、手机的员工也能通过来源内稳定标识匹配；必须同时使用连接及标识类型限定作用域。
    "external_subject" character varying(512) COLLATE "C" NOT NULL,
    -- 本地稳定部门 ID。 设计场景：将人员、规则或变更指向稳定的本地部门，部门改名后关联不丢失，跨企业引用被拒绝。
    "department_id" bigint NOT NULL,
    -- 同连接上级来源部门；根部门可空。 设计场景：外部部门按层级同步时保留来源父子关系，待映射完整后建立本地组织关系，不能跨连接拼接。
    "parent_source_id" bigint,
    -- 来源部门状态，不直接级联删除本地子部门或成员。 设计场景：区分来源明确离职与读取失败、不可见等情况，只有可靠的状态变化才能进入撤权流程。
    "source_status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 来源版本。 设计场景：回调乱序到达时拒绝旧变更覆盖新状态；来源无可比较版本时回查最新状态，不能按任意字符串排序。
    "source_version" character varying(200),
    -- 最近确认存在的运行。 设计场景：全量对账时知道对象在哪个批次被确认存在，避免拿旧批次的可见性判断本次删除。
    "last_seen_run_id" bigint,
    -- 最近成功同步。 设计场景：显示来源数据的最近落地时间，识别资料陈旧或同步中断；不能据此推断当前快照完整。
    "last_synced_at" timestamp with time zone,
    -- 乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "source_department_check" CHECK (parent_source_id IS NULL OR parent_source_id <> id),
    CONSTRAINT "source_department_connection_id_external_subject_key" UNIQUE (connection_id, external_subject),
    CONSTRAINT "source_department_external_subject_check" CHECK (btrim(external_subject::text) <> ''::text),
    CONSTRAINT "source_department_id_check" CHECK (id > 0),
    CONSTRAINT "source_department_pkey" PRIMARY KEY (id),
    CONSTRAINT "source_department_source_status_check" CHECK (source_status::text = ANY (ARRAY['ACTIVE'::character varying, 'DELETED'::character varying, 'OUT_OF_SCOPE'::character varying]::text[])),
    CONSTRAINT "source_department_tenant_id_connection_id_department_id_key" UNIQUE (tenant_id, connection_id, department_id),
    CONSTRAINT "source_department_tenant_id_connection_id_fkey" FOREIGN KEY (tenant_id, connection_id) REFERENCES directory.sync_connection(tenant_id, id),
    CONSTRAINT "source_department_tenant_id_connection_id_id_key" UNIQUE (tenant_id, connection_id, id),
    CONSTRAINT "source_department_tenant_id_connection_id_last_seen_run_id_fkey" FOREIGN KEY (tenant_id, connection_id, last_seen_run_id) REFERENCES directory.sync_run(tenant_id, connection_id, id),
    CONSTRAINT "source_department_tenant_id_connection_id_parent_source_id_fkey" FOREIGN KEY (tenant_id, connection_id, parent_source_id) REFERENCES directory.source_department(tenant_id, connection_id, id),
    CONSTRAINT "source_department_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "source_department_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "source_department_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE directory.source_department IS '外部部门映射；本地部门 ID 稳定，接管本地部门需要显式确认。';
COMMENT ON COLUMN directory.source_department."id" IS '应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.source_department."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.source_department."connection_id" IS '同步连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN directory.source_department."external_subject" IS '连接内外部部门 ID。 设计场景：缺少邮箱、手机的员工也能通过来源内稳定标识匹配；必须同时使用连接及标识类型限定作用域。';
COMMENT ON COLUMN directory.source_department."department_id" IS '本地稳定部门 ID。 设计场景：将人员、规则或变更指向稳定的本地部门，部门改名后关联不丢失，跨企业引用被拒绝。';
COMMENT ON COLUMN directory.source_department."parent_source_id" IS '同连接上级来源部门；根部门可空。 设计场景：外部部门按层级同步时保留来源父子关系，待映射完整后建立本地组织关系，不能跨连接拼接。';
COMMENT ON COLUMN directory.source_department."source_status" IS '来源部门状态，不直接级联删除本地子部门或成员。 设计场景：区分来源明确离职与读取失败、不可见等情况，只有可靠的状态变化才能进入撤权流程。';
COMMENT ON COLUMN directory.source_department."source_version" IS '来源版本。 设计场景：回调乱序到达时拒绝旧变更覆盖新状态；来源无可比较版本时回查最新状态，不能按任意字符串排序。';
COMMENT ON COLUMN directory.source_department."last_seen_run_id" IS '最近确认存在的运行。 设计场景：全量对账时知道对象在哪个批次被确认存在，避免拿旧批次的可见性判断本次删除。';
COMMENT ON COLUMN directory.source_department."last_synced_at" IS '最近成功同步。 设计场景：显示来源数据的最近落地时间，识别资料陈旧或同步中断；不能据此推断当前快照完整。';
COMMENT ON COLUMN directory.source_department."version" IS '乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.source_department."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.source_department."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_source_department_local ON directory.source_department USING btree (tenant_id, department_id);
CREATE INDEX ix_source_department_parent ON directory.source_department USING btree (tenant_id, connection_id, parent_source_id);

-- directory.department：企业部门邻接表；应用锁定企业组织变更并检查无环且深度最多 10 层。
CREATE TABLE directory.department (
    -- 部门 ID，由应用生成雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 部门所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 同企业父部门；空值表示根部门；CHECK 仅禁止直接自指。 设计场景：通过父节点维护部门树；移动部门时检查祖先链和最大深度，数据库的禁止自指不能代替多层防环。
    "parent_id" bigint,
    -- 部门展示名称，不承担授权标识职责。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。
    "name" character varying(200) NOT NULL,
    -- 部门状态：ACTIVE 正常，DISABLED 停用；状态变化不自动改变店铺授权。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 同级部门展示排序值，按升序排列。 设计场景：允许调整展示顺序而不改变业务标识、权限或层级关系。
    "sort_order" integer DEFAULT 0 NOT NULL,
    -- 部门聚合乐观锁版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由应用写入。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 当前资料维护权：LOCAL 本地，EXTERNAL 外部连接；接管需显式确认并保存来源映射。 设计场景：手工维护和外部同步共存时决定谁可以更新资料，避免同步覆盖明确由管理员维护的字段。
    "maintenance_mode" character varying(16) DEFAULT 'LOCAL'::character varying NOT NULL,
    -- 当前资料维护连接；LOCAL 必须为空，EXTERNAL 必须有同企业连接。维护权转移不改变对象 ID。 设计场景：多个目录来源存在时明确当前负责维护的连接，接管来源时保持成员或部门的本地 ID 不变。
    "managed_connection_id" bigint,
    CONSTRAINT "ck_department_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_department_maintainer" CHECK ((maintenance_mode::text = 'EXTERNAL'::text) = (managed_connection_id IS NOT NULL)),
    CONSTRAINT "ck_department_name" CHECK (btrim(name::text) <> ''::text),
    CONSTRAINT "ck_department_parent" CHECK (parent_id IS NULL OR parent_id <> id),
    CONSTRAINT "ck_department_status" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying]::text[])),
    CONSTRAINT "ck_department_version" CHECK (version >= 0),
    CONSTRAINT "department_maintenance_mode_check" CHECK (maintenance_mode::text = ANY (ARRAY['LOCAL'::character varying, 'EXTERNAL'::character varying]::text[])),
    CONSTRAINT "fk_department_maintainer" FOREIGN KEY (tenant_id, managed_connection_id) REFERENCES directory.sync_connection(tenant_id, id),
    CONSTRAINT "fk_department_parent" FOREIGN KEY (tenant_id, parent_id) REFERENCES directory.department(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "fk_department_source_owner" FOREIGN KEY (tenant_id, managed_connection_id, id) REFERENCES directory.source_department(tenant_id, connection_id, department_id) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT "fk_department_tenant" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "pk_directory_department" PRIMARY KEY (id),
    CONSTRAINT "uq_department_tenant_id" UNIQUE (tenant_id, id)
);
COMMENT ON TABLE directory.department IS '企业部门邻接表；应用锁定企业组织变更并检查无环且深度最多 10 层。';
COMMENT ON COLUMN directory.department."id" IS '部门 ID，由应用生成雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.department."tenant_id" IS '部门所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.department."parent_id" IS '同企业父部门；空值表示根部门；CHECK 仅禁止直接自指。 设计场景：通过父节点维护部门树；移动部门时检查祖先链和最大深度，数据库的禁止自指不能代替多层防环。';
COMMENT ON COLUMN directory.department."name" IS '部门展示名称，不承担授权标识职责。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。';
COMMENT ON COLUMN directory.department."status" IS '部门状态：ACTIVE 正常，DISABLED 停用；状态变化不自动改变店铺授权。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.department."sort_order" IS '同级部门展示排序值，按升序排列。 设计场景：允许调整展示顺序而不改变业务标识、权限或层级关系。';
COMMENT ON COLUMN directory.department."version" IS '部门聚合乐观锁版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.department."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.department."updated_at" IS '最近更新时间，由应用写入。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
COMMENT ON COLUMN directory.department."maintenance_mode" IS '当前资料维护权：LOCAL 本地，EXTERNAL 外部连接；接管需显式确认并保存来源映射。 设计场景：手工维护和外部同步共存时决定谁可以更新资料，避免同步覆盖明确由管理员维护的字段。';
COMMENT ON COLUMN directory.department."managed_connection_id" IS '当前资料维护连接；LOCAL 必须为空，EXTERNAL 必须有同企业连接。维护权转移不改变对象 ID。 设计场景：多个目录来源存在时明确当前负责维护的连接，接管来源时保持成员或部门的本地 ID 不变。';
CREATE INDEX ix_department_maintainer ON directory.department USING btree (tenant_id, managed_connection_id);
CREATE INDEX ix_department_tenant_parent ON directory.department USING btree (tenant_id, parent_id);

-- directory.team：企业内非层级协作团队；团队成员关系本身不授予业务权限。
CREATE TABLE directory.team (
    -- 团队 ID，由应用生成雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 团队所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 团队展示名称，不承担授权标识职责。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。
    "name" character varying(200) NOT NULL,
    -- 团队状态：ACTIVE 正常，DISABLED 停用。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 团队聚合乐观锁版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由应用写入。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_team_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_team_name" CHECK (btrim(name::text) <> ''::text),
    CONSTRAINT "ck_team_status" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying]::text[])),
    CONSTRAINT "ck_team_version" CHECK (version >= 0),
    CONSTRAINT "fk_team_tenant" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "pk_directory_team" PRIMARY KEY (id),
    CONSTRAINT "uq_team_tenant_id" UNIQUE (tenant_id, id)
);
COMMENT ON TABLE directory.team IS '企业内非层级协作团队；团队成员关系本身不授予业务权限。';
COMMENT ON COLUMN directory.team."id" IS '团队 ID，由应用生成雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.team."tenant_id" IS '团队所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.team."name" IS '团队展示名称，不承担授权标识职责。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。';
COMMENT ON COLUMN directory.team."status" IS '团队状态：ACTIVE 正常，DISABLED 停用。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.team."version" IS '团队聚合乐观锁版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.team."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.team."updated_at" IS '最近更新时间，由应用写入。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';

-- access.policy_subject：策略适用主体；全员、成员、部门、团队分开建关系并受同企业外键约束
CREATE TABLE access.policy_subject (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 策略版本。 设计场景：主体、动作和范围绑定到同一策略版本，发布与退役后仍可还原当时规则内容。
    "policy_id" bigint NOT NULL,
    -- 主体类别。 设计场景：明确规则面向全员、成员、部门还是团队，据此检查主体字段组合，避免空主体被解释为全员。
    "subject_kind" character varying(16) NOT NULL,
    -- 指定成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint,
    -- 指定部门。 设计场景：将人员、规则或变更指向稳定的本地部门，部门改名后关联不丢失，跨企业引用被拒绝。
    "department_id" bigint,
    -- 指定团队。 设计场景：非层级协作团队可以独立于部门组织，关系或规则只在该企业的明确团队内生效。
    "team_id" bigint,
    -- 部门规则是否包含下级部门。 设计场景：部门自动分配时区分仅本部门与包含下级部门，调整组织树后按当前规则重新计算影响范围。
    "include_descendants" boolean DEFAULT false NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "policy_subject_check" CHECK (updated_at >= created_at),
    CONSTRAINT "policy_subject_check1" CHECK (subject_kind::text = 'ALL_MEMBERS'::text AND num_nonnulls(member_id, department_id, team_id) = 0 OR subject_kind::text = 'MEMBER'::text AND member_id IS NOT NULL AND num_nonnulls(member_id, department_id, team_id) = 1 OR subject_kind::text = 'DEPARTMENT'::text AND department_id IS NOT NULL AND num_nonnulls(member_id, department_id, team_id) = 1 OR subject_kind::text = 'TEAM'::text AND team_id IS NOT NULL AND num_nonnulls(member_id, department_id, team_id) = 1),
    CONSTRAINT "policy_subject_check2" CHECK (NOT include_descendants OR subject_kind::text = 'DEPARTMENT'::text),
    CONSTRAINT "policy_subject_id_check" CHECK (id > 0),
    CONSTRAINT "policy_subject_pkey" PRIMARY KEY (id),
    CONSTRAINT "policy_subject_subject_kind_check" CHECK (subject_kind::text = ANY (ARRAY['ALL_MEMBERS'::character varying, 'MEMBER'::character varying, 'DEPARTMENT'::character varying, 'TEAM'::character varying]::text[])),
    CONSTRAINT "policy_subject_tenant_id_department_id_fkey" FOREIGN KEY (tenant_id, department_id) REFERENCES directory.department(tenant_id, id),
    CONSTRAINT "policy_subject_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "policy_subject_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "policy_subject_tenant_id_member_id_fkey" FOREIGN KEY (tenant_id, member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "policy_subject_tenant_id_policy_id_fkey" FOREIGN KEY (tenant_id, policy_id) REFERENCES access.policy(tenant_id, id),
    CONSTRAINT "policy_subject_tenant_id_policy_id_subject_kind_member_id_d_key" UNIQUE NULLS NOT DISTINCT (tenant_id, policy_id, subject_kind, member_id, department_id, team_id),
    CONSTRAINT "policy_subject_tenant_id_team_id_fkey" FOREIGN KEY (tenant_id, team_id) REFERENCES directory.team(tenant_id, id)
);
COMMENT ON TABLE access.policy_subject IS '策略适用主体；全员、成员、部门、团队分开建关系并受同企业外键约束';
COMMENT ON COLUMN access.policy_subject."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.policy_subject."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.policy_subject."policy_id" IS '策略版本。 设计场景：主体、动作和范围绑定到同一策略版本，发布与退役后仍可还原当时规则内容。';
COMMENT ON COLUMN access.policy_subject."subject_kind" IS '主体类别。 设计场景：明确规则面向全员、成员、部门还是团队，据此检查主体字段组合，避免空主体被解释为全员。';
COMMENT ON COLUMN access.policy_subject."member_id" IS '指定成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN access.policy_subject."department_id" IS '指定部门。 设计场景：将人员、规则或变更指向稳定的本地部门，部门改名后关联不丢失，跨企业引用被拒绝。';
COMMENT ON COLUMN access.policy_subject."team_id" IS '指定团队。 设计场景：非层级协作团队可以独立于部门组织，关系或规则只在该企业的明确团队内生效。';
COMMENT ON COLUMN access.policy_subject."include_descendants" IS '部门规则是否包含下级部门。 设计场景：部门自动分配时区分仅本部门与包含下级部门，调整组织树后按当前规则重新计算影响范围。';
COMMENT ON COLUMN access.policy_subject."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.policy_subject."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_access_policy_subject_department ON access.policy_subject USING btree (tenant_id, department_id);
CREATE INDEX ix_access_policy_subject_member ON access.policy_subject USING btree (tenant_id, member_id);
CREATE INDEX ix_access_policy_subject_team ON access.policy_subject USING btree (tenant_id, team_id);

-- access.request_scope：申请中的资源快照引用；资源停用或权限变化时须重新确认
CREATE TABLE access.request_scope (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 授权申请。 设计场景：把资源明细限定到对应申请；批准时重查这些资源和申请范围，不能把另一申请的范围拼进来。
    "request_id" bigint NOT NULL,
    -- 申请的店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。
    "store_id" bigint,
    -- 申请的其他资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。
    "resource_id" bigint,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "request_scope_check" CHECK (updated_at >= created_at),
    CONSTRAINT "request_scope_check1" CHECK (num_nonnulls(store_id, resource_id) = 1),
    CONSTRAINT "request_scope_id_check" CHECK (id > 0),
    CONSTRAINT "request_scope_pkey" PRIMARY KEY (id),
    CONSTRAINT "request_scope_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "request_scope_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "request_scope_tenant_id_request_id_fkey" FOREIGN KEY (tenant_id, request_id) REFERENCES access.authorization_request(tenant_id, id),
    CONSTRAINT "request_scope_tenant_id_request_id_store_id_resource_id_key" UNIQUE NULLS NOT DISTINCT (tenant_id, request_id, store_id, resource_id),
    CONSTRAINT "request_scope_tenant_id_resource_id_fkey" FOREIGN KEY (tenant_id, resource_id) REFERENCES access.resource(tenant_id, id),
    CONSTRAINT "request_scope_tenant_id_store_id_fkey" FOREIGN KEY (tenant_id, store_id) REFERENCES demo.store(tenant_id, id)
);
COMMENT ON TABLE access.request_scope IS '申请中的资源快照引用；资源停用或权限变化时须重新确认';
COMMENT ON COLUMN access.request_scope."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.request_scope."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.request_scope."request_id" IS '授权申请。 设计场景：把资源明细限定到对应申请；批准时重查这些资源和申请范围，不能把另一申请的范围拼进来。';
COMMENT ON COLUMN access.request_scope."store_id" IS '申请的店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。';
COMMENT ON COLUMN access.request_scope."resource_id" IS '申请的其他资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。';
COMMENT ON COLUMN access.request_scope."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.request_scope."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_access_request_scope_resource ON access.request_scope USING btree (tenant_id, resource_id);
CREATE INDEX ix_access_request_scope_store ON access.request_scope USING btree (tenant_id, store_id);

-- access.resource_relation：同企业资源之间的命名关系；表达资源归属和关系授权，关系语义由受控目录定义
CREATE TABLE access.resource_relation (
    -- 所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 关系起点资源。 设计场景：关系型授权中明确有方向的起点资源，不能将 A 包含 B 反向解释为 B 包含 A。
    "source_resource_id" bigint NOT NULL,
    -- 受控关系代码。 设计场景：给资源关系明确语义，例如归属或包含；授权只能解释登记过的关系类型。
    "relation_code" character varying(64) NOT NULL,
    -- 关系终点资源。 设计场景：与起点及关系类型组成一条明确资源关系，两端必须满足同企业及类型语义。
    "target_resource_id" bigint NOT NULL,
    -- 关系建立时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "resource_relation_check" CHECK (source_resource_id <> target_resource_id),
    CONSTRAINT "resource_relation_pkey" PRIMARY KEY (tenant_id, source_resource_id, relation_code, target_resource_id),
    CONSTRAINT "resource_relation_relation_code_check" CHECK (relation_code::text ~ '^[A-Z][A-Z0-9_]{0,63}$'::text),
    CONSTRAINT "resource_relation_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "resource_relation_tenant_id_source_resource_id_fkey" FOREIGN KEY (tenant_id, source_resource_id) REFERENCES access.resource(tenant_id, id),
    CONSTRAINT "resource_relation_tenant_id_target_resource_id_fkey" FOREIGN KEY (tenant_id, target_resource_id) REFERENCES access.resource(tenant_id, id)
);
COMMENT ON TABLE access.resource_relation IS '同企业资源之间的命名关系；表达资源归属和关系授权，关系语义由受控目录定义';
COMMENT ON COLUMN access.resource_relation."tenant_id" IS '所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.resource_relation."source_resource_id" IS '关系起点资源。 设计场景：关系型授权中明确有方向的起点资源，不能将 A 包含 B 反向解释为 B 包含 A。';
COMMENT ON COLUMN access.resource_relation."relation_code" IS '受控关系代码。 设计场景：给资源关系明确语义，例如归属或包含；授权只能解释登记过的关系类型。';
COMMENT ON COLUMN access.resource_relation."target_resource_id" IS '关系终点资源。 设计场景：与起点及关系类型组成一条明确资源关系，两端必须满足同企业及类型语义。';
COMMENT ON COLUMN access.resource_relation."created_at" IS '关系建立时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_access_resource_relation_reverse ON access.resource_relation USING btree (tenant_id, target_resource_id, relation_code, source_resource_id);

-- access.review_campaign：周期访问复核批次；显式记录范围与截止时间，不由某次审计查询代替
CREATE TABLE access.review_campaign (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 复核名称。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。
    "name" character varying(200) NOT NULL,
    -- 复核负责人。 设计场景：指定负责维护资源、机器或复核任务的企业成员，支持责任交接；负责人关系本身不赋予全部操作权限。
    "owner_member_id" bigint NOT NULL,
    -- 复核批次状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'OPEN'::character varying NOT NULL,
    -- 本次复核截止时间。 设计场景：给本轮访问复核设置截止期，用于提醒和标记逾期，不把无回应自动等同于批准。
    "due_at" timestamp with time zone NOT NULL,
    -- 下一次复核计划时间。 设计场景：安排下一轮周期检查，持续发现人员变化后仍遗留的权限。
    "next_review_at" timestamp with time zone,
    -- 结束时间。 设计场景：记录业务流程完成时间，便于区分处理中与已完成；完成必须以相应业务效果落地为前提。
    "completed_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "review_campaign_check" CHECK (updated_at >= created_at),
    CONSTRAINT "review_campaign_check1" CHECK (due_at > created_at),
    CONSTRAINT "review_campaign_check2" CHECK (next_review_at IS NULL OR next_review_at > due_at),
    CONSTRAINT "review_campaign_check3" CHECK (status::text = 'OPEN'::text AND completed_at IS NULL OR status::text <> 'OPEN'::text AND completed_at IS NOT NULL AND completed_at >= created_at),
    CONSTRAINT "review_campaign_id_check" CHECK (id > 0),
    CONSTRAINT "review_campaign_name_check" CHECK (btrim(name::text) <> ''::text),
    CONSTRAINT "review_campaign_pkey" PRIMARY KEY (id),
    CONSTRAINT "review_campaign_status_check" CHECK (status::text = ANY (ARRAY['OPEN'::character varying, 'COMPLETED'::character varying, 'CANCELLED'::character varying]::text[])),
    CONSTRAINT "review_campaign_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "review_campaign_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "review_campaign_tenant_id_owner_member_id_fkey" FOREIGN KEY (tenant_id, owner_member_id) REFERENCES directory.membership(tenant_id, id)
);
COMMENT ON TABLE access.review_campaign IS '周期访问复核批次；显式记录范围与截止时间，不由某次审计查询代替';
COMMENT ON COLUMN access.review_campaign."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.review_campaign."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.review_campaign."name" IS '复核名称。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。';
COMMENT ON COLUMN access.review_campaign."owner_member_id" IS '复核负责人。 设计场景：指定负责维护资源、机器或复核任务的企业成员，支持责任交接；负责人关系本身不赋予全部操作权限。';
COMMENT ON COLUMN access.review_campaign."status" IS '复核批次状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN access.review_campaign."due_at" IS '本次复核截止时间。 设计场景：给本轮访问复核设置截止期，用于提醒和标记逾期，不把无回应自动等同于批准。';
COMMENT ON COLUMN access.review_campaign."next_review_at" IS '下一次复核计划时间。 设计场景：安排下一轮周期检查，持续发现人员变化后仍遗留的权限。';
COMMENT ON COLUMN access.review_campaign."completed_at" IS '结束时间。 设计场景：记录业务流程完成时间，便于区分处理中与已完成；完成必须以相应业务效果落地为前提。';
COMMENT ON COLUMN access.review_campaign."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.review_campaign."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_access_review_campaign_due ON access.review_campaign USING btree (tenant_id, status, due_at);
CREATE INDEX ix_access_review_campaign_owner ON access.review_campaign USING btree (tenant_id, owner_member_id);

-- access.review_item：成员授权逐条复核记录；撤销决定与撤权执行分别记录，保留历史授权引用
CREATE TABLE access.review_item (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 复核批次。 设计场景：逐条权限复核归入具体批次，便于区分上一轮已经完成的决定和本轮仍待处理的权限。
    "campaign_id" bigint NOT NULL,
    -- 复核的成员授权。 设计场景：资源范围和复核决定归属某一条具体授权，不能将不同授权的动作与范围任意组合。
    "grant_id" bigint NOT NULL,
    -- 指定复核成员。 设计场景：限定由目标企业中有审批资格的人作决定，并检查其与申请人、受益人的职责分离。
    "reviewer_member_id" bigint NOT NULL,
    -- 未决定、保留或撤销。 设计场景：保存明确的处理决定供后续执行与追溯；决定本身和实际执行完成分别验证。
    "decision" character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    -- 复核意见。 设计场景：让审批、撤销或变更决定有可追溯的理由，便于申诉和审计；不能用自由文本代替结构化状态。
    "reason" character varying(1000),
    -- 决定时间。 设计场景：记录批准、拒绝或复核决定的时间，便于判断是否在截止期内作出及追踪审批顺序。
    "decided_at" timestamp with time zone,
    -- 决定已执行时间；撤销未落地不得显示完成。 设计场景：审批人决定撤销后还需真正撤权，保留执行时间避免界面提前显示已完成。
    "enforced_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "review_item_check" CHECK (updated_at >= created_at),
    CONSTRAINT "review_item_check1" CHECK (decision::text = 'PENDING'::text AND decided_at IS NULL AND enforced_at IS NULL OR decision::text <> 'PENDING'::text AND decided_at IS NOT NULL),
    CONSTRAINT "review_item_check2" CHECK (enforced_at IS NULL OR enforced_at >= decided_at),
    CONSTRAINT "review_item_decision_check" CHECK (decision::text = ANY (ARRAY['PENDING'::character varying, 'RETAIN'::character varying, 'REVOKE'::character varying]::text[])),
    CONSTRAINT "review_item_id_check" CHECK (id > 0),
    CONSTRAINT "review_item_pkey" PRIMARY KEY (id),
    CONSTRAINT "review_item_tenant_id_campaign_id_fkey" FOREIGN KEY (tenant_id, campaign_id) REFERENCES access.review_campaign(tenant_id, id),
    CONSTRAINT "review_item_tenant_id_campaign_id_grant_id_key" UNIQUE (tenant_id, campaign_id, grant_id),
    CONSTRAINT "review_item_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "review_item_tenant_id_grant_id_fkey" FOREIGN KEY (tenant_id, grant_id) REFERENCES access.member_grant(tenant_id, id),
    CONSTRAINT "review_item_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "review_item_tenant_id_reviewer_member_id_fkey" FOREIGN KEY (tenant_id, reviewer_member_id) REFERENCES directory.membership(tenant_id, id)
);
COMMENT ON TABLE access.review_item IS '成员授权逐条复核记录；撤销决定与撤权执行分别记录，保留历史授权引用';
COMMENT ON COLUMN access.review_item."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN access.review_item."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.review_item."campaign_id" IS '复核批次。 设计场景：逐条权限复核归入具体批次，便于区分上一轮已经完成的决定和本轮仍待处理的权限。';
COMMENT ON COLUMN access.review_item."grant_id" IS '复核的成员授权。 设计场景：资源范围和复核决定归属某一条具体授权，不能将不同授权的动作与范围任意组合。';
COMMENT ON COLUMN access.review_item."reviewer_member_id" IS '指定复核成员。 设计场景：限定由目标企业中有审批资格的人作决定，并检查其与申请人、受益人的职责分离。';
COMMENT ON COLUMN access.review_item."decision" IS '未决定、保留或撤销。 设计场景：保存明确的处理决定供后续执行与追溯；决定本身和实际执行完成分别验证。';
COMMENT ON COLUMN access.review_item."reason" IS '复核意见。 设计场景：让审批、撤销或变更决定有可追溯的理由，便于申诉和审计；不能用自由文本代替结构化状态。';
COMMENT ON COLUMN access.review_item."decided_at" IS '决定时间。 设计场景：记录批准、拒绝或复核决定的时间，便于判断是否在截止期内作出及追踪审批顺序。';
COMMENT ON COLUMN access.review_item."enforced_at" IS '决定已执行时间；撤销未落地不得显示完成。 设计场景：审批人决定撤销后还需真正撤权，保留执行时间避免界面提前显示已完成。';
COMMENT ON COLUMN access.review_item."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN access.review_item."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_access_review_item_grant ON access.review_item USING btree (tenant_id, grant_id);
CREATE INDEX ix_access_review_item_reviewer ON access.review_item USING btree (tenant_id, reviewer_member_id, decision);

-- access.role_conflict：职责互斥角色对；应用在授予与有效权限计算时检查，不允许绕过继承和规则间接同时取得
CREATE TABLE access.role_conflict (
    -- 所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 较小角色 ID，保证无序角色对唯一。 设计场景：把一对互斥角色按 ID 排序存储，避免 A/B 与 B/A 被当作两个不同规则。
    "lower_role_id" bigint NOT NULL,
    -- 较大角色 ID。 设计场景：与较小 ID 配合形成唯一的互斥角色对，不代表这个角色权限更高。
    "upper_role_id" bigint NOT NULL,
    -- 禁止同时授予或禁止同次激活。 设计场景：区分禁止同时拥有与禁止在同次操作中同时激活，授予和使用阶段分别检查。
    "enforcement" character varying(16) NOT NULL,
    -- 互斥业务原因。 设计场景：让审批、撤销或变更决定有可追溯的理由，便于申诉和审计；不能用自由文本代替结构化状态。
    "reason" character varying(500) NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "role_conflict_check" CHECK (lower_role_id < upper_role_id),
    CONSTRAINT "role_conflict_enforcement_check" CHECK (enforcement::text = ANY (ARRAY['ASSIGNMENT'::character varying, 'ACTIVATION'::character varying]::text[])),
    CONSTRAINT "role_conflict_pkey" PRIMARY KEY (tenant_id, lower_role_id, upper_role_id),
    CONSTRAINT "role_conflict_reason_check" CHECK (btrim(reason::text) <> ''::text),
    CONSTRAINT "role_conflict_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "role_conflict_tenant_id_lower_role_id_fkey" FOREIGN KEY (tenant_id, lower_role_id) REFERENCES access.role(tenant_id, id),
    CONSTRAINT "role_conflict_tenant_id_upper_role_id_fkey" FOREIGN KEY (tenant_id, upper_role_id) REFERENCES access.role(tenant_id, id)
);
COMMENT ON TABLE access.role_conflict IS '职责互斥角色对；应用在授予与有效权限计算时检查，不允许绕过继承和规则间接同时取得';
COMMENT ON COLUMN access.role_conflict."tenant_id" IS '所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.role_conflict."lower_role_id" IS '较小角色 ID，保证无序角色对唯一。 设计场景：把一对互斥角色按 ID 排序存储，避免 A/B 与 B/A 被当作两个不同规则。';
COMMENT ON COLUMN access.role_conflict."upper_role_id" IS '较大角色 ID。 设计场景：与较小 ID 配合形成唯一的互斥角色对，不代表这个角色权限更高。';
COMMENT ON COLUMN access.role_conflict."enforcement" IS '禁止同时授予或禁止同次激活。 设计场景：区分禁止同时拥有与禁止在同次操作中同时激活，授予和使用阶段分别检查。';
COMMENT ON COLUMN access.role_conflict."reason" IS '互斥业务原因。 设计场景：让审批、撤销或变更决定有可追溯的理由，便于申诉和审计；不能用自由文本代替结构化状态。';
COMMENT ON COLUMN access.role_conflict."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_access_role_conflict_upper ON access.role_conflict USING btree (tenant_id, upper_role_id);

-- access.role_inheritance：子角色继承父角色动作；不能扩大具体授权的资源范围，发布和变更必须检查循环
CREATE TABLE access.role_inheritance (
    -- 所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 实际被授予的子角色。 设计场景：标识实际授予用户的角色，继承只增加允许解释的动作，不扩大这一条授权的资源范围。
    "child_role_id" bigint NOT NULL,
    -- 被继承动作的父角色。 设计场景：指出动作来自哪个父角色，角色变更时沿继承关系复核影响并检查循环。
    "parent_role_id" bigint NOT NULL,
    -- 继承关系建立时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "role_inheritance_check" CHECK (child_role_id <> parent_role_id),
    CONSTRAINT "role_inheritance_pkey" PRIMARY KEY (tenant_id, child_role_id, parent_role_id),
    CONSTRAINT "role_inheritance_tenant_id_child_role_id_fkey" FOREIGN KEY (tenant_id, child_role_id) REFERENCES access.role(tenant_id, id),
    CONSTRAINT "role_inheritance_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "role_inheritance_tenant_id_parent_role_id_fkey" FOREIGN KEY (tenant_id, parent_role_id) REFERENCES access.role(tenant_id, id)
);
COMMENT ON TABLE access.role_inheritance IS '子角色继承父角色动作；不能扩大具体授权的资源范围，发布和变更必须检查循环';
COMMENT ON COLUMN access.role_inheritance."tenant_id" IS '所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.role_inheritance."child_role_id" IS '实际被授予的子角色。 设计场景：标识实际授予用户的角色，继承只增加允许解释的动作，不扩大这一条授权的资源范围。';
COMMENT ON COLUMN access.role_inheritance."parent_role_id" IS '被继承动作的父角色。 设计场景：指出动作来自哪个父角色，角色变更时沿继承关系复核影响并检查循环。';
COMMENT ON COLUMN access.role_inheritance."created_at" IS '继承关系建立时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_access_role_inheritance_parent ON access.role_inheritance USING btree (tenant_id, parent_role_id, child_role_id);

-- access.role_permission：企业角色的显式动作集合；变更时须检查角色类型并推进角色版本
CREATE TABLE access.role_permission (
    -- 所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 同企业角色 ID。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。
    "role_id" bigint NOT NULL,
    -- 仅引用受控企业动作目录；CUSTOM 只允许 STORE 动作，由受控用例验证。 设计场景：角色或策略只引用已登记业务动作，禁止通过自由字符串创造未审核的系统权限。
    "permission_code" character varying(120) NOT NULL,
    CONSTRAINT "fk_role_permission_permission" FOREIGN KEY (permission_code) REFERENCES access.permission(code) ON DELETE RESTRICT,
    CONSTRAINT "fk_role_permission_role" FOREIGN KEY (tenant_id, role_id) REFERENCES access.role(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "pk_role_permission" PRIMARY KEY (tenant_id, role_id, permission_code)
);
COMMENT ON TABLE access.role_permission IS '企业角色的显式动作集合；变更时须检查角色类型并推进角色版本';
COMMENT ON COLUMN access.role_permission."tenant_id" IS '所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN access.role_permission."role_id" IS '同企业角色 ID。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。';
COMMENT ON COLUMN access.role_permission."permission_code" IS '仅引用受控企业动作目录；CUSTOM 只允许 STORE 动作，由受控用例验证。 设计场景：角色或策略只引用已登记业务动作，禁止通过自由字符串创造未审核的系统权限。';
CREATE INDEX ix_role_permission_permission ON access.role_permission USING btree (permission_code);

-- identity.auth_session：满足当前所需认证因子后建立的中央会话；不保存当前企业，不替代 Spring Session 或 OAuth 授权。
CREATE TABLE identity.auth_session (
    -- 内部中央会话雪花 ID，不能把公开会话列表中的 ID 直接作为登录凭据。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 会话建立时账号 auth_epoch 快照；请求与刷新必须对照当前账号状态和版本，禁止刷新时改为新值复活旧授权。 设计场景：会话建立时保存账号撤销版本快照；改密或全局禁用推进账号版本后，即使会话 Cookie 仍存在也应拒绝旧会话。
    "auth_epoch" bigint NOT NULL,
    -- 主认证方法PASSWORD/SMS/EXTERNAL/PASSKEY；具体证明及强度另见authentication_evidence。 设计场景：区分密码、短信、外部身份和通行密钥等主认证方式，进入更严格应用时判断是否需要补充认证。
    "primary_method" character varying(16) NOT NULL,
    -- 本次主要身份验证完成时间。 设计场景：敏感操作要求近期重新证明身份时，检查真正的主认证时间，不能用最近访问时间代替。
    "primary_authenticated_at" timestamp with time zone NOT NULL,
    -- 本会话通过 MFA 的时间；是否要求 MFA 由当前账号和权限规则决定，非空本身不代表所有条件满足。 设计场景：判断会话是否完成所需加强验证及是否足够近期；普通登录成功不能自动满足管理员或应用的 MFA 要求。
    "mfa_verified_at" timestamp with time zone,
    -- 最近有效访问时间。 设计场景：区分持续使用与长期不活跃记录，为会话空闲判断或设备管理提供依据；不能刷新绝对有效期。
    "last_seen_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 空闲超时截止。 设计场景：长时间没有有效访问时使会话失效；活动可按规则续期，但不能突破绝对截止。
    "idle_expires_at" timestamp with time zone NOT NULL,
    -- 不可被续期越过的最长会话截止。 设计场景：限制会话最长寿命，即使用户一直活动也需在达到上限后重新认证。
    "absolute_expires_at" timestamp with time zone NOT NULL,
    -- 中央会话撤销时间；派生客户端授权必须同步撤销或在使用时验证中央会话状态。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 脱敏撤销原因。 设计场景：向用户和运维解释会话为何退出，例如改密、本人退出或管理员撤销，并为审计提供分类。
    "revoke_reason" character varying(64),
    -- 受控且脱敏的客户端/来源展示信息，不保存访问令牌、刷新令牌、Cookie 或完整敏感请求体。 设计场景：在会话列表帮助本人识别设备和来源，使用脱敏摘要避免暴露完整地址、令牌或请求内容。
    "source_summary" jsonb NOT NULL,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "auth_session_pkey" PRIMARY KEY (id),
    CONSTRAINT "ck_auth_session_epoch" CHECK (auth_epoch >= 0),
    CONSTRAINT "ck_auth_session_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_auth_session_method" CHECK (primary_method::text = ANY (ARRAY['PASSWORD'::character varying, 'SMS'::character varying, 'EXTERNAL'::character varying, 'PASSKEY'::character varying]::text[])),
    CONSTRAINT "ck_auth_session_revoked" CHECK (revoked_at IS NULL AND revoke_reason IS NULL OR revoked_at IS NOT NULL AND revoke_reason IS NOT NULL AND revoked_at >= created_at AND btrim(revoke_reason::text) <> ''::text),
    CONSTRAINT "ck_auth_session_source" CHECK (jsonb_typeof(source_summary) = 'object'::text),
    CONSTRAINT "ck_auth_session_times" CHECK (last_seen_at >= primary_authenticated_at AND idle_expires_at > last_seen_at AND idle_expires_at <= absolute_expires_at AND (mfa_verified_at IS NULL OR mfa_verified_at >= primary_authenticated_at AND mfa_verified_at <= last_seen_at)),
    CONSTRAINT "ck_auth_session_updated" CHECK (updated_at >= created_at),
    CONSTRAINT "fk_auth_session_account" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "uq_auth_session_account_id" UNIQUE (account_id, id)
);
COMMENT ON TABLE identity.auth_session IS '满足当前所需认证因子后建立的中央会话；不保存当前企业，不替代 Spring Session 或 OAuth 授权。';
COMMENT ON COLUMN identity.auth_session."id" IS '内部中央会话雪花 ID，不能把公开会话列表中的 ID 直接作为登录凭据。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.auth_session."account_id" IS '关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.auth_session."auth_epoch" IS '会话建立时账号 auth_epoch 快照；请求与刷新必须对照当前账号状态和版本，禁止刷新时改为新值复活旧授权。 设计场景：会话建立时保存账号撤销版本快照；改密或全局禁用推进账号版本后，即使会话 Cookie 仍存在也应拒绝旧会话。';
COMMENT ON COLUMN identity.auth_session."primary_method" IS '主认证方法PASSWORD/SMS/EXTERNAL/PASSKEY；具体证明及强度另见authentication_evidence。 设计场景：区分密码、短信、外部身份和通行密钥等主认证方式，进入更严格应用时判断是否需要补充认证。';
COMMENT ON COLUMN identity.auth_session."primary_authenticated_at" IS '本次主要身份验证完成时间。 设计场景：敏感操作要求近期重新证明身份时，检查真正的主认证时间，不能用最近访问时间代替。';
COMMENT ON COLUMN identity.auth_session."mfa_verified_at" IS '本会话通过 MFA 的时间；是否要求 MFA 由当前账号和权限规则决定，非空本身不代表所有条件满足。 设计场景：判断会话是否完成所需加强验证及是否足够近期；普通登录成功不能自动满足管理员或应用的 MFA 要求。';
COMMENT ON COLUMN identity.auth_session."last_seen_at" IS '最近有效访问时间。 设计场景：区分持续使用与长期不活跃记录，为会话空闲判断或设备管理提供依据；不能刷新绝对有效期。';
COMMENT ON COLUMN identity.auth_session."idle_expires_at" IS '空闲超时截止。 设计场景：长时间没有有效访问时使会话失效；活动可按规则续期，但不能突破绝对截止。';
COMMENT ON COLUMN identity.auth_session."absolute_expires_at" IS '不可被续期越过的最长会话截止。 设计场景：限制会话最长寿命，即使用户一直活动也需在达到上限后重新认证。';
COMMENT ON COLUMN identity.auth_session."revoked_at" IS '中央会话撤销时间；派生客户端授权必须同步撤销或在使用时验证中央会话状态。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN identity.auth_session."revoke_reason" IS '脱敏撤销原因。 设计场景：向用户和运维解释会话为何退出，例如改密、本人退出或管理员撤销，并为审计提供分类。';
COMMENT ON COLUMN identity.auth_session."source_summary" IS '受控且脱敏的客户端/来源展示信息，不保存访问令牌、刷新令牌、Cookie 或完整敏感请求体。 设计场景：在会话列表帮助本人识别设备和来源，使用脱敏摘要避免暴露完整地址、令牌或请求内容。';
COMMENT ON COLUMN identity.auth_session."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.auth_session."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_auth_session_absolute_expiry ON identity.auth_session USING btree (absolute_expires_at);
CREATE INDEX ix_auth_session_account_created ON identity.auth_session USING btree (account_id, created_at);
CREATE INDEX ix_auth_session_idle_expiry ON identity.auth_session USING btree (idle_expires_at) WHERE (revoked_at IS NULL);

-- protocol.oauth2_registered_client：Spring OAuth 注册客户端；与业务应用目录分开管理。
CREATE TABLE protocol.oauth2_registered_client (
    -- 框架持久化记录主键，保留框架字符串格式。 设计场景：框架内部记录主键供授权表关联，和对外公开 client_id 区分；保留框架要求的主键类型，不强改为业务雪花 ID。
    "id" character varying(100) NOT NULL,
    -- 协议客户端公开标识，不是平台账号 ID。 设计场景：协议交互时定位具体应用客户端，与平台账号和企业应用 ID 分开；公开标识本身不能证明客户端身份。
    "client_id" character varying(100) NOT NULL,
    -- 客户端标识签发时间。 设计场景：追溯协议客户端何时建立，支持登记审计和凭据治理；不是用户登录时间。
    "client_id_issued_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 框架支持的客户端秘密编码值；不得由普通 API 返回。 设计场景：服务端客户端换取令牌时证明自己的身份；不得把共享秘密嵌入桌面或移动安装包。
    "client_secret" character varying(200) DEFAULT NULL::character varying,
    -- 客户端秘密过期时间。 设计场景：要求服务端应用定期轮换秘密，到期后不能继续凭旧秘密认证。
    "client_secret_expires_at" timestamp with time zone,
    -- 客户端展示名。 设计场景：方便接入管理员辨认不同终端和环境的客户端，实际认证仍使用稳定客户端标识。
    "client_name" character varying(200) NOT NULL,
    -- 框架编码的客户端认证方法集合。 设计场景：按客户端类型限制可接受的认证方法，公共客户端和能安全保存秘密的服务端客户端分别配置。
    "client_authentication_methods" character varying(1000) NOT NULL,
    -- 允许的 OAuth 授权类型集合。 设计场景：限制客户端可使用的授权流程，不能因登记成功就允许所有令牌获取方式。
    "authorization_grant_types" character varying(1000) NOT NULL,
    -- 允许的精确回调地址集合，由接入流程校验。 设计场景：完成授权后只返回精确登记的地址，防止授权码被送到攻击者指定站点。
    "redirect_uris" character varying(1000) DEFAULT NULL::character varying,
    -- 退出后允许返回的地址集合。 设计场景：退出完成后只允许返回可信地址，防止退出入口成为任意跳转工具。
    "post_logout_redirect_uris" character varying(1000) DEFAULT NULL::character varying,
    -- 允许请求的协议范围集合，不等于企业业务权限。 设计场景：界定客户端最多可请求哪些协议范围，实际令牌范围还需授权；不能代替店铺、租户和角色判定。
    "scopes" character varying(1000) NOT NULL,
    -- 框架序列化的客户端设置；接入层严格验证。 设计场景：保存所锁定框架理解的客户端行为设置，按接入规则验证后写入，避免随意 JSON 放宽安全要求。
    "client_settings" character varying(2000) NOT NULL,
    -- 框架序列化的令牌时效等设置。 设计场景：为不同客户端配置令牌寿命等协议策略，减少把统一超长有效期用于所有应用的风险。
    "token_settings" character varying(2000) NOT NULL,
    CONSTRAINT "oauth2_registered_client_pkey" PRIMARY KEY (id)
);
COMMENT ON TABLE protocol.oauth2_registered_client IS 'Spring OAuth 注册客户端；与业务应用目录分开管理。';
COMMENT ON COLUMN protocol.oauth2_registered_client."id" IS '框架持久化记录主键，保留框架字符串格式。 设计场景：框架内部记录主键供授权表关联，和对外公开 client_id 区分；保留框架要求的主键类型，不强改为业务雪花 ID。';
COMMENT ON COLUMN protocol.oauth2_registered_client."client_id" IS '协议客户端公开标识，不是平台账号 ID。 设计场景：协议交互时定位具体应用客户端，与平台账号和企业应用 ID 分开；公开标识本身不能证明客户端身份。';
COMMENT ON COLUMN protocol.oauth2_registered_client."client_id_issued_at" IS '客户端标识签发时间。 设计场景：追溯协议客户端何时建立，支持登记审计和凭据治理；不是用户登录时间。';
COMMENT ON COLUMN protocol.oauth2_registered_client."client_secret" IS '框架支持的客户端秘密编码值；不得由普通 API 返回。 设计场景：服务端客户端换取令牌时证明自己的身份；不得把共享秘密嵌入桌面或移动安装包。';
COMMENT ON COLUMN protocol.oauth2_registered_client."client_secret_expires_at" IS '客户端秘密过期时间。 设计场景：要求服务端应用定期轮换秘密，到期后不能继续凭旧秘密认证。';
COMMENT ON COLUMN protocol.oauth2_registered_client."client_name" IS '客户端展示名。 设计场景：方便接入管理员辨认不同终端和环境的客户端，实际认证仍使用稳定客户端标识。';
COMMENT ON COLUMN protocol.oauth2_registered_client."client_authentication_methods" IS '框架编码的客户端认证方法集合。 设计场景：按客户端类型限制可接受的认证方法，公共客户端和能安全保存秘密的服务端客户端分别配置。';
COMMENT ON COLUMN protocol.oauth2_registered_client."authorization_grant_types" IS '允许的 OAuth 授权类型集合。 设计场景：限制客户端可使用的授权流程，不能因登记成功就允许所有令牌获取方式。';
COMMENT ON COLUMN protocol.oauth2_registered_client."redirect_uris" IS '允许的精确回调地址集合，由接入流程校验。 设计场景：完成授权后只返回精确登记的地址，防止授权码被送到攻击者指定站点。';
COMMENT ON COLUMN protocol.oauth2_registered_client."post_logout_redirect_uris" IS '退出后允许返回的地址集合。 设计场景：退出完成后只允许返回可信地址，防止退出入口成为任意跳转工具。';
COMMENT ON COLUMN protocol.oauth2_registered_client."scopes" IS '允许请求的协议范围集合，不等于企业业务权限。 设计场景：界定客户端最多可请求哪些协议范围，实际令牌范围还需授权；不能代替店铺、租户和角色判定。';
COMMENT ON COLUMN protocol.oauth2_registered_client."client_settings" IS '框架序列化的客户端设置；接入层严格验证。 设计场景：保存所锁定框架理解的客户端行为设置，按接入规则验证后写入，避免随意 JSON 放宽安全要求。';
COMMENT ON COLUMN protocol.oauth2_registered_client."token_settings" IS '框架序列化的令牌时效等设置。 设计场景：为不同客户端配置令牌寿命等协议策略，减少把统一超长有效期用于所有应用的风险。';
CREATE UNIQUE INDEX uq_oauth_client_id ON protocol.oauth2_registered_client USING btree (client_id);

-- identity.client_session：中央认证会话与 OAuth/OIDC 客户端授权的关联；支持按客户端退出及随中央会话撤销，不代替具体企业应用的访问资格。
CREATE TABLE identity.client_session (
    -- 本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 关联的中央认证会话。 设计场景：把各应用登录追溯到中央认证会话，全部退出或中央撤销后能定位依赖它的应用会话。
    "central_session_id" bigint NOT NULL,
    -- 框架注册客户端记录 ID。 设计场景：识别中央登录产生了哪个 OAuth/OIDC 客户端会话，以支持退出单个应用或撤销全部关联授权。
    "registered_client_id" character varying(100) NOT NULL,
    -- 对应的 OAuth 授权记录标识。 设计场景：将应用会话和框架授权记录连起来，撤销时同步处理相关授权，而不只删除浏览器 Cookie。
    "oauth2_authorization_id" character varying(100) NOT NULL,
    -- 撤销时间；撤销后的记录不能参与认证或授权。 设计场景：只撤销这一客户端关联或随中央会话统一撤销，避免把删除一个应用会话等同于删除账号。
    "revoked_at" timestamp with time zone,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "client_session_account_id_central_session_id_fkey" FOREIGN KEY (account_id, central_session_id) REFERENCES identity.auth_session(account_id, id),
    CONSTRAINT "client_session_id_check" CHECK (id > 0),
    CONSTRAINT "client_session_oauth2_authorization_id_key" UNIQUE (oauth2_authorization_id),
    CONSTRAINT "client_session_pkey" PRIMARY KEY (id),
    CONSTRAINT "client_session_registered_client_id_fkey" FOREIGN KEY (registered_client_id) REFERENCES protocol.oauth2_registered_client(id),
    CONSTRAINT "uq_client_session_account_central_id" UNIQUE (account_id, central_session_id, id)
);
COMMENT ON TABLE identity.client_session IS '中央认证会话与 OAuth/OIDC 客户端授权的关联；支持按客户端退出及随中央会话撤销，不代替具体企业应用的访问资格。';
COMMENT ON COLUMN identity.client_session."id" IS '本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.client_session."account_id" IS '关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.client_session."central_session_id" IS '关联的中央认证会话。 设计场景：把各应用登录追溯到中央认证会话，全部退出或中央撤销后能定位依赖它的应用会话。';
COMMENT ON COLUMN identity.client_session."registered_client_id" IS '框架注册客户端记录 ID。 设计场景：识别中央登录产生了哪个 OAuth/OIDC 客户端会话，以支持退出单个应用或撤销全部关联授权。';
COMMENT ON COLUMN identity.client_session."oauth2_authorization_id" IS '对应的 OAuth 授权记录标识。 设计场景：将应用会话和框架授权记录连起来，撤销时同步处理相关授权，而不只删除浏览器 Cookie。';
COMMENT ON COLUMN identity.client_session."revoked_at" IS '撤销时间；撤销后的记录不能参与认证或授权。 设计场景：只撤销这一客户端关联或随中央会话统一撤销，避免把删除一个应用会话等同于删除账号。';
COMMENT ON COLUMN identity.client_session."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.client_session."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_client_session_account ON identity.client_session USING btree (account_id, created_at DESC);
CREATE INDEX ix_client_session_central ON identity.client_session USING btree (central_session_id);

-- application.catalog：平台维护的全局产品应用目录；登记应用不自动向任何企业开通
CREATE TABLE application.catalog (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 平台唯一稳定应用代码。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。
    "code" character varying(64) NOT NULL,
    -- 应用名称。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。
    "name" character varying(200) NOT NULL,
    -- 用户可读的应用说明。 设计场景：向管理员和使用者解释对象用途；展示说明不参与身份认证或权限判定。
    "description" text DEFAULT ''::text NOT NULL,
    -- 图标资源引用，不含临时凭据。 设计场景：门户显示应用图标时读取受控资源，图标地址不夹带长期存储访问凭据。
    "icon_ref" text,
    -- 受控应用分类。 设计场景：按受控类别组织应用或通知展示，筛选分类不代表业务授权范围。
    "category" character varying(64) DEFAULT 'OTHER'::character varying NOT NULL,
    -- 应用接入负责人平台账号。 设计场景：应用接入和配置异常时能找到全局负责人，负责人权限仍需独立授权。
    "owner_account_id" bigint NOT NULL,
    -- 默认手动开通；只有明确配置时才为新企业开通，不自动分配成员。 设计场景：新企业建立时仅按明确规则开通应用，避免登记一个新应用就向所有客户自动开放。
    "default_enablement" character varying(24) DEFAULT 'MANUAL'::character varying NOT NULL,
    -- 明确启用默认规则时使用的环境。 设计场景：默认开通规则启用时选择对应环境，防止客户误进入测试或预发布应用。
    "default_environment" character varying(32) DEFAULT 'production'::character varying NOT NULL,
    -- 平台目录状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'DRAFT'::character varying NOT NULL,
    -- 目录并发版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "catalog_category_check" CHECK (btrim(category::text) <> ''::text),
    CONSTRAINT "catalog_check" CHECK (updated_at >= created_at),
    CONSTRAINT "catalog_code_check" CHECK (code::text ~ '^[a-z][a-z0-9_-]{0,63}$'::text),
    CONSTRAINT "catalog_code_key" UNIQUE (code),
    CONSTRAINT "catalog_default_enablement_check" CHECK (default_enablement::text = ANY (ARRAY['MANUAL'::character varying, 'ON_TENANT_CREATE'::character varying]::text[])),
    CONSTRAINT "catalog_default_environment_check" CHECK (default_environment::text ~ '^[a-z][a-z0-9_-]{0,31}$'::text),
    CONSTRAINT "catalog_id_check" CHECK (id > 0),
    CONSTRAINT "catalog_name_check" CHECK (btrim(name::text) <> ''::text),
    CONSTRAINT "catalog_owner_account_id_fkey" FOREIGN KEY (owner_account_id) REFERENCES directory.account(id),
    CONSTRAINT "catalog_pkey" PRIMARY KEY (id),
    CONSTRAINT "catalog_status_check" CHECK (status::text = ANY (ARRAY['DRAFT'::character varying, 'ACTIVE'::character varying, 'DISABLED'::character varying, 'RETIRED'::character varying]::text[])),
    CONSTRAINT "catalog_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE application.catalog IS '平台维护的全局产品应用目录；登记应用不自动向任何企业开通';
COMMENT ON COLUMN application.catalog."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.catalog."code" IS '平台唯一稳定应用代码。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。';
COMMENT ON COLUMN application.catalog."name" IS '应用名称。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。';
COMMENT ON COLUMN application.catalog."description" IS '用户可读的应用说明。 设计场景：向管理员和使用者解释对象用途；展示说明不参与身份认证或权限判定。';
COMMENT ON COLUMN application.catalog."icon_ref" IS '图标资源引用，不含临时凭据。 设计场景：门户显示应用图标时读取受控资源，图标地址不夹带长期存储访问凭据。';
COMMENT ON COLUMN application.catalog."category" IS '受控应用分类。 设计场景：按受控类别组织应用或通知展示，筛选分类不代表业务授权范围。';
COMMENT ON COLUMN application.catalog."owner_account_id" IS '应用接入负责人平台账号。 设计场景：应用接入和配置异常时能找到全局负责人，负责人权限仍需独立授权。';
COMMENT ON COLUMN application.catalog."default_enablement" IS '默认手动开通；只有明确配置时才为新企业开通，不自动分配成员。 设计场景：新企业建立时仅按明确规则开通应用，避免登记一个新应用就向所有客户自动开放。';
COMMENT ON COLUMN application.catalog."default_environment" IS '明确启用默认规则时使用的环境。 设计场景：默认开通规则启用时选择对应环境，防止客户误进入测试或预发布应用。';
COMMENT ON COLUMN application.catalog."status" IS '平台目录状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN application.catalog."version" IS '目录并发版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN application.catalog."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.catalog."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_catalog_owner ON application.catalog USING btree (owner_account_id);
CREATE INDEX ix_application_catalog_status_category ON application.catalog USING btree (status, category, id);

-- application.tenant_application：企业开通的应用实例；平台目录、企业开通、成员分配分别校验
CREATE TABLE application.tenant_application (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 平台应用。 设计场景：引用平台级应用定义，把应用产品身份与某企业开通实例、协议客户端分开。
    "application_id" bigint NOT NULL,
    -- 环境代码，与协议配置环境一致。 设计场景：同一应用在测试和生产环境中可使用不同配置与客户端，避免跨环境接受凭据或跳转。
    "environment" character varying(32) NOT NULL,
    -- 企业自定义展示名。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。
    "display_name" character varying(200),
    -- 经管理员验证的访问地址，不能由登录请求任意覆盖。 设计场景：门户启动应用时采用已验证地址，不能让请求参数把用户引向任意站点。
    "launch_url" text NOT NULL,
    -- 开通、有效、暂停或关闭。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    -- 开通操作成员。 设计场景：记录谁以企业身份开通应用，发生误开通时可以追溯管理责任。
    "opened_by_member_id" bigint NOT NULL,
    -- 完成开通时间。 设计场景：标记企业应用实际开通时间，区分待配置和已开放使用阶段。
    "opened_at" timestamp with time zone,
    -- 关闭时间。 设计场景：企业关闭或账号终止后保留时间依据，供历史追溯与保留清理；不等于立即物理删除相关数据。
    "closed_at" timestamp with time zone,
    -- 应用实例并发版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "tenant_application_application_id_fkey" FOREIGN KEY (application_id) REFERENCES application.catalog(id),
    CONSTRAINT "tenant_application_check" CHECK (updated_at >= created_at),
    CONSTRAINT "tenant_application_check1" CHECK (status::text = 'PENDING'::text AND opened_at IS NULL AND closed_at IS NULL OR (status::text = ANY (ARRAY['ACTIVE'::character varying, 'SUSPENDED'::character varying]::text[])) AND opened_at IS NOT NULL AND closed_at IS NULL OR status::text = 'CLOSED'::text AND closed_at IS NOT NULL),
    CONSTRAINT "tenant_application_check2" CHECK (closed_at IS NULL OR closed_at >= created_at),
    CONSTRAINT "tenant_application_environment_check" CHECK (environment::text ~ '^[a-z][a-z0-9_-]{0,31}$'::text),
    CONSTRAINT "tenant_application_id_check" CHECK (id > 0),
    CONSTRAINT "tenant_application_launch_url_check" CHECK (launch_url ~ '^https://[^[:space:]]+$'::text),
    CONSTRAINT "tenant_application_pkey" PRIMARY KEY (id),
    CONSTRAINT "tenant_application_status_check" CHECK (status::text = ANY (ARRAY['PENDING'::character varying, 'ACTIVE'::character varying, 'SUSPENDED'::character varying, 'CLOSED'::character varying]::text[])),
    CONSTRAINT "tenant_application_tenant_id_application_id_environment_key" UNIQUE (tenant_id, application_id, environment),
    CONSTRAINT "tenant_application_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "tenant_application_tenant_id_id_application_id_key" UNIQUE (tenant_id, id, application_id),
    CONSTRAINT "tenant_application_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "tenant_application_tenant_id_opened_by_member_id_fkey" FOREIGN KEY (tenant_id, opened_by_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "tenant_application_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE application.tenant_application IS '企业开通的应用实例；平台目录、企业开通、成员分配分别校验';
COMMENT ON COLUMN application.tenant_application."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.tenant_application."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.tenant_application."application_id" IS '平台应用。 设计场景：引用平台级应用定义，把应用产品身份与某企业开通实例、协议客户端分开。';
COMMENT ON COLUMN application.tenant_application."environment" IS '环境代码，与协议配置环境一致。 设计场景：同一应用在测试和生产环境中可使用不同配置与客户端，避免跨环境接受凭据或跳转。';
COMMENT ON COLUMN application.tenant_application."display_name" IS '企业自定义展示名。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。';
COMMENT ON COLUMN application.tenant_application."launch_url" IS '经管理员验证的访问地址，不能由登录请求任意覆盖。 设计场景：门户启动应用时采用已验证地址，不能让请求参数把用户引向任意站点。';
COMMENT ON COLUMN application.tenant_application."status" IS '开通、有效、暂停或关闭。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN application.tenant_application."opened_by_member_id" IS '开通操作成员。 设计场景：记录谁以企业身份开通应用，发生误开通时可以追溯管理责任。';
COMMENT ON COLUMN application.tenant_application."opened_at" IS '完成开通时间。 设计场景：标记企业应用实际开通时间，区分待配置和已开放使用阶段。';
COMMENT ON COLUMN application.tenant_application."closed_at" IS '关闭时间。 设计场景：企业关闭或账号终止后保留时间依据，供历史追溯与保留清理；不等于立即物理删除相关数据。';
COMMENT ON COLUMN application.tenant_application."version" IS '应用实例并发版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN application.tenant_application."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.tenant_application."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_tenant_application_application ON application.tenant_application USING btree (application_id);
CREATE INDEX ix_application_tenant_application_opener ON application.tenant_application USING btree (tenant_id, opened_by_member_id);
CREATE INDEX ix_application_tenant_application_status ON application.tenant_application USING btree (tenant_id, status, id);

-- application.connection：企业应用下游协议连接；登录和账号供应分别登记，配置不包含明文秘密
CREATE TABLE application.connection (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 同应用内连接代码。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。
    "code" character varying(64) NOT NULL,
    -- 登录、账号群组供应或程序云访问。 设计场景：对同一系统区分登录、供应、云访问或其他业务用途，调用时拒绝把一个用途的配置或凭据借给另一个用途。
    "purpose" character varying(16) NOT NULL,
    -- 具体协议；与上下游方向分开解释。 设计场景：选择对应协议适配和校验流程，配置了登录协议不等于完成账号供应或业务授权。
    "protocol" character varying(16) NOT NULL,
    -- 通用适配或阿里云模板。 设计场景：在通用协议能力上选择特定系统的字段与流程适配，避免把阿里云专用规则硬编码到所有应用。
    "connector" character varying(16) DEFAULT 'GENERIC'::character varying NOT NULL,
    -- 签发者或元数据标识，按协议精确验证。 设计场景：验证外部签发者与登记配置一致，防止其他认证中心签发的合法凭证被误用于本连接。
    "issuer" text,
    -- 预期接收者或受众。 设计场景：将凭证限定给预期接收方使用，防止为应用 A 签发的结果被应用 B 接受。
    "audience" text,
    -- 已登记服务、ACS、供应或换取凭据端点；不能使用请求自报地址。 设计场景：实际调用或发送协议结果时使用登记端点，需控制协议、地址和来源，不能信任请求任意指定的目标。
    "endpoint_url" text NOT NULL,
    -- 经过验证的元数据地址，更新时需复核签名和来源。 设计场景：更新协议元数据时读取已验证来源，并复核变化，避免远端地址替换造成信任配置被接管。
    "metadata_url" text,
    -- 协议参数的结构版本。 设计场景：升级协议选项格式时按明确版本解析，旧参数不会在新代码中被误解成另一种配置。
    "config_schema_version" integer DEFAULT 1 NOT NULL,
    -- 协议专用受控选项；关系、密钥和人员不存入此对象。 设计场景：保存协议专属参数以复用统一连接模型；按协议白名单校验，不能把任意代码、秘密或主体关系装入 JSON。
    "protocol_options" jsonb DEFAULT '{}'::jsonb NOT NULL,
    -- 实际验证的退出或停用能力。 设计场景：区分能主动注销、只能停用或只能等待过期的下游系统，向用户说明退出能影响到哪里。
    "logout_capability" character varying(24) DEFAULT 'UNKNOWN'::character varying NOT NULL,
    -- 不能主动撤销时下游凭证最长剩余寿命，未经验证为空。 设计场景：下游无法即时注销时记录经过验证的剩余风险窗口，便于决定是否满足应用安全要求；未知值不能当零。
    "max_downstream_seconds" integer,
    -- 连接状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'DRAFT'::character varying NOT NULL,
    -- 最近真实联调成功时间，不以模拟测试代替。 设计场景：展示最近一次真实联调或核验记录，避免把仅保存配置显示为渠道已可用。
    "last_verified_at" timestamp with time zone,
    -- 脱敏验证证据引用。 设计场景：保留联调环境和结果的脱敏证据，排查渠道失效时能回到具体测试依据。
    "verification_evidence_ref" text,
    -- 协议配置版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "connection_check" CHECK (updated_at >= created_at),
    CONSTRAINT "connection_check1" CHECK (purpose::text = 'LOGIN'::text AND (protocol::text = ANY (ARRAY['OIDC'::character varying, 'SAML'::character varying, 'CAS'::character varying, 'CUSTOM'::character varying]::text[])) OR purpose::text = 'PROVISIONING'::text AND (protocol::text = ANY (ARRAY['SCIM'::character varying, 'CUSTOM'::character varying]::text[])) OR purpose::text = 'CLOUD_API'::text AND connector::text = 'ALIYUN'::text AND protocol::text = 'OIDC'::text),
    CONSTRAINT "connection_check2" CHECK ((last_verified_at IS NULL) = (verification_evidence_ref IS NULL)),
    CONSTRAINT "connection_code_check" CHECK (btrim(code::text) <> ''::text),
    CONSTRAINT "connection_config_schema_version_check" CHECK (config_schema_version > 0),
    CONSTRAINT "connection_connector_check" CHECK (connector::text = ANY (ARRAY['GENERIC'::character varying, 'ALIYUN'::character varying]::text[])),
    CONSTRAINT "connection_endpoint_url_check" CHECK (endpoint_url ~ '^https://[^[:space:]]+$'::text),
    CONSTRAINT "connection_id_check" CHECK (id > 0),
    CONSTRAINT "connection_logout_capability_check" CHECK (logout_capability::text = ANY (ARRAY['UNKNOWN'::character varying, 'NONE'::character varying, 'FRONT_CHANNEL'::character varying, 'BACK_CHANNEL'::character varying, 'API'::character varying]::text[])),
    CONSTRAINT "connection_max_downstream_seconds_check" CHECK (max_downstream_seconds > 0),
    CONSTRAINT "connection_metadata_url_check" CHECK (metadata_url IS NULL OR metadata_url ~ '^https://[^[:space:]]+$'::text),
    CONSTRAINT "connection_pkey" PRIMARY KEY (id),
    CONSTRAINT "connection_protocol_check" CHECK (protocol::text = ANY (ARRAY['OIDC'::character varying, 'SAML'::character varying, 'CAS'::character varying, 'SCIM'::character varying, 'CUSTOM'::character varying]::text[])),
    CONSTRAINT "connection_protocol_options_check" CHECK (jsonb_typeof(protocol_options) = 'object'::text),
    CONSTRAINT "connection_purpose_check" CHECK (purpose::text = ANY (ARRAY['LOGIN'::character varying, 'PROVISIONING'::character varying, 'CLOUD_API'::character varying]::text[])),
    CONSTRAINT "connection_status_check" CHECK (status::text = ANY (ARRAY['DRAFT'::character varying, 'ACTIVE'::character varying, 'DISABLED'::character varying]::text[])),
    CONSTRAINT "connection_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "connection_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "connection_tenant_id_id_protocol_key" UNIQUE (tenant_id, id, protocol),
    CONSTRAINT "connection_tenant_id_id_protocol_purpose_connector_key" UNIQUE (tenant_id, id, protocol, purpose, connector),
    CONSTRAINT "connection_tenant_id_id_purpose_key" UNIQUE (tenant_id, id, purpose),
    CONSTRAINT "connection_tenant_id_tenant_application_id_code_key" UNIQUE (tenant_id, tenant_application_id, code),
    CONSTRAINT "connection_tenant_id_tenant_application_id_fkey" FOREIGN KEY (tenant_id, tenant_application_id) REFERENCES application.tenant_application(tenant_id, id),
    CONSTRAINT "connection_tenant_id_tenant_application_id_id_key" UNIQUE (tenant_id, tenant_application_id, id),
    CONSTRAINT "connection_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE application.connection IS '企业应用下游协议连接；登录和账号供应分别登记，配置不包含明文秘密';
COMMENT ON COLUMN application.connection."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.connection."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.connection."tenant_application_id" IS '企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN application.connection."code" IS '同应用内连接代码。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。';
COMMENT ON COLUMN application.connection."purpose" IS '登录、账号群组供应或程序云访问。 设计场景：对同一系统区分登录、供应、云访问或其他业务用途，调用时拒绝把一个用途的配置或凭据借给另一个用途。';
COMMENT ON COLUMN application.connection."protocol" IS '具体协议；与上下游方向分开解释。 设计场景：选择对应协议适配和校验流程，配置了登录协议不等于完成账号供应或业务授权。';
COMMENT ON COLUMN application.connection."connector" IS '通用适配或阿里云模板。 设计场景：在通用协议能力上选择特定系统的字段与流程适配，避免把阿里云专用规则硬编码到所有应用。';
COMMENT ON COLUMN application.connection."issuer" IS '签发者或元数据标识，按协议精确验证。 设计场景：验证外部签发者与登记配置一致，防止其他认证中心签发的合法凭证被误用于本连接。';
COMMENT ON COLUMN application.connection."audience" IS '预期接收者或受众。 设计场景：将凭证限定给预期接收方使用，防止为应用 A 签发的结果被应用 B 接受。';
COMMENT ON COLUMN application.connection."endpoint_url" IS '已登记服务、ACS、供应或换取凭据端点；不能使用请求自报地址。 设计场景：实际调用或发送协议结果时使用登记端点，需控制协议、地址和来源，不能信任请求任意指定的目标。';
COMMENT ON COLUMN application.connection."metadata_url" IS '经过验证的元数据地址，更新时需复核签名和来源。 设计场景：更新协议元数据时读取已验证来源，并复核变化，避免远端地址替换造成信任配置被接管。';
COMMENT ON COLUMN application.connection."config_schema_version" IS '协议参数的结构版本。 设计场景：升级协议选项格式时按明确版本解析，旧参数不会在新代码中被误解成另一种配置。';
COMMENT ON COLUMN application.connection."protocol_options" IS '协议专用受控选项；关系、密钥和人员不存入此对象。 设计场景：保存协议专属参数以复用统一连接模型；按协议白名单校验，不能把任意代码、秘密或主体关系装入 JSON。';
COMMENT ON COLUMN application.connection."logout_capability" IS '实际验证的退出或停用能力。 设计场景：区分能主动注销、只能停用或只能等待过期的下游系统，向用户说明退出能影响到哪里。';
COMMENT ON COLUMN application.connection."max_downstream_seconds" IS '不能主动撤销时下游凭证最长剩余寿命，未经验证为空。 设计场景：下游无法即时注销时记录经过验证的剩余风险窗口，便于决定是否满足应用安全要求；未知值不能当零。';
COMMENT ON COLUMN application.connection."status" IS '连接状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN application.connection."last_verified_at" IS '最近真实联调成功时间，不以模拟测试代替。 设计场景：展示最近一次真实联调或核验记录，避免把仅保存配置显示为渠道已可用。';
COMMENT ON COLUMN application.connection."verification_evidence_ref" IS '脱敏验证证据引用。 设计场景：保留联调环境和结果的脱敏证据，排查渠道失效时能回到具体测试依据。';
COMMENT ON COLUMN application.connection."version" IS '协议配置版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN application.connection."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.connection."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_connection_status ON application.connection USING btree (tenant_id, status, purpose);

-- application.user_identity：成员在某企业应用中的可选身份；一个成员可有多个，身份存在不绕过应用分配和成员状态
CREATE TABLE application.user_identity (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 身份所属成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 应用内稳定身份键，不按同名账号猜测。 设计场景：一个成员可在下游应用拥有不同业务身份，使用明确映射选择目标账号，不能按名字自动合并。
    "identity_key" character varying(256) NOT NULL,
    -- 供用户选择身份时展示的名称。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。
    "display_name" character varying(200) NOT NULL,
    -- 身份状态；撤销后不允许签发。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 身份映射版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "user_identity_check" CHECK (updated_at >= created_at),
    CONSTRAINT "user_identity_display_name_check" CHECK (btrim(display_name::text) <> ''::text),
    CONSTRAINT "user_identity_id_check" CHECK (id > 0),
    CONSTRAINT "user_identity_identity_key_check" CHECK (btrim(identity_key::text) <> ''::text),
    CONSTRAINT "user_identity_pkey" PRIMARY KEY (id),
    CONSTRAINT "user_identity_status_check" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying, 'REMOVED'::character varying]::text[])),
    CONSTRAINT "user_identity_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "user_identity_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "user_identity_tenant_id_member_id_fkey" FOREIGN KEY (tenant_id, member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "user_identity_tenant_id_tenant_application_id_fkey" FOREIGN KEY (tenant_id, tenant_application_id) REFERENCES application.tenant_application(tenant_id, id),
    CONSTRAINT "user_identity_tenant_id_tenant_application_id_id_key" UNIQUE (tenant_id, tenant_application_id, id),
    CONSTRAINT "user_identity_tenant_id_tenant_application_id_id_member_id_key" UNIQUE (tenant_id, tenant_application_id, id, member_id),
    CONSTRAINT "user_identity_tenant_id_tenant_application_id_identity_key_key" UNIQUE (tenant_id, tenant_application_id, identity_key),
    CONSTRAINT "user_identity_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE application.user_identity IS '成员在某企业应用中的可选身份；一个成员可有多个，身份存在不绕过应用分配和成员状态';
COMMENT ON COLUMN application.user_identity."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.user_identity."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.user_identity."tenant_application_id" IS '企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN application.user_identity."member_id" IS '身份所属成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN application.user_identity."identity_key" IS '应用内稳定身份键，不按同名账号猜测。 设计场景：一个成员可在下游应用拥有不同业务身份，使用明确映射选择目标账号，不能按名字自动合并。';
COMMENT ON COLUMN application.user_identity."display_name" IS '供用户选择身份时展示的名称。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。';
COMMENT ON COLUMN application.user_identity."status" IS '身份状态；撤销后不允许签发。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN application.user_identity."version" IS '身份映射版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN application.user_identity."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.user_identity."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_user_identity_member ON application.user_identity USING btree (tenant_id, member_id, tenant_application_id);

-- application.access_session：企业应用的访问会话；承接OIDC/SAML/CAS等上下文和并发限制，不修改全局账号当前租户
CREATE TABLE application.access_session (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 访问的企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 对应下游协议连接；本地应用可为空。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint,
    -- 访问成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 成员对应账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 来源中央认证会话。 设计场景：把各应用登录追溯到中央认证会话，全部退出或中央撤销后能定位依赖它的应用会话。
    "central_session_id" bigint NOT NULL,
    -- OIDC授权关联；其他协议为空。 设计场景：OIDC 场景关联协议客户端会话，便于协调授权撤销；其他协议不能伪造一条 OIDC 会话填充该字段。
    "protocol_client_session_id" bigint,
    -- 本次选择的应用身份。 设计场景：明确本次登录或供应采用哪个应用内身份，避免一人多身份时切错目标账号。
    "user_identity_id" bigint,
    -- 应用认证协议。 设计场景：选择对应协议适配和校验流程，配置了登录协议不等于完成账号供应或业务授权。
    "protocol" character varying(16) NOT NULL,
    -- 下游会话不透明引用，不包含bearer凭据。 设计场景：对端支持会话注销时用于定位需要结束的会话，保存引用而非可直接调用的 bearer 凭据。
    "downstream_session_ref" character varying(512),
    -- 准入时安全策略版本；使用时仍检查当前策略。 设计场景：记录准入时采用的策略便于审计，策略收紧后仍须按当前策略检查，不能让历史版本永久放行。
    "policy_version" bigint NOT NULL,
    -- 准入时账号撤销版本。 设计场景：记录进入应用时的账号撤销版本，后续访问或续期与当前值比较，防止只检查应用本地会话存在就放行。
    "auth_epoch" bigint NOT NULL,
    -- 应用访问开始时间。 设计场景：记录一次执行真正开始的时刻，用于识别排队与执行耗时、定位长期运行任务。
    "started_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近活动时间。 设计场景：区分持续使用与长期不活跃记录，为会话空闲判断或设备管理提供依据；不能刷新绝对有效期。
    "last_seen_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 绝对最晚到期时间。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone NOT NULL,
    -- 本地撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 下游退出结果；本地撤销不等待外部完成。 设计场景：区分本地已经撤销与下游退出是否完成，网络失败时保留重试或人工处理状态，不假报全部退出。
    "downstream_logout_status" character varying(16) DEFAULT 'NOT_REQUESTED'::character varying NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "access_session_account_id_central_session_id_fkey" FOREIGN KEY (account_id, central_session_id) REFERENCES identity.auth_session(account_id, id),
    CONSTRAINT "access_session_account_id_central_session_id_protocol_clie_fkey" FOREIGN KEY (account_id, central_session_id, protocol_client_session_id) REFERENCES identity.client_session(account_id, central_session_id, id),
    CONSTRAINT "access_session_auth_epoch_check" CHECK (auth_epoch >= 0),
    CONSTRAINT "access_session_check" CHECK (updated_at >= created_at),
    CONSTRAINT "access_session_check1" CHECK (expires_at > started_at),
    CONSTRAINT "access_session_check2" CHECK (last_seen_at >= started_at),
    CONSTRAINT "access_session_check3" CHECK (revoked_at IS NULL OR revoked_at >= started_at),
    CONSTRAINT "access_session_check4" CHECK (protocol::text = 'OIDC'::text OR protocol_client_session_id IS NULL),
    CONSTRAINT "access_session_downstream_logout_status_check" CHECK (downstream_logout_status::text = ANY (ARRAY['NOT_REQUESTED'::character varying, 'PENDING'::character varying, 'SUCCEEDED'::character varying, 'FAILED'::character varying, 'UNSUPPORTED'::character varying]::text[])),
    CONSTRAINT "access_session_id_check" CHECK (id > 0),
    CONSTRAINT "access_session_pkey" PRIMARY KEY (id),
    CONSTRAINT "access_session_policy_version_check" CHECK (policy_version >= 0),
    CONSTRAINT "access_session_protocol_check" CHECK (protocol::text = ANY (ARRAY['OIDC'::character varying, 'SAML'::character varying, 'CAS'::character varying, 'CUSTOM'::character varying]::text[])),
    CONSTRAINT "access_session_protocol_client_session_id_key" UNIQUE (protocol_client_session_id),
    CONSTRAINT "access_session_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "access_session_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "access_session_tenant_id_member_id_account_id_fkey" FOREIGN KEY (tenant_id, member_id, account_id) REFERENCES directory.membership(tenant_id, id, account_id),
    CONSTRAINT "access_session_tenant_id_tenant_application_id_connection__fkey" FOREIGN KEY (tenant_id, tenant_application_id, connection_id) REFERENCES application.connection(tenant_id, tenant_application_id, id),
    CONSTRAINT "access_session_tenant_id_tenant_application_id_fkey" FOREIGN KEY (tenant_id, tenant_application_id) REFERENCES application.tenant_application(tenant_id, id),
    CONSTRAINT "access_session_tenant_id_tenant_application_id_user_identi_fkey" FOREIGN KEY (tenant_id, tenant_application_id, user_identity_id, member_id) REFERENCES application.user_identity(tenant_id, tenant_application_id, id, member_id)
);
COMMENT ON TABLE application.access_session IS '企业应用的访问会话；承接OIDC/SAML/CAS等上下文和并发限制，不修改全局账号当前租户';
COMMENT ON COLUMN application.access_session."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.access_session."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.access_session."tenant_application_id" IS '访问的企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN application.access_session."connection_id" IS '对应下游协议连接；本地应用可为空。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN application.access_session."member_id" IS '访问成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN application.access_session."account_id" IS '成员对应账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN application.access_session."central_session_id" IS '来源中央认证会话。 设计场景：把各应用登录追溯到中央认证会话，全部退出或中央撤销后能定位依赖它的应用会话。';
COMMENT ON COLUMN application.access_session."protocol_client_session_id" IS 'OIDC授权关联；其他协议为空。 设计场景：OIDC 场景关联协议客户端会话，便于协调授权撤销；其他协议不能伪造一条 OIDC 会话填充该字段。';
COMMENT ON COLUMN application.access_session."user_identity_id" IS '本次选择的应用身份。 设计场景：明确本次登录或供应采用哪个应用内身份，避免一人多身份时切错目标账号。';
COMMENT ON COLUMN application.access_session."protocol" IS '应用认证协议。 设计场景：选择对应协议适配和校验流程，配置了登录协议不等于完成账号供应或业务授权。';
COMMENT ON COLUMN application.access_session."downstream_session_ref" IS '下游会话不透明引用，不包含bearer凭据。 设计场景：对端支持会话注销时用于定位需要结束的会话，保存引用而非可直接调用的 bearer 凭据。';
COMMENT ON COLUMN application.access_session."policy_version" IS '准入时安全策略版本；使用时仍检查当前策略。 设计场景：记录准入时采用的策略便于审计，策略收紧后仍须按当前策略检查，不能让历史版本永久放行。';
COMMENT ON COLUMN application.access_session."auth_epoch" IS '准入时账号撤销版本。 设计场景：记录进入应用时的账号撤销版本，后续访问或续期与当前值比较，防止只检查应用本地会话存在就放行。';
COMMENT ON COLUMN application.access_session."started_at" IS '应用访问开始时间。 设计场景：记录一次执行真正开始的时刻，用于识别排队与执行耗时、定位长期运行任务。';
COMMENT ON COLUMN application.access_session."last_seen_at" IS '最近活动时间。 设计场景：区分持续使用与长期不活跃记录，为会话空闲判断或设备管理提供依据；不能刷新绝对有效期。';
COMMENT ON COLUMN application.access_session."expires_at" IS '绝对最晚到期时间。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN application.access_session."revoked_at" IS '本地撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN application.access_session."downstream_logout_status" IS '下游退出结果；本地撤销不等待外部完成。 设计场景：区分本地已经撤销与下游退出是否完成，网络失败时保留重试或人工处理状态，不假报全部退出。';
COMMENT ON COLUMN application.access_session."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.access_session."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_access_session_central ON application.access_session USING btree (account_id, central_session_id);
CREATE INDEX ix_application_access_session_concurrency ON application.access_session USING btree (tenant_id, tenant_application_id, member_id, expires_at) WHERE (revoked_at IS NULL);
CREATE INDEX ix_application_access_session_connection ON application.access_session USING btree (tenant_id, tenant_application_id, connection_id);
CREATE INDEX ix_application_access_session_identity ON application.access_session USING btree (tenant_id, tenant_application_id, user_identity_id, member_id);
CREATE INDEX ix_application_access_session_member ON application.access_session USING btree (tenant_id, member_id, created_at DESC);

-- machine.principal：企业机器主体；非员工账号，独立记录负责人、用途和状态
CREATE TABLE machine.principal (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 企业内稳定机器代码。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。
    "code" character varying(64) NOT NULL,
    -- 机器主体名称。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。
    "name" character varying(200) NOT NULL,
    -- 业务用途。 设计场景：记录为何建立这台机器身份及承担的任务，便于定期审查和退役；用途描述不能代替明确授权。
    "purpose" character varying(1000) NOT NULL,
    -- 负责该机器的同企业成员；负责人停用须交接或停用机器。 设计场景：指定负责维护资源、机器或复核任务的企业成员，支持责任交接；负责人关系本身不赋予全部操作权限。
    "owner_member_id" bigint NOT NULL,
    -- 可选 OAuth 客户端关联，不因注册客户端而取得资源授权。 设计场景：关联框架内部客户端记录，与外部 client_id 区分，便于一个业务应用配置多个终端和环境。
    "registered_client_id" character varying(100),
    -- 机器主体状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 并发版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "principal_check" CHECK (updated_at >= created_at),
    CONSTRAINT "principal_code_check" CHECK (code::text ~ '^[a-z][a-z0-9_-]{0,63}$'::text),
    CONSTRAINT "principal_id_check" CHECK (id > 0),
    CONSTRAINT "principal_name_check" CHECK (btrim(name::text) <> ''::text),
    CONSTRAINT "principal_pkey" PRIMARY KEY (id),
    CONSTRAINT "principal_purpose_check" CHECK (btrim(purpose::text) <> ''::text),
    CONSTRAINT "principal_registered_client_id_fkey" FOREIGN KEY (registered_client_id) REFERENCES protocol.oauth2_registered_client(id),
    CONSTRAINT "principal_registered_client_id_key" UNIQUE (registered_client_id),
    CONSTRAINT "principal_status_check" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying, 'REMOVED'::character varying]::text[])),
    CONSTRAINT "principal_tenant_id_code_key" UNIQUE (tenant_id, code),
    CONSTRAINT "principal_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "principal_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "principal_tenant_id_owner_member_id_fkey" FOREIGN KEY (tenant_id, owner_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "principal_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE machine.principal IS '企业机器主体；非员工账号，独立记录负责人、用途和状态';
COMMENT ON COLUMN machine.principal."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN machine.principal."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN machine.principal."code" IS '企业内稳定机器代码。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。';
COMMENT ON COLUMN machine.principal."name" IS '机器主体名称。 设计场景：用于列表、搜索和管理界面展示；允许按业务规则改名，关联关系继续使用稳定 ID 或编码。';
COMMENT ON COLUMN machine.principal."purpose" IS '业务用途。 设计场景：记录为何建立这台机器身份及承担的任务，便于定期审查和退役；用途描述不能代替明确授权。';
COMMENT ON COLUMN machine.principal."owner_member_id" IS '负责该机器的同企业成员；负责人停用须交接或停用机器。 设计场景：指定负责维护资源、机器或复核任务的企业成员，支持责任交接；负责人关系本身不赋予全部操作权限。';
COMMENT ON COLUMN machine.principal."registered_client_id" IS '可选 OAuth 客户端关联，不因注册客户端而取得资源授权。 设计场景：关联框架内部客户端记录，与外部 client_id 区分，便于一个业务应用配置多个终端和环境。';
COMMENT ON COLUMN machine.principal."status" IS '机器主体状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN machine.principal."version" IS '并发版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN machine.principal."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN machine.principal."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_machine_principal_owner ON machine.principal USING btree (tenant_id, owner_member_id);
CREATE INDEX ix_machine_principal_status ON machine.principal USING btree (tenant_id, status, id);

-- application.aliyun_mapping：阿里云账号/角色准入映射；控制台SAML和程序OIDC分别配置，每条映射限定一个允许主体和角色
CREATE TABLE application.aliyun_mapping (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 阿里云企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 阿里云协议连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 固定阿里云连接模板，不能挂到任意通用连接。 设计场景：在通用协议能力上选择特定系统的字段与流程适配，避免把阿里云专用规则硬编码到所有应用。
    "connector" character varying(16) DEFAULT 'ALIYUN'::character varying NOT NULL,
    -- 控制台登录或程序云访问用途。 设计场景：把映射或任务限定到符合用途的连接，例如 SAML 控制台登录不能误用账号供应连接。
    "connection_purpose" character varying(16) DEFAULT 'LOGIN'::character varying NOT NULL,
    -- 与连接一致的协议。 设计场景：选择对应协议适配和校验流程，配置了登录协议不等于完成账号供应或业务授权。
    "protocol" character varying(16) NOT NULL,
    -- 控制台用户、控制台角色或程序角色模式。 设计场景：分别表达 RAM 用户登录、角色扮演和程序访问，校验各自必需字段，防止混用不同身份映射。
    "mode" character varying(16) NOT NULL,
    -- 可进入控制台的成员应用身份。 设计场景：明确本次登录或供应采用哪个应用内身份，避免一人多身份时切错目标账号。
    "user_identity_id" bigint,
    -- 可换取云临时凭证的机器主体。 设计场景：程序访问云资源时绑定获准的机器主体，避免用任何持有平台令牌的程序换取云凭据。
    "machine_principal_id" bigint,
    -- 目标阿里云账号ID。 设计场景：同一平台对接多个阿里云账号时，明确本次映射目标，防止跨云账号签发登录结果。
    "cloud_account_id" character varying(32) NOT NULL,
    -- 用户单点登录对应的明确RAM用户名。 设计场景：用户 SSO 时精确指定对应 RAM 用户；保存名字不代表云侧已经创建该用户。
    "ram_user_name" character varying(256),
    -- 允许扮演的RAM角色ARN。 设计场景：角色 SSO 或程序访问时限制可扮演的具体 RAM 角色，不能由调用方任意选择更高权限角色。
    "ram_role_arn" character varying(512),
    -- 云侧已配置的身份提供方ARN。 设计场景：把断言或令牌对应到云侧预先信任的身份提供方，不能只凭本地配置认为云端已建立信任。
    "provider_arn" character varying(512),
    -- 程序OIDC的准确受众。 设计场景：程序 OIDC 凭证必须命中云侧信任规则中的受众，防止将其他用途的令牌用于兑换云权限。
    "oidc_audience" character varying(512),
    -- 程序OIDC的准确主体，不接受请求任意指定。 设计场景：限定获准程序的准确主体，云侧和平台两侧都按映射验证，拒绝请求方自行替换主体。
    "oidc_subject" character varying(512),
    -- 经校验的角色会话名模板。 设计场景：云审计中使用可追踪且符合约束的会话名，模板输入由服务端限定，避免随意字符串混淆责任主体。
    "session_name_template" character varying(200),
    -- 实际云能力允许的最大会话或临时凭据寿命。 设计场景：控制云会话或临时凭据的最长有效期，与云侧允许上限共同约束，减少撤权后仍可使用的时间。
    "max_session_seconds" integer NOT NULL,
    -- 映射是否允许签发。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "aliyun_mapping_check" CHECK (updated_at >= created_at),
    CONSTRAINT "aliyun_mapping_check1" CHECK (mode::text = 'SAML_USER'::text AND connection_purpose::text = 'LOGIN'::text AND protocol::text = 'SAML'::text AND user_identity_id IS NOT NULL AND machine_principal_id IS NULL AND ram_user_name IS NOT NULL AND num_nonnulls(ram_role_arn, oidc_audience, oidc_subject) = 0 OR mode::text = 'SAML_ROLE'::text AND connection_purpose::text = 'LOGIN'::text AND protocol::text = 'SAML'::text AND user_identity_id IS NOT NULL AND machine_principal_id IS NULL AND ram_user_name IS NULL AND ram_role_arn IS NOT NULL AND provider_arn IS NOT NULL AND oidc_audience IS NULL AND oidc_subject IS NULL OR mode::text = 'OIDC_ROLE'::text AND connection_purpose::text = 'CLOUD_API'::text AND protocol::text = 'OIDC'::text AND user_identity_id IS NULL AND machine_principal_id IS NOT NULL AND ram_user_name IS NULL AND ram_role_arn IS NOT NULL AND provider_arn IS NOT NULL AND oidc_audience IS NOT NULL AND oidc_subject IS NOT NULL),
    CONSTRAINT "aliyun_mapping_cloud_account_id_check" CHECK (cloud_account_id::text ~ '^[0-9]{1,32}$'::text),
    CONSTRAINT "aliyun_mapping_connection_purpose_check" CHECK (connection_purpose::text = ANY (ARRAY['LOGIN'::character varying, 'CLOUD_API'::character varying]::text[])),
    CONSTRAINT "aliyun_mapping_connector_check" CHECK (connector::text = 'ALIYUN'::text),
    CONSTRAINT "aliyun_mapping_id_check" CHECK (id > 0),
    CONSTRAINT "aliyun_mapping_max_session_seconds_check" CHECK (max_session_seconds > 0),
    CONSTRAINT "aliyun_mapping_mode_check" CHECK (mode::text = ANY (ARRAY['SAML_USER'::character varying, 'SAML_ROLE'::character varying, 'OIDC_ROLE'::character varying]::text[])),
    CONSTRAINT "aliyun_mapping_pkey" PRIMARY KEY (id),
    CONSTRAINT "aliyun_mapping_protocol_check" CHECK (protocol::text = ANY (ARRAY['SAML'::character varying, 'OIDC'::character varying]::text[])),
    CONSTRAINT "aliyun_mapping_status_check" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying]::text[])),
    CONSTRAINT "aliyun_mapping_tenant_id_connection_id_mode_user_identity_i_key" UNIQUE NULLS NOT DISTINCT (tenant_id, connection_id, mode, user_identity_id, machine_principal_id, cloud_account_id, ram_user_name, ram_role_arn),
    CONSTRAINT "aliyun_mapping_tenant_id_connection_id_protocol_connection_fkey" FOREIGN KEY (tenant_id, connection_id, protocol, connection_purpose, connector) REFERENCES application.connection(tenant_id, id, protocol, purpose, connector),
    CONSTRAINT "aliyun_mapping_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "aliyun_mapping_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "aliyun_mapping_tenant_id_machine_principal_id_fkey" FOREIGN KEY (tenant_id, machine_principal_id) REFERENCES machine.principal(tenant_id, id),
    CONSTRAINT "aliyun_mapping_tenant_id_tenant_application_id_connection__fkey" FOREIGN KEY (tenant_id, tenant_application_id, connection_id) REFERENCES application.connection(tenant_id, tenant_application_id, id),
    CONSTRAINT "aliyun_mapping_tenant_id_tenant_application_id_user_identi_fkey" FOREIGN KEY (tenant_id, tenant_application_id, user_identity_id) REFERENCES application.user_identity(tenant_id, tenant_application_id, id)
);
COMMENT ON TABLE application.aliyun_mapping IS '阿里云账号/角色准入映射；控制台SAML和程序OIDC分别配置，每条映射限定一个允许主体和角色';
COMMENT ON COLUMN application.aliyun_mapping."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.aliyun_mapping."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.aliyun_mapping."tenant_application_id" IS '阿里云企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN application.aliyun_mapping."connection_id" IS '阿里云协议连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN application.aliyun_mapping."connector" IS '固定阿里云连接模板，不能挂到任意通用连接。 设计场景：在通用协议能力上选择特定系统的字段与流程适配，避免把阿里云专用规则硬编码到所有应用。';
COMMENT ON COLUMN application.aliyun_mapping."connection_purpose" IS '控制台登录或程序云访问用途。 设计场景：把映射或任务限定到符合用途的连接，例如 SAML 控制台登录不能误用账号供应连接。';
COMMENT ON COLUMN application.aliyun_mapping."protocol" IS '与连接一致的协议。 设计场景：选择对应协议适配和校验流程，配置了登录协议不等于完成账号供应或业务授权。';
COMMENT ON COLUMN application.aliyun_mapping."mode" IS '控制台用户、控制台角色或程序角色模式。 设计场景：分别表达 RAM 用户登录、角色扮演和程序访问，校验各自必需字段，防止混用不同身份映射。';
COMMENT ON COLUMN application.aliyun_mapping."user_identity_id" IS '可进入控制台的成员应用身份。 设计场景：明确本次登录或供应采用哪个应用内身份，避免一人多身份时切错目标账号。';
COMMENT ON COLUMN application.aliyun_mapping."machine_principal_id" IS '可换取云临时凭证的机器主体。 设计场景：程序访问云资源时绑定获准的机器主体，避免用任何持有平台令牌的程序换取云凭据。';
COMMENT ON COLUMN application.aliyun_mapping."cloud_account_id" IS '目标阿里云账号ID。 设计场景：同一平台对接多个阿里云账号时，明确本次映射目标，防止跨云账号签发登录结果。';
COMMENT ON COLUMN application.aliyun_mapping."ram_user_name" IS '用户单点登录对应的明确RAM用户名。 设计场景：用户 SSO 时精确指定对应 RAM 用户；保存名字不代表云侧已经创建该用户。';
COMMENT ON COLUMN application.aliyun_mapping."ram_role_arn" IS '允许扮演的RAM角色ARN。 设计场景：角色 SSO 或程序访问时限制可扮演的具体 RAM 角色，不能由调用方任意选择更高权限角色。';
COMMENT ON COLUMN application.aliyun_mapping."provider_arn" IS '云侧已配置的身份提供方ARN。 设计场景：把断言或令牌对应到云侧预先信任的身份提供方，不能只凭本地配置认为云端已建立信任。';
COMMENT ON COLUMN application.aliyun_mapping."oidc_audience" IS '程序OIDC的准确受众。 设计场景：程序 OIDC 凭证必须命中云侧信任规则中的受众，防止将其他用途的令牌用于兑换云权限。';
COMMENT ON COLUMN application.aliyun_mapping."oidc_subject" IS '程序OIDC的准确主体，不接受请求任意指定。 设计场景：限定获准程序的准确主体，云侧和平台两侧都按映射验证，拒绝请求方自行替换主体。';
COMMENT ON COLUMN application.aliyun_mapping."session_name_template" IS '经校验的角色会话名模板。 设计场景：云审计中使用可追踪且符合约束的会话名，模板输入由服务端限定，避免随意字符串混淆责任主体。';
COMMENT ON COLUMN application.aliyun_mapping."max_session_seconds" IS '实际云能力允许的最大会话或临时凭据寿命。 设计场景：控制云会话或临时凭据的最长有效期，与云侧允许上限共同约束，减少撤权后仍可使用的时间。';
COMMENT ON COLUMN application.aliyun_mapping."status" IS '映射是否允许签发。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN application.aliyun_mapping."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.aliyun_mapping."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_aliyun_mapping_identity ON application.aliyun_mapping USING btree (tenant_id, tenant_application_id, user_identity_id);
CREATE INDEX ix_application_aliyun_mapping_machine ON application.aliyun_mapping USING btree (tenant_id, machine_principal_id);
CREATE INDEX ix_application_aliyun_mapping_protocol ON application.aliyun_mapping USING btree (tenant_id, connection_id, protocol);

-- application.app_group：应用内部群组或业务身份组；不等同企业部门和平台角色
CREATE TABLE application.app_group (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 应用组稳定键。 设计场景：明确下游群组的稳定业务标识，组名变化后关系仍能定位原对象。
    "group_key" character varying(256) NOT NULL,
    -- 组名称。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。
    "display_name" character varying(200) NOT NULL,
    -- 组状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 组版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "app_group_check" CHECK (updated_at >= created_at),
    CONSTRAINT "app_group_display_name_check" CHECK (btrim(display_name::text) <> ''::text),
    CONSTRAINT "app_group_group_key_check" CHECK (btrim(group_key::text) <> ''::text),
    CONSTRAINT "app_group_id_check" CHECK (id > 0),
    CONSTRAINT "app_group_pkey" PRIMARY KEY (id),
    CONSTRAINT "app_group_status_check" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying, 'REMOVED'::character varying]::text[])),
    CONSTRAINT "app_group_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "app_group_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "app_group_tenant_id_tenant_application_id_fkey" FOREIGN KEY (tenant_id, tenant_application_id) REFERENCES application.tenant_application(tenant_id, id),
    CONSTRAINT "app_group_tenant_id_tenant_application_id_group_key_key" UNIQUE (tenant_id, tenant_application_id, group_key),
    CONSTRAINT "app_group_tenant_id_tenant_application_id_id_key" UNIQUE (tenant_id, tenant_application_id, id),
    CONSTRAINT "app_group_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE application.app_group IS '应用内部群组或业务身份组；不等同企业部门和平台角色';
COMMENT ON COLUMN application.app_group."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.app_group."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.app_group."tenant_application_id" IS '企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN application.app_group."group_key" IS '应用组稳定键。 设计场景：明确下游群组的稳定业务标识，组名变化后关系仍能定位原对象。';
COMMENT ON COLUMN application.app_group."display_name" IS '组名称。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。';
COMMENT ON COLUMN application.app_group."status" IS '组状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN application.app_group."version" IS '组版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN application.app_group."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.app_group."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';

-- application.assignment：企业应用资格及来源；部门、团队、全员和直接成员均需显式分配
CREATE TABLE application.assignment (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 被分配的企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 分配对象类别。 设计场景：明确规则面向全员、成员、部门还是团队，据此检查主体字段组合，避免空主体被解释为全员。
    "subject_kind" character varying(16) NOT NULL,
    -- 直接成员对象。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint,
    -- 部门对象。 设计场景：将人员、规则或变更指向稳定的本地部门，部门改名后关联不丢失，跨企业引用被拒绝。
    "department_id" bigint,
    -- 团队对象。 设计场景：非层级协作团队可以独立于部门组织，关系或规则只在该企业的明确团队内生效。
    "team_id" bigint,
    -- 部门分配是否覆盖下级部门。 设计场景：部门自动分配时区分仅本部门与包含下级部门，调整组织树后按当前规则重新计算影响范围。
    "include_descendants" boolean DEFAULT false NOT NULL,
    -- 管理员分配或明确配置的规则。 设计场景：区分手工、策略、审批或委派等来源，撤销某个来源时不误删独立获得的其他资格。
    "source_kind" character varying(16) DEFAULT 'MANUAL'::character varying NOT NULL,
    -- 产生该分配的策略版本。 设计场景：策略停用或变更时只处理依赖该版本形成的关系，便于解释自动授权从何而来。
    "source_policy_id" bigint,
    -- 授权操作或规则配置责任成员。 设计场景：追踪哪位企业成员建立了应用分配或规则，新增和变更时验证其当前管理资格。
    "assigned_by_member_id" bigint NOT NULL,
    -- 最早允许访问时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。
    "valid_from" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 到期时间。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。
    "valid_until" timestamp with time zone,
    -- 撤销时间；历史分配不可自动恢复。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "assignment_check" CHECK (updated_at >= created_at),
    CONSTRAINT "assignment_check1" CHECK (subject_kind::text = 'ALL_MEMBERS'::text AND num_nonnulls(member_id, department_id, team_id) = 0 OR subject_kind::text = 'MEMBER'::text AND member_id IS NOT NULL AND num_nonnulls(member_id, department_id, team_id) = 1 OR subject_kind::text = 'DEPARTMENT'::text AND department_id IS NOT NULL AND num_nonnulls(member_id, department_id, team_id) = 1 OR subject_kind::text = 'TEAM'::text AND team_id IS NOT NULL AND num_nonnulls(member_id, department_id, team_id) = 1),
    CONSTRAINT "assignment_check2" CHECK (NOT include_descendants OR subject_kind::text = 'DEPARTMENT'::text),
    CONSTRAINT "assignment_check3" CHECK (source_kind::text = 'MANUAL'::text AND source_policy_id IS NULL OR source_kind::text = 'POLICY'::text AND source_policy_id IS NOT NULL),
    CONSTRAINT "assignment_check4" CHECK (valid_until IS NULL OR valid_until > valid_from),
    CONSTRAINT "assignment_check5" CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT "assignment_id_check" CHECK (id > 0),
    CONSTRAINT "assignment_pkey" PRIMARY KEY (id),
    CONSTRAINT "assignment_source_kind_check" CHECK (source_kind::text = ANY (ARRAY['MANUAL'::character varying, 'POLICY'::character varying]::text[])),
    CONSTRAINT "assignment_subject_kind_check" CHECK (subject_kind::text = ANY (ARRAY['ALL_MEMBERS'::character varying, 'MEMBER'::character varying, 'DEPARTMENT'::character varying, 'TEAM'::character varying]::text[])),
    CONSTRAINT "assignment_tenant_id_assigned_by_member_id_fkey" FOREIGN KEY (tenant_id, assigned_by_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "assignment_tenant_id_department_id_fkey" FOREIGN KEY (tenant_id, department_id) REFERENCES directory.department(tenant_id, id),
    CONSTRAINT "assignment_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "assignment_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "assignment_tenant_id_member_id_fkey" FOREIGN KEY (tenant_id, member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "assignment_tenant_id_source_policy_id_fkey" FOREIGN KEY (tenant_id, source_policy_id) REFERENCES access.policy(tenant_id, id),
    CONSTRAINT "assignment_tenant_id_team_id_fkey" FOREIGN KEY (tenant_id, team_id) REFERENCES directory.team(tenant_id, id),
    CONSTRAINT "assignment_tenant_id_tenant_application_id_fkey" FOREIGN KEY (tenant_id, tenant_application_id) REFERENCES application.tenant_application(tenant_id, id),
    CONSTRAINT "assignment_tenant_id_tenant_application_id_id_key" UNIQUE (tenant_id, tenant_application_id, id)
);
COMMENT ON TABLE application.assignment IS '企业应用资格及来源；部门、团队、全员和直接成员均需显式分配';
COMMENT ON COLUMN application.assignment."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.assignment."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.assignment."tenant_application_id" IS '被分配的企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN application.assignment."subject_kind" IS '分配对象类别。 设计场景：明确规则面向全员、成员、部门还是团队，据此检查主体字段组合，避免空主体被解释为全员。';
COMMENT ON COLUMN application.assignment."member_id" IS '直接成员对象。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN application.assignment."department_id" IS '部门对象。 设计场景：将人员、规则或变更指向稳定的本地部门，部门改名后关联不丢失，跨企业引用被拒绝。';
COMMENT ON COLUMN application.assignment."team_id" IS '团队对象。 设计场景：非层级协作团队可以独立于部门组织，关系或规则只在该企业的明确团队内生效。';
COMMENT ON COLUMN application.assignment."include_descendants" IS '部门分配是否覆盖下级部门。 设计场景：部门自动分配时区分仅本部门与包含下级部门，调整组织树后按当前规则重新计算影响范围。';
COMMENT ON COLUMN application.assignment."source_kind" IS '管理员分配或明确配置的规则。 设计场景：区分手工、策略、审批或委派等来源，撤销某个来源时不误删独立获得的其他资格。';
COMMENT ON COLUMN application.assignment."source_policy_id" IS '产生该分配的策略版本。 设计场景：策略停用或变更时只处理依赖该版本形成的关系，便于解释自动授权从何而来。';
COMMENT ON COLUMN application.assignment."assigned_by_member_id" IS '授权操作或规则配置责任成员。 设计场景：追踪哪位企业成员建立了应用分配或规则，新增和变更时验证其当前管理资格。';
COMMENT ON COLUMN application.assignment."valid_from" IS '最早允许访问时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。';
COMMENT ON COLUMN application.assignment."valid_until" IS '到期时间。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。';
COMMENT ON COLUMN application.assignment."revoked_at" IS '撤销时间；历史分配不可自动恢复。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN application.assignment."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.assignment."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_assignment_assigner ON application.assignment USING btree (tenant_id, assigned_by_member_id);
CREATE INDEX ix_application_assignment_department ON application.assignment USING btree (tenant_id, department_id);
CREATE INDEX ix_application_assignment_expiry ON application.assignment USING btree (tenant_id, valid_until) WHERE (revoked_at IS NULL);
CREATE INDEX ix_application_assignment_member ON application.assignment USING btree (tenant_id, member_id, tenant_application_id);
CREATE INDEX ix_application_assignment_policy ON application.assignment USING btree (tenant_id, source_policy_id);
CREATE INDEX ix_application_assignment_team ON application.assignment USING btree (tenant_id, team_id);
CREATE UNIQUE INDEX uq_application_assignment_active ON application.assignment USING btree (tenant_id, tenant_application_id, subject_kind, member_id, department_id, team_id, source_kind, source_policy_id) NULLS NOT DISTINCT WHERE (revoked_at IS NULL);

-- application.attribute_mapping：向下游供应或断言的字段映射；一个目标字段一个显式规则，不按同名用户猜测关联
CREATE TABLE application.attribute_mapping (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 下游连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 协议或供应目标字段。 设计场景：明确发送给下游的字段名，一个目标字段使用一条可审查规则，避免隐式复制全部用户资料。
    "target_attribute" character varying(200) NOT NULL,
    -- 受控源字段或固定值。 设计场景：区分手工、策略、审批或委派等来源，撤销某个来源时不误删独立获得的其他资格。
    "source_kind" character varying(24) NOT NULL,
    -- 白名单源字段路径，不允许表达式执行代码。 设计场景：只允许从登记的账号或成员字段取值，防止任意表达式读取秘密或越过字段权限。
    "source_attribute" character varying(200),
    -- 非秘密固定值。 设计场景：对下游要求的固定非秘密属性显式赋值，避免把固定值与动态用户资料混淆。
    "constant_value" text,
    -- 目标是否要求非空；缺失时按明确错误处理。 设计场景：下游必需字段缺失时给出明确失败，不能用空字符串或猜测值伪造完整身份。
    "required" boolean DEFAULT false NOT NULL,
    -- 允许的简单规范化规则。 设计场景：通过受控转换完成大小写等规范化，禁止将自由代码作为字段映射执行。
    "transform_code" character varying(32) DEFAULT 'IDENTITY'::character varying NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "attribute_mapping_check" CHECK (updated_at >= created_at),
    CONSTRAINT "attribute_mapping_check1" CHECK (source_kind::text = 'CONSTANT'::text AND constant_value IS NOT NULL AND source_attribute IS NULL OR source_kind::text <> 'CONSTANT'::text AND source_attribute IS NOT NULL AND btrim(source_attribute::text) <> ''::text AND constant_value IS NULL),
    CONSTRAINT "attribute_mapping_id_check" CHECK (id > 0),
    CONSTRAINT "attribute_mapping_pkey" PRIMARY KEY (id),
    CONSTRAINT "attribute_mapping_source_kind_check" CHECK (source_kind::text = ANY (ARRAY['ACCOUNT_FIELD'::character varying, 'MEMBER_FIELD'::character varying, 'APP_IDENTITY_FIELD'::character varying, 'CONSTANT'::character varying]::text[])),
    CONSTRAINT "attribute_mapping_target_attribute_check" CHECK (btrim(target_attribute::text) <> ''::text),
    CONSTRAINT "attribute_mapping_tenant_id_connection_id_fkey" FOREIGN KEY (tenant_id, connection_id) REFERENCES application.connection(tenant_id, id),
    CONSTRAINT "attribute_mapping_tenant_id_connection_id_target_attribute_key" UNIQUE (tenant_id, connection_id, target_attribute),
    CONSTRAINT "attribute_mapping_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "attribute_mapping_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "attribute_mapping_transform_code_check" CHECK (transform_code::text = ANY (ARRAY['IDENTITY'::character varying, 'LOWERCASE'::character varying, 'UPPERCASE'::character varying, 'STRING'::character varying]::text[]))
);
COMMENT ON TABLE application.attribute_mapping IS '向下游供应或断言的字段映射；一个目标字段一个显式规则，不按同名用户猜测关联';
COMMENT ON COLUMN application.attribute_mapping."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.attribute_mapping."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.attribute_mapping."connection_id" IS '下游连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN application.attribute_mapping."target_attribute" IS '协议或供应目标字段。 设计场景：明确发送给下游的字段名，一个目标字段使用一条可审查规则，避免隐式复制全部用户资料。';
COMMENT ON COLUMN application.attribute_mapping."source_kind" IS '受控源字段或固定值。 设计场景：区分手工、策略、审批或委派等来源，撤销某个来源时不误删独立获得的其他资格。';
COMMENT ON COLUMN application.attribute_mapping."source_attribute" IS '白名单源字段路径，不允许表达式执行代码。 设计场景：只允许从登记的账号或成员字段取值，防止任意表达式读取秘密或越过字段权限。';
COMMENT ON COLUMN application.attribute_mapping."constant_value" IS '非秘密固定值。 设计场景：对下游要求的固定非秘密属性显式赋值，避免把固定值与动态用户资料混淆。';
COMMENT ON COLUMN application.attribute_mapping."required" IS '目标是否要求非空；缺失时按明确错误处理。 设计场景：下游必需字段缺失时给出明确失败，不能用空字符串或猜测值伪造完整身份。';
COMMENT ON COLUMN application.attribute_mapping."transform_code" IS '允许的简单规范化规则。 设计场景：通过受控转换完成大小写等规范化，禁止将自由代码作为字段映射执行。';
COMMENT ON COLUMN application.attribute_mapping."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.attribute_mapping."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';

-- application.client_registration：应用与框架 OAuth/OIDC 客户端的显式关联；一个应用可有多端及环境客户端
CREATE TABLE application.client_registration (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 目录应用。 设计场景：引用平台级应用定义，把应用产品身份与某企业开通实例、协议客户端分开。
    "application_id" bigint NOT NULL,
    -- 框架注册客户端，不承担企业应用分配。 设计场景：关联框架内部客户端记录，与外部 client_id 区分，便于一个业务应用配置多个终端和环境。
    "registered_client_id" character varying(100) NOT NULL,
    -- 明确环境代码，例如 production 或 staging。 设计场景：同一应用在测试和生产环境中可使用不同配置与客户端，避免跨环境接受凭据或跳转。
    "environment" character varying(32) NOT NULL,
    -- 客户端类型。 设计场景：区分 Web 服务端、桌面和移动等客户端，决定是否允许保存秘密以及采用何种回调与令牌策略。
    "client_kind" character varying(16) NOT NULL,
    -- 应用客户端关联是否允许使用。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "client_registration_application_id_fkey" FOREIGN KEY (application_id) REFERENCES application.catalog(id),
    CONSTRAINT "client_registration_application_id_registered_client_id_key" UNIQUE (application_id, registered_client_id),
    CONSTRAINT "client_registration_check" CHECK (updated_at >= created_at),
    CONSTRAINT "client_registration_client_kind_check" CHECK (client_kind::text = ANY (ARRAY['WEB'::character varying, 'DESKTOP'::character varying, 'MOBILE'::character varying, 'SERVICE'::character varying]::text[])),
    CONSTRAINT "client_registration_environment_check" CHECK (environment::text ~ '^[a-z][a-z0-9_-]{0,31}$'::text),
    CONSTRAINT "client_registration_id_check" CHECK (id > 0),
    CONSTRAINT "client_registration_pkey" PRIMARY KEY (id),
    CONSTRAINT "client_registration_registered_client_id_fkey" FOREIGN KEY (registered_client_id) REFERENCES protocol.oauth2_registered_client(id),
    CONSTRAINT "client_registration_registered_client_id_key" UNIQUE (registered_client_id),
    CONSTRAINT "client_registration_status_check" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying]::text[]))
);
COMMENT ON TABLE application.client_registration IS '应用与框架 OAuth/OIDC 客户端的显式关联；一个应用可有多端及环境客户端';
COMMENT ON COLUMN application.client_registration."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.client_registration."application_id" IS '目录应用。 设计场景：引用平台级应用定义，把应用产品身份与某企业开通实例、协议客户端分开。';
COMMENT ON COLUMN application.client_registration."registered_client_id" IS '框架注册客户端，不承担企业应用分配。 设计场景：关联框架内部客户端记录，与外部 client_id 区分，便于一个业务应用配置多个终端和环境。';
COMMENT ON COLUMN application.client_registration."environment" IS '明确环境代码，例如 production 或 staging。 设计场景：同一应用在测试和生产环境中可使用不同配置与客户端，避免跨环境接受凭据或跳转。';
COMMENT ON COLUMN application.client_registration."client_kind" IS '客户端类型。 设计场景：区分 Web 服务端、桌面和移动等客户端，决定是否允许保存秘密以及采用何种回调与令牌策略。';
COMMENT ON COLUMN application.client_registration."status" IS '应用客户端关联是否允许使用。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN application.client_registration."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.client_registration."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_client_registration_application ON application.client_registration USING btree (application_id, environment, status);

-- application.connection_key：下游连接的版本化签名/验证/API凭据引用；保留轮换窗口，秘密由外部密钥存储托管
CREATE TABLE application.connection_key (
    CONSTRAINT ck_connection_public_material_nonempty CHECK(public_material IS NULL OR btrim(public_material)<>''),
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 下游连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 连接内密钥标识。 设计场景：新旧密钥并存时精确选择对应验证材料，密钥标识本身不证明持有私钥。
    "key_id" character varying(200) NOT NULL,
    -- 同密钥标识的版本。 设计场景：标识同一连接密钥材料的具体版本，新旧材料在轮换窗口内可以并存；不能把它直接当作普通业务记录的乐观锁使用。
    "version" integer NOT NULL,
    -- 签名、验签、API认证或加密用途。 设计场景：同一连接可能存在签名、验签、API 认证等材料，必须按用途取用，避免把加密密钥误用于签名。
    "usage" character varying(16) NOT NULL,
    -- 受保护秘密引用，不保存私钥或 API 密钥原文。 设计场景：通过受控引用读取密钥材料，支持轮换和访问审计，避免把明文秘密放进普通配置与日志。
    "secret_ref" text,
    -- 公开证书或公钥；不可填写私钥。 设计场景：允许交换公开验证材料，供对端验签；私钥必须走受控秘密引用，不能混放。
    "public_material" text,
    -- 公钥或证书摘要，用于核对轮换。 设计场景：管理员核对导入或轮换的证书、公钥是否为预期材料，避免只凭名称选错密钥。
    "fingerprint" character varying(128),
    -- 密钥最早有效时间。 设计场景：提前配置下一把密钥但尚不启用，使用时依据有效期选择材料。
    "not_before" timestamp with time zone NOT NULL,
    -- 密钥失效时间。 设计场景：到期停止使用相应密钥材料，支持轮换窗口；到期检查不能只依赖后台清理。
    "not_after" timestamp with time zone NOT NULL,
    -- 待启用、当前、过渡验证或撤销。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    -- 被轮换的同连接密钥版本。 设计场景：保留轮换前后关系，排查新钥启用失败时能定位原材料及过渡窗口。
    "predecessor_id" bigint,
    -- 撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "connection_key_check" CHECK (updated_at >= created_at),
    CONSTRAINT "connection_key_check1" CHECK (num_nonnulls(secret_ref, public_material) > 0),
    CONSTRAINT "connection_key_check2" CHECK (not_after > not_before),
    CONSTRAINT "connection_key_check3" CHECK (status::text = 'REVOKED'::text AND revoked_at IS NOT NULL OR status::text <> 'REVOKED'::text AND revoked_at IS NULL),
    CONSTRAINT "connection_key_check4" CHECK (predecessor_id IS NULL OR predecessor_id <> id),
    CONSTRAINT "connection_key_id_check" CHECK (id > 0),
    CONSTRAINT "connection_key_key_id_check" CHECK (btrim(key_id::text) <> ''::text),
    CONSTRAINT "connection_key_pkey" PRIMARY KEY (id),
    CONSTRAINT "connection_key_public_material_check" CHECK (public_material IS NULL OR public_material !~~ '%PRIVATE KEY%'::text),
    CONSTRAINT "connection_key_secret_ref_check" CHECK (secret_ref IS NULL OR btrim(secret_ref) <> ''::text),
    CONSTRAINT "connection_key_status_check" CHECK (status::text = ANY (ARRAY['PENDING'::character varying, 'ACTIVE'::character varying, 'RETIRING'::character varying, 'REVOKED'::character varying]::text[])),
    CONSTRAINT "connection_key_tenant_id_connection_id_fkey" FOREIGN KEY (tenant_id, connection_id) REFERENCES application.connection(tenant_id, id),
    CONSTRAINT "connection_key_tenant_id_connection_id_id_key" UNIQUE (tenant_id, connection_id, id),
    CONSTRAINT "connection_key_tenant_id_connection_id_key_id_version_key" UNIQUE (tenant_id, connection_id, key_id, version),
    CONSTRAINT "connection_key_tenant_id_connection_id_predecessor_id_fkey" FOREIGN KEY (tenant_id, connection_id, predecessor_id) REFERENCES application.connection_key(tenant_id, connection_id, id),
    CONSTRAINT "connection_key_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "connection_key_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "connection_key_usage_check" CHECK (usage::text = ANY (ARRAY['SIGN'::character varying, 'VERIFY'::character varying, 'API_AUTH'::character varying, 'ENCRYPT'::character varying]::text[])),
    CONSTRAINT "connection_key_version_check" CHECK (version > 0)
);
COMMENT ON TABLE application.connection_key IS '下游连接的版本化签名/验证/API凭据引用；保留轮换窗口，秘密由外部密钥存储托管';
COMMENT ON COLUMN application.connection_key."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.connection_key."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.connection_key."connection_id" IS '下游连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN application.connection_key."key_id" IS '连接内密钥标识。 设计场景：新旧密钥并存时精确选择对应验证材料，密钥标识本身不证明持有私钥。';
COMMENT ON COLUMN application.connection_key."version" IS '同密钥标识的版本。 设计场景：标识同一连接密钥材料的具体版本，新旧材料在轮换窗口内可以并存；不能把它直接当作普通业务记录的乐观锁使用。';
COMMENT ON COLUMN application.connection_key."usage" IS '签名、验签、API认证或加密用途。 设计场景：同一连接可能存在签名、验签、API 认证等材料，必须按用途取用，避免把加密密钥误用于签名。';
COMMENT ON COLUMN application.connection_key."secret_ref" IS '受保护秘密引用，不保存私钥或 API 密钥原文。 设计场景：通过受控引用读取密钥材料，支持轮换和访问审计，避免把明文秘密放进普通配置与日志。';
COMMENT ON COLUMN application.connection_key."public_material" IS '公开证书或公钥；不可填写私钥。 设计场景：允许交换公开验证材料，供对端验签；私钥必须走受控秘密引用，不能混放。';
COMMENT ON COLUMN application.connection_key."fingerprint" IS '公钥或证书摘要，用于核对轮换。 设计场景：管理员核对导入或轮换的证书、公钥是否为预期材料，避免只凭名称选错密钥。';
COMMENT ON COLUMN application.connection_key."not_before" IS '密钥最早有效时间。 设计场景：提前配置下一把密钥但尚不启用，使用时依据有效期选择材料。';
COMMENT ON COLUMN application.connection_key."not_after" IS '密钥失效时间。 设计场景：到期停止使用相应密钥材料，支持轮换窗口；到期检查不能只依赖后台清理。';
COMMENT ON COLUMN application.connection_key."status" IS '待启用、当前、过渡验证或撤销。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN application.connection_key."predecessor_id" IS '被轮换的同连接密钥版本。 设计场景：保留轮换前后关系，排查新钥启用失败时能定位原材料及过渡窗口。';
COMMENT ON COLUMN application.connection_key."revoked_at" IS '撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN application.connection_key."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.connection_key."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_connection_key_expiry ON application.connection_key USING btree (tenant_id, status, not_after);
CREATE INDEX ix_application_connection_key_predecessor ON application.connection_key USING btree (tenant_id, connection_id, predecessor_id);

-- application.favorite：用户在某企业收藏的应用；收藏不形成访问资格
CREATE TABLE application.favorite (
    -- 所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 收藏者企业成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 收藏的企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 个人展示排序。 设计场景：允许调整展示顺序而不改变业务标识、权限或层级关系。
    "sort_order" integer DEFAULT 0 NOT NULL,
    -- 收藏时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "favorite_pkey" PRIMARY KEY (tenant_id, member_id, tenant_application_id),
    CONSTRAINT "favorite_sort_order_check" CHECK (sort_order >= 0),
    CONSTRAINT "favorite_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "favorite_tenant_id_member_id_fkey" FOREIGN KEY (tenant_id, member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "favorite_tenant_id_tenant_application_id_fkey" FOREIGN KEY (tenant_id, tenant_application_id) REFERENCES application.tenant_application(tenant_id, id)
);
COMMENT ON TABLE application.favorite IS '用户在某企业收藏的应用；收藏不形成访问资格';
COMMENT ON COLUMN application.favorite."tenant_id" IS '所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.favorite."member_id" IS '收藏者企业成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN application.favorite."tenant_application_id" IS '收藏的企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN application.favorite."sort_order" IS '个人展示排序。 设计场景：允许调整展示顺序而不改变业务标识、权限或层级关系。';
COMMENT ON COLUMN application.favorite."created_at" IS '收藏时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_application_favorite_application ON application.favorite USING btree (tenant_id, tenant_application_id);

-- application.identity_group：应用身份与应用组关系；保留来源以避免规则移除误删手工关系
CREATE TABLE application.identity_group (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 企业应用，约束两侧属于同一应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 应用身份。 设计场景：明确本次登录或供应采用哪个应用内身份，避免一人多身份时切错目标账号。
    "user_identity_id" bigint NOT NULL,
    -- 应用群组。 设计场景：把某应用身份加入明确的应用内群组，企业部门或平台角色不会自动成为这个群组。
    "app_group_id" bigint NOT NULL,
    -- 手工或规则来源。 设计场景：区分手工、策略、审批或委派等来源，撤销某个来源时不误删独立获得的其他资格。
    "source_kind" character varying(16) DEFAULT 'MANUAL'::character varying NOT NULL,
    -- 来源策略版本。 设计场景：策略停用或变更时只处理依赖该版本形成的关系，便于解释自动授权从何而来。
    "source_policy_id" bigint,
    -- 此份来源的撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "identity_group_check" CHECK (updated_at >= created_at),
    CONSTRAINT "identity_group_check1" CHECK (source_kind::text = 'MANUAL'::text AND source_policy_id IS NULL OR source_kind::text = 'POLICY'::text AND source_policy_id IS NOT NULL),
    CONSTRAINT "identity_group_check2" CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT "identity_group_id_check" CHECK (id > 0),
    CONSTRAINT "identity_group_pkey" PRIMARY KEY (id),
    CONSTRAINT "identity_group_source_kind_check" CHECK (source_kind::text = ANY (ARRAY['MANUAL'::character varying, 'POLICY'::character varying]::text[])),
    CONSTRAINT "identity_group_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "identity_group_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "identity_group_tenant_id_source_policy_id_fkey" FOREIGN KEY (tenant_id, source_policy_id) REFERENCES access.policy(tenant_id, id),
    CONSTRAINT "identity_group_tenant_id_tenant_application_id_app_group_i_fkey" FOREIGN KEY (tenant_id, tenant_application_id, app_group_id) REFERENCES application.app_group(tenant_id, tenant_application_id, id),
    CONSTRAINT "identity_group_tenant_id_tenant_application_id_user_identi_fkey" FOREIGN KEY (tenant_id, tenant_application_id, user_identity_id) REFERENCES application.user_identity(tenant_id, tenant_application_id, id)
);
COMMENT ON TABLE application.identity_group IS '应用身份与应用组关系；保留来源以避免规则移除误删手工关系';
COMMENT ON COLUMN application.identity_group."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.identity_group."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.identity_group."tenant_application_id" IS '企业应用，约束两侧属于同一应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN application.identity_group."user_identity_id" IS '应用身份。 设计场景：明确本次登录或供应采用哪个应用内身份，避免一人多身份时切错目标账号。';
COMMENT ON COLUMN application.identity_group."app_group_id" IS '应用群组。 设计场景：把某应用身份加入明确的应用内群组，企业部门或平台角色不会自动成为这个群组。';
COMMENT ON COLUMN application.identity_group."source_kind" IS '手工或规则来源。 设计场景：区分手工、策略、审批或委派等来源，撤销某个来源时不误删独立获得的其他资格。';
COMMENT ON COLUMN application.identity_group."source_policy_id" IS '来源策略版本。 设计场景：策略停用或变更时只处理依赖该版本形成的关系，便于解释自动授权从何而来。';
COMMENT ON COLUMN application.identity_group."revoked_at" IS '此份来源的撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN application.identity_group."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.identity_group."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_identity_group_group ON application.identity_group USING btree (tenant_id, tenant_application_id, app_group_id);
CREATE INDEX ix_application_identity_group_policy ON application.identity_group USING btree (tenant_id, source_policy_id);
CREATE UNIQUE INDEX uq_identity_group_active ON application.identity_group USING btree (tenant_id, tenant_application_id, user_identity_id, app_group_id, source_kind, source_policy_id) NULLS NOT DISTINCT WHERE (revoked_at IS NULL);

-- application.launch_ticket：专用应用跳转短期票据；绑定本人、企业、应用和用途，不能成为管理员任意冒充入口
CREATE TABLE application.launch_ticket (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 目标企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 目标专用协议连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 已认证且获准的企业成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 成员对应账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 已获准选择的应用身份。 设计场景：明确本次登录或供应采用哪个应用内身份，避免一人多身份时切错目标账号。
    "user_identity_id" bigint NOT NULL,
    -- 签发时本人中央会话。 设计场景：把各应用登录追溯到中央认证会话，全部退出或中央撤销后能定位依赖它的应用会话。
    "central_session_id" bigint NOT NULL,
    -- 高熵随机票据的 SHA-256 验证值，不存明文。 设计场景：专用跳转票据只保存验证值，避免数据库读取者直接拿到可登录的原票据。
    "token_digest" bytea NOT NULL,
    -- 固定用途，不可混作恢复、邀请或其他凭据。 设计场景：限定专用跳转票据只用于明确业务动作，禁止把一次应用启动票据复用为管理员模拟任意用户的入口。
    "purpose" character varying(24) NOT NULL,
    -- 签发时账号撤销版本，使用时与当前版本比较。 设计场景：跳转票据签发后账号可能改密或冻结，消费时核对原始版本，防止短期票据绕过刚发生的撤销。
    "auth_epoch" bigint NOT NULL,
    -- 短期到期时间。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone NOT NULL,
    -- 允许消费次数。 设计场景：显式限制专用票据允许消费次数，普通一次性跳转按规则只允许一次，不能重放为持续登录入口。
    "max_uses" smallint DEFAULT 1 NOT NULL,
    -- 已原子消费次数。 设计场景：并发消费时原子递增并检查上限，防止两次请求同时读取未使用状态后都成功。
    "used_count" smallint DEFAULT 0 NOT NULL,
    -- 最近消费时间。 设计场景：帮助用户识别仍在使用的凭据、设备或票据，支持轮换和清理；不是独立的有效性证明。
    "last_used_at" timestamp with time zone,
    -- 撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "launch_ticket_account_id_central_session_id_fkey" FOREIGN KEY (account_id, central_session_id) REFERENCES identity.auth_session(account_id, id),
    CONSTRAINT "launch_ticket_auth_epoch_check" CHECK (auth_epoch >= 0),
    CONSTRAINT "launch_ticket_check" CHECK (updated_at >= created_at),
    CONSTRAINT "launch_ticket_check1" CHECK (expires_at > created_at),
    CONSTRAINT "launch_ticket_check2" CHECK (used_count <= max_uses),
    CONSTRAINT "launch_ticket_check3" CHECK (used_count = 0 AND last_used_at IS NULL OR used_count > 0 AND last_used_at IS NOT NULL),
    CONSTRAINT "launch_ticket_check4" CHECK (last_used_at IS NULL OR last_used_at >= created_at AND last_used_at < expires_at),
    CONSTRAINT "launch_ticket_id_check" CHECK (id > 0),
    CONSTRAINT "launch_ticket_max_uses_check" CHECK (max_uses > 0),
    CONSTRAINT "launch_ticket_pkey" PRIMARY KEY (id),
    CONSTRAINT "launch_ticket_purpose_check" CHECK (purpose::text = ANY (ARRAY['APPLICATION_LOGIN'::character varying, 'APPLICATION_HANDOFF'::character varying]::text[])),
    CONSTRAINT "launch_ticket_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "launch_ticket_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "launch_ticket_tenant_id_member_id_account_id_fkey" FOREIGN KEY (tenant_id, member_id, account_id) REFERENCES directory.membership(tenant_id, id, account_id),
    CONSTRAINT "launch_ticket_tenant_id_tenant_application_id_connection_i_fkey" FOREIGN KEY (tenant_id, tenant_application_id, connection_id) REFERENCES application.connection(tenant_id, tenant_application_id, id),
    CONSTRAINT "launch_ticket_tenant_id_tenant_application_id_user_identit_fkey" FOREIGN KEY (tenant_id, tenant_application_id, user_identity_id, member_id) REFERENCES application.user_identity(tenant_id, tenant_application_id, id, member_id),
    CONSTRAINT "launch_ticket_token_digest_check" CHECK (octet_length(token_digest) = 32),
    CONSTRAINT "launch_ticket_token_digest_key" UNIQUE (token_digest),
    CONSTRAINT "launch_ticket_used_count_check" CHECK (used_count >= 0)
);
COMMENT ON TABLE application.launch_ticket IS '专用应用跳转短期票据；绑定本人、企业、应用和用途，不能成为管理员任意冒充入口';
COMMENT ON COLUMN application.launch_ticket."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.launch_ticket."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.launch_ticket."tenant_application_id" IS '目标企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN application.launch_ticket."connection_id" IS '目标专用协议连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN application.launch_ticket."member_id" IS '已认证且获准的企业成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN application.launch_ticket."account_id" IS '成员对应账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN application.launch_ticket."user_identity_id" IS '已获准选择的应用身份。 设计场景：明确本次登录或供应采用哪个应用内身份，避免一人多身份时切错目标账号。';
COMMENT ON COLUMN application.launch_ticket."central_session_id" IS '签发时本人中央会话。 设计场景：把各应用登录追溯到中央认证会话，全部退出或中央撤销后能定位依赖它的应用会话。';
COMMENT ON COLUMN application.launch_ticket."token_digest" IS '高熵随机票据的 SHA-256 验证值，不存明文。 设计场景：专用跳转票据只保存验证值，避免数据库读取者直接拿到可登录的原票据。';
COMMENT ON COLUMN application.launch_ticket."purpose" IS '固定用途，不可混作恢复、邀请或其他凭据。 设计场景：限定专用跳转票据只用于明确业务动作，禁止把一次应用启动票据复用为管理员模拟任意用户的入口。';
COMMENT ON COLUMN application.launch_ticket."auth_epoch" IS '签发时账号撤销版本，使用时与当前版本比较。 设计场景：跳转票据签发后账号可能改密或冻结，消费时核对原始版本，防止短期票据绕过刚发生的撤销。';
COMMENT ON COLUMN application.launch_ticket."expires_at" IS '短期到期时间。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN application.launch_ticket."max_uses" IS '允许消费次数。 设计场景：显式限制专用票据允许消费次数，普通一次性跳转按规则只允许一次，不能重放为持续登录入口。';
COMMENT ON COLUMN application.launch_ticket."used_count" IS '已原子消费次数。 设计场景：并发消费时原子递增并检查上限，防止两次请求同时读取未使用状态后都成功。';
COMMENT ON COLUMN application.launch_ticket."last_used_at" IS '最近消费时间。 设计场景：帮助用户识别仍在使用的凭据、设备或票据，支持轮换和清理；不是独立的有效性证明。';
COMMENT ON COLUMN application.launch_ticket."revoked_at" IS '撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN application.launch_ticket."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.launch_ticket."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_launch_ticket_connection ON application.launch_ticket USING btree (tenant_id, tenant_application_id, connection_id);
CREATE INDEX ix_application_launch_ticket_expiry ON application.launch_ticket USING btree (tenant_id, expires_at);
CREATE INDEX ix_application_launch_ticket_identity ON application.launch_ticket USING btree (tenant_id, tenant_application_id, user_identity_id, member_id);
CREATE INDEX ix_application_launch_ticket_member ON application.launch_ticket USING btree (tenant_id, member_id);
CREATE INDEX ix_application_launch_ticket_session ON application.launch_ticket USING btree (account_id, central_session_id);

-- application.preapproval：企业管理员对特定应用客户端及范围的预批准；不等于应用分配，扩大范围须新版本审批
CREATE TABLE application.preapproval (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 平台应用，约束客户端属于同一应用。 设计场景：引用平台级应用定义，把应用产品身份与某企业开通实例、协议客户端分开。
    "application_id" bigint NOT NULL,
    -- 被预批准的协议客户端。 设计场景：关联框架内部客户端记录，与外部 client_id 区分，便于一个业务应用配置多个终端和环境。
    "registered_client_id" character varying(100) NOT NULL,
    -- 预批准版本。 设计场景：同一个策略或预批准保留多个业务版本，已执行结果能引用当时版本；与记录乐观锁 version 分工不同。
    "revision" integer NOT NULL,
    -- 管理员明确批准的接口与身份范围，使用时与客户端登记范围求交集。 设计场景：企业管理员可以预先批准一定协议范围，应用新请求扩大范围时不能复用旧批准。
    "approved_scopes" character varying(120)[] NOT NULL,
    -- 可释放的身份字段白名单，不含任意资料。 设计场景：只释放企业批准且当前仍有权提供的身份字段，避免把应用登录等同于允许获取完整员工资料。
    "approved_claims" character varying(120)[] DEFAULT '{}'::character varying(120)[] NOT NULL,
    -- 批准管理员；必须验证其当前企业管理资格。 设计场景：追踪预批准或工作委派由哪位管理员作出，当前身份无效时按对应规则重新核验。
    "approved_by_member_id" bigint NOT NULL,
    -- 批准状态；旧版本不因客户端变更恢复。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 开始时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。
    "valid_from" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 到期时间。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。
    "valid_until" timestamp with time zone,
    -- 撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "preapproval_application_id_registered_client_id_fkey" FOREIGN KEY (application_id, registered_client_id) REFERENCES application.client_registration(application_id, registered_client_id),
    CONSTRAINT "preapproval_approved_claims_check" CHECK (array_position(approved_claims, NULL::character varying) IS NULL AND NOT ('*'::text = ANY (approved_claims::text[]))),
    CONSTRAINT "preapproval_approved_scopes_check" CHECK (cardinality(approved_scopes) > 0 AND array_position(approved_scopes, NULL::character varying) IS NULL AND NOT ('*'::text = ANY (approved_scopes::text[]))),
    CONSTRAINT "preapproval_check" CHECK (updated_at >= created_at),
    CONSTRAINT "preapproval_check1" CHECK (valid_until IS NULL OR valid_until > valid_from),
    CONSTRAINT "preapproval_check2" CHECK (status::text = 'REVOKED'::text AND revoked_at IS NOT NULL OR status::text <> 'REVOKED'::text AND revoked_at IS NULL),
    CONSTRAINT "preapproval_id_check" CHECK (id > 0),
    CONSTRAINT "preapproval_pkey" PRIMARY KEY (id),
    CONSTRAINT "preapproval_revision_check" CHECK (revision > 0),
    CONSTRAINT "preapproval_status_check" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'REVOKED'::character varying, 'SUPERSEDED'::character varying]::text[])),
    CONSTRAINT "preapproval_tenant_id_approved_by_member_id_fkey" FOREIGN KEY (tenant_id, approved_by_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "preapproval_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "preapproval_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "preapproval_tenant_id_tenant_application_id_application_id_fkey" FOREIGN KEY (tenant_id, tenant_application_id, application_id) REFERENCES application.tenant_application(tenant_id, id, application_id),
    CONSTRAINT "preapproval_tenant_id_tenant_application_id_registered_clie_key" UNIQUE (tenant_id, tenant_application_id, registered_client_id, revision)
);
COMMENT ON TABLE application.preapproval IS '企业管理员对特定应用客户端及范围的预批准；不等于应用分配，扩大范围须新版本审批';
COMMENT ON COLUMN application.preapproval."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.preapproval."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.preapproval."tenant_application_id" IS '企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN application.preapproval."application_id" IS '平台应用，约束客户端属于同一应用。 设计场景：引用平台级应用定义，把应用产品身份与某企业开通实例、协议客户端分开。';
COMMENT ON COLUMN application.preapproval."registered_client_id" IS '被预批准的协议客户端。 设计场景：关联框架内部客户端记录，与外部 client_id 区分，便于一个业务应用配置多个终端和环境。';
COMMENT ON COLUMN application.preapproval."revision" IS '预批准版本。 设计场景：同一个策略或预批准保留多个业务版本，已执行结果能引用当时版本；与记录乐观锁 version 分工不同。';
COMMENT ON COLUMN application.preapproval."approved_scopes" IS '管理员明确批准的接口与身份范围，使用时与客户端登记范围求交集。 设计场景：企业管理员可以预先批准一定协议范围，应用新请求扩大范围时不能复用旧批准。';
COMMENT ON COLUMN application.preapproval."approved_claims" IS '可释放的身份字段白名单，不含任意资料。 设计场景：只释放企业批准且当前仍有权提供的身份字段，避免把应用登录等同于允许获取完整员工资料。';
COMMENT ON COLUMN application.preapproval."approved_by_member_id" IS '批准管理员；必须验证其当前企业管理资格。 设计场景：追踪预批准或工作委派由哪位管理员作出，当前身份无效时按对应规则重新核验。';
COMMENT ON COLUMN application.preapproval."status" IS '批准状态；旧版本不因客户端变更恢复。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN application.preapproval."valid_from" IS '开始时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。';
COMMENT ON COLUMN application.preapproval."valid_until" IS '到期时间。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。';
COMMENT ON COLUMN application.preapproval."revoked_at" IS '撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN application.preapproval."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.preapproval."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_preapproval_approver ON application.preapproval USING btree (tenant_id, approved_by_member_id);
CREATE INDEX ix_application_preapproval_client ON application.preapproval USING btree (application_id, registered_client_id);
CREATE UNIQUE INDEX uq_preapproval_current ON application.preapproval USING btree (tenant_id, tenant_application_id, registered_client_id) WHERE ((status)::text = 'ACTIVE'::text);

-- application.provisioned_object：下游账号或群组的生命周期映射；期望状态与确认状态分开，冲突和失败不会假报成功
CREATE TABLE application.provisioned_object (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 账号供应连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 固定供应用途，数据库禁止误用登录连接。 设计场景：把映射或任务限定到符合用途的连接，例如 SAML 控制台登录不能误用账号供应连接。
    "connection_purpose" character varying(16) DEFAULT 'PROVISIONING'::character varying NOT NULL,
    -- 用户或群组。 设计场景：区分下游用户与群组，选择不同的供应接口及映射关系，避免把组标识当用户标识处理。
    "object_kind" character varying(8) NOT NULL,
    -- 本地应用用户身份。 设计场景：明确本次登录或供应采用哪个应用内身份，避免一人多身份时切错目标账号。
    "user_identity_id" bigint,
    -- 本地应用群组。 设计场景：把某应用身份加入明确的应用内群组，企业部门或平台角色不会自动成为这个群组。
    "app_group_id" bigint,
    -- 下游确认的主体标识；未创建前为空。 设计场景：下游确认创建后保留它返回的稳定标识，超时未知时先查询对账，避免再次创建重复账号。
    "external_id" character varying(512),
    -- 本地期望状态。 设计场景：本地先记录希望下游达到的状态，例如停用；远端尚未成功时仍能明确任务目标。
    "desired_state" character varying(16) NOT NULL,
    -- 最近实际确认的下游状态。 设计场景：单独保存已确认的远端状态，避免本地发出请求就把下游显示为已更新。
    "observed_state" character varying(16) DEFAULT 'UNKNOWN'::character varying NOT NULL,
    -- 期望版本，任务按版本幂等。 设计场景：同一对象连续变更时让任务关联具体期望版本，旧任务不能覆盖更新后的目标。
    "desired_version" bigint DEFAULT 1 NOT NULL,
    -- 已确认版本；不表示下游原生版本。 设计场景：标明远端已确认追上哪一版本，便于识别尚未完成的供应差距。
    "observed_version" bigint,
    -- 最近查询或写入确认时间。 设计场景：记录何时真正观察或确认远端状态，用于识别本地期望已变但下游尚未核实的差距。
    "last_confirmed_at" timestamp with time zone,
    -- 脱敏错误代码。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。
    "last_error_code" character varying(64),
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "provisioned_object_check" CHECK (updated_at >= created_at),
    CONSTRAINT "provisioned_object_check1" CHECK (object_kind::text = 'USER'::text AND user_identity_id IS NOT NULL AND app_group_id IS NULL OR object_kind::text = 'GROUP'::text AND app_group_id IS NOT NULL AND user_identity_id IS NULL),
    CONSTRAINT "provisioned_object_check2" CHECK (observed_version IS NULL OR observed_version <= desired_version),
    CONSTRAINT "provisioned_object_connection_purpose_check" CHECK (connection_purpose::text = 'PROVISIONING'::text),
    CONSTRAINT "provisioned_object_desired_state_check" CHECK (desired_state::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying, 'REMOVED'::character varying]::text[])),
    CONSTRAINT "provisioned_object_desired_version_check" CHECK (desired_version > 0),
    CONSTRAINT "provisioned_object_external_id_check" CHECK (external_id IS NULL OR btrim(external_id::text) <> ''::text),
    CONSTRAINT "provisioned_object_id_check" CHECK (id > 0),
    CONSTRAINT "provisioned_object_object_kind_check" CHECK (object_kind::text = ANY (ARRAY['USER'::character varying, 'GROUP'::character varying]::text[])),
    CONSTRAINT "provisioned_object_observed_state_check" CHECK (observed_state::text = ANY (ARRAY['UNKNOWN'::character varying, 'ABSENT'::character varying, 'ACTIVE'::character varying, 'DISABLED'::character varying, 'REMOVED'::character varying, 'CONFLICT'::character varying]::text[])),
    CONSTRAINT "provisioned_object_observed_version_check" CHECK (observed_version >= 0),
    CONSTRAINT "provisioned_object_pkey" PRIMARY KEY (id),
    CONSTRAINT "provisioned_object_tenant_id_connection_id_connection_purp_fkey" FOREIGN KEY (tenant_id, connection_id, connection_purpose) REFERENCES application.connection(tenant_id, id, purpose),
    CONSTRAINT "provisioned_object_tenant_id_connection_id_id_key" UNIQUE (tenant_id, connection_id, id),
    CONSTRAINT "provisioned_object_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "provisioned_object_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "provisioned_object_tenant_id_tenant_application_id_app_gro_fkey" FOREIGN KEY (tenant_id, tenant_application_id, app_group_id) REFERENCES application.app_group(tenant_id, tenant_application_id, id),
    CONSTRAINT "provisioned_object_tenant_id_tenant_application_id_connect_fkey" FOREIGN KEY (tenant_id, tenant_application_id, connection_id) REFERENCES application.connection(tenant_id, tenant_application_id, id),
    CONSTRAINT "provisioned_object_tenant_id_tenant_application_id_user_id_fkey" FOREIGN KEY (tenant_id, tenant_application_id, user_identity_id) REFERENCES application.user_identity(tenant_id, tenant_application_id, id)
);
COMMENT ON TABLE application.provisioned_object IS '下游账号或群组的生命周期映射；期望状态与确认状态分开，冲突和失败不会假报成功';
COMMENT ON COLUMN application.provisioned_object."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.provisioned_object."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.provisioned_object."tenant_application_id" IS '企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN application.provisioned_object."connection_id" IS '账号供应连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN application.provisioned_object."connection_purpose" IS '固定供应用途，数据库禁止误用登录连接。 设计场景：把映射或任务限定到符合用途的连接，例如 SAML 控制台登录不能误用账号供应连接。';
COMMENT ON COLUMN application.provisioned_object."object_kind" IS '用户或群组。 设计场景：区分下游用户与群组，选择不同的供应接口及映射关系，避免把组标识当用户标识处理。';
COMMENT ON COLUMN application.provisioned_object."user_identity_id" IS '本地应用用户身份。 设计场景：明确本次登录或供应采用哪个应用内身份，避免一人多身份时切错目标账号。';
COMMENT ON COLUMN application.provisioned_object."app_group_id" IS '本地应用群组。 设计场景：把某应用身份加入明确的应用内群组，企业部门或平台角色不会自动成为这个群组。';
COMMENT ON COLUMN application.provisioned_object."external_id" IS '下游确认的主体标识；未创建前为空。 设计场景：下游确认创建后保留它返回的稳定标识，超时未知时先查询对账，避免再次创建重复账号。';
COMMENT ON COLUMN application.provisioned_object."desired_state" IS '本地期望状态。 设计场景：本地先记录希望下游达到的状态，例如停用；远端尚未成功时仍能明确任务目标。';
COMMENT ON COLUMN application.provisioned_object."observed_state" IS '最近实际确认的下游状态。 设计场景：单独保存已确认的远端状态，避免本地发出请求就把下游显示为已更新。';
COMMENT ON COLUMN application.provisioned_object."desired_version" IS '期望版本，任务按版本幂等。 设计场景：同一对象连续变更时让任务关联具体期望版本，旧任务不能覆盖更新后的目标。';
COMMENT ON COLUMN application.provisioned_object."observed_version" IS '已确认版本；不表示下游原生版本。 设计场景：标明远端已确认追上哪一版本，便于识别尚未完成的供应差距。';
COMMENT ON COLUMN application.provisioned_object."last_confirmed_at" IS '最近查询或写入确认时间。 设计场景：记录何时真正观察或确认远端状态，用于识别本地期望已变但下游尚未核实的差距。';
COMMENT ON COLUMN application.provisioned_object."last_error_code" IS '脱敏错误代码。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。';
COMMENT ON COLUMN application.provisioned_object."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.provisioned_object."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_provisioned_object_group ON application.provisioned_object USING btree (tenant_id, tenant_application_id, app_group_id);
CREATE INDEX ix_application_provisioned_object_identity ON application.provisioned_object USING btree (tenant_id, tenant_application_id, user_identity_id);
CREATE INDEX ix_application_provisioned_object_pending ON application.provisioned_object USING btree (tenant_id, connection_id, observed_state);
CREATE UNIQUE INDEX uq_provisioned_external ON application.provisioned_object USING btree (tenant_id, connection_id, object_kind, external_id) WHERE (external_id IS NOT NULL);
CREATE UNIQUE INDEX uq_provisioned_group ON application.provisioned_object USING btree (tenant_id, connection_id, app_group_id) WHERE (app_group_id IS NOT NULL);
CREATE UNIQUE INDEX uq_provisioned_user ON application.provisioned_object USING btree (tenant_id, connection_id, user_identity_id) WHERE (user_identity_id IS NOT NULL);

-- application.provisioning_run：下游批量供应和对账批次；只在完整分页成功后计算缺失，不能把网络失败认作删除
CREATE TABLE application.provisioning_run (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 供应连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 固定供应用途。 设计场景：把映射或任务限定到符合用途的连接，例如 SAML 控制台登录不能误用账号供应连接。
    "connection_purpose" character varying(16) DEFAULT 'PROVISIONING'::character varying NOT NULL,
    -- 全量、增量或对账。 设计场景：区分全量、增量和对账批次，缺失对象处理仅使用满足条件的完整结果。
    "kind" character varying(16) NOT NULL,
    -- 运行状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'QUEUED'::character varying NOT NULL,
    -- 受控过滤及范围快照，关系保存在正式映射表。 设计场景：保留批次的筛选与范围快照，重试或对账时按同一范围解释结果，而非套用后来修改的条件。
    "scope_descriptor" jsonb DEFAULT '{}'::jsonb NOT NULL,
    -- 需要时加密保存供应商分页游标，不写日志。 设计场景：分页或断点续传时恢复读取进度；游标可能携带敏感参数，应加密并限定对应批次使用。
    "cursor_ciphertext" bytea,
    -- 处理条数。 设计场景：显示已经处理的条目规模并支持进度核对，不能单凭计数证明整批完成。
    "processed_count" bigint DEFAULT 0 NOT NULL,
    -- 失败条数。 设计场景：将局部失败显式呈现，后续只重试失败对象，不把一部分成功当作整批成功。
    "failed_count" bigint DEFAULT 0 NOT NULL,
    -- 完整结果标志；只有成功全量或对账可用于缺失处理。 设计场景：对账未拉完或中途失败时不得计算远端缺失对象，避免把网络故障当作账号已被删除。
    "complete_snapshot" boolean DEFAULT false NOT NULL,
    -- 开始时间。 设计场景：记录一次执行真正开始的时刻，用于识别排队与执行耗时、定位长期运行任务。
    "started_at" timestamp with time zone,
    -- 结束时间。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。
    "finished_at" timestamp with time zone,
    -- 脱敏失败原因。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。
    "last_error_code" character varying(64),
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "provisioning_run_check" CHECK (updated_at >= created_at),
    CONSTRAINT "provisioning_run_check1" CHECK (NOT complete_snapshot OR status::text = 'SUCCEEDED'::text AND (kind::text = ANY (ARRAY['FULL'::character varying, 'RECONCILE'::character varying]::text[]))),
    CONSTRAINT "provisioning_run_check2" CHECK (status::text = 'QUEUED'::text AND started_at IS NULL AND finished_at IS NULL OR status::text = 'RUNNING'::text AND started_at IS NOT NULL AND finished_at IS NULL OR (status::text = ANY (ARRAY['SUCCEEDED'::character varying, 'FAILED'::character varying, 'CANCELLED'::character varying]::text[])) AND finished_at IS NOT NULL),
    CONSTRAINT "provisioning_run_check3" CHECK (finished_at IS NULL OR finished_at >= COALESCE(started_at, created_at)),
    CONSTRAINT "provisioning_run_check4" CHECK (failed_count <= processed_count),
    CONSTRAINT "provisioning_run_connection_purpose_check" CHECK (connection_purpose::text = 'PROVISIONING'::text),
    CONSTRAINT "provisioning_run_failed_count_check" CHECK (failed_count >= 0),
    CONSTRAINT "provisioning_run_id_check" CHECK (id > 0),
    CONSTRAINT "provisioning_run_kind_check" CHECK (kind::text = ANY (ARRAY['FULL'::character varying, 'INCREMENTAL'::character varying, 'RECONCILE'::character varying]::text[])),
    CONSTRAINT "provisioning_run_pkey" PRIMARY KEY (id),
    CONSTRAINT "provisioning_run_processed_count_check" CHECK (processed_count >= 0),
    CONSTRAINT "provisioning_run_scope_descriptor_check" CHECK (jsonb_typeof(scope_descriptor) = 'object'::text),
    CONSTRAINT "provisioning_run_status_check" CHECK (status::text = ANY (ARRAY['QUEUED'::character varying, 'RUNNING'::character varying, 'SUCCEEDED'::character varying, 'FAILED'::character varying, 'CANCELLED'::character varying]::text[])),
    CONSTRAINT "provisioning_run_tenant_id_connection_id_connection_purpos_fkey" FOREIGN KEY (tenant_id, connection_id, connection_purpose) REFERENCES application.connection(tenant_id, id, purpose),
    CONSTRAINT "provisioning_run_tenant_id_connection_id_id_key" UNIQUE (tenant_id, connection_id, id),
    CONSTRAINT "provisioning_run_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "provisioning_run_tenant_id_id_key" UNIQUE (tenant_id, id)
);
COMMENT ON TABLE application.provisioning_run IS '下游批量供应和对账批次；只在完整分页成功后计算缺失，不能把网络失败认作删除';
COMMENT ON COLUMN application.provisioning_run."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.provisioning_run."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.provisioning_run."connection_id" IS '供应连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN application.provisioning_run."connection_purpose" IS '固定供应用途。 设计场景：把映射或任务限定到符合用途的连接，例如 SAML 控制台登录不能误用账号供应连接。';
COMMENT ON COLUMN application.provisioning_run."kind" IS '全量、增量或对账。 设计场景：区分全量、增量和对账批次，缺失对象处理仅使用满足条件的完整结果。';
COMMENT ON COLUMN application.provisioning_run."status" IS '运行状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN application.provisioning_run."scope_descriptor" IS '受控过滤及范围快照，关系保存在正式映射表。 设计场景：保留批次的筛选与范围快照，重试或对账时按同一范围解释结果，而非套用后来修改的条件。';
COMMENT ON COLUMN application.provisioning_run."cursor_ciphertext" IS '需要时加密保存供应商分页游标，不写日志。 设计场景：分页或断点续传时恢复读取进度；游标可能携带敏感参数，应加密并限定对应批次使用。';
COMMENT ON COLUMN application.provisioning_run."processed_count" IS '处理条数。 设计场景：显示已经处理的条目规模并支持进度核对，不能单凭计数证明整批完成。';
COMMENT ON COLUMN application.provisioning_run."failed_count" IS '失败条数。 设计场景：将局部失败显式呈现，后续只重试失败对象，不把一部分成功当作整批成功。';
COMMENT ON COLUMN application.provisioning_run."complete_snapshot" IS '完整结果标志；只有成功全量或对账可用于缺失处理。 设计场景：对账未拉完或中途失败时不得计算远端缺失对象，避免把网络故障当作账号已被删除。';
COMMENT ON COLUMN application.provisioning_run."started_at" IS '开始时间。 设计场景：记录一次执行真正开始的时刻，用于识别排队与执行耗时、定位长期运行任务。';
COMMENT ON COLUMN application.provisioning_run."finished_at" IS '结束时间。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。';
COMMENT ON COLUMN application.provisioning_run."last_error_code" IS '脱敏失败原因。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。';
COMMENT ON COLUMN application.provisioning_run."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.provisioning_run."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_provisioning_run_queue ON application.provisioning_run USING btree (tenant_id, connection_id, status, created_at);

-- application.provisioning_task：可靠下游创建/更新/停用任务；本地撤权先成立，未知结果须对账而非盲目重复创建
CREATE TABLE application.provisioning_task (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 供应连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 待同步的下游映射。 设计场景：多个重试任务指向同一稳定下游对象，避免每次重试都建立新的账号映射。
    "provisioned_object_id" bigint NOT NULL,
    -- 可选批次。 设计场景：将逐项变更或任务归入具体批次，便于查看进度、失败行和恢复范围；是否允许单独任务见字段可空性。
    "run_id" bigint,
    -- 本次期望操作。 设计场景：显式区分创建、更新、停用、归档或清理等动作，重试继续相同意图，不根据当前显示文案猜测操作。
    "operation" character varying(16) NOT NULL,
    -- 此任务的期望版本，旧任务不能覆盖新状态。 设计场景：同一对象连续变更时让任务关联具体期望版本，旧任务不能覆盖更新后的目标。
    "desired_version" bigint NOT NULL,
    -- 连接内幂等键。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。
    "idempotency_key" character varying(200) NOT NULL,
    -- 待执行、领取、成功、重试、终止、结果未知或被新版本替代。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'READY'::character varying NOT NULL,
    -- 尝试次数。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。
    "attempts" integer DEFAULT 0 NOT NULL,
    -- 下一次允许领取时间。 设计场景：支持延迟执行和失败后的退避重试，后台只能领取已经到可执行时间的任务。
    "available_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 工作进程租约持有人。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。
    "lease_owner" character varying(64),
    -- 租约到期时间。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。
    "lease_until" timestamp with time zone,
    -- 脱敏错误代码。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。
    "last_error_code" character varying(64),
    -- 确认完成或被替代时间。 设计场景：记录业务流程完成时间，便于区分处理中与已完成；完成必须以相应业务效果落地为前提。
    "completed_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "provisioning_task_attempts_check" CHECK (attempts >= 0),
    CONSTRAINT "provisioning_task_check" CHECK (updated_at >= created_at),
    CONSTRAINT "provisioning_task_check1" CHECK (status::text = 'CLAIMED'::text AND lease_owner IS NOT NULL AND lease_until IS NOT NULL OR status::text <> 'CLAIMED'::text AND lease_owner IS NULL AND lease_until IS NULL),
    CONSTRAINT "provisioning_task_check2" CHECK ((status::text = ANY (ARRAY['SUCCEEDED'::character varying, 'SUPERSEDED'::character varying]::text[])) AND completed_at IS NOT NULL OR (status::text <> ALL (ARRAY['SUCCEEDED'::character varying, 'SUPERSEDED'::character varying]::text[])) AND completed_at IS NULL),
    CONSTRAINT "provisioning_task_desired_version_check" CHECK (desired_version > 0),
    CONSTRAINT "provisioning_task_id_check" CHECK (id > 0),
    CONSTRAINT "provisioning_task_idempotency_key_check" CHECK (btrim(idempotency_key::text) <> ''::text),
    CONSTRAINT "provisioning_task_operation_check" CHECK (operation::text = ANY (ARRAY['CREATE'::character varying, 'UPDATE'::character varying, 'DISABLE'::character varying, 'DELETE'::character varying, 'RECONCILE'::character varying]::text[])),
    CONSTRAINT "provisioning_task_pkey" PRIMARY KEY (id),
    CONSTRAINT "provisioning_task_status_check" CHECK (status::text = ANY (ARRAY['READY'::character varying, 'CLAIMED'::character varying, 'SUCCEEDED'::character varying, 'RETRY'::character varying, 'DEAD'::character varying, 'UNKNOWN'::character varying, 'SUPERSEDED'::character varying]::text[])),
    CONSTRAINT "provisioning_task_tenant_id_connection_id_idempotency_key_key" UNIQUE (tenant_id, connection_id, idempotency_key),
    CONSTRAINT "provisioning_task_tenant_id_connection_id_provisioned_obje_fkey" FOREIGN KEY (tenant_id, connection_id, provisioned_object_id) REFERENCES application.provisioned_object(tenant_id, connection_id, id),
    CONSTRAINT "provisioning_task_tenant_id_connection_id_run_id_fkey" FOREIGN KEY (tenant_id, connection_id, run_id) REFERENCES application.provisioning_run(tenant_id, connection_id, id),
    CONSTRAINT "provisioning_task_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "provisioning_task_tenant_id_id_key" UNIQUE (tenant_id, id)
);
COMMENT ON TABLE application.provisioning_task IS '可靠下游创建/更新/停用任务；本地撤权先成立，未知结果须对账而非盲目重复创建';
COMMENT ON COLUMN application.provisioning_task."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.provisioning_task."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.provisioning_task."connection_id" IS '供应连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN application.provisioning_task."provisioned_object_id" IS '待同步的下游映射。 设计场景：多个重试任务指向同一稳定下游对象，避免每次重试都建立新的账号映射。';
COMMENT ON COLUMN application.provisioning_task."run_id" IS '可选批次。 设计场景：将逐项变更或任务归入具体批次，便于查看进度、失败行和恢复范围；是否允许单独任务见字段可空性。';
COMMENT ON COLUMN application.provisioning_task."operation" IS '本次期望操作。 设计场景：显式区分创建、更新、停用、归档或清理等动作，重试继续相同意图，不根据当前显示文案猜测操作。';
COMMENT ON COLUMN application.provisioning_task."desired_version" IS '此任务的期望版本，旧任务不能覆盖新状态。 设计场景：同一对象连续变更时让任务关联具体期望版本，旧任务不能覆盖更新后的目标。';
COMMENT ON COLUMN application.provisioning_task."idempotency_key" IS '连接内幂等键。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。';
COMMENT ON COLUMN application.provisioning_task."status" IS '待执行、领取、成功、重试、终止、结果未知或被新版本替代。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN application.provisioning_task."attempts" IS '尝试次数。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。';
COMMENT ON COLUMN application.provisioning_task."available_at" IS '下一次允许领取时间。 设计场景：支持延迟执行和失败后的退避重试，后台只能领取已经到可执行时间的任务。';
COMMENT ON COLUMN application.provisioning_task."lease_owner" IS '工作进程租约持有人。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。';
COMMENT ON COLUMN application.provisioning_task."lease_until" IS '租约到期时间。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。';
COMMENT ON COLUMN application.provisioning_task."last_error_code" IS '脱敏错误代码。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。';
COMMENT ON COLUMN application.provisioning_task."completed_at" IS '确认完成或被替代时间。 设计场景：记录业务流程完成时间，便于区分处理中与已完成；完成必须以相应业务效果落地为前提。';
COMMENT ON COLUMN application.provisioning_task."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.provisioning_task."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_provisioning_task_due ON application.provisioning_task USING btree (tenant_id, available_at, id) WHERE ((status)::text = ANY ((ARRAY['READY'::character varying, 'RETRY'::character varying])::text[]));
CREATE INDEX ix_application_provisioning_task_lease ON application.provisioning_task USING btree (tenant_id, lease_until) WHERE ((status)::text = 'CLAIMED'::text);
CREATE INDEX ix_application_provisioning_task_object ON application.provisioning_task USING btree (tenant_id, connection_id, provisioned_object_id);
CREATE INDEX ix_application_provisioning_task_run ON application.provisioning_task USING btree (tenant_id, connection_id, run_id);

-- application.role_mapping：平台角色到下游角色/组名称的明确映射；映射不自动授予本地角色或云资源权限
CREATE TABLE application.role_mapping (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 下游连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 平台企业角色。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。
    "role_id" bigint NOT NULL,
    -- 下游角色、群组或协议属性值。 设计场景：把本地角色映射成下游角色、群组或协议属性值，按目标类型选择适配，不自动授予远端资源权限。
    "target_kind" character varying(16) NOT NULL,
    -- 下游明确标识。 设计场景：把本地角色映射到下游明确的角色或群组键，不能因名称相似就授予远端权限。
    "target_key" character varying(256) NOT NULL,
    -- 映射状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "role_mapping_check" CHECK (updated_at >= created_at),
    CONSTRAINT "role_mapping_id_check" CHECK (id > 0),
    CONSTRAINT "role_mapping_pkey" PRIMARY KEY (id),
    CONSTRAINT "role_mapping_status_check" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'DISABLED'::character varying]::text[])),
    CONSTRAINT "role_mapping_target_key_check" CHECK (btrim(target_key::text) <> ''::text),
    CONSTRAINT "role_mapping_target_kind_check" CHECK (target_kind::text = ANY (ARRAY['ROLE'::character varying, 'GROUP'::character varying, 'CLAIM'::character varying]::text[])),
    CONSTRAINT "role_mapping_tenant_id_connection_id_fkey" FOREIGN KEY (tenant_id, connection_id) REFERENCES application.connection(tenant_id, id),
    CONSTRAINT "role_mapping_tenant_id_connection_id_role_id_target_kind_ta_key" UNIQUE (tenant_id, connection_id, role_id, target_kind, target_key),
    CONSTRAINT "role_mapping_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "role_mapping_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "role_mapping_tenant_id_role_id_fkey" FOREIGN KEY (tenant_id, role_id) REFERENCES access.role(tenant_id, id)
);
COMMENT ON TABLE application.role_mapping IS '平台角色到下游角色/组名称的明确映射；映射不自动授予本地角色或云资源权限';
COMMENT ON COLUMN application.role_mapping."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.role_mapping."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.role_mapping."connection_id" IS '下游连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN application.role_mapping."role_id" IS '平台企业角色。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。';
COMMENT ON COLUMN application.role_mapping."target_kind" IS '下游角色、群组或协议属性值。 设计场景：把本地角色映射成下游角色、群组或协议属性值，按目标类型选择适配，不自动授予远端资源权限。';
COMMENT ON COLUMN application.role_mapping."target_key" IS '下游明确标识。 设计场景：把本地角色映射到下游明确的角色或群组键，不能因名称相似就授予远端权限。';
COMMENT ON COLUMN application.role_mapping."status" IS '映射状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN application.role_mapping."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.role_mapping."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_application_role_mapping_role ON application.role_mapping USING btree (tenant_id, role_id);

-- application.security_policy：企业应用附加认证策略；与企业策略取更严格有效要求，不能借应用策略放宽企业限制
CREATE TABLE application.security_policy (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 策略对应的企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 允许主认证方式，按认证证据检查而不是只看登录按钮。 设计场景：同一用户可能有多种登录方式，进入企业或应用时检查实际认证证据属于允许集合。
    "allowed_primary_methods" character varying(24)[] DEFAULT ARRAY['PASSWORD'::character varying(24), 'SMS'::character varying(24), 'EXTERNAL'::character varying(24), 'PASSKEY'::character varying(24)] NOT NULL,
    -- 允许的加强验证证据类型；恢复流程仍受其用途限制。 设计场景：限制哪些加强验证方式能满足当前策略，不能把短信、恢复流程或任意扫码自动认定为合格 MFA。
    "allowed_mfa_methods" character varying(24)[] DEFAULT ARRAY['TOTP'::character varying(24), 'PASSKEY'::character varying(24)] NOT NULL,
    -- 普通成员访问此应用是否也强制加强验证；管理员强制规则独立成立。 设计场景：企业或应用可以要求普通成员也加强验证，管理员必须 MFA 的规则仍独立成立。
    "require_member_mfa" boolean DEFAULT false NOT NULL,
    -- 是否要求具有抗钓鱼能力的可验证证据。 设计场景：高敏感应用要求具有抗钓鱼能力的认证证据，不能仅凭做过任何第二步验证就满足。
    "require_phishing_resistance" boolean DEFAULT false NOT NULL,
    -- 敏感或应用准入操作认可的最近认证时长。 设计场景：改密、绑因子或访问敏感应用前要求重新认证，避免多年有效的会话直接执行高风险操作。
    "recent_auth_seconds" integer DEFAULT 900 NOT NULL,
    -- 应用访问空闲最长时长。 设计场景：不同企业或应用可以要求不同空闲期限，进入时按有效的更严格策略计算。
    "idle_timeout_seconds" integer DEFAULT 1800 NOT NULL,
    -- 应用访问绝对最长时长。 设计场景：限定最长连续使用时长，防止活跃访问或刷新令牌让会话无限延期。
    "absolute_timeout_seconds" integer DEFAULT 43200 NOT NULL,
    -- 并发会话上限；空表示本策略不加限制。 设计场景：控制同一身份允许同时使用的会话数，并发创建会话时需原子检查上限。
    "max_concurrent_sessions" integer,
    -- 达到并发限制时拒绝新会话或撤销最旧会话。 设计场景：达到会话上限时明确是拒绝新登录还是淘汰旧会话，避免不同客户端表现不一致。
    "concurrency_action" character varying(16) DEFAULT 'REJECT_NEW'::character varying NOT NULL,
    -- 可信设备最长认可时间；零表示不认可免重复验证。 设计场景：限定设备信任免重复验证的窗口，到期重新核验；可信设备不能绕过企业最新策略。
    "trusted_device_seconds" integer DEFAULT 0 NOT NULL,
    -- 受控风险规则参数，不保存凭据、关系或任意执行代码。 设计场景：配置可解释的风险判定条件，在异常登录时要求额外验证或拒绝，不接受任意执行代码。
    "risk_rules" jsonb DEFAULT '{}'::jsonb NOT NULL,
    -- 安全策略版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "security_policy_absolute_timeout_seconds_check" CHECK (absolute_timeout_seconds > 0),
    CONSTRAINT "security_policy_allowed_mfa_methods_check" CHECK (cardinality(allowed_mfa_methods) > 0 AND array_position(allowed_mfa_methods, NULL::character varying) IS NULL AND allowed_mfa_methods <@ ARRAY['TOTP'::character varying(24), 'PASSKEY'::character varying(24)]),
    CONSTRAINT "security_policy_allowed_primary_methods_check" CHECK (cardinality(allowed_primary_methods) > 0 AND array_position(allowed_primary_methods, NULL::character varying) IS NULL AND allowed_primary_methods <@ ARRAY['PASSWORD'::character varying(24), 'SMS'::character varying(24), 'EXTERNAL'::character varying(24), 'PASSKEY'::character varying(24)]),
    CONSTRAINT "security_policy_check" CHECK (updated_at >= created_at),
    CONSTRAINT "security_policy_check1" CHECK (absolute_timeout_seconds >= idle_timeout_seconds),
    CONSTRAINT "security_policy_check2" CHECK (NOT require_phishing_resistance OR require_member_mfa AND ('PASSKEY'::text = ANY (allowed_mfa_methods::text[]))),
    CONSTRAINT "security_policy_concurrency_action_check" CHECK (concurrency_action::text = ANY (ARRAY['REJECT_NEW'::character varying, 'REVOKE_OLDEST'::character varying]::text[])),
    CONSTRAINT "security_policy_id_check" CHECK (id > 0),
    CONSTRAINT "security_policy_idle_timeout_seconds_check" CHECK (idle_timeout_seconds > 0),
    CONSTRAINT "security_policy_max_concurrent_sessions_check" CHECK (max_concurrent_sessions > 0),
    CONSTRAINT "security_policy_pkey" PRIMARY KEY (id),
    CONSTRAINT "security_policy_recent_auth_seconds_check" CHECK (recent_auth_seconds > 0),
    CONSTRAINT "security_policy_risk_rules_check" CHECK (jsonb_typeof(risk_rules) = 'object'::text),
    CONSTRAINT "security_policy_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "security_policy_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "security_policy_tenant_id_tenant_application_id_fkey" FOREIGN KEY (tenant_id, tenant_application_id) REFERENCES application.tenant_application(tenant_id, id),
    CONSTRAINT "security_policy_tenant_id_tenant_application_id_key" UNIQUE (tenant_id, tenant_application_id),
    CONSTRAINT "security_policy_trusted_device_seconds_check" CHECK (trusted_device_seconds >= 0),
    CONSTRAINT "security_policy_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE application.security_policy IS '企业应用附加认证策略；与企业策略取更严格有效要求，不能借应用策略放宽企业限制';
COMMENT ON COLUMN application.security_policy."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN application.security_policy."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN application.security_policy."tenant_application_id" IS '策略对应的企业应用。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN application.security_policy."allowed_primary_methods" IS '允许主认证方式，按认证证据检查而不是只看登录按钮。 设计场景：同一用户可能有多种登录方式，进入企业或应用时检查实际认证证据属于允许集合。';
COMMENT ON COLUMN application.security_policy."allowed_mfa_methods" IS '允许的加强验证证据类型；恢复流程仍受其用途限制。 设计场景：限制哪些加强验证方式能满足当前策略，不能把短信、恢复流程或任意扫码自动认定为合格 MFA。';
COMMENT ON COLUMN application.security_policy."require_member_mfa" IS '普通成员访问此应用是否也强制加强验证；管理员强制规则独立成立。 设计场景：企业或应用可以要求普通成员也加强验证，管理员必须 MFA 的规则仍独立成立。';
COMMENT ON COLUMN application.security_policy."require_phishing_resistance" IS '是否要求具有抗钓鱼能力的可验证证据。 设计场景：高敏感应用要求具有抗钓鱼能力的认证证据，不能仅凭做过任何第二步验证就满足。';
COMMENT ON COLUMN application.security_policy."recent_auth_seconds" IS '敏感或应用准入操作认可的最近认证时长。 设计场景：改密、绑因子或访问敏感应用前要求重新认证，避免多年有效的会话直接执行高风险操作。';
COMMENT ON COLUMN application.security_policy."idle_timeout_seconds" IS '应用访问空闲最长时长。 设计场景：不同企业或应用可以要求不同空闲期限，进入时按有效的更严格策略计算。';
COMMENT ON COLUMN application.security_policy."absolute_timeout_seconds" IS '应用访问绝对最长时长。 设计场景：限定最长连续使用时长，防止活跃访问或刷新令牌让会话无限延期。';
COMMENT ON COLUMN application.security_policy."max_concurrent_sessions" IS '并发会话上限；空表示本策略不加限制。 设计场景：控制同一身份允许同时使用的会话数，并发创建会话时需原子检查上限。';
COMMENT ON COLUMN application.security_policy."concurrency_action" IS '达到并发限制时拒绝新会话或撤销最旧会话。 设计场景：达到会话上限时明确是拒绝新登录还是淘汰旧会话，避免不同客户端表现不一致。';
COMMENT ON COLUMN application.security_policy."trusted_device_seconds" IS '可信设备最长认可时间；零表示不认可免重复验证。 设计场景：限定设备信任免重复验证的窗口，到期重新核验；可信设备不能绕过企业最新策略。';
COMMENT ON COLUMN application.security_policy."risk_rules" IS '受控风险规则参数，不保存凭据、关系或任意执行代码。 设计场景：配置可解释的风险判定条件，在异常登录时要求额外验证或拒绝，不接受任意执行代码。';
COMMENT ON COLUMN application.security_policy."version" IS '安全策略版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN application.security_policy."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN application.security_policy."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';

-- audit.retention_policy：企业数据保留策略；时长是配置而非通用合规结论，法律保留和实际删除审批由授权用例执行。
CREATE TABLE audit.retention_policy (
    -- 应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；同企业关联和行级隔离的边界。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 数据类别；不允许任意表名驱动动态删除。 设计场景：按受控类别选择需要导出、归档或清理的数据，避免把任意表名变成后台删除命令。
    "data_category" character varying(32) NOT NULL,
    -- 最低保留天数。 设计场景：依据已配置的保留要求计算最早可清理范围；执行前复核当前策略，不能仅按记录年龄直接删除。
    "retain_days" integer NOT NULL,
    -- 到期清理前是否必须完成并核验归档。 设计场景：要求先成功归档并核验产物，再清理原始记录，避免删除后才发现归档不可恢复。
    "archive_before_purge" boolean DEFAULT true NOT NULL,
    -- 暂停到期删除的保留标志，启用后任务执行必须阻止清理。 设计场景：争议或调查期间暂停到期清理，即使已经生成清理任务，执行时也必须重新检查此标志。
    "legal_hold" boolean DEFAULT false NOT NULL,
    -- 策略状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 配置或修订策略的账号。 设计场景：记录谁调整了保留策略，发生过度保留或误清理时可追溯变更责任。
    "configured_by_account_id" bigint NOT NULL,
    -- 配置人在本企业的身份。 设计场景：明确策略配置者在目标企业中的管理身份，不能借另一家企业的管理员身份操作。
    "configured_by_member_id" bigint NOT NULL,
    -- 策略版本，执行前重新检查当前保留要求，不能用旧快照缩短保留。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近修改时间，由应用更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "retention_policy_check" CHECK (updated_at >= created_at),
    CONSTRAINT "retention_policy_configured_by_account_id_fkey" FOREIGN KEY (configured_by_account_id) REFERENCES directory.account(id),
    CONSTRAINT "retention_policy_data_category_check" CHECK (data_category::text = ANY (ARRAY['AUDIT_EVENT'::character varying, 'DOMAIN_EVENT'::character varying, 'NOTIFICATION'::character varying, 'EXPORT_ARTIFACT'::character varying]::text[])),
    CONSTRAINT "retention_policy_id_check" CHECK (id > 0),
    CONSTRAINT "retention_policy_pkey" PRIMARY KEY (id),
    CONSTRAINT "retention_policy_retain_days_check" CHECK (retain_days > 0),
    CONSTRAINT "retention_policy_status_check" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'SUSPENDED'::character varying]::text[])),
    CONSTRAINT "retention_policy_tenant_id_configured_by_member_id_configu_fkey" FOREIGN KEY (tenant_id, configured_by_member_id, configured_by_account_id) REFERENCES directory.membership(tenant_id, id, account_id),
    CONSTRAINT "retention_policy_tenant_id_data_category_key" UNIQUE (tenant_id, data_category),
    CONSTRAINT "retention_policy_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "retention_policy_tenant_id_id_data_category_key" UNIQUE (tenant_id, id, data_category),
    CONSTRAINT "retention_policy_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "retention_policy_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE audit.retention_policy IS '企业数据保留策略；时长是配置而非通用合规结论，法律保留和实际删除审批由授权用例执行。';
COMMENT ON COLUMN audit.retention_policy."id" IS '应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN audit.retention_policy."tenant_id" IS '所属企业；同企业关联和行级隔离的边界。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN audit.retention_policy."data_category" IS '数据类别；不允许任意表名驱动动态删除。 设计场景：按受控类别选择需要导出、归档或清理的数据，避免把任意表名变成后台删除命令。';
COMMENT ON COLUMN audit.retention_policy."retain_days" IS '最低保留天数。 设计场景：依据已配置的保留要求计算最早可清理范围；执行前复核当前策略，不能仅按记录年龄直接删除。';
COMMENT ON COLUMN audit.retention_policy."archive_before_purge" IS '到期清理前是否必须完成并核验归档。 设计场景：要求先成功归档并核验产物，再清理原始记录，避免删除后才发现归档不可恢复。';
COMMENT ON COLUMN audit.retention_policy."legal_hold" IS '暂停到期删除的保留标志，启用后任务执行必须阻止清理。 设计场景：争议或调查期间暂停到期清理，即使已经生成清理任务，执行时也必须重新检查此标志。';
COMMENT ON COLUMN audit.retention_policy."status" IS '策略状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN audit.retention_policy."configured_by_account_id" IS '配置或修订策略的账号。 设计场景：记录谁调整了保留策略，发生过度保留或误清理时可追溯变更责任。';
COMMENT ON COLUMN audit.retention_policy."configured_by_member_id" IS '配置人在本企业的身份。 设计场景：明确策略配置者在目标企业中的管理身份，不能借另一家企业的管理员身份操作。';
COMMENT ON COLUMN audit.retention_policy."version" IS '策略版本，执行前重新检查当前保留要求，不能用旧快照缩短保留。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN audit.retention_policy."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN audit.retention_policy."updated_at" IS '最近修改时间，由应用更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_retention_configurer ON audit.retention_policy USING btree (configured_by_account_id);
CREATE INDEX ix_retention_configurer_member ON audit.retention_policy USING btree (tenant_id, configured_by_member_id, configured_by_account_id);

-- audit.data_operation：归档、到期清理和受权导出任务；个人资料导出与企业审计导出分型，不作为任意 SQL 执行队列。
CREATE TABLE audit.data_operation (
    -- 应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 企业任务边界；个人账号资料导出可为空。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint,
    -- 明确任务类型：归档、清理、审计导出、个人资料导出。 设计场景：显式区分创建、更新、停用、归档或清理等动作，重试继续相同意图，不根据当前显示文案猜测操作。
    "operation" character varying(24) NOT NULL,
    -- 处理的数据类别，不接受任意 schema 或表名。 设计场景：按受控类别选择需要导出、归档或清理的数据，避免把任意表名变成后台删除命令。
    "data_category" character varying(32) NOT NULL,
    -- 归档或清理所依据的同企业保留策略。 设计场景：让清理或归档任务有明确的策略依据，执行前确认策略适用于同一企业和数据类别。
    "retention_policy_id" bigint,
    -- 申请时策略版本；执行时必须复核当前版本和 legal_hold。 设计场景：任务排队期间保留策略可能变更，领取和执行时检测差异并重新核验，避免按过期条件删除。
    "retention_version" bigint,
    -- 申请人；个人导出只能处理经过验证的本人账号。 设计场景：区分人工发起和允许的后台操作，追溯请求来源；保存账号不替代执行时的权限复核。
    "requested_by_account_id" bigint NOT NULL,
    -- 企业任务申请人的同企业成员身份。 设计场景：明确申请人是在什么企业身份下发起操作，避免跨企业借用另一成员的管理资格。
    "requested_by_member_id" bigint,
    -- 个人资料导出的目标账号，必须等于申请人。 设计场景：个人资料导出只面向被授权的本人，不能借个人导出入口读取其他账号或企业业务数据。
    "subject_account_id" bigint,
    -- 授权或复核任务的账号；不表示此字段本身授予执行权限。 设计场景：记录同意执行或订阅的责任账号，真正执行前仍核验当前权限和授权期限。
    "authorized_by_account_id" bigint NOT NULL,
    -- 企业授权人的同企业成员身份。 设计场景：把企业授权限定到明确的成员身份，成员离职后不能继续依赖过去的授权记录无限执行。
    "authorized_by_member_id" bigint,
    -- 权限核验通过时间。 设计场景：记录任务或订阅何时完成权限核验，用于追踪审批链和有效窗口。
    "authorized_at" timestamp with time zone NOT NULL,
    -- 任务授权截止时间，领取及产物下载都重新核验。 设计场景：长时间排队的任务或晚于批准期的下载需要重新授权，不能将一次审批永久复用。
    "authorization_expires_at" timestamp with time zone NOT NULL,
    -- 作用域内唯一任务幂等键。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。
    "idempotency_key" character varying(200) NOT NULL,
    -- 处理时间范围起点。 设计场景：限定数据处理范围的起点，便于审查与归档核对；边界包含规则由用例统一定义。
    "range_start" timestamp with time zone,
    -- 处理时间范围终点；到期清理必须满足策略阈值。 设计场景：限定本次数据处理的终点，避免新产生的数据被旧清理任务一并删除。
    "range_end" timestamp with time zone,
    -- 经授权的对象筛选快照，不保存任意 SQL；个人导出不得扩大到其他企业业务资料。 设计场景：冻结经过授权的对象筛选条件，执行时只能在当前权限内处理，禁止任意 SQL 或扩大范围。
    "selection" jsonb DEFAULT '{}'::jsonb NOT NULL,
    -- 清理前已成功的同企业归档任务；应用验证类型、覆盖范围和产物完整性。 设计场景：删除前关联已成功的归档任务，核实其覆盖范围和校验结果，避免以无关归档作为清理依据。
    "archive_operation_id" bigint,
    -- 受保护对象存储引用，不是公开 URL，不含下载令牌。 设计场景：后台产物通过受保护引用访问，下载时再次检查权限，避免把导出数据暴露为永久公共链接。
    "artifact_ref" text,
    -- 产物内容 SHA-256，用于归档和恢复校验。 设计场景：传输或恢复归档时核对内容是否完整，不能只因文件存在就认定归档成功。
    "artifact_sha256" bytea,
    -- 导出或归档产物访问截止时间，不表示相关审计立即删除。 设计场景：导出链接与产物访问有单独有效期，减少长期暴露；不等同原始审计数据保留期限。
    "artifact_expires_at" timestamp with time zone,
    -- 任务状态：READY 待执行，CLAIMED 已领取，RETRY 待重试，SUCCEEDED 完成，DEAD 终止，CANCELLED 取消；若允许 UNKNOWN 则表示外部结果待对账。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'READY'::character varying NOT NULL,
    -- 已发起的执行次数；领取事务递增。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。
    "attempts" integer DEFAULT 0 NOT NULL,
    -- 自动执行次数上限；超过上限需明确处理，不无限重试。 设计场景：限制自动执行或校验次数，避免无限重试和暴力猜测；具体场景由所在表决定。
    "max_attempts" integer DEFAULT 8 NOT NULL,
    -- 允许再次执行的最早时间。 设计场景：支持延迟执行和失败后的退避重试，后台只能领取已经到可执行时间的任务。
    "available_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 本次领取的唯一租约标识；每次领取重新生成，不能只使用固定进程名。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。
    "lease_owner" character varying(100),
    -- 租约截止时间；完成更新必须同时比较租约标识和截止时间。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。
    "lease_until" timestamp with time zone,
    -- 不含请求正文、令牌或个人资料的结构化错误码。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。
    "last_error_code" character varying(100),
    -- 进入完成、终止或取消状态的时间。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。
    "finished_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近修改时间，由应用更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "data_operation_artifact_sha256_check" CHECK (artifact_sha256 IS NULL OR octet_length(artifact_sha256) = 32),
    CONSTRAINT "data_operation_attempts_check" CHECK (attempts >= 0),
    CONSTRAINT "data_operation_authorized_by_account_id_fkey" FOREIGN KEY (authorized_by_account_id) REFERENCES directory.account(id),
    CONSTRAINT "data_operation_check" CHECK (operation::text = 'PERSONAL_EXPORT'::text AND tenant_id IS NULL AND subject_account_id IS NOT NULL AND subject_account_id = requested_by_account_id AND authorized_by_account_id = requested_by_account_id AND data_category::text = 'PERSONAL_PROFILE'::text AND requested_by_member_id IS NULL AND authorized_by_member_id IS NULL OR operation::text <> 'PERSONAL_EXPORT'::text AND tenant_id IS NOT NULL AND requested_by_member_id IS NOT NULL AND authorized_by_member_id IS NOT NULL AND subject_account_id IS NULL AND data_category::text <> 'PERSONAL_PROFILE'::text),
    CONSTRAINT "data_operation_check1" CHECK ((operation::text = ANY (ARRAY['ARCHIVE'::character varying, 'PURGE'::character varying]::text[])) AND retention_policy_id IS NOT NULL AND retention_version IS NOT NULL AND range_start IS NOT NULL AND range_end IS NOT NULL OR (operation::text = ANY (ARRAY['AUDIT_EXPORT'::character varying, 'PERSONAL_EXPORT'::character varying]::text[])) AND retention_policy_id IS NULL AND retention_version IS NULL),
    CONSTRAINT "data_operation_check10" CHECK ((status::text = ANY (ARRAY['SUCCEEDED'::character varying, 'DEAD'::character varying, 'CANCELLED'::character varying]::text[])) = (finished_at IS NOT NULL)),
    CONSTRAINT "data_operation_check11" CHECK (finished_at IS NULL OR finished_at >= created_at),
    CONSTRAINT "data_operation_check12" CHECK (updated_at >= created_at),
    CONSTRAINT "data_operation_check2" CHECK (operation::text <> 'AUDIT_EXPORT'::text OR data_category::text = 'AUDIT_EVENT'::text),
    CONSTRAINT "data_operation_check3" CHECK (authorization_expires_at > authorized_at),
    CONSTRAINT "data_operation_check4" CHECK ((range_start IS NULL) = (range_end IS NULL)),
    CONSTRAINT "data_operation_check5" CHECK (range_end IS NULL OR range_end > range_start),
    CONSTRAINT "data_operation_check6" CHECK (archive_operation_id IS NULL OR operation::text = 'PURGE'::text AND archive_operation_id <> id),
    CONSTRAINT "data_operation_check7" CHECK (artifact_ref IS NULL AND artifact_sha256 IS NULL AND artifact_expires_at IS NULL OR artifact_ref IS NOT NULL AND btrim(artifact_ref) <> ''::text AND artifact_sha256 IS NOT NULL AND artifact_expires_at IS NOT NULL AND artifact_expires_at > created_at),
    CONSTRAINT "data_operation_check8" CHECK (status::text <> 'SUCCEEDED'::text OR operation::text = 'PURGE'::text OR artifact_ref IS NOT NULL),
    CONSTRAINT "data_operation_check9" CHECK (status::text = 'CLAIMED'::text AND lease_owner IS NOT NULL AND btrim(lease_owner::text) <> ''::text AND lease_until IS NOT NULL AND lease_until > updated_at OR status::text <> 'CLAIMED'::text AND lease_owner IS NULL AND lease_until IS NULL),
    CONSTRAINT "data_operation_data_category_check" CHECK (data_category::text = ANY (ARRAY['AUDIT_EVENT'::character varying, 'DOMAIN_EVENT'::character varying, 'NOTIFICATION'::character varying, 'EXPORT_ARTIFACT'::character varying, 'PERSONAL_PROFILE'::character varying]::text[])),
    CONSTRAINT "data_operation_id_check" CHECK (id > 0),
    CONSTRAINT "data_operation_idempotency_key_check" CHECK (btrim(idempotency_key::text) <> ''::text),
    CONSTRAINT "data_operation_max_attempts_check" CHECK (max_attempts > 0),
    CONSTRAINT "data_operation_operation_check" CHECK (operation::text = ANY (ARRAY['ARCHIVE'::character varying, 'PURGE'::character varying, 'AUDIT_EXPORT'::character varying, 'PERSONAL_EXPORT'::character varying]::text[])),
    CONSTRAINT "data_operation_pkey" PRIMARY KEY (id),
    CONSTRAINT "data_operation_requested_by_account_id_fkey" FOREIGN KEY (requested_by_account_id) REFERENCES directory.account(id),
    CONSTRAINT "data_operation_retention_version_check" CHECK (retention_version >= 0),
    CONSTRAINT "data_operation_selection_check" CHECK (jsonb_typeof(selection) = 'object'::text),
    CONSTRAINT "data_operation_status_check" CHECK (status::text = ANY (ARRAY['READY'::character varying, 'CLAIMED'::character varying, 'RETRY'::character varying, 'SUCCEEDED'::character varying, 'DEAD'::character varying, 'CANCELLED'::character varying]::text[])),
    CONSTRAINT "data_operation_subject_account_id_fkey" FOREIGN KEY (subject_account_id) REFERENCES directory.account(id),
    CONSTRAINT "data_operation_tenant_id_archive_operation_id_fkey" FOREIGN KEY (tenant_id, archive_operation_id) REFERENCES audit.data_operation(tenant_id, id),
    CONSTRAINT "data_operation_tenant_id_authorized_by_member_id_authorize_fkey" FOREIGN KEY (tenant_id, authorized_by_member_id, authorized_by_account_id) REFERENCES directory.membership(tenant_id, id, account_id),
    CONSTRAINT "data_operation_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "data_operation_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "data_operation_tenant_id_requested_by_account_id_idempotenc_key" UNIQUE NULLS NOT DISTINCT (tenant_id, requested_by_account_id, idempotency_key),
    CONSTRAINT "data_operation_tenant_id_requested_by_member_id_requested__fkey" FOREIGN KEY (tenant_id, requested_by_member_id, requested_by_account_id) REFERENCES directory.membership(tenant_id, id, account_id),
    CONSTRAINT "data_operation_tenant_id_retention_policy_id_data_category_fkey" FOREIGN KEY (tenant_id, retention_policy_id, data_category) REFERENCES audit.retention_policy(tenant_id, id, data_category)
);
COMMENT ON TABLE audit.data_operation IS '归档、到期清理和受权导出任务；个人资料导出与企业审计导出分型，不作为任意 SQL 执行队列。';
COMMENT ON COLUMN audit.data_operation."id" IS '应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN audit.data_operation."tenant_id" IS '企业任务边界；个人账号资料导出可为空。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN audit.data_operation."operation" IS '明确任务类型：归档、清理、审计导出、个人资料导出。 设计场景：显式区分创建、更新、停用、归档或清理等动作，重试继续相同意图，不根据当前显示文案猜测操作。';
COMMENT ON COLUMN audit.data_operation."data_category" IS '处理的数据类别，不接受任意 schema 或表名。 设计场景：按受控类别选择需要导出、归档或清理的数据，避免把任意表名变成后台删除命令。';
COMMENT ON COLUMN audit.data_operation."retention_policy_id" IS '归档或清理所依据的同企业保留策略。 设计场景：让清理或归档任务有明确的策略依据，执行前确认策略适用于同一企业和数据类别。';
COMMENT ON COLUMN audit.data_operation."retention_version" IS '申请时策略版本；执行时必须复核当前版本和 legal_hold。 设计场景：任务排队期间保留策略可能变更，领取和执行时检测差异并重新核验，避免按过期条件删除。';
COMMENT ON COLUMN audit.data_operation."requested_by_account_id" IS '申请人；个人导出只能处理经过验证的本人账号。 设计场景：区分人工发起和允许的后台操作，追溯请求来源；保存账号不替代执行时的权限复核。';
COMMENT ON COLUMN audit.data_operation."requested_by_member_id" IS '企业任务申请人的同企业成员身份。 设计场景：明确申请人是在什么企业身份下发起操作，避免跨企业借用另一成员的管理资格。';
COMMENT ON COLUMN audit.data_operation."subject_account_id" IS '个人资料导出的目标账号，必须等于申请人。 设计场景：个人资料导出只面向被授权的本人，不能借个人导出入口读取其他账号或企业业务数据。';
COMMENT ON COLUMN audit.data_operation."authorized_by_account_id" IS '授权或复核任务的账号；不表示此字段本身授予执行权限。 设计场景：记录同意执行或订阅的责任账号，真正执行前仍核验当前权限和授权期限。';
COMMENT ON COLUMN audit.data_operation."authorized_by_member_id" IS '企业授权人的同企业成员身份。 设计场景：把企业授权限定到明确的成员身份，成员离职后不能继续依赖过去的授权记录无限执行。';
COMMENT ON COLUMN audit.data_operation."authorized_at" IS '权限核验通过时间。 设计场景：记录任务或订阅何时完成权限核验，用于追踪审批链和有效窗口。';
COMMENT ON COLUMN audit.data_operation."authorization_expires_at" IS '任务授权截止时间，领取及产物下载都重新核验。 设计场景：长时间排队的任务或晚于批准期的下载需要重新授权，不能将一次审批永久复用。';
COMMENT ON COLUMN audit.data_operation."idempotency_key" IS '作用域内唯一任务幂等键。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。';
COMMENT ON COLUMN audit.data_operation."range_start" IS '处理时间范围起点。 设计场景：限定数据处理范围的起点，便于审查与归档核对；边界包含规则由用例统一定义。';
COMMENT ON COLUMN audit.data_operation."range_end" IS '处理时间范围终点；到期清理必须满足策略阈值。 设计场景：限定本次数据处理的终点，避免新产生的数据被旧清理任务一并删除。';
COMMENT ON COLUMN audit.data_operation."selection" IS '经授权的对象筛选快照，不保存任意 SQL；个人导出不得扩大到其他企业业务资料。 设计场景：冻结经过授权的对象筛选条件，执行时只能在当前权限内处理，禁止任意 SQL 或扩大范围。';
COMMENT ON COLUMN audit.data_operation."archive_operation_id" IS '清理前已成功的同企业归档任务；应用验证类型、覆盖范围和产物完整性。 设计场景：删除前关联已成功的归档任务，核实其覆盖范围和校验结果，避免以无关归档作为清理依据。';
COMMENT ON COLUMN audit.data_operation."artifact_ref" IS '受保护对象存储引用，不是公开 URL，不含下载令牌。 设计场景：后台产物通过受保护引用访问，下载时再次检查权限，避免把导出数据暴露为永久公共链接。';
COMMENT ON COLUMN audit.data_operation."artifact_sha256" IS '产物内容 SHA-256，用于归档和恢复校验。 设计场景：传输或恢复归档时核对内容是否完整，不能只因文件存在就认定归档成功。';
COMMENT ON COLUMN audit.data_operation."artifact_expires_at" IS '导出或归档产物访问截止时间，不表示相关审计立即删除。 设计场景：导出链接与产物访问有单独有效期，减少长期暴露；不等同原始审计数据保留期限。';
COMMENT ON COLUMN audit.data_operation."status" IS '任务状态：READY 待执行，CLAIMED 已领取，RETRY 待重试，SUCCEEDED 完成，DEAD 终止，CANCELLED 取消；若允许 UNKNOWN 则表示外部结果待对账。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN audit.data_operation."attempts" IS '已发起的执行次数；领取事务递增。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。';
COMMENT ON COLUMN audit.data_operation."max_attempts" IS '自动执行次数上限；超过上限需明确处理，不无限重试。 设计场景：限制自动执行或校验次数，避免无限重试和暴力猜测；具体场景由所在表决定。';
COMMENT ON COLUMN audit.data_operation."available_at" IS '允许再次执行的最早时间。 设计场景：支持延迟执行和失败后的退避重试，后台只能领取已经到可执行时间的任务。';
COMMENT ON COLUMN audit.data_operation."lease_owner" IS '本次领取的唯一租约标识；每次领取重新生成，不能只使用固定进程名。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。';
COMMENT ON COLUMN audit.data_operation."lease_until" IS '租约截止时间；完成更新必须同时比较租约标识和截止时间。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。';
COMMENT ON COLUMN audit.data_operation."last_error_code" IS '不含请求正文、令牌或个人资料的结构化错误码。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。';
COMMENT ON COLUMN audit.data_operation."finished_at" IS '进入完成、终止或取消状态的时间。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。';
COMMENT ON COLUMN audit.data_operation."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN audit.data_operation."updated_at" IS '最近修改时间，由应用更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_data_operation_archive ON audit.data_operation USING btree (tenant_id, archive_operation_id) WHERE (archive_operation_id IS NOT NULL);
CREATE INDEX ix_data_operation_authorizer ON audit.data_operation USING btree (authorized_by_account_id);
CREATE INDEX ix_data_operation_authorizer_member ON audit.data_operation USING btree (tenant_id, authorized_by_member_id, authorized_by_account_id) WHERE (authorized_by_member_id IS NOT NULL);
CREATE INDEX ix_data_operation_due ON audit.data_operation USING btree (tenant_id, available_at, id) WHERE ((status)::text = ANY ((ARRAY['READY'::character varying, 'RETRY'::character varying])::text[]));
CREATE INDEX ix_data_operation_lease ON audit.data_operation USING btree (tenant_id, lease_until, id) WHERE ((status)::text = 'CLAIMED'::text);
CREATE INDEX ix_data_operation_requester ON audit.data_operation USING btree (requested_by_account_id, created_at DESC, id DESC);
CREATE INDEX ix_data_operation_requester_member ON audit.data_operation USING btree (tenant_id, requested_by_member_id, requested_by_account_id) WHERE (requested_by_member_id IS NOT NULL);
CREATE INDEX ix_data_operation_retention ON audit.data_operation USING btree (tenant_id, retention_policy_id) WHERE (retention_policy_id IS NOT NULL);
CREATE INDEX ix_data_operation_subject ON audit.data_operation USING btree (subject_account_id) WHERE (subject_account_id IS NOT NULL);

-- audit.data_operation_execution：追加式归档、清理和导出执行证据；业务数据清理后仍保留操作范围、数量和结果，不保存被删除的敏感原文。
CREATE TABLE audit.data_operation_execution (
    -- 执行记录雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 企业任务边界；个人导出为空。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint,
    -- 被执行的数据任务。 设计场景：把每次执行证据归入同一数据任务，重试和接管后仍能还原整条执行历史。
    "operation_id" bigint NOT NULL,
    -- 此任务的执行序号。 设计场景：将每一次执行独立编号，重试后仍能还原前一次失败、超时或成功的经过。
    "attempt_no" integer NOT NULL,
    -- 受控执行组件标识。 设计场景：识别实际负责导出、归档或清理的受控组件，定位不同执行器的行为和故障。
    "executor_code" character varying(100) NOT NULL,
    -- 执行时唯一租约标识。 设计场景：区分同一任务不同轮次的执行权，防止旧执行器在任务已被接管后迟到回写结果。
    "lease_token" character varying(100) NOT NULL,
    -- 本次执行结果；未知必须核查，不能直接再次删除。 设计场景：区分成功、拒绝、失败和结果未知等执行结果；不能把超时直接当作远端未执行。
    "result" character varying(16) NOT NULL,
    -- 实际处理的记录或对象数量。 设计场景：对照审批范围核对实际处理量，识别异常大范围操作，不能用预估数量冒充执行结果。
    "affected_count" bigint DEFAULT 0 NOT NULL,
    -- 脱敏处理范围和保留策略核验摘要，不复制原始员工资料。 设计场景：在不复制敏感原文的前提下保留执行范围，业务数据清理后仍可解释处理了什么。
    "scope_summary" jsonb DEFAULT '{}'::jsonb NOT NULL,
    -- 结构化错误代码。 设计场景：用稳定且脱敏的分类定位失败和选择补偿方式；不把凭据、完整响应或个人资料写入错误字段。
    "error_code" character varying(100),
    -- 受控执行证据或归档清单引用，不包含访问令牌。 设计场景：关联受保护的核验材料或执行证据，审查时可以回溯；普通接口不直接暴露证据内容与访问凭据。
    "evidence_ref" text,
    -- 执行开始时间。 设计场景：记录一次执行真正开始的时刻，用于识别排队与执行耗时、定位长期运行任务。
    "started_at" timestamp with time zone NOT NULL,
    -- 执行结果形成时间。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。
    "finished_at" timestamp with time zone NOT NULL,
    -- 记录追加时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "data_operation_execution_affected_count_check" CHECK (affected_count >= 0),
    CONSTRAINT "data_operation_execution_attempt_no_check" CHECK (attempt_no > 0),
    CONSTRAINT "data_operation_execution_check" CHECK (finished_at >= started_at),
    CONSTRAINT "data_operation_execution_executor_code_check" CHECK (btrim(executor_code::text) <> ''::text),
    CONSTRAINT "data_operation_execution_id_check" CHECK (id > 0),
    CONSTRAINT "data_operation_execution_lease_token_check" CHECK (btrim(lease_token::text) <> ''::text),
    CONSTRAINT "data_operation_execution_operation_id_attempt_no_key" UNIQUE (operation_id, attempt_no),
    CONSTRAINT "data_operation_execution_operation_id_fkey" FOREIGN KEY (operation_id) REFERENCES audit.data_operation(id),
    CONSTRAINT "data_operation_execution_pkey" PRIMARY KEY (id),
    CONSTRAINT "data_operation_execution_result_check" CHECK (result::text = ANY (ARRAY['SUCCEEDED'::character varying, 'FAILED'::character varying, 'UNKNOWN'::character varying, 'SKIPPED'::character varying]::text[])),
    CONSTRAINT "data_operation_execution_scope_summary_check" CHECK (jsonb_typeof(scope_summary) = 'object'::text),
    CONSTRAINT "data_operation_execution_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "data_operation_execution_tenant_id_operation_id_fkey" FOREIGN KEY (tenant_id, operation_id) REFERENCES audit.data_operation(tenant_id, id)
);
COMMENT ON TABLE audit.data_operation_execution IS '追加式归档、清理和导出执行证据；业务数据清理后仍保留操作范围、数量和结果，不保存被删除的敏感原文。';
COMMENT ON COLUMN audit.data_operation_execution."id" IS '执行记录雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN audit.data_operation_execution."tenant_id" IS '企业任务边界；个人导出为空。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN audit.data_operation_execution."operation_id" IS '被执行的数据任务。 设计场景：把每次执行证据归入同一数据任务，重试和接管后仍能还原整条执行历史。';
COMMENT ON COLUMN audit.data_operation_execution."attempt_no" IS '此任务的执行序号。 设计场景：将每一次执行独立编号，重试后仍能还原前一次失败、超时或成功的经过。';
COMMENT ON COLUMN audit.data_operation_execution."executor_code" IS '受控执行组件标识。 设计场景：识别实际负责导出、归档或清理的受控组件，定位不同执行器的行为和故障。';
COMMENT ON COLUMN audit.data_operation_execution."lease_token" IS '执行时唯一租约标识。 设计场景：区分同一任务不同轮次的执行权，防止旧执行器在任务已被接管后迟到回写结果。';
COMMENT ON COLUMN audit.data_operation_execution."result" IS '本次执行结果；未知必须核查，不能直接再次删除。 设计场景：区分成功、拒绝、失败和结果未知等执行结果；不能把超时直接当作远端未执行。';
COMMENT ON COLUMN audit.data_operation_execution."affected_count" IS '实际处理的记录或对象数量。 设计场景：对照审批范围核对实际处理量，识别异常大范围操作，不能用预估数量冒充执行结果。';
COMMENT ON COLUMN audit.data_operation_execution."scope_summary" IS '脱敏处理范围和保留策略核验摘要，不复制原始员工资料。 设计场景：在不复制敏感原文的前提下保留执行范围，业务数据清理后仍可解释处理了什么。';
COMMENT ON COLUMN audit.data_operation_execution."error_code" IS '结构化错误代码。 设计场景：用稳定且脱敏的分类定位失败和选择补偿方式；不把凭据、完整响应或个人资料写入错误字段。';
COMMENT ON COLUMN audit.data_operation_execution."evidence_ref" IS '受控执行证据或归档清单引用，不包含访问令牌。 设计场景：关联受保护的核验材料或执行证据，审查时可以回溯；普通接口不直接暴露证据内容与访问凭据。';
COMMENT ON COLUMN audit.data_operation_execution."started_at" IS '执行开始时间。 设计场景：记录一次执行真正开始的时刻，用于识别排队与执行耗时、定位长期运行任务。';
COMMENT ON COLUMN audit.data_operation_execution."finished_at" IS '执行结果形成时间。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。';
COMMENT ON COLUMN audit.data_operation_execution."created_at" IS '记录追加时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_data_execution_tenant_time ON audit.data_operation_execution USING btree (tenant_id, created_at DESC, id DESC);

-- identity.authentication_attempt：短期受限认证过程；不能作为已完成 MFA 的中央会话使用。
CREATE TABLE identity.authentication_attempt (
    -- 本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 未识别账号或邀请开户前可空；升格到主认证已完成状态时必须在账号锁下绑定账号和当时 epoch。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint,
    -- 业务认证用途；所属 challenge 必须使用相同用途，禁止跨用途消费。 设计场景：区分登录、改密、绑定或恢复等受限过程，证明只能在相应用途中消费，未完成 MFA 的过程不能作为完整会话。
    "purpose" character varying(32) NOT NULL,
    -- 主认证方式；允许方法见数据库约束，成功状态仍需要真实验证。 设计场景：区分密码、短信、外部身份和通行密钥等主认证方式，进入更严格应用时判断是否需要补充认证。
    "primary_method" character varying(16),
    -- 主认证证明通过时间。 设计场景：区分仅创建认证过程与已经通过主认证，未完成主认证不能进入被认可的第二步验证。
    "primary_verified_at" timestamp with time zone,
    -- 主认证成功时的账号撤销版本快照；继续 MFA/恢复及建立会话时核对当前值，不能读新值覆盖旧快照使旧认证复活。 设计场景：用户通过密码后、完成 MFA 前可能被禁用或改密；保留最初版本，在后续步骤拒绝这段旧认证，不能读取新版本覆盖它。
    "primary_auth_epoch" bigint,
    -- 所需附加因子快照；TOTP/PASSKEY，去重及是否满足目标租户/应用策略由用例重新计算，不能把短信或任意扫码自动当作MFA。 设计场景：保留本次认证还需完成的步骤，防止半认证直接升级为完整会话；最终仍复核当前策略。
    "required_factors" character varying(16)[] DEFAULT '{}'::character varying[] NOT NULL,
    -- 带 version=1 的受控 JSON 对象；保存经服务端验证的浏览器、客户端、授权请求与安全回跳关联，不信任前端声明。 设计场景：将认证过程绑定发起浏览器、客户端和合法回跳上下文，防止把另一请求的证明拿来使用。
    "request_context" jsonb NOT NULL,
    -- 有效期截止；每次使用按服务端时间检查。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone NOT NULL,
    -- 本次业务认证过程完成时间；LOGIN/REAUTHENTICATION 必须已完成主认证，其他用途的完成不自动授予中央会话。MFA 登记和恢复仍须由应用强制要求主认证。 设计场景：记录业务流程完成时间，便于区分处理中与已完成；完成必须以相应业务效果落地为前提。
    "completed_at" timestamp with time zone,
    -- 撤销时间；撤销后的记录不能参与认证或授权。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "authentication_attempt_pkey" PRIMARY KEY (id),
    CONSTRAINT "ck_authentication_attempt_completed" CHECK (completed_at IS NULL OR completed_at >= created_at AND completed_at < expires_at AND ((purpose::text <> ALL (ARRAY['LOGIN'::character varying, 'REAUTHENTICATION'::character varying]::text[])) OR primary_verified_at IS NOT NULL AND completed_at >= primary_verified_at)),
    CONSTRAINT "ck_authentication_attempt_context" CHECK (jsonb_typeof(request_context) = 'object'::text AND request_context @> '{"version": 1}'::jsonb),
    CONSTRAINT "ck_authentication_attempt_expiry" CHECK (expires_at > created_at),
    CONSTRAINT "ck_authentication_attempt_factors" CHECK (required_factors <@ ARRAY['TOTP'::character varying(16), 'PASSKEY'::character varying(16)] AND array_position(required_factors, NULL::character varying) IS NULL AND cardinality(required_factors) <= 2),
    CONSTRAINT "ck_authentication_attempt_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_authentication_attempt_method" CHECK (primary_method IS NULL OR (primary_method::text = ANY (ARRAY['PASSWORD'::character varying, 'SMS'::character varying, 'EXTERNAL'::character varying, 'PASSKEY'::character varying]::text[]))),
    CONSTRAINT "ck_authentication_attempt_primary" CHECK (primary_verified_at IS NULL AND primary_auth_epoch IS NULL OR account_id IS NOT NULL AND primary_method IS NOT NULL AND primary_verified_at IS NOT NULL AND primary_auth_epoch IS NOT NULL AND primary_auth_epoch >= 0 AND primary_verified_at >= created_at AND primary_verified_at < expires_at),
    CONSTRAINT "ck_authentication_attempt_purpose" CHECK (purpose::text = ANY (ARRAY['LOGIN'::character varying, 'REAUTHENTICATION'::character varying, 'PASSWORD_RESET'::character varying, 'IDENTIFIER_BIND'::character varying, 'IDENTIFIER_CHANGE'::character varying, 'EXTERNAL_BIND'::character varying, 'INVITATION_ACCEPT'::character varying, 'MFA_ENROLLMENT'::character varying, 'MFA_RECOVERY'::character varying, 'PASSKEY_ENROLLMENT'::character varying, 'ACCOUNT_ACTIVATION'::character varying, 'ACCOUNT_RECOVERY'::character varying, 'ACCOUNT_MERGE'::character varying, 'ACCOUNT_CLOSURE'::character varying, 'USERNAME_CHANGE'::character varying, 'DEVICE_TRUST'::character varying]::text[])),
    CONSTRAINT "ck_authentication_attempt_revoked" CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT "ck_authentication_attempt_updated" CHECK (updated_at >= created_at),
    CONSTRAINT "fk_authentication_attempt_account" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "uq_authentication_attempt_account_id" UNIQUE (account_id, id),
    CONSTRAINT "uq_authentication_attempt_id_purpose" UNIQUE (id, purpose)
);
COMMENT ON TABLE identity.authentication_attempt IS '短期受限认证过程；不能作为已完成 MFA 的中央会话使用。';
COMMENT ON COLUMN identity.authentication_attempt."id" IS '本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.authentication_attempt."account_id" IS '未识别账号或邀请开户前可空；升格到主认证已完成状态时必须在账号锁下绑定账号和当时 epoch。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.authentication_attempt."purpose" IS '业务认证用途；所属 challenge 必须使用相同用途，禁止跨用途消费。 设计场景：区分登录、改密、绑定或恢复等受限过程，证明只能在相应用途中消费，未完成 MFA 的过程不能作为完整会话。';
COMMENT ON COLUMN identity.authentication_attempt."primary_method" IS '主认证方式；允许方法见数据库约束，成功状态仍需要真实验证。 设计场景：区分密码、短信、外部身份和通行密钥等主认证方式，进入更严格应用时判断是否需要补充认证。';
COMMENT ON COLUMN identity.authentication_attempt."primary_verified_at" IS '主认证证明通过时间。 设计场景：区分仅创建认证过程与已经通过主认证，未完成主认证不能进入被认可的第二步验证。';
COMMENT ON COLUMN identity.authentication_attempt."primary_auth_epoch" IS '主认证成功时的账号撤销版本快照；继续 MFA/恢复及建立会话时核对当前值，不能读新值覆盖旧快照使旧认证复活。 设计场景：用户通过密码后、完成 MFA 前可能被禁用或改密；保留最初版本，在后续步骤拒绝这段旧认证，不能读取新版本覆盖它。';
COMMENT ON COLUMN identity.authentication_attempt."required_factors" IS '所需附加因子快照；TOTP/PASSKEY，去重及是否满足目标租户/应用策略由用例重新计算，不能把短信或任意扫码自动当作MFA。 设计场景：保留本次认证还需完成的步骤，防止半认证直接升级为完整会话；最终仍复核当前策略。';
COMMENT ON COLUMN identity.authentication_attempt."request_context" IS '带 version=1 的受控 JSON 对象；保存经服务端验证的浏览器、客户端、授权请求与安全回跳关联，不信任前端声明。 设计场景：将认证过程绑定发起浏览器、客户端和合法回跳上下文，防止把另一请求的证明拿来使用。';
COMMENT ON COLUMN identity.authentication_attempt."expires_at" IS '有效期截止；每次使用按服务端时间检查。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN identity.authentication_attempt."completed_at" IS '本次业务认证过程完成时间；LOGIN/REAUTHENTICATION 必须已完成主认证，其他用途的完成不自动授予中央会话。MFA 登记和恢复仍须由应用强制要求主认证。 设计场景：记录业务流程完成时间，便于区分处理中与已完成；完成必须以相应业务效果落地为前提。';
COMMENT ON COLUMN identity.authentication_attempt."revoked_at" IS '撤销时间；撤销后的记录不能参与认证或授权。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN identity.authentication_attempt."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.authentication_attempt."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_authentication_attempt_expiry ON identity.authentication_attempt USING btree (expires_at);

-- machine.grant：机器自身的业务权限与接口范围；协议认证成功不能代替该授权
CREATE TABLE machine.grant (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 机器主体。 设计场景：将机器凭据、授权和委托关联到稳定机器主体，轮换凭据不改变其身份与审计归属。
    "principal_id" bigint NOT NULL,
    -- 业务角色。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。
    "role_id" bigint NOT NULL,
    -- 业务资源范围。 设计场景：显式区分全企业、指定店铺或指定资源等范围；空的明细集合不能被解释为全部权限。
    "scope_mode" character varying(24) NOT NULL,
    -- 经过受控目录验证的接口范围；不等于本地资源范围。 设计场景：限制程序可调用的协议接口范围，业务资源访问仍与机器及用户的当前权限求交集。
    "oauth_scopes" character varying(120)[] NOT NULL,
    -- 授权管理员成员。 设计场景：明确授权是在目标企业中的哪位管理员身份下完成，避免跨企业借权。
    "granted_by_member_id" bigint NOT NULL,
    -- 最早有效时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。
    "valid_from" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 授权到期时间。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。
    "valid_until" timestamp with time zone,
    -- 撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "grant_check" CHECK (updated_at >= created_at),
    CONSTRAINT "grant_check1" CHECK (valid_until IS NULL OR valid_until > valid_from),
    CONSTRAINT "grant_check2" CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT "grant_id_check" CHECK (id > 0),
    CONSTRAINT "grant_oauth_scopes_check" CHECK (cardinality(oauth_scopes) > 0 AND array_position(oauth_scopes, NULL::character varying) IS NULL AND NOT ('*'::text = ANY (oauth_scopes::text[]))),
    CONSTRAINT "grant_pkey" PRIMARY KEY (id),
    CONSTRAINT "grant_scope_mode_check" CHECK (scope_mode::text = ANY (ARRAY['ALL_TENANT'::character varying, 'SELECTED_STORES'::character varying, 'SELECTED_RESOURCES'::character varying]::text[])),
    CONSTRAINT "grant_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "grant_tenant_id_granted_by_member_id_fkey" FOREIGN KEY (tenant_id, granted_by_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "grant_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "grant_tenant_id_id_principal_id_key" UNIQUE (tenant_id, id, principal_id),
    CONSTRAINT "grant_tenant_id_principal_id_fkey" FOREIGN KEY (tenant_id, principal_id) REFERENCES machine.principal(tenant_id, id),
    CONSTRAINT "grant_tenant_id_role_id_fkey" FOREIGN KEY (tenant_id, role_id) REFERENCES access.role(tenant_id, id)
);
COMMENT ON TABLE machine.grant IS '机器自身的业务权限与接口范围；协议认证成功不能代替该授权';
COMMENT ON COLUMN machine.grant."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN machine.grant."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN machine.grant."principal_id" IS '机器主体。 设计场景：将机器凭据、授权和委托关联到稳定机器主体，轮换凭据不改变其身份与审计归属。';
COMMENT ON COLUMN machine.grant."role_id" IS '业务角色。 设计场景：将关系绑定到明确业务角色，权限计算同时核对角色当前状态、动作集合和这条关系自身的资源范围。';
COMMENT ON COLUMN machine.grant."scope_mode" IS '业务资源范围。 设计场景：显式区分全企业、指定店铺或指定资源等范围；空的明细集合不能被解释为全部权限。';
COMMENT ON COLUMN machine.grant."oauth_scopes" IS '经过受控目录验证的接口范围；不等于本地资源范围。 设计场景：限制程序可调用的协议接口范围，业务资源访问仍与机器及用户的当前权限求交集。';
COMMENT ON COLUMN machine.grant."granted_by_member_id" IS '授权管理员成员。 设计场景：明确授权是在目标企业中的哪位管理员身份下完成，避免跨企业借权。';
COMMENT ON COLUMN machine.grant."valid_from" IS '最早有效时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。';
COMMENT ON COLUMN machine.grant."valid_until" IS '授权到期时间。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。';
COMMENT ON COLUMN machine.grant."revoked_at" IS '撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN machine.grant."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN machine.grant."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_machine_grant_granter ON machine."grant" USING btree (tenant_id, granted_by_member_id);
CREATE INDEX ix_machine_grant_principal ON machine."grant" USING btree (tenant_id, principal_id, valid_until);
CREATE INDEX ix_machine_grant_role ON machine."grant" USING btree (tenant_id, role_id);

-- machine.user_delegation：用户授权机器执行指定任务；有效权限是用户当前授权、机器当前授权和委托范围的交集
CREATE TABLE machine.user_delegation (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 执行任务的机器。 设计场景：将机器凭据、授权和委托关联到稳定机器主体，轮换凭据不改变其身份与审计归属。
    "principal_id" bigint NOT NULL,
    -- 被代表的企业成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 被代表的平台账号；必须与成员匹配。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 依赖的机器授权。 设计场景：用户委托不得超过机器原有资格，机器授权撤销或缩小后委托同步受限。
    "machine_grant_id" bigint NOT NULL,
    -- 依赖的用户授权；撤销或离职后委托立即无效。 设计场景：委托绑定用户的实际授权，用户离职或授权撤销后程序不能继续以旧委托代办。
    "member_grant_id" bigint NOT NULL,
    -- 限定任务或工作流标识。 设计场景：用户只批准程序代办特定任务，防止将一次任务授权复用成任意长期操作权。
    "task_key" character varying(200) NOT NULL,
    -- 用户可理解的委托用途。 设计场景：用户可以审查程序本次要代办什么，执行仍受 task_key、范围、期限和双方当前权限共同限制。
    "purpose" character varying(1000) NOT NULL,
    -- 委托最大业务资源范围，不能超过两边来源授权。 设计场景：显式区分全企业、指定店铺或指定资源等范围；空的明细集合不能被解释为全部权限。
    "scope_mode" character varying(24) NOT NULL,
    -- 委托接口范围，必须是用户与机器允许范围的交集。 设计场景：限制程序可调用的协议接口范围，业务资源访问仍与机器及用户的当前权限求交集。
    "oauth_scopes" character varying(120)[] NOT NULL,
    -- 委托开始时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。
    "valid_from" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 强制到期时间。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。
    "valid_until" timestamp with time zone NOT NULL,
    -- 撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 本人近期验证证明；受控消费与委托创建同事务。 设计场景：把激活、委托等敏感操作与本人验证关联，最终事务检查用途、完成状态、期限和撤销版本。
    "authentication_attempt_id" bigint NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "user_delegation_account_id_authentication_attempt_id_fkey" FOREIGN KEY (account_id, authentication_attempt_id) REFERENCES identity.authentication_attempt(account_id, id),
    CONSTRAINT "user_delegation_check" CHECK (updated_at >= created_at),
    CONSTRAINT "user_delegation_check1" CHECK (valid_until > valid_from),
    CONSTRAINT "user_delegation_check2" CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT "user_delegation_id_check" CHECK (id > 0),
    CONSTRAINT "user_delegation_oauth_scopes_check" CHECK (cardinality(oauth_scopes) > 0 AND array_position(oauth_scopes, NULL::character varying) IS NULL AND NOT ('*'::text = ANY (oauth_scopes::text[]))),
    CONSTRAINT "user_delegation_pkey" PRIMARY KEY (id),
    CONSTRAINT "user_delegation_purpose_check" CHECK (btrim(purpose::text) <> ''::text),
    CONSTRAINT "user_delegation_scope_mode_check" CHECK (scope_mode::text = ANY (ARRAY['ALL_TENANT'::character varying, 'SELECTED_STORES'::character varying, 'SELECTED_RESOURCES'::character varying]::text[])),
    CONSTRAINT "user_delegation_task_key_check" CHECK (btrim(task_key::text) <> ''::text),
    CONSTRAINT "user_delegation_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "user_delegation_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "user_delegation_tenant_id_id_principal_id_member_id_key" UNIQUE (tenant_id, id, principal_id, member_id),
    CONSTRAINT "user_delegation_tenant_id_machine_grant_id_principal_id_fkey" FOREIGN KEY (tenant_id, machine_grant_id, principal_id) REFERENCES machine."grant"(tenant_id, id, principal_id),
    CONSTRAINT "user_delegation_tenant_id_member_grant_id_member_id_fkey" FOREIGN KEY (tenant_id, member_grant_id, member_id) REFERENCES access.member_grant(tenant_id, id, member_id),
    CONSTRAINT "user_delegation_tenant_id_member_id_account_id_fkey" FOREIGN KEY (tenant_id, member_id, account_id) REFERENCES directory.membership(tenant_id, id, account_id),
    CONSTRAINT "user_delegation_tenant_id_principal_id_fkey" FOREIGN KEY (tenant_id, principal_id) REFERENCES machine.principal(tenant_id, id)
);
COMMENT ON TABLE machine.user_delegation IS '用户授权机器执行指定任务；有效权限是用户当前授权、机器当前授权和委托范围的交集';
COMMENT ON COLUMN machine.user_delegation."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN machine.user_delegation."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN machine.user_delegation."principal_id" IS '执行任务的机器。 设计场景：将机器凭据、授权和委托关联到稳定机器主体，轮换凭据不改变其身份与审计归属。';
COMMENT ON COLUMN machine.user_delegation."member_id" IS '被代表的企业成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN machine.user_delegation."account_id" IS '被代表的平台账号；必须与成员匹配。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN machine.user_delegation."machine_grant_id" IS '依赖的机器授权。 设计场景：用户委托不得超过机器原有资格，机器授权撤销或缩小后委托同步受限。';
COMMENT ON COLUMN machine.user_delegation."member_grant_id" IS '依赖的用户授权；撤销或离职后委托立即无效。 设计场景：委托绑定用户的实际授权，用户离职或授权撤销后程序不能继续以旧委托代办。';
COMMENT ON COLUMN machine.user_delegation."task_key" IS '限定任务或工作流标识。 设计场景：用户只批准程序代办特定任务，防止将一次任务授权复用成任意长期操作权。';
COMMENT ON COLUMN machine.user_delegation."purpose" IS '用户可理解的委托用途。 设计场景：用户可以审查程序本次要代办什么，执行仍受 task_key、范围、期限和双方当前权限共同限制。';
COMMENT ON COLUMN machine.user_delegation."scope_mode" IS '委托最大业务资源范围，不能超过两边来源授权。 设计场景：显式区分全企业、指定店铺或指定资源等范围；空的明细集合不能被解释为全部权限。';
COMMENT ON COLUMN machine.user_delegation."oauth_scopes" IS '委托接口范围，必须是用户与机器允许范围的交集。 设计场景：限制程序可调用的协议接口范围，业务资源访问仍与机器及用户的当前权限求交集。';
COMMENT ON COLUMN machine.user_delegation."valid_from" IS '委托开始时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。';
COMMENT ON COLUMN machine.user_delegation."valid_until" IS '强制到期时间。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。';
COMMENT ON COLUMN machine.user_delegation."revoked_at" IS '撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN machine.user_delegation."authentication_attempt_id" IS '本人近期验证证明；受控消费与委托创建同事务。 设计场景：把激活、委托等敏感操作与本人验证关联，最终事务检查用途、完成状态、期限和撤销版本。';
COMMENT ON COLUMN machine.user_delegation."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN machine.user_delegation."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_machine_user_delegation_machine_grant ON machine.user_delegation USING btree (tenant_id, machine_grant_id, principal_id);
CREATE INDEX ix_machine_user_delegation_member ON machine.user_delegation USING btree (tenant_id, member_id, valid_until);
CREATE INDEX ix_machine_user_delegation_member_grant ON machine.user_delegation USING btree (tenant_id, member_grant_id, member_id);
CREATE INDEX ix_machine_user_delegation_principal ON machine.user_delegation USING btree (tenant_id, principal_id, valid_until);
CREATE INDEX ix_machine_user_delegation_proof ON machine.user_delegation USING btree (account_id, authentication_attempt_id);

-- audit.event：追加式审计；运行角色仅SELECT/INSERT，不允许修改删除；不保存密码令牌或敏感请求体
CREATE TABLE audit.event (
    -- 应用生成的审计事件雪花 ID，记录追加后不修改。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- ACCOUNT 为实际操作者；MACHINE 委托操作为被代表的账号；机器自行操作及系统事件为空。 设计场景：在审计中识别人或被机器代表的账号；纯系统或机器自有操作不能伪造一个人的身份。
    "actor_account_id" bigint,
    -- 操作所属企业；全局个人安全事件可为空，不代表任何管理员可跨企业读取。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint,
    -- 结构化动作代码。 设计场景：使用稳定动作代码查询和统计安全事件，避免依赖会变化的中文提示文字。
    "action" character varying(100) NOT NULL,
    -- 被操作对象类型代码。 设计场景：与目标 ID 一起解释操作对象，避免不同类型对象的相同 ID 被混为一谈。
    "target_type" character varying(64) NOT NULL,
    -- 被操作对象标识快照；可指向已归档或清理的对象。 设计场景：对象删除或归档后仍保留当时操作目标的标识，审计不能因业务对象不存在就失去解释。
    "target_id" character varying(128),
    -- 执行结果：SUCCESS 成功，FAILURE 失败，DENIED 拒绝。 设计场景：区分成功、拒绝、失败和结果未知等执行结果；不能把超时直接当作远端未执行。
    "result" character varying(32) NOT NULL,
    -- 请求关联标识，不包含凭据。 设计场景：将当前审计关联到产生它的请求，配合 correlation_id 排查跨步骤问题；不存原始请求体或凭据。
    "request_id" character varying(64) NOT NULL,
    -- 事件发生时间。 设计场景：记录事实实际发生时间，异步入库和投递延迟时仍可正确追溯先后关系。
    "occurred_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 主体类型：ACCOUNT 人员、MACHINE 机器、SYSTEM 系统；未显式传入时按主体字段推导。 设计场景：区分人、机器和系统产生的动作，审计检查对应主体字段组合，避免责任归属不明。
    "actor_type" character varying(16) NOT NULL,
    -- 人员在当前企业的身份；机器委托时为被代表成员，复合外键验证账号归属。 设计场景：明确操作发生于哪个企业成员身份下，支持一人多企业和机器代办时的责任追溯。
    "actor_member_id" bigint,
    -- 机器主体；必须属于事件企业。 设计场景：识别实际执行调用的机器，用户委托时同时记录人和机器，不能只保留被代表的人。
    "actor_machine_id" bigint,
    -- 机器代表成员操作的委托记录；复合外键绑定同一机器和成员。 设计场景：机器代表成员操作时同时追溯用户委托、机器和被代表成员，避免审计只显示机器而无法解释授权来源。
    "delegation_id" bigint,
    -- 产生事件的受控服务或系统代码，默认 platform。 设计场景：多来源事件汇聚时解释事件由哪个受控系统产生，和来源事件 ID 共同追踪。
    "source_system" character varying(100) DEFAULT 'platform'::character varying NOT NULL,
    -- 跨请求、事件和任务的链路标识。 设计场景：将一次操作涉及的 HTTP 请求、审计、事件和后台任务串联起来，排查跨步骤失败。
    "correlation_id" character varying(128),
    -- 外部来源事件标识快照，必须结合 source_system 解释，不作全局主体标识。 设计场景：追溯外部触发事实或回调，结合来源系统解释；不能当作全局账号 ID 使用。
    "source_event_id" character varying(200),
    -- 白名单脱敏变化摘要对象；不得包含密码、验证码、令牌、密钥或完整员工资料。 设计场景：保留允许查看的变更差异以解释谁改了什么，避免审计成为密码、令牌或整份员工资料的副本。
    "change_summary" jsonb,
    -- 受访问控制的详细证据引用，不存公开下载地址或带凭据的 URL。 设计场景：关联受保护的核验材料或执行证据，审查时可以回溯；普通接口不直接暴露证据内容与访问凭据。
    "evidence_ref" text,
    CONSTRAINT "ck_audit_actor_shape" CHECK (actor_type::text = 'ACCOUNT'::text AND actor_account_id IS NOT NULL AND actor_machine_id IS NULL AND delegation_id IS NULL OR actor_type::text = 'MACHINE'::text AND tenant_id IS NOT NULL AND actor_machine_id IS NOT NULL AND (delegation_id IS NULL AND actor_account_id IS NULL AND actor_member_id IS NULL OR delegation_id IS NOT NULL AND actor_account_id IS NOT NULL AND actor_member_id IS NOT NULL) OR actor_type::text = 'SYSTEM'::text AND actor_account_id IS NULL AND actor_member_id IS NULL AND actor_machine_id IS NULL AND delegation_id IS NULL),
    CONSTRAINT "ck_audit_change" CHECK (change_summary IS NULL OR jsonb_typeof(change_summary) = 'object'::text),
    CONSTRAINT "ck_audit_evidence" CHECK (evidence_ref IS NULL OR btrim(evidence_ref) <> ''::text),
    CONSTRAINT "ck_audit_member_context" CHECK (actor_member_id IS NULL OR tenant_id IS NOT NULL AND actor_account_id IS NOT NULL),
    CONSTRAINT "ck_audit_source" CHECK (btrim(source_system::text) <> ''::text),
    CONSTRAINT "event_actor_account_id_fkey" FOREIGN KEY (actor_account_id) REFERENCES directory.account(id),
    CONSTRAINT "event_id_check" CHECK (id > 0),
    CONSTRAINT "event_pkey" PRIMARY KEY (id),
    CONSTRAINT "event_result_check" CHECK (result::text = ANY (ARRAY['SUCCESS'::character varying, 'FAILURE'::character varying, 'DENIED'::character varying]::text[])),
    CONSTRAINT "event_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "fk_audit_actor_machine" FOREIGN KEY (tenant_id, actor_machine_id) REFERENCES machine.principal(tenant_id, id),
    CONSTRAINT "fk_audit_actor_member" FOREIGN KEY (tenant_id, actor_member_id, actor_account_id) REFERENCES directory.membership(tenant_id, id, account_id),
    CONSTRAINT "fk_audit_delegation" FOREIGN KEY (tenant_id, delegation_id, actor_machine_id, actor_member_id) REFERENCES machine.user_delegation(tenant_id, id, principal_id, member_id),
    CONSTRAINT "uq_audit_event_tenant_id" UNIQUE (tenant_id, id)
);
COMMENT ON TABLE audit.event IS '追加式审计；运行角色仅SELECT/INSERT，不允许修改删除；不保存密码令牌或敏感请求体';
COMMENT ON COLUMN audit.event."id" IS '应用生成的审计事件雪花 ID，记录追加后不修改。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN audit.event."actor_account_id" IS 'ACCOUNT 为实际操作者；MACHINE 委托操作为被代表的账号；机器自行操作及系统事件为空。 设计场景：在审计中识别人或被机器代表的账号；纯系统或机器自有操作不能伪造一个人的身份。';
COMMENT ON COLUMN audit.event."tenant_id" IS '操作所属企业；全局个人安全事件可为空，不代表任何管理员可跨企业读取。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN audit.event."action" IS '结构化动作代码。 设计场景：使用稳定动作代码查询和统计安全事件，避免依赖会变化的中文提示文字。';
COMMENT ON COLUMN audit.event."target_type" IS '被操作对象类型代码。 设计场景：与目标 ID 一起解释操作对象，避免不同类型对象的相同 ID 被混为一谈。';
COMMENT ON COLUMN audit.event."target_id" IS '被操作对象标识快照；可指向已归档或清理的对象。 设计场景：对象删除或归档后仍保留当时操作目标的标识，审计不能因业务对象不存在就失去解释。';
COMMENT ON COLUMN audit.event."result" IS '执行结果：SUCCESS 成功，FAILURE 失败，DENIED 拒绝。 设计场景：区分成功、拒绝、失败和结果未知等执行结果；不能把超时直接当作远端未执行。';
COMMENT ON COLUMN audit.event."request_id" IS '请求关联标识，不包含凭据。 设计场景：将当前审计关联到产生它的请求，配合 correlation_id 排查跨步骤问题；不存原始请求体或凭据。';
COMMENT ON COLUMN audit.event."occurred_at" IS '事件发生时间。 设计场景：记录事实实际发生时间，异步入库和投递延迟时仍可正确追溯先后关系。';
COMMENT ON COLUMN audit.event."actor_type" IS '主体类型：ACCOUNT 人员、MACHINE 机器、SYSTEM 系统；未显式传入时按主体字段推导。 设计场景：区分人、机器和系统产生的动作，审计检查对应主体字段组合，避免责任归属不明。';
COMMENT ON COLUMN audit.event."actor_member_id" IS '人员在当前企业的身份；机器委托时为被代表成员，复合外键验证账号归属。 设计场景：明确操作发生于哪个企业成员身份下，支持一人多企业和机器代办时的责任追溯。';
COMMENT ON COLUMN audit.event."actor_machine_id" IS '机器主体；必须属于事件企业。 设计场景：识别实际执行调用的机器，用户委托时同时记录人和机器，不能只保留被代表的人。';
COMMENT ON COLUMN audit.event."delegation_id" IS '机器代表成员操作的委托记录；复合外键绑定同一机器和成员。 设计场景：机器代表成员操作时同时追溯用户委托、机器和被代表成员，避免审计只显示机器而无法解释授权来源。';
COMMENT ON COLUMN audit.event."source_system" IS '产生事件的受控服务或系统代码，默认 platform。 设计场景：多来源事件汇聚时解释事件由哪个受控系统产生，和来源事件 ID 共同追踪。';
COMMENT ON COLUMN audit.event."correlation_id" IS '跨请求、事件和任务的链路标识。 设计场景：将一次操作涉及的 HTTP 请求、审计、事件和后台任务串联起来，排查跨步骤失败。';
COMMENT ON COLUMN audit.event."source_event_id" IS '外部来源事件标识快照，必须结合 source_system 解释，不作全局主体标识。 设计场景：追溯外部触发事实或回调，结合来源系统解释；不能当作全局账号 ID 使用。';
COMMENT ON COLUMN audit.event."change_summary" IS '白名单脱敏变化摘要对象；不得包含密码、验证码、令牌、密钥或完整员工资料。 设计场景：保留允许查看的变更差异以解释谁改了什么，避免审计成为密码、令牌或整份员工资料的副本。';
COMMENT ON COLUMN audit.event."evidence_ref" IS '受访问控制的详细证据引用，不存公开下载地址或带凭据的 URL。 设计场景：关联受保护的核验材料或执行证据，审查时可以回溯；普通接口不直接暴露证据内容与访问凭据。';
CREATE INDEX ix_audit_actor_time ON audit.event USING btree (actor_account_id, occurred_at DESC, id DESC);
CREATE INDEX ix_audit_correlation ON audit.event USING btree (tenant_id, correlation_id, id) WHERE (correlation_id IS NOT NULL);
CREATE INDEX ix_audit_delegation ON audit.event USING btree (tenant_id, delegation_id, actor_machine_id, actor_member_id) WHERE (delegation_id IS NOT NULL);
CREATE INDEX ix_audit_machine_time ON audit.event USING btree (tenant_id, actor_machine_id, occurred_at DESC, id DESC) WHERE (actor_machine_id IS NOT NULL);
CREATE INDEX ix_audit_member_time ON audit.event USING btree (tenant_id, actor_member_id, occurred_at DESC, id DESC) WHERE (actor_member_id IS NOT NULL);
CREATE INDEX ix_audit_target_time ON audit.event USING btree (tenant_id, target_type, target_id, occurred_at DESC, id DESC);
CREATE INDEX ix_audit_tenant_time ON audit.event USING btree (tenant_id, occurred_at DESC, id DESC);

-- delivery.daily_quota：邮件和短信的每日发送额度预留。
CREATE TABLE delivery.daily_quota (
    -- 发送渠道 EMAIL 或 SMS。 设计场景：同一投递队列按邮件或短信选择发送适配器和额度，渠道配置不改变业务操作结果。
    "channel" character varying(16) NOT NULL,
    -- 额度统计日期，按平台配置的统一日界计算。 设计场景：按统一日界统计发送额度，避免实例时区不同造成一天被拆成多段或重复计费。
    "day" date NOT NULL,
    -- 当日已经预留的发送额度，失败和未知结果按投递规则核销。 设计场景：并发发送前先原子预留额度，防止多个实例同时读到剩余额度后超量发送。
    "reserved_count" integer NOT NULL,
    CONSTRAINT "daily_quota_pkey" PRIMARY KEY (channel, day),
    CONSTRAINT "daily_quota_reserved_count_check" CHECK (reserved_count >= 0)
);
COMMENT ON TABLE delivery.daily_quota IS '邮件和短信的每日发送额度预留。';
COMMENT ON COLUMN delivery.daily_quota."channel" IS '发送渠道 EMAIL 或 SMS。 设计场景：同一投递队列按邮件或短信选择发送适配器和额度，渠道配置不改变业务操作结果。';
COMMENT ON COLUMN delivery.daily_quota."day" IS '额度统计日期，按平台配置的统一日界计算。 设计场景：按统一日界统计发送额度，避免实例时区不同造成一天被拆成多段或重复计费。';
COMMENT ON COLUMN delivery.daily_quota."reserved_count" IS '当日已经预留的发送额度，失败和未知结果按投递规则核销。 设计场景：并发发送前先原子预留额度，防止多个实例同时读到剩余额度后超量发送。';

-- delivery.domain_event：与业务变更同事务落库的身份领域事件；队列完成表示订阅投递任务已幂等展开，不表示所有远端已收到。
CREATE TABLE delivery.domain_event (
    -- 应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；同企业关联和行级隔离的边界。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 稳定事件类型代码。 设计场景：让订阅方按明确契约选择事件和处理器，避免解析任意业务对象猜测事件含义。
    "event_type" character varying(100) NOT NULL,
    -- 事件载荷契约版本。 设计场景：事件结构升级后按版本解析载荷，不能让旧消费者把新增字段误读成旧语义。
    "schema_version" integer DEFAULT 1 NOT NULL,
    -- 产生事件的业务对象类型。 设计场景：与聚合 ID 配合区分事件属于账号、成员或其他业务对象，支持按对象回溯变化。
    "aggregate_type" character varying(64) NOT NULL,
    -- 业务对象标识快照。 设计场景：将多次事件归到同一业务对象，供消费者幂等处理与排查，不携带完整领域实体。
    "aggregate_id" character varying(128) NOT NULL,
    -- 事件产生时业务对象版本；供接收方识别乱序。 设计场景：消费者遇到乱序事件时识别旧版本，避免后到达的旧状态覆盖更新状态。
    "aggregate_version" bigint NOT NULL,
    -- 本企业内事件唯一幂等键，不使用变化时间代替业务幂等标识。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。
    "idempotency_key" character varying(200) NOT NULL,
    -- 最小必要事件载荷；不得包含认证秘密；外发前仍按订阅字段与资源授权投影。 设计场景：记录最小业务事实，投递时仍按订阅权限裁剪，不能把整个领域对象序列化后直接外发。
    "payload" jsonb NOT NULL,
    -- 同一业务变更对应的审计事件，必须同企业。 设计场景：把可靠事件与同一次业务修改的审计连起来，核对业务已提交但投递未完成的情况。
    "audit_event_id" bigint,
    -- 跨请求与异步投递的关联标识。 设计场景：将一次操作涉及的 HTTP 请求、审计、事件和后台任务串联起来，排查跨步骤失败。
    "correlation_id" character varying(128) NOT NULL,
    -- 业务事件发生时间。 设计场景：记录事实实际发生时间，异步入库和投递延迟时仍可正确追溯先后关系。
    "occurred_at" timestamp with time zone NOT NULL,
    -- 任务状态：READY 待执行，CLAIMED 已领取，RETRY 待重试，SUCCEEDED 完成，DEAD 终止，CANCELLED 取消；若允许 UNKNOWN 则表示外部结果待对账。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'READY'::character varying NOT NULL,
    -- 已发起的执行次数；领取事务递增。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。
    "attempts" integer DEFAULT 0 NOT NULL,
    -- 自动执行次数上限；超过上限需明确处理，不无限重试。 设计场景：限制自动执行或校验次数，避免无限重试和暴力猜测；具体场景由所在表决定。
    "max_attempts" integer DEFAULT 8 NOT NULL,
    -- 允许再次执行的最早时间。 设计场景：支持延迟执行和失败后的退避重试，后台只能领取已经到可执行时间的任务。
    "available_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 本次领取的唯一租约标识；每次领取重新生成，不能只使用固定进程名。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。
    "lease_owner" character varying(100),
    -- 租约截止时间；完成更新必须同时比较租约标识和截止时间。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。
    "lease_until" timestamp with time zone,
    -- 不含请求正文、令牌或个人资料的结构化错误码。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。
    "last_error_code" character varying(100),
    -- 进入完成、终止或取消状态的时间。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。
    "finished_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近修改时间，由应用更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "domain_event_aggregate_id_check" CHECK (btrim(aggregate_id::text) <> ''::text),
    CONSTRAINT "domain_event_aggregate_type_check" CHECK (btrim(aggregate_type::text) <> ''::text),
    CONSTRAINT "domain_event_aggregate_version_check" CHECK (aggregate_version >= 0),
    CONSTRAINT "domain_event_attempts_check" CHECK (attempts >= 0),
    CONSTRAINT "domain_event_check" CHECK (status::text = 'CLAIMED'::text AND lease_owner IS NOT NULL AND btrim(lease_owner::text) <> ''::text AND lease_until IS NOT NULL AND lease_until > updated_at OR status::text <> 'CLAIMED'::text AND lease_owner IS NULL AND lease_until IS NULL),
    CONSTRAINT "domain_event_check1" CHECK ((status::text = ANY (ARRAY['SUCCEEDED'::character varying, 'DEAD'::character varying, 'CANCELLED'::character varying]::text[])) = (finished_at IS NOT NULL)),
    CONSTRAINT "domain_event_check2" CHECK (finished_at IS NULL OR finished_at >= created_at),
    CONSTRAINT "domain_event_check3" CHECK (updated_at >= created_at),
    CONSTRAINT "domain_event_event_type_check" CHECK (btrim(event_type::text) <> ''::text),
    CONSTRAINT "domain_event_id_check" CHECK (id > 0),
    CONSTRAINT "domain_event_idempotency_key_check" CHECK (btrim(idempotency_key::text) <> ''::text),
    CONSTRAINT "domain_event_max_attempts_check" CHECK (max_attempts > 0),
    CONSTRAINT "domain_event_payload_check" CHECK (jsonb_typeof(payload) = 'object'::text),
    CONSTRAINT "domain_event_pkey" PRIMARY KEY (id),
    CONSTRAINT "domain_event_schema_version_check" CHECK (schema_version > 0),
    CONSTRAINT "domain_event_status_check" CHECK (status::text = ANY (ARRAY['READY'::character varying, 'CLAIMED'::character varying, 'RETRY'::character varying, 'SUCCEEDED'::character varying, 'DEAD'::character varying, 'CANCELLED'::character varying]::text[])),
    CONSTRAINT "domain_event_tenant_id_audit_event_id_fkey" FOREIGN KEY (tenant_id, audit_event_id) REFERENCES audit.event(tenant_id, id),
    CONSTRAINT "domain_event_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "domain_event_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "domain_event_tenant_id_idempotency_key_key" UNIQUE (tenant_id, idempotency_key)
);
COMMENT ON TABLE delivery.domain_event IS '与业务变更同事务落库的身份领域事件；队列完成表示订阅投递任务已幂等展开，不表示所有远端已收到。';
COMMENT ON COLUMN delivery.domain_event."id" IS '应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN delivery.domain_event."tenant_id" IS '所属企业；同企业关联和行级隔离的边界。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN delivery.domain_event."event_type" IS '稳定事件类型代码。 设计场景：让订阅方按明确契约选择事件和处理器，避免解析任意业务对象猜测事件含义。';
COMMENT ON COLUMN delivery.domain_event."schema_version" IS '事件载荷契约版本。 设计场景：事件结构升级后按版本解析载荷，不能让旧消费者把新增字段误读成旧语义。';
COMMENT ON COLUMN delivery.domain_event."aggregate_type" IS '产生事件的业务对象类型。 设计场景：与聚合 ID 配合区分事件属于账号、成员或其他业务对象，支持按对象回溯变化。';
COMMENT ON COLUMN delivery.domain_event."aggregate_id" IS '业务对象标识快照。 设计场景：将多次事件归到同一业务对象，供消费者幂等处理与排查，不携带完整领域实体。';
COMMENT ON COLUMN delivery.domain_event."aggregate_version" IS '事件产生时业务对象版本；供接收方识别乱序。 设计场景：消费者遇到乱序事件时识别旧版本，避免后到达的旧状态覆盖更新状态。';
COMMENT ON COLUMN delivery.domain_event."idempotency_key" IS '本企业内事件唯一幂等键，不使用变化时间代替业务幂等标识。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。';
COMMENT ON COLUMN delivery.domain_event."payload" IS '最小必要事件载荷；不得包含认证秘密；外发前仍按订阅字段与资源授权投影。 设计场景：记录最小业务事实，投递时仍按订阅权限裁剪，不能把整个领域对象序列化后直接外发。';
COMMENT ON COLUMN delivery.domain_event."audit_event_id" IS '同一业务变更对应的审计事件，必须同企业。 设计场景：把可靠事件与同一次业务修改的审计连起来，核对业务已提交但投递未完成的情况。';
COMMENT ON COLUMN delivery.domain_event."correlation_id" IS '跨请求与异步投递的关联标识。 设计场景：将一次操作涉及的 HTTP 请求、审计、事件和后台任务串联起来，排查跨步骤失败。';
COMMENT ON COLUMN delivery.domain_event."occurred_at" IS '业务事件发生时间。 设计场景：记录事实实际发生时间，异步入库和投递延迟时仍可正确追溯先后关系。';
COMMENT ON COLUMN delivery.domain_event."status" IS '任务状态：READY 待执行，CLAIMED 已领取，RETRY 待重试，SUCCEEDED 完成，DEAD 终止，CANCELLED 取消；若允许 UNKNOWN 则表示外部结果待对账。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN delivery.domain_event."attempts" IS '已发起的执行次数；领取事务递增。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。';
COMMENT ON COLUMN delivery.domain_event."max_attempts" IS '自动执行次数上限；超过上限需明确处理，不无限重试。 设计场景：限制自动执行或校验次数，避免无限重试和暴力猜测；具体场景由所在表决定。';
COMMENT ON COLUMN delivery.domain_event."available_at" IS '允许再次执行的最早时间。 设计场景：支持延迟执行和失败后的退避重试，后台只能领取已经到可执行时间的任务。';
COMMENT ON COLUMN delivery.domain_event."lease_owner" IS '本次领取的唯一租约标识；每次领取重新生成，不能只使用固定进程名。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。';
COMMENT ON COLUMN delivery.domain_event."lease_until" IS '租约截止时间；完成更新必须同时比较租约标识和截止时间。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。';
COMMENT ON COLUMN delivery.domain_event."last_error_code" IS '不含请求正文、令牌或个人资料的结构化错误码。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。';
COMMENT ON COLUMN delivery.domain_event."finished_at" IS '进入完成、终止或取消状态的时间。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。';
COMMENT ON COLUMN delivery.domain_event."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN delivery.domain_event."updated_at" IS '最近修改时间，由应用更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_domain_event_aggregate ON delivery.domain_event USING btree (tenant_id, aggregate_type, aggregate_id, aggregate_version);
CREATE INDEX ix_domain_event_audit ON delivery.domain_event USING btree (tenant_id, audit_event_id) WHERE (audit_event_id IS NOT NULL);
CREATE INDEX ix_domain_event_due ON delivery.domain_event USING btree (tenant_id, available_at, id) WHERE ((status)::text = ANY ((ARRAY['READY'::character varying, 'RETRY'::character varying])::text[]));
CREATE INDEX ix_domain_event_lease ON delivery.domain_event USING btree (tenant_id, lease_until, id) WHERE ((status)::text = 'CLAIMED'::text);

-- delivery.event_subscription：企业授权的身份事件订阅；停用或授权到期后必须停止领取和发送，重试时再次验证当前权限。
CREATE TABLE delivery.event_subscription (
    -- 应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；同企业关联和行级隔离的边界。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 接收应用在本企业的开通记录；应用开通不自动等于订阅授权。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。
    "tenant_application_id" bigint NOT NULL,
    -- 企业内唯一订阅编码。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。
    "code" character varying(100) NOT NULL,
    -- 订阅状态：ACTIVE 有效，SUSPENDED 暂停，REVOKED 撤销。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- HTTPS 接收地址；应用还需防 SSRF、校验允许域名和重定向，禁止 URL 内携带凭据。 设计场景：实际调用或发送协议结果时使用登记端点，需控制协议、地址和来源，不能信任请求任意指定的目标。
    "endpoint_url" text NOT NULL,
    -- 用于消息签名的加密密钥；不以明文保存。 设计场景：向订阅方发送消息时证明来源，密钥加密保存并支持轮换，不向普通查询返回明文。
    "signing_key_ciphertext" bytea NOT NULL,
    -- 密钥加密版本，支撑轮换。 设计场景：密钥轮换后按写入时版本选择正确解密材料；不能把新旧密文混用同一把默认密钥。
    "key_version" integer NOT NULL,
    -- 批准订阅范围的账号，不能只凭应用登记自助开通。 设计场景：记录同意执行或订阅的责任账号，真正执行前仍核验当前权限和授权期限。
    "authorized_by_account_id" bigint NOT NULL,
    -- 批准者在本企业的成员身份。 设计场景：把企业授权限定到明确的成员身份，成员离职后不能继续依赖过去的授权记录无限执行。
    "authorized_by_member_id" bigint NOT NULL,
    -- 订阅权限审核通过时间。 设计场景：记录任务或订阅何时完成权限核验，用于追踪审批链和有效窗口。
    "authorized_at" timestamp with time zone NOT NULL,
    -- 订阅授权到期时间，每次外发都重新检查。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone NOT NULL,
    -- 撤销时间，仅 REVOKED 状态非空。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 配置和授权范围版本；收窄后旧待发送投影不能直接继续发送。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近修改时间，由应用更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "event_subscription_authorized_by_account_id_fkey" FOREIGN KEY (authorized_by_account_id) REFERENCES directory.account(id),
    CONSTRAINT "event_subscription_check" CHECK ((status::text = 'REVOKED'::text) = (revoked_at IS NOT NULL)),
    CONSTRAINT "event_subscription_check1" CHECK (expires_at > authorized_at),
    CONSTRAINT "event_subscription_check2" CHECK (revoked_at IS NULL OR revoked_at >= authorized_at),
    CONSTRAINT "event_subscription_check3" CHECK (updated_at >= created_at),
    CONSTRAINT "event_subscription_code_check" CHECK (btrim(code::text) <> ''::text),
    CONSTRAINT "event_subscription_endpoint_url_check" CHECK (endpoint_url ~ '^https://[^[:space:]]+$'::text),
    CONSTRAINT "event_subscription_id_check" CHECK (id > 0),
    CONSTRAINT "event_subscription_key_version_check" CHECK (key_version > 0),
    CONSTRAINT "event_subscription_pkey" PRIMARY KEY (id),
    CONSTRAINT "event_subscription_signing_key_ciphertext_check" CHECK (octet_length(signing_key_ciphertext) > 0),
    CONSTRAINT "event_subscription_status_check" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'SUSPENDED'::character varying, 'REVOKED'::character varying]::text[])),
    CONSTRAINT "event_subscription_tenant_id_authorized_by_member_id_autho_fkey" FOREIGN KEY (tenant_id, authorized_by_member_id, authorized_by_account_id) REFERENCES directory.membership(tenant_id, id, account_id),
    CONSTRAINT "event_subscription_tenant_id_code_key" UNIQUE (tenant_id, code),
    CONSTRAINT "event_subscription_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "event_subscription_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "event_subscription_tenant_id_tenant_application_id_fkey" FOREIGN KEY (tenant_id, tenant_application_id) REFERENCES application.tenant_application(tenant_id, id),
    CONSTRAINT "event_subscription_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE delivery.event_subscription IS '企业授权的身份事件订阅；停用或授权到期后必须停止领取和发送，重试时再次验证当前权限。';
COMMENT ON COLUMN delivery.event_subscription."id" IS '应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN delivery.event_subscription."tenant_id" IS '所属企业；同企业关联和行级隔离的边界。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN delivery.event_subscription."tenant_application_id" IS '接收应用在本企业的开通记录；应用开通不自动等于订阅授权。 设计场景：定位某企业开通的具体应用实例，防止全局应用登记被误认为所有租户都已获得访问资格。';
COMMENT ON COLUMN delivery.event_subscription."code" IS '企业内唯一订阅编码。 设计场景：提供便于配置、接口引用和检索的业务编码；唯一作用域以本表约束为准，不能把编码当访问凭据。';
COMMENT ON COLUMN delivery.event_subscription."status" IS '订阅状态：ACTIVE 有效，SUSPENDED 暂停，REVOKED 撤销。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN delivery.event_subscription."endpoint_url" IS 'HTTPS 接收地址；应用还需防 SSRF、校验允许域名和重定向，禁止 URL 内携带凭据。 设计场景：实际调用或发送协议结果时使用登记端点，需控制协议、地址和来源，不能信任请求任意指定的目标。';
COMMENT ON COLUMN delivery.event_subscription."signing_key_ciphertext" IS '用于消息签名的加密密钥；不以明文保存。 设计场景：向订阅方发送消息时证明来源，密钥加密保存并支持轮换，不向普通查询返回明文。';
COMMENT ON COLUMN delivery.event_subscription."key_version" IS '密钥加密版本，支撑轮换。 设计场景：密钥轮换后按写入时版本选择正确解密材料；不能把新旧密文混用同一把默认密钥。';
COMMENT ON COLUMN delivery.event_subscription."authorized_by_account_id" IS '批准订阅范围的账号，不能只凭应用登记自助开通。 设计场景：记录同意执行或订阅的责任账号，真正执行前仍核验当前权限和授权期限。';
COMMENT ON COLUMN delivery.event_subscription."authorized_by_member_id" IS '批准者在本企业的成员身份。 设计场景：把企业授权限定到明确的成员身份，成员离职后不能继续依赖过去的授权记录无限执行。';
COMMENT ON COLUMN delivery.event_subscription."authorized_at" IS '订阅权限审核通过时间。 设计场景：记录任务或订阅何时完成权限核验，用于追踪审批链和有效窗口。';
COMMENT ON COLUMN delivery.event_subscription."expires_at" IS '订阅授权到期时间，每次外发都重新检查。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN delivery.event_subscription."revoked_at" IS '撤销时间，仅 REVOKED 状态非空。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN delivery.event_subscription."version" IS '配置和授权范围版本；收窄后旧待发送投影不能直接继续发送。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN delivery.event_subscription."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN delivery.event_subscription."updated_at" IS '最近修改时间，由应用更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_subscription_application ON delivery.event_subscription USING btree (tenant_id, tenant_application_id);
CREATE INDEX ix_subscription_authorizer ON delivery.event_subscription USING btree (authorized_by_account_id);
CREATE INDEX ix_subscription_authorizer_member ON delivery.event_subscription USING btree (tenant_id, authorized_by_member_id, authorized_by_account_id);
CREATE INDEX ix_subscription_expiry ON delivery.event_subscription USING btree (tenant_id, expires_at, id) WHERE ((status)::text = 'ACTIVE'::text);

-- delivery.event_delivery：一条领域事件对一个订阅的投递状态；允许重复网络投递但接收方按稳定幂等键去重，UNKNOWN 先对账。
CREATE TABLE delivery.event_delivery (
    -- 应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；同企业关联和行级隔离的边界。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 目标订阅，与事件属于同企业。 设计场景：定位消息接收方及其授权范围，发送或重试时重新检查订阅是否仍有效。
    "subscription_id" bigint NOT NULL,
    -- 来源领域事件，不复制业务变更。 设计场景：同一业务事件可以投递给多个订阅方，各自记录结果，不重新执行业务修改。
    "event_id" bigint NOT NULL,
    -- 生成消息投影时的订阅版本；外发时必须检查最新授权并重新投影或取消。 设计场景：消息生成后订阅权限可能收紧，外发前检测版本变化并重新裁剪或取消，防止旧载荷泄露字段。
    "subscription_version" bigint NOT NULL,
    -- 已按订阅授权裁剪的消息对象，不能直接复制原始完整资料。 设计场景：不同订阅方仅获得各自允许的字段和资源，原事件不能直接原样复制给所有接收方。
    "projected_payload" jsonb NOT NULL,
    -- 发送和对账共用的稳定幂等键；重试时保持不变。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。
    "idempotency_key" character varying(200) NOT NULL,
    -- 远端回执标识，不存回执正文或凭据。 设计场景：保存远端受理凭据用于对账，网络超时后可以核实是否已处理，避免盲目重复发送。
    "remote_receipt" character varying(200),
    -- 结果未知时下次对账时间；其他状态为空。 设计场景：结果未知时先等待可核实的时间点再查询，避免立即重发导致重复副作用。
    "reconcile_after" timestamp with time zone,
    -- 最近一次有证据的对账时间。 设计场景：记录最近一次有证据的状态核实，区分仍不确定与已确认成功或失败。
    "reconciled_at" timestamp with time zone,
    -- 任务状态：READY 待执行，CLAIMED 已领取，RETRY 待重试，SUCCEEDED 完成，DEAD 终止，CANCELLED 取消；若允许 UNKNOWN 则表示外部结果待对账。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'READY'::character varying NOT NULL,
    -- 已发起的执行次数；领取事务递增。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。
    "attempts" integer DEFAULT 0 NOT NULL,
    -- 自动执行次数上限；超过上限需明确处理，不无限重试。 设计场景：限制自动执行或校验次数，避免无限重试和暴力猜测；具体场景由所在表决定。
    "max_attempts" integer DEFAULT 8 NOT NULL,
    -- 允许再次执行的最早时间。 设计场景：支持延迟执行和失败后的退避重试，后台只能领取已经到可执行时间的任务。
    "available_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 本次领取的唯一租约标识；每次领取重新生成，不能只使用固定进程名。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。
    "lease_owner" character varying(100),
    -- 租约截止时间；完成更新必须同时比较租约标识和截止时间。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。
    "lease_until" timestamp with time zone,
    -- 不含请求正文、令牌或个人资料的结构化错误码。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。
    "last_error_code" character varying(100),
    -- 进入完成、终止或取消状态的时间。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。
    "finished_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近修改时间，由应用更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "event_delivery_attempts_check" CHECK (attempts >= 0),
    CONSTRAINT "event_delivery_check" CHECK ((status::text = 'UNKNOWN'::text) = (reconcile_after IS NOT NULL)),
    CONSTRAINT "event_delivery_check1" CHECK (status::text = 'CLAIMED'::text AND lease_owner IS NOT NULL AND btrim(lease_owner::text) <> ''::text AND lease_until IS NOT NULL AND lease_until > updated_at OR status::text <> 'CLAIMED'::text AND lease_owner IS NULL AND lease_until IS NULL),
    CONSTRAINT "event_delivery_check2" CHECK ((status::text = ANY (ARRAY['SUCCEEDED'::character varying, 'DEAD'::character varying, 'CANCELLED'::character varying]::text[])) = (finished_at IS NOT NULL)),
    CONSTRAINT "event_delivery_check3" CHECK (finished_at IS NULL OR finished_at >= created_at),
    CONSTRAINT "event_delivery_check4" CHECK (updated_at >= created_at),
    CONSTRAINT "event_delivery_id_check" CHECK (id > 0),
    CONSTRAINT "event_delivery_idempotency_key_check" CHECK (btrim(idempotency_key::text) <> ''::text),
    CONSTRAINT "event_delivery_max_attempts_check" CHECK (max_attempts > 0),
    CONSTRAINT "event_delivery_pkey" PRIMARY KEY (id),
    CONSTRAINT "event_delivery_projected_payload_check" CHECK (jsonb_typeof(projected_payload) = 'object'::text),
    CONSTRAINT "event_delivery_status_check" CHECK (status::text = ANY (ARRAY['READY'::character varying, 'CLAIMED'::character varying, 'RETRY'::character varying, 'SUCCEEDED'::character varying, 'DEAD'::character varying, 'CANCELLED'::character varying, 'UNKNOWN'::character varying]::text[])),
    CONSTRAINT "event_delivery_subscription_version_check" CHECK (subscription_version >= 0),
    CONSTRAINT "event_delivery_tenant_id_event_id_fkey" FOREIGN KEY (tenant_id, event_id) REFERENCES delivery.domain_event(tenant_id, id),
    CONSTRAINT "event_delivery_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "event_delivery_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "event_delivery_tenant_id_idempotency_key_key" UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT "event_delivery_tenant_id_subscription_id_event_id_key" UNIQUE (tenant_id, subscription_id, event_id),
    CONSTRAINT "event_delivery_tenant_id_subscription_id_fkey" FOREIGN KEY (tenant_id, subscription_id) REFERENCES delivery.event_subscription(tenant_id, id)
);
COMMENT ON TABLE delivery.event_delivery IS '一条领域事件对一个订阅的投递状态；允许重复网络投递但接收方按稳定幂等键去重，UNKNOWN 先对账。';
COMMENT ON COLUMN delivery.event_delivery."id" IS '应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN delivery.event_delivery."tenant_id" IS '所属企业；同企业关联和行级隔离的边界。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN delivery.event_delivery."subscription_id" IS '目标订阅，与事件属于同企业。 设计场景：定位消息接收方及其授权范围，发送或重试时重新检查订阅是否仍有效。';
COMMENT ON COLUMN delivery.event_delivery."event_id" IS '来源领域事件，不复制业务变更。 设计场景：同一业务事件可以投递给多个订阅方，各自记录结果，不重新执行业务修改。';
COMMENT ON COLUMN delivery.event_delivery."subscription_version" IS '生成消息投影时的订阅版本；外发时必须检查最新授权并重新投影或取消。 设计场景：消息生成后订阅权限可能收紧，外发前检测版本变化并重新裁剪或取消，防止旧载荷泄露字段。';
COMMENT ON COLUMN delivery.event_delivery."projected_payload" IS '已按订阅授权裁剪的消息对象，不能直接复制原始完整资料。 设计场景：不同订阅方仅获得各自允许的字段和资源，原事件不能直接原样复制给所有接收方。';
COMMENT ON COLUMN delivery.event_delivery."idempotency_key" IS '发送和对账共用的稳定幂等键；重试时保持不变。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。';
COMMENT ON COLUMN delivery.event_delivery."remote_receipt" IS '远端回执标识，不存回执正文或凭据。 设计场景：保存远端受理凭据用于对账，网络超时后可以核实是否已处理，避免盲目重复发送。';
COMMENT ON COLUMN delivery.event_delivery."reconcile_after" IS '结果未知时下次对账时间；其他状态为空。 设计场景：结果未知时先等待可核实的时间点再查询，避免立即重发导致重复副作用。';
COMMENT ON COLUMN delivery.event_delivery."reconciled_at" IS '最近一次有证据的对账时间。 设计场景：记录最近一次有证据的状态核实，区分仍不确定与已确认成功或失败。';
COMMENT ON COLUMN delivery.event_delivery."status" IS '任务状态：READY 待执行，CLAIMED 已领取，RETRY 待重试，SUCCEEDED 完成，DEAD 终止，CANCELLED 取消；若允许 UNKNOWN 则表示外部结果待对账。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN delivery.event_delivery."attempts" IS '已发起的执行次数；领取事务递增。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。';
COMMENT ON COLUMN delivery.event_delivery."max_attempts" IS '自动执行次数上限；超过上限需明确处理，不无限重试。 设计场景：限制自动执行或校验次数，避免无限重试和暴力猜测；具体场景由所在表决定。';
COMMENT ON COLUMN delivery.event_delivery."available_at" IS '允许再次执行的最早时间。 设计场景：支持延迟执行和失败后的退避重试，后台只能领取已经到可执行时间的任务。';
COMMENT ON COLUMN delivery.event_delivery."lease_owner" IS '本次领取的唯一租约标识；每次领取重新生成，不能只使用固定进程名。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。';
COMMENT ON COLUMN delivery.event_delivery."lease_until" IS '租约截止时间；完成更新必须同时比较租约标识和截止时间。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。';
COMMENT ON COLUMN delivery.event_delivery."last_error_code" IS '不含请求正文、令牌或个人资料的结构化错误码。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。';
COMMENT ON COLUMN delivery.event_delivery."finished_at" IS '进入完成、终止或取消状态的时间。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。';
COMMENT ON COLUMN delivery.event_delivery."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN delivery.event_delivery."updated_at" IS '最近修改时间，由应用更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_event_delivery_due ON delivery.event_delivery USING btree (tenant_id, available_at, id) WHERE ((status)::text = ANY ((ARRAY['READY'::character varying, 'RETRY'::character varying])::text[]));
CREATE INDEX ix_event_delivery_event ON delivery.event_delivery USING btree (tenant_id, event_id);
CREATE INDEX ix_event_delivery_lease ON delivery.event_delivery USING btree (tenant_id, lease_until, id) WHERE ((status)::text = 'CLAIMED'::text);
CREATE INDEX ix_event_delivery_reconcile ON delivery.event_delivery USING btree (tenant_id, reconcile_after, id) WHERE ((status)::text = 'UNKNOWN'::text);

-- delivery.event_delivery_attempt：追加式外发和对账执行记录；每次尝试结束或租约回收后写入结果，不把超时推断成远端失败。
CREATE TABLE delivery.event_delivery_attempt (
    -- 应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；同企业关联和行级隔离的边界。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 对应的订阅投递记录。 设计场景：把多次发送和对账尝试关联到同一投递记录，方便还原重试经过。
    "delivery_id" bigint NOT NULL,
    -- 该投递的执行记录序号，包含发送与对账并发控制。 设计场景：将每一次执行独立编号，重试后仍能还原前一次失败、超时或成功的经过。
    "attempt_no" integer NOT NULL,
    -- 本次操作：SEND 发送，RECONCILE 对账。 设计场景：显式区分创建、更新、停用、归档或清理等动作，重试继续相同意图，不根据当前显示文案猜测操作。
    "operation" character varying(16) NOT NULL,
    -- 结果；CONFIRMED_ABSENT 仅用于对账确认远端未接收，不能由超时直接推断。 设计场景：区分成功、拒绝、失败和结果未知等执行结果；不能把超时直接当作远端未执行。
    "result" character varying(24) NOT NULL,
    -- 执行时的唯一租约标识，用于识别过期执行者。 设计场景：区分同一任务不同轮次的执行权，防止旧执行器在任务已被接管后迟到回写结果。
    "lease_token" character varying(100) NOT NULL,
    -- 远端 HTTP 状态码。 设计场景：记录远端传输响应便于分类排障；收到 HTTP 成功不一定代表下游业务已经完成。
    "http_status" integer,
    -- 脱敏错误代码。 设计场景：用稳定且脱敏的分类定位失败和选择补偿方式；不把凭据、完整响应或个人资料写入错误字段。
    "error_code" character varying(100),
    -- 远端回执或受控对账证据引用，不保存认证信息。 设计场景：将外发结果和受控回执证据连接起来，核查时取受保护材料，日志不复制敏感响应。
    "receipt_ref" character varying(200),
    -- 本次执行链路标识。 设计场景：在日志与网络调用中定位这一轮发送或对账请求，重试仍保留各自执行记录。
    "request_id" character varying(128) NOT NULL,
    -- 本次执行开始时间。 设计场景：记录一次执行真正开始的时刻，用于识别排队与执行耗时、定位长期运行任务。
    "started_at" timestamp with time zone NOT NULL,
    -- 本次结果形成时间。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。
    "finished_at" timestamp with time zone NOT NULL,
    -- 结果追加时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "event_delivery_attempt_attempt_no_check" CHECK (attempt_no > 0),
    CONSTRAINT "event_delivery_attempt_check" CHECK (result::text <> 'CONFIRMED_ABSENT'::text OR operation::text = 'RECONCILE'::text),
    CONSTRAINT "event_delivery_attempt_check1" CHECK (finished_at >= started_at),
    CONSTRAINT "event_delivery_attempt_http_status_check" CHECK (http_status >= 100 AND http_status <= 599),
    CONSTRAINT "event_delivery_attempt_id_check" CHECK (id > 0),
    CONSTRAINT "event_delivery_attempt_lease_token_check" CHECK (btrim(lease_token::text) <> ''::text),
    CONSTRAINT "event_delivery_attempt_operation_check" CHECK (operation::text = ANY (ARRAY['SEND'::character varying, 'RECONCILE'::character varying]::text[])),
    CONSTRAINT "event_delivery_attempt_pkey" PRIMARY KEY (id),
    CONSTRAINT "event_delivery_attempt_result_check" CHECK (result::text = ANY (ARRAY['SUCCESS'::character varying, 'RETRYABLE_FAILURE'::character varying, 'PERMANENT_FAILURE'::character varying, 'UNKNOWN'::character varying, 'CONFIRMED_ABSENT'::character varying, 'CANCELLED'::character varying]::text[])),
    CONSTRAINT "event_delivery_attempt_tenant_id_delivery_id_attempt_no_key" UNIQUE (tenant_id, delivery_id, attempt_no),
    CONSTRAINT "event_delivery_attempt_tenant_id_delivery_id_fkey" FOREIGN KEY (tenant_id, delivery_id) REFERENCES delivery.event_delivery(tenant_id, id),
    CONSTRAINT "event_delivery_attempt_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id)
);
COMMENT ON TABLE delivery.event_delivery_attempt IS '追加式外发和对账执行记录；每次尝试结束或租约回收后写入结果，不把超时推断成远端失败。';
COMMENT ON COLUMN delivery.event_delivery_attempt."id" IS '应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN delivery.event_delivery_attempt."tenant_id" IS '所属企业；同企业关联和行级隔离的边界。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN delivery.event_delivery_attempt."delivery_id" IS '对应的订阅投递记录。 设计场景：把多次发送和对账尝试关联到同一投递记录，方便还原重试经过。';
COMMENT ON COLUMN delivery.event_delivery_attempt."attempt_no" IS '该投递的执行记录序号，包含发送与对账并发控制。 设计场景：将每一次执行独立编号，重试后仍能还原前一次失败、超时或成功的经过。';
COMMENT ON COLUMN delivery.event_delivery_attempt."operation" IS '本次操作：SEND 发送，RECONCILE 对账。 设计场景：显式区分创建、更新、停用、归档或清理等动作，重试继续相同意图，不根据当前显示文案猜测操作。';
COMMENT ON COLUMN delivery.event_delivery_attempt."result" IS '结果；CONFIRMED_ABSENT 仅用于对账确认远端未接收，不能由超时直接推断。 设计场景：区分成功、拒绝、失败和结果未知等执行结果；不能把超时直接当作远端未执行。';
COMMENT ON COLUMN delivery.event_delivery_attempt."lease_token" IS '执行时的唯一租约标识，用于识别过期执行者。 设计场景：区分同一任务不同轮次的执行权，防止旧执行器在任务已被接管后迟到回写结果。';
COMMENT ON COLUMN delivery.event_delivery_attempt."http_status" IS '远端 HTTP 状态码。 设计场景：记录远端传输响应便于分类排障；收到 HTTP 成功不一定代表下游业务已经完成。';
COMMENT ON COLUMN delivery.event_delivery_attempt."error_code" IS '脱敏错误代码。 设计场景：用稳定且脱敏的分类定位失败和选择补偿方式；不把凭据、完整响应或个人资料写入错误字段。';
COMMENT ON COLUMN delivery.event_delivery_attempt."receipt_ref" IS '远端回执或受控对账证据引用，不保存认证信息。 设计场景：将外发结果和受控回执证据连接起来，核查时取受保护材料，日志不复制敏感响应。';
COMMENT ON COLUMN delivery.event_delivery_attempt."request_id" IS '本次执行链路标识。 设计场景：在日志与网络调用中定位这一轮发送或对账请求，重试仍保留各自执行记录。';
COMMENT ON COLUMN delivery.event_delivery_attempt."started_at" IS '本次执行开始时间。 设计场景：记录一次执行真正开始的时刻，用于识别排队与执行耗时、定位长期运行任务。';
COMMENT ON COLUMN delivery.event_delivery_attempt."finished_at" IS '本次结果形成时间。 设计场景：记录本次执行结束以统计耗时和追踪结果；成功或失败仍看状态，不能仅凭有结束时间认定成功。';
COMMENT ON COLUMN delivery.event_delivery_attempt."created_at" IS '结果追加时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';

-- delivery.task：事务outbox：内容认证加密，跨进程租约认领；发送结果不确定标UNKNOWN，不盲目重发
CREATE TABLE delivery.task (
    -- 本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 业务幂等键，避免同一操作重复建立任务。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。
    "idempotency_key" character varying(200) NOT NULL,
    -- 发送渠道 EMAIL 或 SMS。 设计场景：同一投递队列按邮件或短信选择发送适配器和额度，渠道配置不改变业务操作结果。
    "channel" character varying(16) NOT NULL,
    -- 加密的最小投递内容，普通日志和接口不得输出明文。 设计场景：消息正文、收件地址或来源事件可能含敏感信息，按最小必要范围加密保存，执行时受控解密。
    "payload_ciphertext" bytea NOT NULL,
    -- 用于密文解密的受控密钥版本。 设计场景：密钥轮换后按写入时版本选择正确解密材料；不能把新旧密文混用同一把默认密钥。
    "key_version" integer NOT NULL,
    -- 对象状态，允许值及字段组合见本表 CHECK 约束。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'READY'::character varying NOT NULL,
    -- 已尝试次数。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。
    "attempts" integer DEFAULT 0 NOT NULL,
    -- 任务最早可再次领取时间。 设计场景：支持延迟执行和失败后的退避重试，后台只能领取已经到可执行时间的任务。
    "available_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 当前租约持有实例。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。
    "lease_owner" character varying(64),
    -- 当前租约截止时间。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。
    "lease_until" timestamp with time zone,
    -- 最近一次脱敏错误码。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。
    "last_error_code" character varying(64),
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "task_attempts_check" CHECK (attempts >= 0),
    CONSTRAINT "task_channel_check" CHECK (channel::text = ANY (ARRAY['EMAIL'::character varying, 'SMS'::character varying]::text[])),
    CONSTRAINT "task_check" CHECK (status::text = 'CLAIMED'::text AND lease_owner IS NOT NULL AND lease_until IS NOT NULL OR status::text <> 'CLAIMED'::text AND lease_owner IS NULL AND lease_until IS NULL),
    CONSTRAINT "task_id_check" CHECK (id > 0),
    CONSTRAINT "task_idempotency_key_key" UNIQUE (idempotency_key),
    CONSTRAINT "task_key_version_check" CHECK (key_version > 0),
    CONSTRAINT "task_pkey" PRIMARY KEY (id),
    CONSTRAINT "task_status_check" CHECK (status::text = ANY (ARRAY['READY'::character varying, 'CLAIMED'::character varying, 'SENT'::character varying, 'RETRY'::character varying, 'DEAD'::character varying, 'UNKNOWN'::character varying]::text[]))
);
COMMENT ON TABLE delivery.task IS '事务outbox：内容认证加密，跨进程租约认领；发送结果不确定标UNKNOWN，不盲目重发';
COMMENT ON COLUMN delivery.task."id" IS '本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN delivery.task."idempotency_key" IS '业务幂等键，避免同一操作重复建立任务。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。';
COMMENT ON COLUMN delivery.task."channel" IS '发送渠道 EMAIL 或 SMS。 设计场景：同一投递队列按邮件或短信选择发送适配器和额度，渠道配置不改变业务操作结果。';
COMMENT ON COLUMN delivery.task."payload_ciphertext" IS '加密的最小投递内容，普通日志和接口不得输出明文。 设计场景：消息正文、收件地址或来源事件可能含敏感信息，按最小必要范围加密保存，执行时受控解密。';
COMMENT ON COLUMN delivery.task."key_version" IS '用于密文解密的受控密钥版本。 设计场景：密钥轮换后按写入时版本选择正确解密材料；不能把新旧密文混用同一把默认密钥。';
COMMENT ON COLUMN delivery.task."status" IS '对象状态，允许值及字段组合见本表 CHECK 约束。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN delivery.task."attempts" IS '已尝试次数。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。';
COMMENT ON COLUMN delivery.task."available_at" IS '任务最早可再次领取时间。 设计场景：支持延迟执行和失败后的退避重试，后台只能领取已经到可执行时间的任务。';
COMMENT ON COLUMN delivery.task."lease_owner" IS '当前租约持有实例。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。';
COMMENT ON COLUMN delivery.task."lease_until" IS '当前租约截止时间。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。';
COMMENT ON COLUMN delivery.task."last_error_code" IS '最近一次脱敏错误码。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。';
COMMENT ON COLUMN delivery.task."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN delivery.task."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_delivery_due ON delivery.task USING btree (available_at, id) WHERE ((status)::text = ANY ((ARRAY['READY'::character varying, 'RETRY'::character varying])::text[]));
CREATE INDEX ix_delivery_lease ON delivery.task USING btree (lease_until) WHERE ((status)::text = 'CLAIMED'::text);

-- delivery.notification：安全和权限通知元数据；发送队列唯一来源为 delivery.task，通知失败不重做已成功的业务操作。
CREATE TABLE delivery.notification (
    -- 应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 企业通知所属企业；全局账号安全通知为空。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint,
    -- 通知接收账号；本人仅可查看自己的全局安全通知。 设计场景：个人安全通知按全局账号归属展示，不能让其他企业成员查看本人的全部安全事件。
    "recipient_account_id" bigint NOT NULL,
    -- 企业内接收成员，可选；非空时与接收账号和企业一致。 设计场景：企业通知定位到具体成员身份，确认与账号和租户一致，防止跨企业误发。
    "recipient_member_id" bigint,
    -- 复用 EMAIL/SMS 发送任务；发送状态、重试、密文收件地址均在原队列，不维护第二份发送状态。 设计场景：通知元数据关联唯一发送任务，避免通知表和队列表各维护一份状态导致重复投递。
    "task_id" bigint NOT NULL,
    -- 密码变化、登录标识变化、风险登录、权限到期等稳定通知类型。 设计场景：按受控类别组织应用或通知展示，筛选分类不代表业务授权范围。
    "category" character varying(100) NOT NULL,
    -- 通知模板代码，不保存渲染后的敏感正文。 设计场景：由受控模板渲染通知内容，模板升级和语言变化不要求在业务记录复制整段敏感正文。
    "template_code" character varying(100) NOT NULL,
    -- 脱敏目的地址快照，供界面解释投递位置。 设计场景：界面提示邮件或短信发往哪里，同时隐藏完整联系方式，排障不需要暴露原始地址。
    "recipient_masked" character varying(254) NOT NULL,
    -- 产生通知的业务事件幂等关联，不用于重新执行业务。 设计场景：把通知追溯到已完成的业务事件，发送失败后只重试通知，不重做改密或邀请等业务操作。
    "business_event_ref" character varying(200) NOT NULL,
    -- 供应商投递回执状态，与 task 的发送受理状态分开；无回执能力时不得假报已送达。 设计场景：将供应商受理与实际送达分开，未提供回执的渠道不能显示为已送达。
    "receipt_status" character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    -- 供应商回执标识；不保存含密钥的响应。 设计场景：供应商异步回调到达时定位对应通知，回调需要验签与幂等后更新状态。
    "provider_receipt_id" character varying(200),
    -- 已取得明确送达或失败回执的时间。 设计场景：记录供应商明确确认送达或失败的时间，和平台提交发送时间区分。
    "receipt_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近修改时间，由应用更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "notification_category_check" CHECK (btrim(category::text) <> ''::text),
    CONSTRAINT "notification_check" CHECK (recipient_member_id IS NULL OR tenant_id IS NOT NULL),
    CONSTRAINT "notification_check1" CHECK ((receipt_status::text = ANY (ARRAY['DELIVERED'::character varying, 'FAILED'::character varying]::text[])) = (receipt_at IS NOT NULL)),
    CONSTRAINT "notification_check2" CHECK (receipt_at IS NULL OR receipt_at >= created_at),
    CONSTRAINT "notification_check3" CHECK (updated_at >= created_at),
    CONSTRAINT "notification_id_check" CHECK (id > 0),
    CONSTRAINT "notification_pkey" PRIMARY KEY (id),
    CONSTRAINT "notification_receipt_status_check" CHECK (receipt_status::text = ANY (ARRAY['PENDING'::character varying, 'DELIVERED'::character varying, 'FAILED'::character varying, 'UNKNOWN'::character varying]::text[])),
    CONSTRAINT "notification_recipient_account_id_fkey" FOREIGN KEY (recipient_account_id) REFERENCES directory.account(id),
    CONSTRAINT "notification_task_id_fkey" FOREIGN KEY (task_id) REFERENCES delivery.task(id),
    CONSTRAINT "notification_task_id_key" UNIQUE (task_id),
    CONSTRAINT "notification_template_code_check" CHECK (btrim(template_code::text) <> ''::text),
    CONSTRAINT "notification_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "notification_tenant_id_recipient_account_id_business_event__key" UNIQUE NULLS NOT DISTINCT (tenant_id, recipient_account_id, business_event_ref, template_code),
    CONSTRAINT "notification_tenant_id_recipient_member_id_recipient_accou_fkey" FOREIGN KEY (tenant_id, recipient_member_id, recipient_account_id) REFERENCES directory.membership(tenant_id, id, account_id)
);
COMMENT ON TABLE delivery.notification IS '安全和权限通知元数据；发送队列唯一来源为 delivery.task，通知失败不重做已成功的业务操作。';
COMMENT ON COLUMN delivery.notification."id" IS '应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN delivery.notification."tenant_id" IS '企业通知所属企业；全局账号安全通知为空。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN delivery.notification."recipient_account_id" IS '通知接收账号；本人仅可查看自己的全局安全通知。 设计场景：个人安全通知按全局账号归属展示，不能让其他企业成员查看本人的全部安全事件。';
COMMENT ON COLUMN delivery.notification."recipient_member_id" IS '企业内接收成员，可选；非空时与接收账号和企业一致。 设计场景：企业通知定位到具体成员身份，确认与账号和租户一致，防止跨企业误发。';
COMMENT ON COLUMN delivery.notification."task_id" IS '复用 EMAIL/SMS 发送任务；发送状态、重试、密文收件地址均在原队列，不维护第二份发送状态。 设计场景：通知元数据关联唯一发送任务，避免通知表和队列表各维护一份状态导致重复投递。';
COMMENT ON COLUMN delivery.notification."category" IS '密码变化、登录标识变化、风险登录、权限到期等稳定通知类型。 设计场景：按受控类别组织应用或通知展示，筛选分类不代表业务授权范围。';
COMMENT ON COLUMN delivery.notification."template_code" IS '通知模板代码，不保存渲染后的敏感正文。 设计场景：由受控模板渲染通知内容，模板升级和语言变化不要求在业务记录复制整段敏感正文。';
COMMENT ON COLUMN delivery.notification."recipient_masked" IS '脱敏目的地址快照，供界面解释投递位置。 设计场景：界面提示邮件或短信发往哪里，同时隐藏完整联系方式，排障不需要暴露原始地址。';
COMMENT ON COLUMN delivery.notification."business_event_ref" IS '产生通知的业务事件幂等关联，不用于重新执行业务。 设计场景：把通知追溯到已完成的业务事件，发送失败后只重试通知，不重做改密或邀请等业务操作。';
COMMENT ON COLUMN delivery.notification."receipt_status" IS '供应商投递回执状态，与 task 的发送受理状态分开；无回执能力时不得假报已送达。 设计场景：将供应商受理与实际送达分开，未提供回执的渠道不能显示为已送达。';
COMMENT ON COLUMN delivery.notification."provider_receipt_id" IS '供应商回执标识；不保存含密钥的响应。 设计场景：供应商异步回调到达时定位对应通知，回调需要验签与幂等后更新状态。';
COMMENT ON COLUMN delivery.notification."receipt_at" IS '已取得明确送达或失败回执的时间。 设计场景：记录供应商明确确认送达或失败的时间，和平台提交发送时间区分。';
COMMENT ON COLUMN delivery.notification."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN delivery.notification."updated_at" IS '最近修改时间，由应用更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_notification_member ON delivery.notification USING btree (tenant_id, recipient_member_id, recipient_account_id) WHERE (recipient_member_id IS NOT NULL);
CREATE INDEX ix_notification_recipient ON delivery.notification USING btree (recipient_account_id, created_at DESC, id DESC);
CREATE INDEX ix_notification_tenant_time ON delivery.notification USING btree (tenant_id, created_at DESC, id DESC);

-- delivery.subscription_event_type：订阅被明确批准的事件类型及字段白名单；空字段列表拒绝，不能把原始员工对象自动全量发送。
CREATE TABLE delivery.subscription_event_type (
    -- 所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 所属订阅。 设计场景：定位消息接收方及其授权范围，发送或重试时重新检查订阅是否仍有效。
    "subscription_id" bigint NOT NULL,
    -- 允许接收的精确事件类型代码，不使用默认全事件通配符。 设计场景：让订阅方按明确契约选择事件和处理器，避免解析任意业务对象猜测事件含义。
    "event_type" character varying(100) NOT NULL,
    -- 可投影的字段路径白名单，由应用校验支持路径及逐字段权限。 设计场景：企业明确批准哪些字段可以外发，新增字段默认不会自动获得订阅授权。
    "allowed_fields" text[] NOT NULL,
    -- 受控资源过滤条件；只能进一步缩小当前应用与授权人允许的资源范围。 设计场景：同一事件类型只外发订阅有权访问的资源，过滤条件只能缩小范围，不能扩权。
    "resource_filter" jsonb DEFAULT '{}'::jsonb NOT NULL,
    -- 授权条目创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "subscription_event_type_allowed_fields_check" CHECK (cardinality(allowed_fields) > 0 AND array_ndims(allowed_fields) = 1 AND array_position(allowed_fields, NULL::text) IS NULL AND array_position(allowed_fields, ''::text) IS NULL AND array_position(allowed_fields, '*'::text) IS NULL),
    CONSTRAINT "subscription_event_type_event_type_check" CHECK (btrim(event_type::text) <> ''::text),
    CONSTRAINT "subscription_event_type_pkey" PRIMARY KEY (tenant_id, subscription_id, event_type),
    CONSTRAINT "subscription_event_type_resource_filter_check" CHECK (jsonb_typeof(resource_filter) = 'object'::text),
    CONSTRAINT "subscription_event_type_tenant_id_subscription_id_fkey" FOREIGN KEY (tenant_id, subscription_id) REFERENCES delivery.event_subscription(tenant_id, id)
);
COMMENT ON TABLE delivery.subscription_event_type IS '订阅被明确批准的事件类型及字段白名单；空字段列表拒绝，不能把原始员工对象自动全量发送。';
COMMENT ON COLUMN delivery.subscription_event_type."tenant_id" IS '所属企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN delivery.subscription_event_type."subscription_id" IS '所属订阅。 设计场景：定位消息接收方及其授权范围，发送或重试时重新检查订阅是否仍有效。';
COMMENT ON COLUMN delivery.subscription_event_type."event_type" IS '允许接收的精确事件类型代码，不使用默认全事件通配符。 设计场景：让订阅方按明确契约选择事件和处理器，避免解析任意业务对象猜测事件含义。';
COMMENT ON COLUMN delivery.subscription_event_type."allowed_fields" IS '可投影的字段路径白名单，由应用校验支持路径及逐字段权限。 设计场景：企业明确批准哪些字段可以外发，新增字段默认不会自动获得订阅授权。';
COMMENT ON COLUMN delivery.subscription_event_type."resource_filter" IS '受控资源过滤条件；只能进一步缩小当前应用与授权人允许的资源范围。 设计场景：同一事件类型只外发订阅有权访问的资源，过滤条件只能缩小范围，不能扩权。';
COMMENT ON COLUMN delivery.subscription_event_type."created_at" IS '授权条目创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';

-- demo.store_note：每家演示店铺至多一条当前备注；编辑历史由审计保存
CREATE TABLE demo.store_note (
    -- 所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 同企业店铺 ID。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。
    "store_id" bigint NOT NULL,
    -- 演示备注正文，允许清空；不得存放认证凭据。 设计场景：提供最小可编辑业务资源用于验证权限和审计链路，允许按规则清空正文，不承载身份凭据。
    "note" text DEFAULT ''::text NOT NULL,
    -- 最后编辑账号，必须与最后编辑成员对应同一账号。 设计场景：记录最后修改者，便于审计和问题定位；提交时仍须核实其当前账号及业务资格。
    "updated_by_account_id" bigint NOT NULL,
    -- 最后编辑人在此企业的成员身份；复合外键防止跨企业引用。 设计场景：记录操作者在目标企业中的身份，防止只校验全局账号却漏掉企业成员资格。
    "updated_by_member_id" bigint NOT NULL,
    -- 备注独立乐观锁版本；更新匹配旧版本并递增，冲突由应用拒绝。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 由应用在成功编辑备注时显式更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_store_note_times" CHECK (updated_at >= created_at),
    CONSTRAINT "ck_store_note_version" CHECK (version >= 0),
    CONSTRAINT "fk_store_note_editor_account" FOREIGN KEY (updated_by_account_id) REFERENCES directory.account(id) ON DELETE RESTRICT,
    CONSTRAINT "fk_store_note_editor_member" FOREIGN KEY (tenant_id, updated_by_member_id, updated_by_account_id) REFERENCES directory.membership(tenant_id, id, account_id) ON DELETE RESTRICT,
    CONSTRAINT "fk_store_note_store" FOREIGN KEY (tenant_id, store_id) REFERENCES demo.store(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "pk_store_note" PRIMARY KEY (tenant_id, store_id)
);
COMMENT ON TABLE demo.store_note IS '每家演示店铺至多一条当前备注；编辑历史由审计保存';
COMMENT ON COLUMN demo.store_note."tenant_id" IS '所属企业 ID；通过可信事务上下文进行隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN demo.store_note."store_id" IS '同企业店铺 ID。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。';
COMMENT ON COLUMN demo.store_note."note" IS '演示备注正文，允许清空；不得存放认证凭据。 设计场景：提供最小可编辑业务资源用于验证权限和审计链路，允许按规则清空正文，不承载身份凭据。';
COMMENT ON COLUMN demo.store_note."updated_by_account_id" IS '最后编辑账号，必须与最后编辑成员对应同一账号。 设计场景：记录最后修改者，便于审计和问题定位；提交时仍须核实其当前账号及业务资格。';
COMMENT ON COLUMN demo.store_note."updated_by_member_id" IS '最后编辑人在此企业的成员身份；复合外键防止跨企业引用。 设计场景：记录操作者在目标企业中的身份，防止只校验全局账号却漏掉企业成员资格。';
COMMENT ON COLUMN demo.store_note."version" IS '备注独立乐观锁版本；更新匹配旧版本并递增，冲突由应用拒绝。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN demo.store_note."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN demo.store_note."updated_at" IS '由应用在成功编辑备注时显式更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_store_note_editor_account ON demo.store_note USING btree (updated_by_account_id);
CREATE INDEX ix_store_note_editor_member ON demo.store_note USING btree (tenant_id, updated_by_member_id, updated_by_account_id);

-- directory.account_profile：账号展示资料，账号可暂时没有资料；登录邮箱和手机号由 Identity 单独维护。
CREATE TABLE directory.account_profile (
    -- 所属全局账号，一个账号最多一份资料。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 全局显示名称，不唯一且不能用于身份匹配。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。
    "display_name" character varying(200) NOT NULL,
    -- 头像展示引用，不保存长期访问令牌。 设计场景：头像更新不改变账号或成员身份，图片通过受控资源引用展示，不把存储长期凭据写入资料。
    "avatar_ref" text,
    -- 应用校验的语言区域标识，例如 zh-CN。 设计场景：根据个人或企业偏好展示语言与格式，不能改变协议标识的规范化规则。
    "locale" character varying(35) NOT NULL,
    -- 应用校验的 IANA 时区名称，例如 Asia/Shanghai。 设计场景：将 UTC 事实时间转换为用户或企业当地时间展示，避免不同地区把同一时刻解释为不同业务事实。
    "time_zone" character varying(64) NOT NULL,
    -- 资料聚合乐观锁版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由应用写入。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_account_profile_display_name" CHECK (btrim(display_name::text) <> ''::text),
    CONSTRAINT "ck_account_profile_locale" CHECK (btrim(locale::text) <> ''::text),
    CONSTRAINT "ck_account_profile_time_zone" CHECK (btrim(time_zone::text) <> ''::text),
    CONSTRAINT "ck_account_profile_version" CHECK (version >= 0),
    CONSTRAINT "fk_account_profile_account" FOREIGN KEY (account_id) REFERENCES directory.account(id) ON DELETE RESTRICT,
    CONSTRAINT "pk_directory_account_profile" PRIMARY KEY (account_id)
);
COMMENT ON TABLE directory.account_profile IS '账号展示资料，账号可暂时没有资料；登录邮箱和手机号由 Identity 单独维护。';
COMMENT ON COLUMN directory.account_profile."account_id" IS '所属全局账号，一个账号最多一份资料。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN directory.account_profile."display_name" IS '全局显示名称，不唯一且不能用于身份匹配。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。';
COMMENT ON COLUMN directory.account_profile."avatar_ref" IS '头像展示引用，不保存长期访问令牌。 设计场景：头像更新不改变账号或成员身份，图片通过受控资源引用展示，不把存储长期凭据写入资料。';
COMMENT ON COLUMN directory.account_profile."locale" IS '应用校验的语言区域标识，例如 zh-CN。 设计场景：根据个人或企业偏好展示语言与格式，不能改变协议标识的规范化规则。';
COMMENT ON COLUMN directory.account_profile."time_zone" IS '应用校验的 IANA 时区名称，例如 Asia/Shanghai。 设计场景：将 UTC 事实时间转换为用户或企业当地时间展示，避免不同地区把同一时刻解释为不同业务事实。';
COMMENT ON COLUMN directory.account_profile."version" IS '资料聚合乐观锁版本。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.account_profile."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.account_profile."updated_at" IS '最近更新时间，由应用写入。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';

-- identity.verification_challenge：绑定认证过程、用途及目标的一次性证明；校验、错误计数、消费、重发替代必须原子执行。
CREATE TABLE identity.verification_challenge (
    -- 本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 关联的受限认证过程 ID。 设计场景：一次性挑战或认证证据只能用于其所属认证过程，避免把重置密码验证码拿去完成其他登录步骤。
    "attempt_id" bigint NOT NULL,
    -- 非空时复合外键保证与 attempt 同账号；空值用于尚未绑定账号的证明，外键不强制父过程账号也为空。开户/升格须在事务中重新核对并绑定，空值不授予任何账号权限。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint,
    -- 一次性证明用途，消费时必须精确匹配。 设计场景：即使手机号与验证码相同，也必须区分登录、绑定、换绑和恢复，避免证明跨用途复用。
    "purpose" character varying(32) NOT NULL,
    -- 证明目标类型，如 EMAIL/PHONE；允许为空时见约束。 设计场景：标明本次验证的是邮箱还是手机号等目标；没有目标的证明按用途约束，不能拿另一种目标的验证码来绑定。
    "target_kind" character varying(16),
    -- 待验证邮箱或国际手机号，与login_identifier使用相同规范；用户名不发送归属验证码。 设计场景：校验证明时绑定准确的邮箱或手机号，防止验证了地址 A 却把地址 B 绑定为登录方式。
    "target_normalized" character varying(254),
    -- 固定 32 字节：高熵令牌的 SHA-256 或短验证码的 HMAC-SHA-256；摘要/HMAC 均由应用实现，绝不保存原始令牌。 设计场景：只保留令牌摘要或短验证码 HMAC，校验时重新计算；低熵验证码不能用裸散列抵抗离线枚举。
    "verifier" bytea NOT NULL,
    -- HMAC 服务端密钥版本，密钥在数据库之外；为 NULL 仅允许高熵令牌的 SHA-256。手机号验证码强制设置版本，其他短验证码也必须用 HMAC。 设计场景：密钥轮换后按写入时版本选择正确解密材料；不能把新旧密文混用同一把默认密钥。
    "key_version" integer,
    -- 调用时与 attempt 的 expires_at 一并检查，不能依赖清理任务；已消费、被替代或耗尽次数的记录也必须拒绝。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone NOT NULL,
    -- 累计校验尝试次数。 设计场景：错误校验原子计数并达到上限后拒绝，避免并发猜码绕过次数限制。
    "attempt_count" integer DEFAULT 0 NOT NULL,
    -- 允许的最大校验尝试次数。 设计场景：限制自动执行或校验次数，避免无限重试和暴力猜测；具体场景由所在表决定。
    "max_attempts" integer DEFAULT 5 NOT NULL,
    -- 一次性证明成功消费时间。 设计场景：一次性证明成功使用后立即标记，业务效果与消费同事务完成，防止重复回调再次生效。
    "consumed_at" timestamp with time zone,
    -- 被重发的新证明替代的时间，之后不可再使用。 设计场景：重发验证码后使旧码失效，用户翻到旧消息时不能继续完成当前流程。
    "superseded_at" timestamp with time zone,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_verification_challenge_attempts" CHECK (max_attempts > 0 AND attempt_count >= 0 AND attempt_count <= max_attempts),
    CONSTRAINT "ck_verification_challenge_consumed" CHECK (consumed_at IS NULL OR consumed_at >= created_at AND consumed_at < expires_at),
    CONSTRAINT "ck_verification_challenge_expiry" CHECK (expires_at > created_at),
    CONSTRAINT "ck_verification_challenge_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_verification_challenge_key" CHECK (key_version IS NULL OR key_version > 0),
    CONSTRAINT "ck_verification_challenge_phone_hmac" CHECK (target_kind::text IS DISTINCT FROM 'PHONE'::text OR key_version IS NOT NULL),
    CONSTRAINT "ck_verification_challenge_superseded" CHECK (superseded_at IS NULL OR superseded_at >= created_at),
    CONSTRAINT "ck_verification_challenge_target" CHECK (target_kind IS NULL AND target_normalized IS NULL OR target_kind IS NOT NULL AND target_normalized IS NOT NULL AND (target_kind::text = ANY (ARRAY['EMAIL'::character varying, 'PHONE'::character varying]::text[])) AND target_normalized::text <> ''::text AND target_normalized::text = btrim(target_normalized::text) AND (target_kind::text = 'EMAIL'::text AND target_normalized::text = lower(target_normalized::text) OR target_kind::text = 'PHONE'::text AND target_normalized::text ~ '^\+[1-9][0-9]{1,14}$'::text)),
    CONSTRAINT "ck_verification_challenge_updated" CHECK (updated_at >= created_at),
    CONSTRAINT "ck_verification_challenge_verifier" CHECK (octet_length(verifier) = 32),
    CONSTRAINT "fk_verification_challenge_account" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "fk_verification_challenge_attempt" FOREIGN KEY (attempt_id, purpose) REFERENCES identity.authentication_attempt(id, purpose),
    CONSTRAINT "fk_verification_challenge_attempt_account" FOREIGN KEY (account_id, attempt_id) REFERENCES identity.authentication_attempt(account_id, id),
    CONSTRAINT "uq_verification_challenge_account_id" UNIQUE (account_id, id),
    CONSTRAINT "verification_challenge_pkey" PRIMARY KEY (id)
);
COMMENT ON TABLE identity.verification_challenge IS '绑定认证过程、用途及目标的一次性证明；校验、错误计数、消费、重发替代必须原子执行。';
COMMENT ON COLUMN identity.verification_challenge."id" IS '本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.verification_challenge."attempt_id" IS '关联的受限认证过程 ID。 设计场景：一次性挑战或认证证据只能用于其所属认证过程，避免把重置密码验证码拿去完成其他登录步骤。';
COMMENT ON COLUMN identity.verification_challenge."account_id" IS '非空时复合外键保证与 attempt 同账号；空值用于尚未绑定账号的证明，外键不强制父过程账号也为空。开户/升格须在事务中重新核对并绑定，空值不授予任何账号权限。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.verification_challenge."purpose" IS '一次性证明用途，消费时必须精确匹配。 设计场景：即使手机号与验证码相同，也必须区分登录、绑定、换绑和恢复，避免证明跨用途复用。';
COMMENT ON COLUMN identity.verification_challenge."target_kind" IS '证明目标类型，如 EMAIL/PHONE；允许为空时见约束。 设计场景：标明本次验证的是邮箱还是手机号等目标；没有目标的证明按用途约束，不能拿另一种目标的验证码来绑定。';
COMMENT ON COLUMN identity.verification_challenge."target_normalized" IS '待验证邮箱或国际手机号，与login_identifier使用相同规范；用户名不发送归属验证码。 设计场景：校验证明时绑定准确的邮箱或手机号，防止验证了地址 A 却把地址 B 绑定为登录方式。';
COMMENT ON COLUMN identity.verification_challenge."verifier" IS '固定 32 字节：高熵令牌的 SHA-256 或短验证码的 HMAC-SHA-256；摘要/HMAC 均由应用实现，绝不保存原始令牌。 设计场景：只保留令牌摘要或短验证码 HMAC，校验时重新计算；低熵验证码不能用裸散列抵抗离线枚举。';
COMMENT ON COLUMN identity.verification_challenge."key_version" IS 'HMAC 服务端密钥版本，密钥在数据库之外；为 NULL 仅允许高熵令牌的 SHA-256。手机号验证码强制设置版本，其他短验证码也必须用 HMAC。 设计场景：密钥轮换后按写入时版本选择正确解密材料；不能把新旧密文混用同一把默认密钥。';
COMMENT ON COLUMN identity.verification_challenge."expires_at" IS '调用时与 attempt 的 expires_at 一并检查，不能依赖清理任务；已消费、被替代或耗尽次数的记录也必须拒绝。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN identity.verification_challenge."attempt_count" IS '累计校验尝试次数。 设计场景：错误校验原子计数并达到上限后拒绝，避免并发猜码绕过次数限制。';
COMMENT ON COLUMN identity.verification_challenge."max_attempts" IS '允许的最大校验尝试次数。 设计场景：限制自动执行或校验次数，避免无限重试和暴力猜测；具体场景由所在表决定。';
COMMENT ON COLUMN identity.verification_challenge."consumed_at" IS '一次性证明成功消费时间。 设计场景：一次性证明成功使用后立即标记，业务效果与消费同事务完成，防止重复回调再次生效。';
COMMENT ON COLUMN identity.verification_challenge."superseded_at" IS '被重发的新证明替代的时间，之后不可再使用。 设计场景：重发验证码后使旧码失效，用户翻到旧消息时不能继续完成当前流程。';
COMMENT ON COLUMN identity.verification_challenge."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.verification_challenge."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_verification_challenge_account ON identity.verification_challenge USING btree (account_id, attempt_id);
CREATE INDEX ix_verification_challenge_attempt ON identity.verification_challenge USING btree (attempt_id, purpose);
CREATE INDEX ix_verification_challenge_expiry ON identity.verification_challenge USING btree (expires_at);

-- directory.invitation_proof：已有账号接受其他联系地址邀请的独立证明；不写入个人登录标识。
CREATE TABLE directory.invitation_proof (
    -- 应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 对应邀请。 设计场景：将待授予权限或归属证明绑定到同一邀请，邀请被撤销、过期或重发后按规则重新核验。
    "invitation_id" bigint NOT NULL,
    -- 邀请重发代数；消费时检查仍为当前代数。 设计场景：重发邀请后旧邮件链接必须失效；递增代数让旧证明也不能拿来接受新一轮邀请。
    "token_generation" bigint NOT NULL,
    -- 完成证明的当前账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 验证邀请联系地址的已消费验证码证明；账号目标可不用。 设计场景：将邀请归属验证关联到具体挑战结果，最终检查证明用途、账号与邀请代数是否匹配。
    "challenge_id" bigint,
    -- 证明方式；受控链接需要业务核验其领取资格。 设计场景：按邀请类型选择对应核验方式，验证联系邮箱和指定账号本人不能混用。
    "proof_kind" character varying(16) NOT NULL,
    -- 核验时间。 设计场景：区分仅声明拥有身份、地址或域名与已经实际完成核验，核验结果是否仍有效由期限与状态共同决定。
    "verified_at" timestamp with time zone NOT NULL,
    -- 证明有效期。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone NOT NULL,
    -- 邀请接受时原子消费。 设计场景：一次性证明成功使用后立即标记，业务效果与消费同事务完成，防止重复回调再次生效。
    "consumed_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_invitation_proof_consumed_time" CHECK (consumed_at IS NULL OR consumed_at >= verified_at AND consumed_at < expires_at),
    CONSTRAINT "fk_invitation_proof_challenge_owner" FOREIGN KEY (account_id, challenge_id) REFERENCES identity.verification_challenge(account_id, id),
    CONSTRAINT "invitation_proof_account_id_fkey" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "invitation_proof_challenge_id_fkey" FOREIGN KEY (challenge_id) REFERENCES identity.verification_challenge(id),
    CONSTRAINT "invitation_proof_check" CHECK (expires_at > verified_at),
    CONSTRAINT "invitation_proof_check1" CHECK (proof_kind::text <> 'EMAIL'::text OR challenge_id IS NOT NULL),
    CONSTRAINT "invitation_proof_id_check" CHECK (id > 0),
    CONSTRAINT "invitation_proof_invitation_id_token_generation_account_id_key" UNIQUE (invitation_id, token_generation, account_id),
    CONSTRAINT "invitation_proof_pkey" PRIMARY KEY (id),
    CONSTRAINT "invitation_proof_proof_kind_check" CHECK (proof_kind::text = ANY (ARRAY['EMAIL'::character varying, 'ACCOUNT'::character varying, 'REVIEWED_LINK'::character varying]::text[])),
    CONSTRAINT "invitation_proof_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "invitation_proof_tenant_id_invitation_id_fkey" FOREIGN KEY (tenant_id, invitation_id) REFERENCES directory.invitation(tenant_id, id),
    CONSTRAINT "invitation_proof_token_generation_check" CHECK (token_generation > 0)
);
COMMENT ON TABLE directory.invitation_proof IS '已有账号接受其他联系地址邀请的独立证明；不写入个人登录标识。';
COMMENT ON COLUMN directory.invitation_proof."id" IS '应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.invitation_proof."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.invitation_proof."invitation_id" IS '对应邀请。 设计场景：将待授予权限或归属证明绑定到同一邀请，邀请被撤销、过期或重发后按规则重新核验。';
COMMENT ON COLUMN directory.invitation_proof."token_generation" IS '邀请重发代数；消费时检查仍为当前代数。 设计场景：重发邀请后旧邮件链接必须失效；递增代数让旧证明也不能拿来接受新一轮邀请。';
COMMENT ON COLUMN directory.invitation_proof."account_id" IS '完成证明的当前账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN directory.invitation_proof."challenge_id" IS '验证邀请联系地址的已消费验证码证明；账号目标可不用。 设计场景：将邀请归属验证关联到具体挑战结果，最终检查证明用途、账号与邀请代数是否匹配。';
COMMENT ON COLUMN directory.invitation_proof."proof_kind" IS '证明方式；受控链接需要业务核验其领取资格。 设计场景：按邀请类型选择对应核验方式，验证联系邮箱和指定账号本人不能混用。';
COMMENT ON COLUMN directory.invitation_proof."verified_at" IS '核验时间。 设计场景：区分仅声明拥有身份、地址或域名与已经实际完成核验，核验结果是否仍有效由期限与状态共同决定。';
COMMENT ON COLUMN directory.invitation_proof."expires_at" IS '证明有效期。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN directory.invitation_proof."consumed_at" IS '邀请接受时原子消费。 设计场景：一次性证明成功使用后立即标记，业务效果与消费同事务完成，防止重复回调再次生效。';
COMMENT ON COLUMN directory.invitation_proof."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_invitation_proof_tenant ON directory.invitation_proof USING btree (tenant_id, invitation_id);

-- directory.member_activation：预登记员工与账号的受控关联/激活证明；不能仅凭企业手机号或管理员修改就接管账号。
CREATE TABLE directory.member_activation (
    -- 应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 待关联的稳定员工记录。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 本人证明对应的目标平台账号。 设计场景：待激活员工先于平台账号存在，最终激活事务将本人验证过的账号绑定到稳定员工，不能依据管理员填写的工作邮箱猜测。
    "account_id" bigint NOT NULL,
    -- 目标账号本人的受限认证过程；消费时还需检查已完成、用途、时效及认证撤销版本。 设计场景：把激活、委托等敏感操作与本人验证关联，最终事务检查用途、完成状态、期限和撤销版本。
    "authentication_attempt_id" bigint NOT NULL,
    -- 关联证明方式。 设计场景：记录实际使用的证明方式，敏感操作按可信验证结果判断，而非接受前端自报方式。
    "method" character varying(24) NOT NULL,
    -- 身份核验/邀请/来源回调的受控证据引用，非裸手机号。 设计场景：关联受保护的核验材料或执行证据，审查时可以回溯；普通接口不直接暴露证据内容与访问凭据。
    "evidence_ref" character varying(200) NOT NULL,
    -- 证明状态；消费与成员账号关联同事务。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    -- 一次性证明截止时间。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone NOT NULL,
    -- 核验通过时间。 设计场景：区分仅声明拥有身份、地址或域名与已经实际完成核验，核验结果是否仍有效由期限与状态共同决定。
    "verified_at" timestamp with time zone,
    -- 单次消费时间。 设计场景：一次性证明成功使用后立即标记，业务效果与消费同事务完成，防止重复回调再次生效。
    "consumed_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "member_activation_account_id_authentication_attempt_id_fkey" FOREIGN KEY (account_id, authentication_attempt_id) REFERENCES identity.authentication_attempt(account_id, id),
    CONSTRAINT "member_activation_account_id_fkey" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "member_activation_check" CHECK (expires_at > created_at),
    CONSTRAINT "member_activation_check1" CHECK (verified_at IS NULL OR verified_at >= created_at AND verified_at < expires_at),
    CONSTRAINT "member_activation_check2" CHECK (consumed_at IS NULL OR verified_at IS NOT NULL AND consumed_at >= verified_at AND consumed_at < expires_at),
    CONSTRAINT "member_activation_check3" CHECK ((status::text <> ALL (ARRAY['VERIFIED'::character varying, 'CONSUMED'::character varying]::text[])) OR verified_at IS NOT NULL),
    CONSTRAINT "member_activation_check4" CHECK ((status::text = 'CONSUMED'::text) = (consumed_at IS NOT NULL)),
    CONSTRAINT "member_activation_evidence_ref_check" CHECK (btrim(evidence_ref::text) <> ''::text),
    CONSTRAINT "member_activation_id_check" CHECK (id > 0),
    CONSTRAINT "member_activation_method_check" CHECK (method::text = ANY (ARRAY['INVITATION'::character varying, 'EXTERNAL_LOGIN'::character varying, 'ACCOUNT_REAUTH'::character varying, 'RECOVERY'::character varying]::text[])),
    CONSTRAINT "member_activation_pkey" PRIMARY KEY (id),
    CONSTRAINT "member_activation_status_check" CHECK (status::text = ANY (ARRAY['PENDING'::character varying, 'VERIFIED'::character varying, 'CONSUMED'::character varying, 'REVOKED'::character varying]::text[])),
    CONSTRAINT "member_activation_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "member_activation_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "member_activation_tenant_id_member_id_fkey" FOREIGN KEY (tenant_id, member_id) REFERENCES directory.membership(tenant_id, id)
);
COMMENT ON TABLE directory.member_activation IS '预登记员工与账号的受控关联/激活证明；不能仅凭企业手机号或管理员修改就接管账号。';
COMMENT ON COLUMN directory.member_activation."id" IS '应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.member_activation."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.member_activation."member_id" IS '待关联的稳定员工记录。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN directory.member_activation."account_id" IS '本人证明对应的目标平台账号。 设计场景：待激活员工先于平台账号存在，最终激活事务将本人验证过的账号绑定到稳定员工，不能依据管理员填写的工作邮箱猜测。';
COMMENT ON COLUMN directory.member_activation."authentication_attempt_id" IS '目标账号本人的受限认证过程；消费时还需检查已完成、用途、时效及认证撤销版本。 设计场景：把激活、委托等敏感操作与本人验证关联，最终事务检查用途、完成状态、期限和撤销版本。';
COMMENT ON COLUMN directory.member_activation."method" IS '关联证明方式。 设计场景：记录实际使用的证明方式，敏感操作按可信验证结果判断，而非接受前端自报方式。';
COMMENT ON COLUMN directory.member_activation."evidence_ref" IS '身份核验/邀请/来源回调的受控证据引用，非裸手机号。 设计场景：关联受保护的核验材料或执行证据，审查时可以回溯；普通接口不直接暴露证据内容与访问凭据。';
COMMENT ON COLUMN directory.member_activation."status" IS '证明状态；消费与成员账号关联同事务。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.member_activation."expires_at" IS '一次性证明截止时间。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN directory.member_activation."verified_at" IS '核验通过时间。 设计场景：区分仅声明拥有身份、地址或域名与已经实际完成核验，核验结果是否仍有效由期限与状态共同决定。';
COMMENT ON COLUMN directory.member_activation."consumed_at" IS '单次消费时间。 设计场景：一次性证明成功使用后立即标记，业务效果与消费同事务完成，防止重复回调再次生效。';
COMMENT ON COLUMN directory.member_activation."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_member_activation_account ON directory.member_activation USING btree (account_id);
CREATE INDEX ix_member_activation_pending ON directory.member_activation USING btree (tenant_id, member_id, status);

-- directory.member_department：成员当前有效的部门关系；允许待激活员工预分配组织。member_department_source 保留独立维护来源，只有最后来源移除后才能删除关系。
CREATE TABLE directory.member_department (
    -- 所属企业，两端复合外键保证成员与部门同企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 本企业稳定员工 ID；PENDING 可预分配组织，但只有 ACTIVE 成员可访问业务。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 所属部门 ID。 设计场景：将人员、规则或变更指向稳定的本地部门，部门改名后关联不丢失，跨企业引用被拒绝。
    "department_id" bigint NOT NULL,
    -- 是否主部门；部分唯一索引保证每位企业成员最多一个主部门。 设计场景：人员同时属于多个部门时保留唯一主部门，方便通讯录和业务默认展示；其他任职关系仍保留。
    "is_primary" boolean DEFAULT false NOT NULL,
    -- 关系建立时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "fk_member_department_department" FOREIGN KEY (tenant_id, department_id) REFERENCES directory.department(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "fk_member_department_member" FOREIGN KEY (tenant_id, member_id) REFERENCES directory.membership(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "pk_directory_member_department" PRIMARY KEY (tenant_id, member_id, department_id)
);
COMMENT ON TABLE directory.member_department IS '成员当前有效的部门关系；允许待激活员工预分配组织。member_department_source 保留独立维护来源，只有最后来源移除后才能删除关系。';
COMMENT ON COLUMN directory.member_department."tenant_id" IS '所属企业，两端复合外键保证成员与部门同企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.member_department."member_id" IS '本企业稳定员工 ID；PENDING 可预分配组织，但只有 ACTIVE 成员可访问业务。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN directory.member_department."department_id" IS '所属部门 ID。 设计场景：将人员、规则或变更指向稳定的本地部门，部门改名后关联不丢失，跨企业引用被拒绝。';
COMMENT ON COLUMN directory.member_department."is_primary" IS '是否主部门；部分唯一索引保证每位企业成员最多一个主部门。 设计场景：人员同时属于多个部门时保留唯一主部门，方便通讯录和业务默认展示；其他任职关系仍保留。';
COMMENT ON COLUMN directory.member_department."created_at" IS '关系建立时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_member_department_department_member ON directory.member_department USING btree (tenant_id, department_id, member_id);
CREATE UNIQUE INDEX uq_member_department_primary ON directory.member_department USING btree (tenant_id, member_id) WHERE is_primary;

-- directory.member_department_source：成员部门关系的独立来源事实；保留一个有效来源就保留关系，同步不能删除 LOCAL 来源。
CREATE TABLE directory.member_department_source (
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 成员 ID。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 部门 ID。 设计场景：将人员、规则或变更指向稳定的本地部门，部门改名后关联不丢失，跨企业引用被拒绝。
    "department_id" bigint NOT NULL,
    -- LOCAL 或 CONNECTION:连接ID；一个来源对同一关系最多一条事实。 设计场景：同一部门任职可由手工和多个连接同时支持，删除其中一个来源不应删除整个有效关系。
    "source_key" character varying(100) NOT NULL,
    -- 外部来源连接；LOCAL 为空。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint,
    -- 来源是否声称主部门；多个来源冲突由用例明确选定，最终表仍只允许一个主部门。 设计场景：保存各来源声称的主部门信息，冲突时由明确规则选定最终主部门，不随机覆盖。
    "is_primary_claim" boolean DEFAULT false NOT NULL,
    -- 最近确认关系的运行；本地关系为空。 设计场景：全量对账时知道对象在哪个批次被确认存在，避免拿旧批次的可见性判断本次删除。
    "last_seen_run_id" bigint,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "fk_department_source_department_mapping" FOREIGN KEY (tenant_id, connection_id, department_id) REFERENCES directory.source_department(tenant_id, connection_id, department_id),
    CONSTRAINT "fk_department_source_member_mapping" FOREIGN KEY (tenant_id, connection_id, member_id) REFERENCES directory.source_member(tenant_id, connection_id, member_id),
    CONSTRAINT "member_department_source_check" CHECK (connection_id IS NULL AND source_key::text = 'LOCAL'::text AND last_seen_run_id IS NULL OR connection_id IS NOT NULL AND source_key::text = ('CONNECTION:'::text || connection_id::text)),
    CONSTRAINT "member_department_source_pkey" PRIMARY KEY (tenant_id, member_id, department_id, source_key),
    CONSTRAINT "member_department_source_tenant_id_connection_id_fkey" FOREIGN KEY (tenant_id, connection_id) REFERENCES directory.sync_connection(tenant_id, id),
    CONSTRAINT "member_department_source_tenant_id_connection_id_last_seen_fkey" FOREIGN KEY (tenant_id, connection_id, last_seen_run_id) REFERENCES directory.sync_run(tenant_id, connection_id, id),
    CONSTRAINT "member_department_source_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "member_department_source_tenant_id_member_id_department_id_fkey" FOREIGN KEY (tenant_id, member_id, department_id) REFERENCES directory.member_department(tenant_id, member_id, department_id) ON DELETE RESTRICT
);
COMMENT ON TABLE directory.member_department_source IS '成员部门关系的独立来源事实；保留一个有效来源就保留关系，同步不能删除 LOCAL 来源。';
COMMENT ON COLUMN directory.member_department_source."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.member_department_source."member_id" IS '成员 ID。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN directory.member_department_source."department_id" IS '部门 ID。 设计场景：将人员、规则或变更指向稳定的本地部门，部门改名后关联不丢失，跨企业引用被拒绝。';
COMMENT ON COLUMN directory.member_department_source."source_key" IS 'LOCAL 或 CONNECTION:连接ID；一个来源对同一关系最多一条事实。 设计场景：同一部门任职可由手工和多个连接同时支持，删除其中一个来源不应删除整个有效关系。';
COMMENT ON COLUMN directory.member_department_source."connection_id" IS '外部来源连接；LOCAL 为空。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN directory.member_department_source."is_primary_claim" IS '来源是否声称主部门；多个来源冲突由用例明确选定，最终表仍只允许一个主部门。 设计场景：保存各来源声称的主部门信息，冲突时由明确规则选定最终主部门，不随机覆盖。';
COMMENT ON COLUMN directory.member_department_source."last_seen_run_id" IS '最近确认关系的运行；本地关系为空。 设计场景：全量对账时知道对象在哪个批次被确认存在，避免拿旧批次的可见性判断本次删除。';
COMMENT ON COLUMN directory.member_department_source."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.member_department_source."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_member_department_source_connection ON directory.member_department_source USING btree (tenant_id, connection_id, member_id);

-- identity.external_identity：完成外部身份归属证明后的账号绑定；有效 subject 在连接命名空间内唯一。
CREATE TABLE identity.external_identity (
    -- 本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 外部来源类型，不作为跨连接统一用户身份。 设计场景：区分飞书、钉钉等身份来源并选择适配器，不能将不同厂商返回的相同用户字符串认作同一人。
    "provider" character varying(32) NOT NULL,
    -- 对应来源连接的稳定 ID。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 适配器提供的可信、不透明主体标识；不得按姓名/邮箱合并，不做大小写转换或渠道无关的格式改写。 设计场景：将验证后的外部身份限定在连接命名空间，跨连接同名或同邮箱不能自动合并为同一个人。
    "subject" character varying(512) COLLATE "C" NOT NULL,
    -- 本人归属证明完成并建立绑定的时间。 设计场景：区分来源曾出现某个人和本人已经建立可登录绑定，绑定前需完成归属证明。
    "bound_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近使用该身份成功认证的时间。 设计场景：帮助本人识别长期不用或异常活跃的外部登录方式，来源存在不代表最近认证成功。
    "last_authenticated_at" timestamp with time zone,
    -- 撤销绑定保留历史；重新绑定需要重新证明归属，不开放管理员直接改挂账号。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_external_identity_authenticated" CHECK (last_authenticated_at IS NULL OR last_authenticated_at >= bound_at),
    CONSTRAINT "ck_external_identity_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_external_identity_revoked" CHECK (revoked_at IS NULL OR revoked_at >= bound_at),
    CONSTRAINT "ck_external_identity_subject" CHECK (btrim(subject::text) <> ''::text),
    CONSTRAINT "ck_external_identity_updated" CHECK (updated_at >= created_at),
    CONSTRAINT "external_identity_pkey" PRIMARY KEY (id),
    CONSTRAINT "fk_external_identity_account" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "fk_external_identity_connection" FOREIGN KEY (provider, connection_id) REFERENCES identity.external_connection(provider, id),
    CONSTRAINT "uq_external_identity_id_account" UNIQUE (id, account_id),
    CONSTRAINT "uq_external_identity_id_account_connection" UNIQUE (id, account_id, connection_id)
);
COMMENT ON TABLE identity.external_identity IS '完成外部身份归属证明后的账号绑定；有效 subject 在连接命名空间内唯一。';
COMMENT ON COLUMN identity.external_identity."id" IS '本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.external_identity."account_id" IS '关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.external_identity."provider" IS '外部来源类型，不作为跨连接统一用户身份。 设计场景：区分飞书、钉钉等身份来源并选择适配器，不能将不同厂商返回的相同用户字符串认作同一人。';
COMMENT ON COLUMN identity.external_identity."connection_id" IS '对应来源连接的稳定 ID。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN identity.external_identity."subject" IS '适配器提供的可信、不透明主体标识；不得按姓名/邮箱合并，不做大小写转换或渠道无关的格式改写。 设计场景：将验证后的外部身份限定在连接命名空间，跨连接同名或同邮箱不能自动合并为同一个人。';
COMMENT ON COLUMN identity.external_identity."bound_at" IS '本人归属证明完成并建立绑定的时间。 设计场景：区分来源曾出现某个人和本人已经建立可登录绑定，绑定前需完成归属证明。';
COMMENT ON COLUMN identity.external_identity."last_authenticated_at" IS '最近使用该身份成功认证的时间。 设计场景：帮助本人识别长期不用或异常活跃的外部登录方式，来源存在不代表最近认证成功。';
COMMENT ON COLUMN identity.external_identity."revoked_at" IS '撤销绑定保留历史；重新绑定需要重新证明归属，不开放管理员直接改挂账号。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN identity.external_identity."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.external_identity."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_external_identity_account ON identity.external_identity USING btree (account_id, created_at);
CREATE INDEX ix_external_identity_connection ON identity.external_identity USING btree (provider, connection_id);
CREATE UNIQUE INDEX uq_external_identity_active_subject ON identity.external_identity USING btree (provider, connection_id, subject) WHERE (revoked_at IS NULL);

-- directory.member_external_login：已确认的外部登录绑定与企业来源员工关联；目录映射本身不等于已验证登录凭据。
CREATE TABLE directory.member_external_login (
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 来源员工与登录身份必须属于同一个企业连接命名空间。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 同企业来源员工。 设计场景：把经验证的外部登录绑定关联到同企业、同连接的来源员工；确认该员工离职后阻断这一来源登录，其他独立企业身份继续按各自规则判断。
    "source_member_id" bigint NOT NULL,
    -- 来源记录所对应的成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 已验证的平台账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 已完成归属证明的外部登录身份。 设计场景：企业来源员工必须关联经验证的登录身份，离职后禁用相应入口而不误伤其他独立登录方式。
    "external_identity_id" bigint NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "member_external_login_account_id_fkey" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "member_external_login_external_identity_id_account_id_conn_fkey" FOREIGN KEY (external_identity_id, account_id, connection_id) REFERENCES identity.external_identity(id, account_id, connection_id),
    CONSTRAINT "member_external_login_external_identity_id_key" UNIQUE (external_identity_id),
    CONSTRAINT "member_external_login_pkey" PRIMARY KEY (tenant_id, source_member_id, external_identity_id),
    CONSTRAINT "member_external_login_tenant_id_connection_id_source_membe_fkey" FOREIGN KEY (tenant_id, connection_id, source_member_id) REFERENCES directory.source_member(tenant_id, connection_id, id),
    CONSTRAINT "member_external_login_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "member_external_login_tenant_id_member_id_account_id_fkey" FOREIGN KEY (tenant_id, member_id, account_id) REFERENCES directory.membership(tenant_id, id, account_id),
    CONSTRAINT "member_external_login_tenant_id_source_member_id_member_id_fkey" FOREIGN KEY (tenant_id, source_member_id, member_id) REFERENCES directory.source_member(tenant_id, id, member_id)
);
COMMENT ON TABLE directory.member_external_login IS '已确认的外部登录绑定与企业来源员工关联；目录映射本身不等于已验证登录凭据。';
COMMENT ON COLUMN directory.member_external_login."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.member_external_login."connection_id" IS '来源员工与登录身份必须属于同一个企业连接命名空间。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN directory.member_external_login."source_member_id" IS '同企业来源员工。 设计场景：把经验证的外部登录绑定关联到同企业、同连接的来源员工；确认该员工离职后阻断这一来源登录，其他独立企业身份继续按各自规则判断。';
COMMENT ON COLUMN directory.member_external_login."member_id" IS '来源记录所对应的成员。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN directory.member_external_login."account_id" IS '已验证的平台账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN directory.member_external_login."external_identity_id" IS '已完成归属证明的外部登录身份。 设计场景：企业来源员工必须关联经验证的登录身份，离职后禁用相应入口而不误伤其他独立登录方式。';
COMMENT ON COLUMN directory.member_external_login."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_member_external_login_member ON directory.member_external_login USING btree (tenant_id, member_id);

-- directory.member_field_source：被来源维护的成员字段；未提供/未授权/读取失败与明确清空分别记录。
CREATE TABLE directory.member_field_source (
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 成员 ID。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 受控标准字段或已定义扩展字段键。 设计场景：使用受控标准键或已登记扩展字段，防止同步写入不存在、不可维护或敏感的任意字段。
    "field_key" character varying(64) NOT NULL,
    -- 该字段的权威来源。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 外部字段路径。 设计场景：字段映射变化时知道本地值来自外部哪一个字段，便于排查覆盖和数据缺失。
    "source_field" character varying(200) NOT NULL,
    -- 字段读取结果；只有明确 CLEARED 可按规则清空。 设计场景：来源未授权、未提供、读取失败和明确清空分别处理，避免接口没返回手机号就删除本地资料。
    "availability" character varying(24) NOT NULL,
    -- 最后成功读到或明确清空的时间。 设计场景：显示来源数据的最近落地时间，识别资料陈旧或同步中断；不能据此推断当前快照完整。
    "last_synced_at" timestamp with time zone,
    -- 来源字段版本。 设计场景：回调乱序到达时拒绝旧变更覆盖新状态；来源无可比较版本时回查最新状态，不能按任意字符串排序。
    "source_version" character varying(200),
    CONSTRAINT "fk_member_field_source_mapping" FOREIGN KEY (tenant_id, connection_id, member_id) REFERENCES directory.source_member(tenant_id, connection_id, member_id),
    CONSTRAINT "member_field_source_availability_check" CHECK (availability::text = ANY (ARRAY['PRESENT'::character varying, 'CLEARED'::character varying, 'NOT_PROVIDED'::character varying, 'NOT_AUTHORIZED'::character varying, 'FETCH_FAILED'::character varying]::text[])),
    CONSTRAINT "member_field_source_field_key_check" CHECK (btrim(field_key::text) <> ''::text),
    CONSTRAINT "member_field_source_pkey" PRIMARY KEY (tenant_id, member_id, field_key),
    CONSTRAINT "member_field_source_tenant_id_connection_id_fkey" FOREIGN KEY (tenant_id, connection_id) REFERENCES directory.sync_connection(tenant_id, id),
    CONSTRAINT "member_field_source_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "member_field_source_tenant_id_member_id_fkey" FOREIGN KEY (tenant_id, member_id) REFERENCES directory.membership(tenant_id, id)
);
COMMENT ON TABLE directory.member_field_source IS '被来源维护的成员字段；未提供/未授权/读取失败与明确清空分别记录。';
COMMENT ON COLUMN directory.member_field_source."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.member_field_source."member_id" IS '成员 ID。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN directory.member_field_source."field_key" IS '受控标准字段或已定义扩展字段键。 设计场景：使用受控标准键或已登记扩展字段，防止同步写入不存在、不可维护或敏感的任意字段。';
COMMENT ON COLUMN directory.member_field_source."connection_id" IS '该字段的权威来源。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN directory.member_field_source."source_field" IS '外部字段路径。 设计场景：字段映射变化时知道本地值来自外部哪一个字段，便于排查覆盖和数据缺失。';
COMMENT ON COLUMN directory.member_field_source."availability" IS '字段读取结果；只有明确 CLEARED 可按规则清空。 设计场景：来源未授权、未提供、读取失败和明确清空分别处理，避免接口没返回手机号就删除本地资料。';
COMMENT ON COLUMN directory.member_field_source."last_synced_at" IS '最后成功读到或明确清空的时间。 设计场景：显示来源数据的最近落地时间，识别资料陈旧或同步中断；不能据此推断当前快照完整。';
COMMENT ON COLUMN directory.member_field_source."source_version" IS '来源字段版本。 设计场景：回调乱序到达时拒绝旧变更覆盖新状态；来源无可比较版本时回查最新状态，不能按任意字符串排序。';
CREATE INDEX ix_member_field_source_connection ON directory.member_field_source USING btree (tenant_id, connection_id);

-- directory.member_profile：企业员工资料；允许无账号的预登记员工。不把企业邮箱或手机号当作个人登录标识。
CREATE TABLE directory.member_profile (
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 稳定成员 ID，与账号是否已激活无关。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 企业工号；非所有来源都保证唯一。 设计场景：支持企业按内部工号检索员工，实际唯一性取决于来源和约束，不能拿工号跨企业合并账号。
    "employee_number" character varying(100),
    -- 企业头像受控引用。 设计场景：头像更新不改变账号或成员身份，图片通过受控资源引用展示，不把存储长期凭据写入资料。
    "avatar_ref" text,
    -- 岗位名称。 设计场景：通讯录展示员工岗位，职位名称变化不自动改变角色或业务权限。
    "job_title" character varying(200),
    -- 受控人员类型，如正式员工、外包、客户对接人员。 设计场景：区分正式员工、外包等受控类型，支持资料管理和显式策略条件，不能按文字隐式授予权限。
    "personnel_type" character varying(32),
    -- 同企业主管，可空；事务检查主管链无环。 设计场景：表达企业内主管关系供管理和策略使用，变更时检查循环，避免形成互相汇报链。
    "manager_member_id" bigint,
    -- 企业邮箱，可空、可与其他成员或企业重复；不自动验证。 设计场景：企业可以维护工作联系方式，即使重复、为空或尚未验证也不改变个人登录邮箱。
    "work_email" character varying(254),
    -- 企业电话原始展示值，可空、可重复，不要求手机登录格式。 设计场景：保留员工办公联系信息，座机或来源原始号码不强行转换为可用于短信登录的手机号。
    "work_phone" character varying(64),
    -- 入职日期。 设计场景：记录业务上的入职日期，可能早于平台建档时间，不直接等于账号创建或认证生效时间。
    "hired_on" date,
    -- 离职日期。 设计场景：保留业务离职日期用于资料和审计，阻断访问仍需执行成员停用与关联撤权。
    "left_on" date,
    -- 按企业已定义字段校验的扩展资料；不存权限或登录凭据。 设计场景：企业扩展资料按预先登记的字段定义验证，增加行业资料不必把权限关系和登录凭据塞进 JSON。
    "extensions" jsonb DEFAULT '{}'::jsonb NOT NULL,
    -- 乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "member_profile_check" CHECK (manager_member_id IS NULL OR manager_member_id <> member_id),
    CONSTRAINT "member_profile_check1" CHECK (left_on IS NULL OR hired_on IS NULL OR left_on >= hired_on),
    CONSTRAINT "member_profile_extensions_check" CHECK (jsonb_typeof(extensions) = 'object'::text),
    CONSTRAINT "member_profile_pkey" PRIMARY KEY (tenant_id, member_id),
    CONSTRAINT "member_profile_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "member_profile_tenant_id_manager_member_id_fkey" FOREIGN KEY (tenant_id, manager_member_id) REFERENCES directory.membership(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "member_profile_tenant_id_member_id_fkey" FOREIGN KEY (tenant_id, member_id) REFERENCES directory.membership(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "member_profile_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE directory.member_profile IS '企业员工资料；允许无账号的预登记员工。不把企业邮箱或手机号当作个人登录标识。';
COMMENT ON COLUMN directory.member_profile."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.member_profile."member_id" IS '稳定成员 ID，与账号是否已激活无关。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN directory.member_profile."employee_number" IS '企业工号；非所有来源都保证唯一。 设计场景：支持企业按内部工号检索员工，实际唯一性取决于来源和约束，不能拿工号跨企业合并账号。';
COMMENT ON COLUMN directory.member_profile."avatar_ref" IS '企业头像受控引用。 设计场景：头像更新不改变账号或成员身份，图片通过受控资源引用展示，不把存储长期凭据写入资料。';
COMMENT ON COLUMN directory.member_profile."job_title" IS '岗位名称。 设计场景：通讯录展示员工岗位，职位名称变化不自动改变角色或业务权限。';
COMMENT ON COLUMN directory.member_profile."personnel_type" IS '受控人员类型，如正式员工、外包、客户对接人员。 设计场景：区分正式员工、外包等受控类型，支持资料管理和显式策略条件，不能按文字隐式授予权限。';
COMMENT ON COLUMN directory.member_profile."manager_member_id" IS '同企业主管，可空；事务检查主管链无环。 设计场景：表达企业内主管关系供管理和策略使用，变更时检查循环，避免形成互相汇报链。';
COMMENT ON COLUMN directory.member_profile."work_email" IS '企业邮箱，可空、可与其他成员或企业重复；不自动验证。 设计场景：企业可以维护工作联系方式，即使重复、为空或尚未验证也不改变个人登录邮箱。';
COMMENT ON COLUMN directory.member_profile."work_phone" IS '企业电话原始展示值，可空、可重复，不要求手机登录格式。 设计场景：保留员工办公联系信息，座机或来源原始号码不强行转换为可用于短信登录的手机号。';
COMMENT ON COLUMN directory.member_profile."hired_on" IS '入职日期。 设计场景：记录业务上的入职日期，可能早于平台建档时间，不直接等于账号创建或认证生效时间。';
COMMENT ON COLUMN directory.member_profile."left_on" IS '离职日期。 设计场景：保留业务离职日期用于资料和审计，阻断访问仍需执行成员停用与关联撤权。';
COMMENT ON COLUMN directory.member_profile."extensions" IS '按企业已定义字段校验的扩展资料；不存权限或登录凭据。 设计场景：企业扩展资料按预先登记的字段定义验证，增加行业资料不必把权限关系和登录凭据塞进 JSON。';
COMMENT ON COLUMN directory.member_profile."version" IS '乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.member_profile."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_member_profile_manager ON directory.member_profile USING btree (tenant_id, manager_member_id);

-- directory.platform_settings：平台受控单例配置；内部公司本身必须是正常企业，不自动拥有客户数据权限。
CREATE TABLE directory.platform_settings (
    -- 固定为 true 的单例键。 设计场景：保证平台设置只有一个受控配置入口，避免多个记录各自声称代表内部运营公司。
    "singleton" boolean DEFAULT true NOT NULL,
    -- 内部运营公司租户；由部署管理用例显式选择，不猜测已有客户租户。 设计场景：明确哪家企业是平台内部公司，防止根据名称猜测或把普通客户企业当作平台管理来源。
    "internal_tenant_id" bigint NOT NULL,
    -- 乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "platform_settings_internal_tenant_id_fkey" FOREIGN KEY (internal_tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "platform_settings_internal_tenant_id_key" UNIQUE (internal_tenant_id),
    CONSTRAINT "platform_settings_pkey" PRIMARY KEY (singleton),
    CONSTRAINT "platform_settings_singleton_check" CHECK (singleton),
    CONSTRAINT "platform_settings_singleton_internal_tenant_id_key" UNIQUE (singleton, internal_tenant_id),
    CONSTRAINT "platform_settings_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE directory.platform_settings IS '平台受控单例配置；内部公司本身必须是正常企业，不自动拥有客户数据权限。';
COMMENT ON COLUMN directory.platform_settings."singleton" IS '固定为 true 的单例键。 设计场景：保证平台设置只有一个受控配置入口，避免多个记录各自声称代表内部运营公司。';
COMMENT ON COLUMN directory.platform_settings."internal_tenant_id" IS '内部运营公司租户；由部署管理用例显式选择，不猜测已有客户租户。 设计场景：明确哪家企业是平台内部公司，防止根据名称猜测或把普通客户企业当作平台管理来源。';
COMMENT ON COLUMN directory.platform_settings."version" IS '乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.platform_settings."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';

-- directory.platform_operator：平台职责的内部工作身份前提；已有 platform_role_assignment 仍是职责，运行时必须同时检查此关联及有效成员。
CREATE TABLE directory.platform_operator (
    -- 平台职责账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 引用平台单例配置。 设计场景：保证平台设置只有一个受控配置入口，避免多个记录各自声称代表内部运营公司。
    "singleton" boolean DEFAULT true NOT NULL,
    -- 必须等于受控配置的内部租户。 设计场景：明确哪家企业是平台内部公司，防止根据名称猜测或把普通客户企业当作平台管理来源。
    "internal_tenant_id" bigint NOT NULL,
    -- 此账号在内部租户中的成员。 设计场景：平台职责还要求本人拥有有效内部成员身份，内部离职后不能仅凭全局管理员角色继续操作。
    "internal_member_id" bigint NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "platform_operator_account_id_fkey" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "platform_operator_internal_tenant_id_internal_member_id_ac_fkey" FOREIGN KEY (internal_tenant_id, internal_member_id, account_id) REFERENCES directory.membership(tenant_id, id, account_id),
    CONSTRAINT "platform_operator_pkey" PRIMARY KEY (account_id),
    CONSTRAINT "platform_operator_singleton_check" CHECK (singleton),
    CONSTRAINT "platform_operator_singleton_internal_tenant_id_fkey" FOREIGN KEY (singleton, internal_tenant_id) REFERENCES directory.platform_settings(singleton, internal_tenant_id)
);
COMMENT ON TABLE directory.platform_operator IS '平台职责的内部工作身份前提；已有 platform_role_assignment 仍是职责，运行时必须同时检查此关联及有效成员。';
COMMENT ON COLUMN directory.platform_operator."account_id" IS '平台职责账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN directory.platform_operator."singleton" IS '引用平台单例配置。 设计场景：保证平台设置只有一个受控配置入口，避免多个记录各自声称代表内部运营公司。';
COMMENT ON COLUMN directory.platform_operator."internal_tenant_id" IS '必须等于受控配置的内部租户。 设计场景：明确哪家企业是平台内部公司，防止根据名称猜测或把普通客户企业当作平台管理来源。';
COMMENT ON COLUMN directory.platform_operator."internal_member_id" IS '此账号在内部租户中的成员。 设计场景：平台职责还要求本人拥有有效内部成员身份，内部离职后不能仅凭全局管理员角色继续操作。';
COMMENT ON COLUMN directory.platform_operator."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_platform_operator_member ON directory.platform_operator USING btree (internal_tenant_id, internal_member_id);

-- directory.profile_field_definition：企业可用扩展资料字段的受控定义；来源字段映射引用此约定，不能任意写 JSON。
CREATE TABLE directory.profile_field_definition (
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 企业内唯一字段键。 设计场景：使用受控标准键或已登记扩展字段，防止同步写入不存在、不可维护或敏感的任意字段。
    "field_key" character varying(64) NOT NULL,
    -- 给管理员看的中文字段名。 设计场景：管理员阅读扩展资料字段时使用友好名称，改显示标签不改变字段键及历史数据归属。
    "label" character varying(100) NOT NULL,
    -- 值类型。 设计场景：扩展字段按文本、数字、日期等受控类型验证，避免同一个字段在不同来源被写成不兼容类型。
    "value_type" character varying(16) NOT NULL,
    -- 受控约束：长度、数值边界或枚举值；服务端校验。 设计场景：字段导入和接口写入共用长度、边界或枚举规则，防止前端校验被绕过后产生无效资料。
    "validation" jsonb DEFAULT '{}'::jsonb NOT NULL,
    -- 是否限制展示和导出。 设计场景：对敏感扩展字段限制查看与导出，不能因为字段存在于资料 JSON 中就对所有管理员开放。
    "sensitive" boolean DEFAULT false NOT NULL,
    -- 是否仍可写入。 设计场景：停止使用旧扩展字段时禁止新的写入，同时按保留规则处理已有值，避免直接删除定义导致历史无法解释。
    "enabled" boolean DEFAULT true NOT NULL,
    -- 乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "profile_field_definition_field_key_check" CHECK (field_key::text ~ '^[a-z][a-z0-9_]{0,63}$'::text),
    CONSTRAINT "profile_field_definition_label_check" CHECK (btrim(label::text) <> ''::text),
    CONSTRAINT "profile_field_definition_pkey" PRIMARY KEY (tenant_id, field_key),
    CONSTRAINT "profile_field_definition_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "profile_field_definition_validation_check" CHECK (jsonb_typeof(validation) = 'object'::text),
    CONSTRAINT "profile_field_definition_value_type_check" CHECK (value_type::text = ANY (ARRAY['STRING'::character varying, 'NUMBER'::character varying, 'BOOLEAN'::character varying, 'DATE'::character varying, 'ENUM'::character varying]::text[])),
    CONSTRAINT "profile_field_definition_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE directory.profile_field_definition IS '企业可用扩展资料字段的受控定义；来源字段映射引用此约定，不能任意写 JSON。';
COMMENT ON COLUMN directory.profile_field_definition."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.profile_field_definition."field_key" IS '企业内唯一字段键。 设计场景：使用受控标准键或已登记扩展字段，防止同步写入不存在、不可维护或敏感的任意字段。';
COMMENT ON COLUMN directory.profile_field_definition."label" IS '给管理员看的中文字段名。 设计场景：管理员阅读扩展资料字段时使用友好名称，改显示标签不改变字段键及历史数据归属。';
COMMENT ON COLUMN directory.profile_field_definition."value_type" IS '值类型。 设计场景：扩展字段按文本、数字、日期等受控类型验证，避免同一个字段在不同来源被写成不兼容类型。';
COMMENT ON COLUMN directory.profile_field_definition."validation" IS '受控约束：长度、数值边界或枚举值；服务端校验。 设计场景：字段导入和接口写入共用长度、边界或枚举规则，防止前端校验被绕过后产生无效资料。';
COMMENT ON COLUMN directory.profile_field_definition."sensitive" IS '是否限制展示和导出。 设计场景：对敏感扩展字段限制查看与导出，不能因为字段存在于资料 JSON 中就对所有管理员开放。';
COMMENT ON COLUMN directory.profile_field_definition."enabled" IS '是否仍可写入。 设计场景：停止使用旧扩展字段时禁止新的写入，同时按保留规则处理已有值，避免直接删除定义导致历史无法解释。';
COMMENT ON COLUMN directory.profile_field_definition."version" IS '乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.profile_field_definition."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';

-- directory.sync_change：同步/导入逐项预览、异常和复核记录；大批移除需批准，不因不完整快照删除。
CREATE TABLE directory.sync_change (
    -- 应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 所属运行。 设计场景：将逐项变更或任务归入具体批次，便于查看进度、失败行和恢复范围；是否允许单独任务见字段可空性。
    "run_id" bigint NOT NULL,
    -- 来源对象键或导入行号，用于安全重试。 设计场景：导入失败后定位具体行或来源对象，用户修正后可以安全重试该项而非重做整批。
    "item_key" character varying(512) NOT NULL,
    -- 变更对象类型。 设计场景：同步预览区分员工、部门等对象，选择正确的校验和应用变更流程。
    "object_type" character varying(24) NOT NULL,
    -- 涉及的成员，可在创建前为空。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint,
    -- 涉及的部门，可在创建前为空。 设计场景：将人员、规则或变更指向稳定的本地部门，部门改名后关联不丢失，跨企业引用被拒绝。
    "department_id" bigint,
    -- 拟执行动作。 设计场景：显式区分创建、更新、停用、归档或清理等动作，重试继续相同意图，不根据当前显示文案猜测操作。
    "operation" character varying(16) NOT NULL,
    -- 预览、复核与处理状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'PREVIEW'::character varying NOT NULL,
    -- 受保护的前后差异，界面按权限解密和脱敏。 设计场景：批量变更审批时展示有权查看的前后差异，后台加密保存，避免预览副本泄露敏感员工资料。
    "diff_ciphertext" bytea,
    -- 差异加密密钥版本。 设计场景：密钥轮换后按写入时版本选择正确解密材料；不能把新旧密文混用同一把默认密钥。
    "key_version" integer,
    -- 本企业复核人。 设计场景：记录对批量变更等高影响操作负责的企业复核人，用于追踪批准来源及复核其资格。
    "reviewed_by_member_id" bigint,
    -- 复核时间。 设计场景：追踪人工审核何时作出；执行时还需复核期限与当前资格，不能把历史审核当永久许可。
    "reviewed_at" timestamp with time zone,
    -- 逐行脱敏错误码。 设计场景：用稳定且脱敏的分类定位失败和选择补偿方式；不把凭据、完整响应或个人资料写入错误字段。
    "error_code" character varying(64),
    -- 变更成功时间。 设计场景：把已计算或已审核的变更与实际成功落库区分开，重试时不能重复应用已完成变更。
    "applied_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "sync_change_check" CHECK ((diff_ciphertext IS NULL) = (key_version IS NULL)),
    CONSTRAINT "sync_change_check1" CHECK ((status::text <> ALL (ARRAY['APPROVED'::character varying, 'REJECTED'::character varying]::text[])) OR reviewed_by_member_id IS NOT NULL AND reviewed_at IS NOT NULL),
    CONSTRAINT "sync_change_check2" CHECK (status::text <> 'APPLIED'::text OR applied_at IS NOT NULL),
    CONSTRAINT "sync_change_id_check" CHECK (id > 0),
    CONSTRAINT "sync_change_key_version_check" CHECK (key_version > 0),
    CONSTRAINT "sync_change_object_type_check" CHECK (object_type::text = ANY (ARRAY['MEMBER'::character varying, 'DEPARTMENT'::character varying, 'MEMBER_DEPARTMENT'::character varying]::text[])),
    CONSTRAINT "sync_change_operation_check" CHECK (operation::text = ANY (ARRAY['CREATE'::character varying, 'UPDATE'::character varying, 'LINK'::character varying, 'SUSPEND'::character varying, 'REMOVE'::character varying, 'NOOP'::character varying]::text[])),
    CONSTRAINT "sync_change_pkey" PRIMARY KEY (id),
    CONSTRAINT "sync_change_run_id_item_key_key" UNIQUE (run_id, item_key),
    CONSTRAINT "sync_change_status_check" CHECK (status::text = ANY (ARRAY['PREVIEW'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'APPLIED'::character varying, 'ERROR'::character varying]::text[])),
    CONSTRAINT "sync_change_tenant_id_department_id_fkey" FOREIGN KEY (tenant_id, department_id) REFERENCES directory.department(tenant_id, id),
    CONSTRAINT "sync_change_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "sync_change_tenant_id_member_id_fkey" FOREIGN KEY (tenant_id, member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "sync_change_tenant_id_reviewed_by_member_id_fkey" FOREIGN KEY (tenant_id, reviewed_by_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "sync_change_tenant_id_run_id_fkey" FOREIGN KEY (tenant_id, run_id) REFERENCES directory.sync_run(tenant_id, id)
);
COMMENT ON TABLE directory.sync_change IS '同步/导入逐项预览、异常和复核记录；大批移除需批准，不因不完整快照删除。';
COMMENT ON COLUMN directory.sync_change."id" IS '应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.sync_change."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.sync_change."run_id" IS '所属运行。 设计场景：将逐项变更或任务归入具体批次，便于查看进度、失败行和恢复范围；是否允许单独任务见字段可空性。';
COMMENT ON COLUMN directory.sync_change."item_key" IS '来源对象键或导入行号，用于安全重试。 设计场景：导入失败后定位具体行或来源对象，用户修正后可以安全重试该项而非重做整批。';
COMMENT ON COLUMN directory.sync_change."object_type" IS '变更对象类型。 设计场景：同步预览区分员工、部门等对象，选择正确的校验和应用变更流程。';
COMMENT ON COLUMN directory.sync_change."member_id" IS '涉及的成员，可在创建前为空。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN directory.sync_change."department_id" IS '涉及的部门，可在创建前为空。 设计场景：将人员、规则或变更指向稳定的本地部门，部门改名后关联不丢失，跨企业引用被拒绝。';
COMMENT ON COLUMN directory.sync_change."operation" IS '拟执行动作。 设计场景：显式区分创建、更新、停用、归档或清理等动作，重试继续相同意图，不根据当前显示文案猜测操作。';
COMMENT ON COLUMN directory.sync_change."status" IS '预览、复核与处理状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.sync_change."diff_ciphertext" IS '受保护的前后差异，界面按权限解密和脱敏。 设计场景：批量变更审批时展示有权查看的前后差异，后台加密保存，避免预览副本泄露敏感员工资料。';
COMMENT ON COLUMN directory.sync_change."key_version" IS '差异加密密钥版本。 设计场景：密钥轮换后按写入时版本选择正确解密材料；不能把新旧密文混用同一把默认密钥。';
COMMENT ON COLUMN directory.sync_change."reviewed_by_member_id" IS '本企业复核人。 设计场景：记录对批量变更等高影响操作负责的企业复核人，用于追踪批准来源及复核其资格。';
COMMENT ON COLUMN directory.sync_change."reviewed_at" IS '复核时间。 设计场景：追踪人工审核何时作出；执行时还需复核期限与当前资格，不能把历史审核当永久许可。';
COMMENT ON COLUMN directory.sync_change."error_code" IS '逐行脱敏错误码。 设计场景：用稳定且脱敏的分类定位失败和选择补偿方式；不把凭据、完整响应或个人资料写入错误字段。';
COMMENT ON COLUMN directory.sync_change."applied_at" IS '变更成功时间。 设计场景：把已计算或已审核的变更与实际成功落库区分开，重试时不能重复应用已完成变更。';
COMMENT ON COLUMN directory.sync_change."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.sync_change."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_sync_change_run ON directory.sync_change USING btree (tenant_id, run_id, status);

-- directory.sync_event：来源事件收件箱；验证签名后入库，按连接和事件 ID 去重，重试不重复变更。
CREATE TABLE directory.sync_event (
    -- 应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 来源连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 来源事件去重键；无事件 ID 时由适配器根据稳定事实生成。 设计场景：同一来源回调可能重复投递，按连接和事件标识去重，避免重复新增或离职操作。
    "external_event_id" character varying(256) NOT NULL,
    -- 受支持的成员/部门事件类型。 设计场景：让订阅方按明确契约选择事件和处理器，避免解析任意业务对象猜测事件含义。
    "event_type" character varying(100) NOT NULL,
    -- 关联外部主体。 设计场景：缺少邮箱、手机的员工也能通过来源内稳定标识匹配；必须同时使用连接及标识类型限定作用域。
    "external_subject" character varying(512),
    -- 用于乱序判断；无可靠版本需回源。 设计场景：回调乱序到达时拒绝旧变更覆盖新状态；来源无可比较版本时回查最新状态，不能按任意字符串排序。
    "source_version" character varying(200),
    -- 加密的最小必要事件内容。 设计场景：消息正文、收件地址或来源事件可能含敏感信息，按最小必要范围加密保存，执行时受控解密。
    "payload_ciphertext" bytea NOT NULL,
    -- 加密密钥版本。 设计场景：密钥轮换后按写入时版本选择正确解密材料；不能把新旧密文混用同一把默认密钥。
    "key_version" integer NOT NULL,
    -- 消费状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'READY'::character varying NOT NULL,
    -- 尝试次数。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。
    "attempts" integer DEFAULT 0 NOT NULL,
    -- 下次可处理时间。 设计场景：支持延迟执行和失败后的退避重试，后台只能领取已经到可执行时间的任务。
    "available_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 认领实例。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。
    "lease_owner" character varying(128),
    -- 租约截止。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。
    "lease_until" timestamp with time zone,
    -- 脱敏错误。 设计场景：用稳定且脱敏的分类定位失败和选择补偿方式；不把凭据、完整响应或个人资料写入错误字段。
    "error_code" character varying(64),
    -- 生效或确认为无需变更的时间。 设计场景：把已计算或已审核的变更与实际成功落库区分开，重试时不能重复应用已完成变更。
    "applied_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "sync_event_attempts_check" CHECK (attempts >= 0),
    CONSTRAINT "sync_event_check" CHECK ((status::text = 'CLAIMED'::text) = (lease_owner IS NOT NULL AND lease_until IS NOT NULL)),
    CONSTRAINT "sync_event_check1" CHECK ((lease_owner IS NULL) = (lease_until IS NULL)),
    CONSTRAINT "sync_event_check2" CHECK ((status::text <> ALL (ARRAY['APPLIED'::character varying, 'IGNORED'::character varying]::text[])) OR applied_at IS NOT NULL),
    CONSTRAINT "sync_event_connection_id_external_event_id_key" UNIQUE (connection_id, external_event_id),
    CONSTRAINT "sync_event_id_check" CHECK (id > 0),
    CONSTRAINT "sync_event_key_version_check" CHECK (key_version > 0),
    CONSTRAINT "sync_event_pkey" PRIMARY KEY (id),
    CONSTRAINT "sync_event_status_check" CHECK (status::text = ANY (ARRAY['READY'::character varying, 'CLAIMED'::character varying, 'APPLIED'::character varying, 'RETRY'::character varying, 'DEAD'::character varying, 'IGNORED'::character varying]::text[])),
    CONSTRAINT "sync_event_tenant_id_connection_id_fkey" FOREIGN KEY (tenant_id, connection_id) REFERENCES directory.sync_connection(tenant_id, id),
    CONSTRAINT "sync_event_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT
);
COMMENT ON TABLE directory.sync_event IS '来源事件收件箱；验证签名后入库，按连接和事件 ID 去重，重试不重复变更。';
COMMENT ON COLUMN directory.sync_event."id" IS '应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.sync_event."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.sync_event."connection_id" IS '来源连接。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN directory.sync_event."external_event_id" IS '来源事件去重键；无事件 ID 时由适配器根据稳定事实生成。 设计场景：同一来源回调可能重复投递，按连接和事件标识去重，避免重复新增或离职操作。';
COMMENT ON COLUMN directory.sync_event."event_type" IS '受支持的成员/部门事件类型。 设计场景：让订阅方按明确契约选择事件和处理器，避免解析任意业务对象猜测事件含义。';
COMMENT ON COLUMN directory.sync_event."external_subject" IS '关联外部主体。 设计场景：缺少邮箱、手机的员工也能通过来源内稳定标识匹配；必须同时使用连接及标识类型限定作用域。';
COMMENT ON COLUMN directory.sync_event."source_version" IS '用于乱序判断；无可靠版本需回源。 设计场景：回调乱序到达时拒绝旧变更覆盖新状态；来源无可比较版本时回查最新状态，不能按任意字符串排序。';
COMMENT ON COLUMN directory.sync_event."payload_ciphertext" IS '加密的最小必要事件内容。 设计场景：消息正文、收件地址或来源事件可能含敏感信息，按最小必要范围加密保存，执行时受控解密。';
COMMENT ON COLUMN directory.sync_event."key_version" IS '加密密钥版本。 设计场景：密钥轮换后按写入时版本选择正确解密材料；不能把新旧密文混用同一把默认密钥。';
COMMENT ON COLUMN directory.sync_event."status" IS '消费状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.sync_event."attempts" IS '尝试次数。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。';
COMMENT ON COLUMN directory.sync_event."available_at" IS '下次可处理时间。 设计场景：支持延迟执行和失败后的退避重试，后台只能领取已经到可执行时间的任务。';
COMMENT ON COLUMN directory.sync_event."lease_owner" IS '认领实例。 设计场景：多个实例竞争执行时记录当前领取者；更新结果时必须核对归属，不能仅凭之前读取过任务就提交。';
COMMENT ON COLUMN directory.sync_event."lease_until" IS '租约截止。 设计场景：实例宕机后允许其他实例在租约到期后接管；远端副作用仍需幂等或对账，租约不保证只执行一次。';
COMMENT ON COLUMN directory.sync_event."error_code" IS '脱敏错误。 设计场景：用稳定且脱敏的分类定位失败和选择补偿方式；不把凭据、完整响应或个人资料写入错误字段。';
COMMENT ON COLUMN directory.sync_event."applied_at" IS '生效或确认为无需变更的时间。 设计场景：把已计算或已审核的变更与实际成功落库区分开，重试时不能重复应用已完成变更。';
COMMENT ON COLUMN directory.sync_event."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.sync_event."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_sync_event_due ON directory.sync_event USING btree (tenant_id, available_at, id) WHERE ((status)::text = ANY ((ARRAY['READY'::character varying, 'RETRY'::character varying])::text[]));
CREATE INDEX ix_sync_event_lease ON directory.sync_event USING btree (tenant_id, lease_until) WHERE ((status)::text = 'CLAIMED'::text);

-- directory.team_member：团队成员关系；同一成员可以加入多个团队，移除成员时由应用清理组织关系。
CREATE TABLE directory.team_member (
    -- 所属企业，两端复合外键保证团队与成员同企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 团队 ID。 设计场景：非层级协作团队可以独立于部门组织，关系或规则只在该企业的明确团队内生效。
    "team_id" bigint NOT NULL,
    -- 本企业成员；待激活员工可预登记团队，团队身份不自动产生有效业务授权。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 关系建立时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "fk_team_member_member" FOREIGN KEY (tenant_id, member_id) REFERENCES directory.membership(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "fk_team_member_team" FOREIGN KEY (tenant_id, team_id) REFERENCES directory.team(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT "pk_directory_team_member" PRIMARY KEY (tenant_id, team_id, member_id)
);
COMMENT ON TABLE directory.team_member IS '团队成员关系；同一成员可以加入多个团队，移除成员时由应用清理组织关系。';
COMMENT ON COLUMN directory.team_member."tenant_id" IS '所属企业，两端复合外键保证团队与成员同企业。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.team_member."team_id" IS '团队 ID。 设计场景：非层级协作团队可以独立于部门组织，关系或规则只在该企业的明确团队内生效。';
COMMENT ON COLUMN directory.team_member."member_id" IS '本企业成员；待激活员工可预登记团队，团队身份不自动产生有效业务授权。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN directory.team_member."created_at" IS '关系建立时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_team_member_member_team ON directory.team_member USING btree (tenant_id, member_id, team_id);

-- directory.tenant_domain：企业专属域名控制权证明；启用前验证 DNS/HTTP，不能从请求 Host 推断租户。
CREATE TABLE directory.tenant_domain (
    -- 应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 全局唯一、规范化的域名，不含协议和路径。 设计场景：企业绑定专属入口前规范化并验证控制权，不能仅按不可信请求 Host 自动认定租户。
    "domain_name" character varying(253) NOT NULL,
    -- 域名校验随机证明的摘要。 设计场景：域名验证随机证明只留摘要，防止读取数据库后直接伪造对域名的控制权。
    "proof_hash" bytea NOT NULL,
    -- 控制权验证状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    -- 待验证证明的过期时间。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone NOT NULL,
    -- 最近通过验证的时间。 设计场景：区分仅声明拥有身份、地址或域名与已经实际完成核验，核验结果是否仍有效由期限与状态共同决定。
    "verified_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "tenant_domain_check" CHECK (status::text <> 'VERIFIED'::text OR verified_at IS NOT NULL),
    CONSTRAINT "tenant_domain_check1" CHECK (expires_at > created_at),
    CONSTRAINT "tenant_domain_domain_name_check" CHECK (domain_name::text = lower(btrim(domain_name::text)) AND domain_name::text !~ '[/:[:space:]]'::text),
    CONSTRAINT "tenant_domain_domain_name_key" UNIQUE (domain_name),
    CONSTRAINT "tenant_domain_id_check" CHECK (id > 0),
    CONSTRAINT "tenant_domain_pkey" PRIMARY KEY (id),
    CONSTRAINT "tenant_domain_proof_hash_check" CHECK (octet_length(proof_hash) = 32),
    CONSTRAINT "tenant_domain_status_check" CHECK (status::text = ANY (ARRAY['PENDING'::character varying, 'VERIFIED'::character varying, 'DISABLED'::character varying]::text[])),
    CONSTRAINT "tenant_domain_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "tenant_domain_tenant_id_id_key" UNIQUE (tenant_id, id)
);
COMMENT ON TABLE directory.tenant_domain IS '企业专属域名控制权证明；启用前验证 DNS/HTTP，不能从请求 Host 推断租户。';
COMMENT ON COLUMN directory.tenant_domain."id" IS '应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.tenant_domain."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.tenant_domain."domain_name" IS '全局唯一、规范化的域名，不含协议和路径。 设计场景：企业绑定专属入口前规范化并验证控制权，不能仅按不可信请求 Host 自动认定租户。';
COMMENT ON COLUMN directory.tenant_domain."proof_hash" IS '域名校验随机证明的摘要。 设计场景：域名验证随机证明只留摘要，防止读取数据库后直接伪造对域名的控制权。';
COMMENT ON COLUMN directory.tenant_domain."status" IS '控制权验证状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.tenant_domain."expires_at" IS '待验证证明的过期时间。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN directory.tenant_domain."verified_at" IS '最近通过验证的时间。 设计场景：区分仅声明拥有身份、地址或域名与已经实际完成核验，核验结果是否仍有效由期限与状态共同决定。';
COMMENT ON COLUMN directory.tenant_domain."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.tenant_domain."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_tenant_domain_tenant ON directory.tenant_domain USING btree (tenant_id, status);

-- directory.tenant_lifecycle_request：企业开通、关闭、管理员交接与恢复申请；受控执行，不通过请求直接授予权限。
CREATE TABLE directory.tenant_lifecycle_request (
    -- 应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 开通申请未创建企业时可空；其他申请必填。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint,
    -- 申请类型。 设计场景：开通、关闭、恢复与管理员交接分别要求不同资格和证明，不能通过切换一个类型值绕过对应流程。
    "kind" character varying(24) NOT NULL,
    -- 提出申请的已验证平台账号。 设计场景：尚未建立企业成员时也能表达受控开通请求，后续必须验证本人和允许的开通条件。
    "requester_account_id" bigint NOT NULL,
    -- 管理员交接接收账号；其他类型不用。 设计场景：管理员交接必须明确接收者并完成规定确认，普通关闭或开通流程不能借此字段给任意人提权。
    "target_account_id" bigint,
    -- 同申请人的请求幂等键。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。
    "idempotency_key" character varying(128) NOT NULL,
    -- 申请处理状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(24) DEFAULT 'REQUESTED'::character varying NOT NULL,
    -- 审核者；关闭/交接的业务流程验证权限和近期认证。 设计场景：用于企业开通、关闭和管理员交接的审核追踪，审批时校验操作者职责及近期认证。
    "reviewer_account_id" bigint,
    -- 版本化申请资料：企业名称、管理员交接确认、保留计划；禁止放凭据。 设计场景：保存开通、关闭或交接所需的版本化申请资料，审批后执行仍需复核当前事实。
    "request_data" jsonb DEFAULT '{}'::jsonb NOT NULL,
    -- request_data 的受控结构版本。 设计场景：事件结构升级后按版本解析载荷，不能让旧消费者把新增字段误读成旧语义。
    "schema_version" integer DEFAULT 1 NOT NULL,
    -- 审核完成时间。 设计场景：追踪人工审核何时作出；执行时还需复核期限与当前资格，不能把历史审核当永久许可。
    "reviewed_at" timestamp with time zone,
    -- 执行完成时间。 设计场景：记录业务流程完成时间，便于区分处理中与已完成；完成必须以相应业务效果落地为前提。
    "completed_at" timestamp with time zone,
    -- 脱敏错误码。 设计场景：用稳定且脱敏的分类定位失败和选择补偿方式；不把凭据、完整响应或个人资料写入错误字段。
    "error_code" character varying(64),
    -- 乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "tenant_lifecycle_request_check" CHECK (kind::text = 'CREATE'::text OR tenant_id IS NOT NULL),
    CONSTRAINT "tenant_lifecycle_request_check1" CHECK ((kind::text = 'ADMIN_TRANSFER'::text) = (target_account_id IS NOT NULL)),
    CONSTRAINT "tenant_lifecycle_request_check2" CHECK (status::text <> 'COMPLETED'::text OR completed_at IS NOT NULL AND tenant_id IS NOT NULL),
    CONSTRAINT "tenant_lifecycle_request_id_check" CHECK (id > 0),
    CONSTRAINT "tenant_lifecycle_request_kind_check" CHECK (kind::text = ANY (ARRAY['CREATE'::character varying, 'CLOSE'::character varying, 'ADMIN_TRANSFER'::character varying, 'RESTORE'::character varying]::text[])),
    CONSTRAINT "tenant_lifecycle_request_pkey" PRIMARY KEY (id),
    CONSTRAINT "tenant_lifecycle_request_request_data_check" CHECK (jsonb_typeof(request_data) = 'object'::text),
    CONSTRAINT "tenant_lifecycle_request_requester_account_id_fkey" FOREIGN KEY (requester_account_id) REFERENCES directory.account(id),
    CONSTRAINT "tenant_lifecycle_request_requester_account_id_idempotency_k_key" UNIQUE (requester_account_id, idempotency_key),
    CONSTRAINT "tenant_lifecycle_request_reviewer_account_id_fkey" FOREIGN KEY (reviewer_account_id) REFERENCES directory.account(id),
    CONSTRAINT "tenant_lifecycle_request_schema_version_check" CHECK (schema_version > 0),
    CONSTRAINT "tenant_lifecycle_request_status_check" CHECK (status::text = ANY (ARRAY['REQUESTED'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'EXECUTING'::character varying, 'COMPLETED'::character varying, 'FAILED'::character varying, 'CANCELLED'::character varying]::text[])),
    CONSTRAINT "tenant_lifecycle_request_target_account_id_fkey" FOREIGN KEY (target_account_id) REFERENCES directory.account(id),
    CONSTRAINT "tenant_lifecycle_request_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "tenant_lifecycle_request_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE directory.tenant_lifecycle_request IS '企业开通、关闭、管理员交接与恢复申请；受控执行，不通过请求直接授予权限。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."id" IS '应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."tenant_id" IS '开通申请未创建企业时可空；其他申请必填。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."kind" IS '申请类型。 设计场景：开通、关闭、恢复与管理员交接分别要求不同资格和证明，不能通过切换一个类型值绕过对应流程。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."requester_account_id" IS '提出申请的已验证平台账号。 设计场景：尚未建立企业成员时也能表达受控开通请求，后续必须验证本人和允许的开通条件。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."target_account_id" IS '管理员交接接收账号；其他类型不用。 设计场景：管理员交接必须明确接收者并完成规定确认，普通关闭或开通流程不能借此字段给任意人提权。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."idempotency_key" IS '同申请人的请求幂等键。 设计场景：客户端重试、重复回调或任务重新领取时识别同一业务请求，避免重复创建、重复授权或重复发送。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."status" IS '申请处理状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."reviewer_account_id" IS '审核者；关闭/交接的业务流程验证权限和近期认证。 设计场景：用于企业开通、关闭和管理员交接的审核追踪，审批时校验操作者职责及近期认证。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."request_data" IS '版本化申请资料：企业名称、管理员交接确认、保留计划；禁止放凭据。 设计场景：保存开通、关闭或交接所需的版本化申请资料，审批后执行仍需复核当前事实。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."schema_version" IS 'request_data 的受控结构版本。 设计场景：事件结构升级后按版本解析载荷，不能让旧消费者把新增字段误读成旧语义。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."reviewed_at" IS '审核完成时间。 设计场景：追踪人工审核何时作出；执行时还需复核期限与当前资格，不能把历史审核当永久许可。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."completed_at" IS '执行完成时间。 设计场景：记录业务流程完成时间，便于区分处理中与已完成；完成必须以相应业务效果落地为前提。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."error_code" IS '脱敏错误码。 设计场景：用稳定且脱敏的分类定位失败和选择补偿方式；不把凭据、完整响应或个人资料写入错误字段。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."version" IS '乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN directory.tenant_lifecycle_request."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_tenant_lifecycle_requester ON directory.tenant_lifecycle_request USING btree (requester_account_id, created_at DESC);
CREATE INDEX ix_tenant_lifecycle_tenant ON directory.tenant_lifecycle_request USING btree (tenant_id, created_at DESC);

-- directory.tenant_settings：企业展示与首次配置；登录及认证策略由 Identity 管理。
CREATE TABLE directory.tenant_settings (
    -- 企业 ID。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 受控图片存储引用。 设计场景：企业品牌展示使用受控图像资源，变更标识不影响身份、租户与访问资格。
    "logo_ref" text,
    -- 登录页展示名称。 设计场景：企业入口可定制展示名称，品牌文字不作为可信身份中心或租户匹配依据。
    "brand_name" character varying(200),
    -- 首次配置进度，不代表相关功能已成功联调。 设计场景：管理员可以继续上次未完成的配置步骤，进度到最后不代表真实渠道联调已经通过。
    "onboarding_step" character varying(32) DEFAULT 'PROFILE'::character varying NOT NULL,
    -- 企业默认语言。 设计场景：根据个人或企业偏好展示语言与格式，不能改变协议标识的规范化规则。
    "locale" character varying(35) DEFAULT 'zh-CN'::character varying NOT NULL,
    -- 企业默认时区；业务需验证有效 IANA 名称。 设计场景：将 UTC 事实时间转换为用户或企业当地时间展示，避免不同地区把同一时刻解释为不同业务事实。
    "time_zone" character varying(64) DEFAULT 'Asia/Shanghai'::character varying NOT NULL,
    -- 乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "tenant_settings_onboarding_step_check" CHECK (onboarding_step::text = ANY (ARRAY['PROFILE'::character varying, 'ADMIN'::character varying, 'DIRECTORY'::character varying, 'APPLICATIONS'::character varying, 'COMPLETE'::character varying]::text[])),
    CONSTRAINT "tenant_settings_pkey" PRIMARY KEY (tenant_id),
    CONSTRAINT "tenant_settings_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "tenant_settings_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE directory.tenant_settings IS '企业展示与首次配置；登录及认证策略由 Identity 管理。';
COMMENT ON COLUMN directory.tenant_settings."tenant_id" IS '企业 ID。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.tenant_settings."logo_ref" IS '受控图片存储引用。 设计场景：企业品牌展示使用受控图像资源，变更标识不影响身份、租户与访问资格。';
COMMENT ON COLUMN directory.tenant_settings."brand_name" IS '登录页展示名称。 设计场景：企业入口可定制展示名称，品牌文字不作为可信身份中心或租户匹配依据。';
COMMENT ON COLUMN directory.tenant_settings."onboarding_step" IS '首次配置进度，不代表相关功能已成功联调。 设计场景：管理员可以继续上次未完成的配置步骤，进度到最后不代表真实渠道联调已经通过。';
COMMENT ON COLUMN directory.tenant_settings."locale" IS '企业默认语言。 设计场景：根据个人或企业偏好展示语言与格式，不能改变协议标识的规范化规则。';
COMMENT ON COLUMN directory.tenant_settings."time_zone" IS '企业默认时区；业务需验证有效 IANA 名称。 设计场景：将 UTC 事实时间转换为用户或企业当地时间展示，避免不同地区把同一时刻解释为不同业务事实。';
COMMENT ON COLUMN directory.tenant_settings."version" IS '乐观锁版本，由业务事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN directory.tenant_settings."updated_at" IS '最后更新时间，由业务事务更新。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';

-- directory.work_assignment：内部工作身份到客户协作身份的明确依赖；不把所有跨企业成员自动认定为工作委派。
CREATE TABLE directory.work_assignment (
    -- 应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 客户企业成员，必须已经关联账号。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。
    "member_id" bigint NOT NULL,
    -- 两个企业身份共同的平台账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 委派来源企业；通常为内部企业。 设计场景：员工在内部公司与客户企业的工作关系显式关联，来源离职只影响依赖该工作身份的客户资格。
    "source_tenant_id" bigint NOT NULL,
    -- 来源工作成员。 设计场景：记录明确依赖的来源成员或来源员工对象，按所在表限定语义；来源失效时据此定位受影响关系。
    "source_member_id" bigint NOT NULL,
    -- 客户企业批准人，必须是本企业成员。 设计场景：追踪预批准或工作委派由哪位管理员作出，当前身份无效时按对应规则重新核验。
    "approved_by_member_id" bigint NOT NULL,
    -- 工作委派状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'ACTIVE'::character varying NOT NULL,
    -- 生效时间。 设计场景：支持预先登记但尚未生效的工作关系；访问时检查时间条件，不能创建后立即生效。
    "starts_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 截止时间，空代表长期但仍依赖来源身份。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone,
    -- 撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "work_assignment_account_id_fkey" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "work_assignment_check" CHECK (source_tenant_id <> tenant_id),
    CONSTRAINT "work_assignment_check1" CHECK (expires_at IS NULL OR expires_at > starts_at),
    CONSTRAINT "work_assignment_check2" CHECK ((status::text = 'REVOKED'::text) = (revoked_at IS NOT NULL)),
    CONSTRAINT "work_assignment_id_check" CHECK (id > 0),
    CONSTRAINT "work_assignment_pkey" PRIMARY KEY (id),
    CONSTRAINT "work_assignment_source_tenant_id_fkey" FOREIGN KEY (source_tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "work_assignment_source_tenant_id_source_member_id_account__fkey" FOREIGN KEY (source_tenant_id, source_member_id, account_id) REFERENCES directory.membership(tenant_id, id, account_id),
    CONSTRAINT "work_assignment_status_check" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying, 'REVOKED'::character varying]::text[])),
    CONSTRAINT "work_assignment_tenant_id_approved_by_member_id_fkey" FOREIGN KEY (tenant_id, approved_by_member_id) REFERENCES directory.membership(tenant_id, id),
    CONSTRAINT "work_assignment_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id) ON DELETE RESTRICT,
    CONSTRAINT "work_assignment_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "work_assignment_tenant_id_member_id_account_id_fkey" FOREIGN KEY (tenant_id, member_id, account_id) REFERENCES directory.membership(tenant_id, id, account_id)
);
COMMENT ON TABLE directory.work_assignment IS '内部工作身份到客户协作身份的明确依赖；不把所有跨企业成员自动认定为工作委派。';
COMMENT ON COLUMN directory.work_assignment."id" IS '应用生成的稳定雪花 ID；前端按字符串传递。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN directory.work_assignment."tenant_id" IS '所属企业；由可信事务上下文检查。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN directory.work_assignment."member_id" IS '客户企业成员，必须已经关联账号。 设计场景：定位人在某一家企业内的成员身份；离职或调岗只影响相应企业，不能据此删除全局账号。';
COMMENT ON COLUMN directory.work_assignment."account_id" IS '两个企业身份共同的平台账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN directory.work_assignment."source_tenant_id" IS '委派来源企业；通常为内部企业。 设计场景：员工在内部公司与客户企业的工作关系显式关联，来源离职只影响依赖该工作身份的客户资格。';
COMMENT ON COLUMN directory.work_assignment."source_member_id" IS '来源工作成员。 设计场景：记录明确依赖的来源成员或来源员工对象，按所在表限定语义；来源失效时据此定位受影响关系。';
COMMENT ON COLUMN directory.work_assignment."approved_by_member_id" IS '客户企业批准人，必须是本企业成员。 设计场景：追踪预批准或工作委派由哪位管理员作出，当前身份无效时按对应规则重新核验。';
COMMENT ON COLUMN directory.work_assignment."status" IS '工作委派状态。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN directory.work_assignment."starts_at" IS '生效时间。 设计场景：支持预先登记但尚未生效的工作关系；访问时检查时间条件，不能创建后立即生效。';
COMMENT ON COLUMN directory.work_assignment."expires_at" IS '截止时间，空代表长期但仍依赖来源身份。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN directory.work_assignment."revoked_at" IS '撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN directory.work_assignment."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_work_assignment_source ON directory.work_assignment USING btree (source_tenant_id, source_member_id, status);
CREATE UNIQUE INDEX uq_active_work_assignment ON directory.work_assignment USING btree (tenant_id, member_id, source_tenant_id, source_member_id) WHERE ((status)::text = 'ACTIVE'::text);

-- identity.account_lifecycle_request：账号申诉恢复、合并及注销受控流程；记录证明和审查决定，执行前锁定账号复核身份、管理员交接、保留及权限冲突，不自动叠加授权。
CREATE TABLE identity.account_lifecycle_request (
    -- 应用生成的正数雪花生命周期请求ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 请求处理的原账号；合并时是将关闭的来源账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 仅合并时指定保留账号，不能与来源相同。 设计场景：账号合并时明确最终保留的账号，必须独立证明双方、检查冲突且禁止合并到自身。
    "target_account_id" bigint,
    -- RECOVERY申诉恢复、MERGE重复账号合并、CLOSURE个人账号注销；成员离职不使用本表。 设计场景：区分账号恢复、合并和注销，对每类执行不同证明、冲突处理及保留流程，不能拿成员离职替代账号注销。
    "request_kind" character varying(16) NOT NULL,
    -- 流程状态；过期请求须先显式取消/拒绝才释放唯一进行中名额，不能仅因时间到达就继续执行。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    -- 原账号近期身份证明；用途、完成状态、期限和auth_epoch由最终事务验证。 设计场景：合并或敏感生命周期操作前证明原账号本人，执行时检查证明仍有效，不能只凭知道账号 ID 操作。
    "source_proof_attempt_id" bigint,
    -- 合并目标账号独立证明；必须与目标账号一致，不得复用另一个人的证明。 设计场景：账号合并还需独立证明目标账号，避免只验证一边就把另一人的身份和权限搬走。
    "target_proof_attempt_id" bigint,
    -- 已认证申请人；全部登录方式丢失的申诉入口可空，不能据此取得会话。 设计场景：区分人工发起和允许的后台操作，追溯请求来源；保存账号不替代执行时的权限复核。
    "requested_by_account_id" bigint,
    -- 人工审核人；账号恢复不能由租户管理员单方面接管，需受控平台恢复权限。 设计场景：记录平台级受控审核人；恢复账号等操作不能因为填写了某个管理员 ID 就绕过审核权限。
    "reviewed_by_account_id" bigint,
    -- 受保护证据材料引用，不保存身份证件或恢复秘密明文，访问另行授权并按保留期清理。 设计场景：关联受保护的核验材料或执行证据，审查时可以回溯；普通接口不直接暴露证据内容与访问凭据。
    "evidence_ref" text,
    -- version=1的冻结决策快照：双方证明摘要、冲突预览版本、管理员交接结果、需保留/移除的权限决定及资料删除范围；仅审查证据，实际成员与授权仍存规范关系表并按版本复核。 设计场景：记录审核时的证明摘要和冲突处理方案，执行前按版本复核，避免把过期预览作为当前事实。
    "decision_snapshot" jsonb DEFAULT '{"version": 1}'::jsonb NOT NULL,
    -- 服务端幂等请求键，重复提交返回同一流程，不重复迁移账号。 设计场景：多次点击或网络重试复用同一账号生命周期流程，避免重复合并、注销或恢复。
    "request_key" character varying(128) NOT NULL,
    -- 允许完成确认/批准的最晚时间；执行前还须复核每份证明更短的期限。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone NOT NULL,
    -- 人工审核决定时间，与审核人同时存在。 设计场景：追踪人工审核何时作出；执行时还需复核期限与当前资格，不能把历史审核当永久许可。
    "reviewed_at" timestamp with time zone,
    -- 本地变更及撤销记录完成时间，外部异步停用结果另行追踪。 设计场景：记录业务流程完成时间，便于区分处理中与已完成；完成必须以相应业务效果落地为前提。
    "completed_at" timestamp with time zone,
    -- 脱敏失败原因代码；异常恢复不能直接重放已完成的成员或凭据变更。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。
    "last_error_code" character varying(64),
    -- 流程并发版本，防止旧审核覆盖新的冲突方案。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 请求创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近流程状态修改时间。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "account_lifecycle_request_account_id_fkey" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "account_lifecycle_request_id_check" CHECK (id > 0),
    CONSTRAINT "account_lifecycle_request_pkey" PRIMARY KEY (id),
    CONSTRAINT "account_lifecycle_request_request_key_check" CHECK (btrim(request_key::text) <> ''::text),
    CONSTRAINT "account_lifecycle_request_request_key_key" UNIQUE (request_key),
    CONSTRAINT "account_lifecycle_request_request_kind_check" CHECK (request_kind::text = ANY (ARRAY['RECOVERY'::character varying, 'MERGE'::character varying, 'CLOSURE'::character varying]::text[])),
    CONSTRAINT "account_lifecycle_request_requested_by_account_id_fkey" FOREIGN KEY (requested_by_account_id) REFERENCES directory.account(id),
    CONSTRAINT "account_lifecycle_request_reviewed_by_account_id_fkey" FOREIGN KEY (reviewed_by_account_id) REFERENCES directory.account(id),
    CONSTRAINT "account_lifecycle_request_status_check" CHECK (status::text = ANY (ARRAY['PENDING'::character varying, 'PROVING'::character varying, 'REVIEW'::character varying, 'APPROVED'::character varying, 'EXECUTING'::character varying, 'COMPLETED'::character varying, 'REJECTED'::character varying, 'CANCELLED'::character varying, 'FAILED'::character varying]::text[])),
    CONSTRAINT "account_lifecycle_request_target_account_id_fkey" FOREIGN KEY (target_account_id) REFERENCES directory.account(id),
    CONSTRAINT "account_lifecycle_request_version_check" CHECK (version >= 0),
    CONSTRAINT "ck_lifecycle_closure_proof" CHECK (request_kind::text <> 'CLOSURE'::text OR (status::text <> ALL (ARRAY['APPROVED'::character varying, 'EXECUTING'::character varying, 'COMPLETED'::character varying]::text[])) OR source_proof_attempt_id IS NOT NULL),
    CONSTRAINT "ck_lifecycle_completion" CHECK ((status::text = 'COMPLETED'::text) = (completed_at IS NOT NULL)),
    CONSTRAINT "ck_lifecycle_evidence_ref" CHECK (evidence_ref IS NULL OR btrim(evidence_ref) <> ''::text),
    CONSTRAINT "ck_lifecycle_merge_proof" CHECK (request_kind::text <> 'MERGE'::text OR (status::text <> ALL (ARRAY['APPROVED'::character varying, 'EXECUTING'::character varying, 'COMPLETED'::character varying]::text[])) OR source_proof_attempt_id IS NOT NULL AND target_proof_attempt_id IS NOT NULL),
    CONSTRAINT "ck_lifecycle_recovery_review" CHECK (request_kind::text <> 'RECOVERY'::text OR (status::text <> ALL (ARRAY['APPROVED'::character varying, 'EXECUTING'::character varying, 'COMPLETED'::character varying]::text[])) OR reviewed_by_account_id IS NOT NULL AND evidence_ref IS NOT NULL),
    CONSTRAINT "ck_lifecycle_review" CHECK (reviewed_by_account_id IS NULL AND reviewed_at IS NULL OR reviewed_by_account_id IS NOT NULL AND reviewed_at IS NOT NULL AND reviewed_at >= created_at),
    CONSTRAINT "ck_lifecycle_snapshot" CHECK (jsonb_typeof(decision_snapshot) = 'object'::text AND decision_snapshot @> '{"version": 1}'::jsonb),
    CONSTRAINT "ck_lifecycle_target" CHECK (request_kind::text = 'MERGE'::text AND target_account_id IS NOT NULL AND target_account_id <> account_id OR request_kind::text <> 'MERGE'::text AND target_account_id IS NULL AND target_proof_attempt_id IS NULL),
    CONSTRAINT "ck_lifecycle_times" CHECK (expires_at > created_at AND updated_at >= created_at AND (completed_at IS NULL OR completed_at >= created_at)),
    CONSTRAINT "fk_lifecycle_source_proof" FOREIGN KEY (account_id, source_proof_attempt_id) REFERENCES identity.authentication_attempt(account_id, id),
    CONSTRAINT "fk_lifecycle_target_proof" FOREIGN KEY (target_account_id, target_proof_attempt_id) REFERENCES identity.authentication_attempt(account_id, id)
);
COMMENT ON TABLE identity.account_lifecycle_request IS '账号申诉恢复、合并及注销受控流程；记录证明和审查决定，执行前锁定账号复核身份、管理员交接、保留及权限冲突，不自动叠加授权。';
COMMENT ON COLUMN identity.account_lifecycle_request."id" IS '应用生成的正数雪花生命周期请求ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.account_lifecycle_request."account_id" IS '请求处理的原账号；合并时是将关闭的来源账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.account_lifecycle_request."target_account_id" IS '仅合并时指定保留账号，不能与来源相同。 设计场景：账号合并时明确最终保留的账号，必须独立证明双方、检查冲突且禁止合并到自身。';
COMMENT ON COLUMN identity.account_lifecycle_request."request_kind" IS 'RECOVERY申诉恢复、MERGE重复账号合并、CLOSURE个人账号注销；成员离职不使用本表。 设计场景：区分账号恢复、合并和注销，对每类执行不同证明、冲突处理及保留流程，不能拿成员离职替代账号注销。';
COMMENT ON COLUMN identity.account_lifecycle_request."status" IS '流程状态；过期请求须先显式取消/拒绝才释放唯一进行中名额，不能仅因时间到达就继续执行。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN identity.account_lifecycle_request."source_proof_attempt_id" IS '原账号近期身份证明；用途、完成状态、期限和auth_epoch由最终事务验证。 设计场景：合并或敏感生命周期操作前证明原账号本人，执行时检查证明仍有效，不能只凭知道账号 ID 操作。';
COMMENT ON COLUMN identity.account_lifecycle_request."target_proof_attempt_id" IS '合并目标账号独立证明；必须与目标账号一致，不得复用另一个人的证明。 设计场景：账号合并还需独立证明目标账号，避免只验证一边就把另一人的身份和权限搬走。';
COMMENT ON COLUMN identity.account_lifecycle_request."requested_by_account_id" IS '已认证申请人；全部登录方式丢失的申诉入口可空，不能据此取得会话。 设计场景：区分人工发起和允许的后台操作，追溯请求来源；保存账号不替代执行时的权限复核。';
COMMENT ON COLUMN identity.account_lifecycle_request."reviewed_by_account_id" IS '人工审核人；账号恢复不能由租户管理员单方面接管，需受控平台恢复权限。 设计场景：记录平台级受控审核人；恢复账号等操作不能因为填写了某个管理员 ID 就绕过审核权限。';
COMMENT ON COLUMN identity.account_lifecycle_request."evidence_ref" IS '受保护证据材料引用，不保存身份证件或恢复秘密明文，访问另行授权并按保留期清理。 设计场景：关联受保护的核验材料或执行证据，审查时可以回溯；普通接口不直接暴露证据内容与访问凭据。';
COMMENT ON COLUMN identity.account_lifecycle_request."decision_snapshot" IS 'version=1的冻结决策快照：双方证明摘要、冲突预览版本、管理员交接结果、需保留/移除的权限决定及资料删除范围；仅审查证据，实际成员与授权仍存规范关系表并按版本复核。 设计场景：记录审核时的证明摘要和冲突处理方案，执行前按版本复核，避免把过期预览作为当前事实。';
COMMENT ON COLUMN identity.account_lifecycle_request."request_key" IS '服务端幂等请求键，重复提交返回同一流程，不重复迁移账号。 设计场景：多次点击或网络重试复用同一账号生命周期流程，避免重复合并、注销或恢复。';
COMMENT ON COLUMN identity.account_lifecycle_request."expires_at" IS '允许完成确认/批准的最晚时间；执行前还须复核每份证明更短的期限。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN identity.account_lifecycle_request."reviewed_at" IS '人工审核决定时间，与审核人同时存在。 设计场景：追踪人工审核何时作出；执行时还需复核期限与当前资格，不能把历史审核当永久许可。';
COMMENT ON COLUMN identity.account_lifecycle_request."completed_at" IS '本地变更及撤销记录完成时间，外部异步停用结果另行追踪。 设计场景：记录业务流程完成时间，便于区分处理中与已完成；完成必须以相应业务效果落地为前提。';
COMMENT ON COLUMN identity.account_lifecycle_request."last_error_code" IS '脱敏失败原因代码；异常恢复不能直接重放已完成的成员或凭据变更。 设计场景：保留最近一次失败分类，供管理界面和重试逻辑解释当前阻塞原因；历史尝试另有执行记录时保留在那里。';
COMMENT ON COLUMN identity.account_lifecycle_request."version" IS '流程并发版本，防止旧审核覆盖新的冲突方案。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN identity.account_lifecycle_request."created_at" IS '请求创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.account_lifecycle_request."updated_at" IS '最近流程状态修改时间。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_lifecycle_pending_expiry ON identity.account_lifecycle_request USING btree (expires_at) WHERE ((status)::text = ANY ((ARRAY['PENDING'::character varying, 'PROVING'::character varying, 'REVIEW'::character varying, 'APPROVED'::character varying])::text[]));
CREATE INDEX ix_lifecycle_requester ON identity.account_lifecycle_request USING btree (requested_by_account_id) WHERE (requested_by_account_id IS NOT NULL);
CREATE INDEX ix_lifecycle_reviewer ON identity.account_lifecycle_request USING btree (reviewed_by_account_id) WHERE (reviewed_by_account_id IS NOT NULL);
CREATE INDEX ix_lifecycle_source_proof ON identity.account_lifecycle_request USING btree (source_proof_attempt_id) WHERE (source_proof_attempt_id IS NOT NULL);
CREATE INDEX ix_lifecycle_target ON identity.account_lifecycle_request USING btree (target_account_id) WHERE (target_account_id IS NOT NULL);
CREATE INDEX ix_lifecycle_target_proof ON identity.account_lifecycle_request USING btree (target_proof_attempt_id) WHERE (target_proof_attempt_id IS NOT NULL);
CREATE UNIQUE INDEX uq_lifecycle_active_source ON identity.account_lifecycle_request USING btree (account_id) WHERE ((status)::text = ANY ((ARRAY['PENDING'::character varying, 'PROVING'::character varying, 'REVIEW'::character varying, 'APPROVED'::character varying, 'EXECUTING'::character varying])::text[]));

-- identity.webauthn_user：账号在一个RP范围内的稳定WebAuthn用户句柄；多个通行密钥共用，避免以邮箱作句柄或将同一句柄给不同账号。
CREATE TABLE identity.webauthn_user (
    -- 所属平台账号，引用已有正数雪花账号ID。 设计场景：同一个账号在一个 RP 下共享稳定用户句柄，多设备通行密钥均归该账号，不能为每个设备创建一个平台账号。
    "account_id" bigint NOT NULL,
    -- 登记方RP ID，账号与RP构成唯一用户句柄记录。 设计场景：将通行密钥限定到对应登记方作用域，认证时由协议库核验，不能跨站点使用凭据。
    "rp_id" character varying(253) NOT NULL,
    -- 应用生成的1～64字节随机不透明用户句柄，RP内唯一，不随用户名/邮箱变化。 设计场景：邮箱或用户名变化时通行密钥仍能识别同一账号，使用随机不透明句柄避免泄露个人标识。
    "user_handle" bytea NOT NULL,
    -- 首次登记WebAuthn用户句柄时间；撤销所有密钥不自动回收句柄。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "uq_webauthn_user_binding" UNIQUE (account_id, rp_id, user_handle),
    CONSTRAINT "uq_webauthn_user_handle" UNIQUE (rp_id, user_handle),
    CONSTRAINT "webauthn_user_account_id_fkey" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "webauthn_user_pkey" PRIMARY KEY (account_id, rp_id),
    CONSTRAINT "webauthn_user_rp_id_check" CHECK (rp_id::text = lower(btrim(rp_id::text)) AND rp_id::text <> ''::text),
    CONSTRAINT "webauthn_user_user_handle_check" CHECK (octet_length(user_handle) >= 1 AND octet_length(user_handle) <= 64)
);
COMMENT ON TABLE identity.webauthn_user IS '账号在一个RP范围内的稳定WebAuthn用户句柄；多个通行密钥共用，避免以邮箱作句柄或将同一句柄给不同账号。';
COMMENT ON COLUMN identity.webauthn_user."account_id" IS '所属平台账号，引用已有正数雪花账号ID。 设计场景：同一个账号在一个 RP 下共享稳定用户句柄，多设备通行密钥均归该账号，不能为每个设备创建一个平台账号。';
COMMENT ON COLUMN identity.webauthn_user."rp_id" IS '登记方RP ID，账号与RP构成唯一用户句柄记录。 设计场景：将通行密钥限定到对应登记方作用域，认证时由协议库核验，不能跨站点使用凭据。';
COMMENT ON COLUMN identity.webauthn_user."user_handle" IS '应用生成的1～64字节随机不透明用户句柄，RP内唯一，不随用户名/邮箱变化。 设计场景：邮箱或用户名变化时通行密钥仍能识别同一账号，使用随机不透明句柄避免泄露个人标识。';
COMMENT ON COLUMN identity.webauthn_user."created_at" IS '首次登记WebAuthn用户句柄时间；撤销所有密钥不自动回收句柄。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';

-- identity.webauthn_credential：通行密钥/安全密钥公钥凭据；允许同账号多个设备，私钥及设备生物特征不进入平台；所有协议校验由成熟WebAuthn库完成。
CREATE TABLE identity.webauthn_credential (
    -- 应用生成的正数雪花凭据ID，不是浏览器协议credentialId。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 凭据所属全局账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 认证器返回的不透明credentialId字节，全局唯一并原样比较。 设计场景：同一账号可以有多个通行密钥，认证器返回的凭据 ID 用于精确选择公钥，原样比较不进行文本规范化。
    "credential_id" bytea NOT NULL,
    -- 登记时分配给账号的稳定随机WebAuthn用户句柄，同账号同RP通过复合外键保持一致，不使用邮箱或手机号。 设计场景：邮箱或用户名变化时通行密钥仍能识别同一账号，使用随机不透明句柄避免泄露个人标识。
    "user_handle" bytea NOT NULL,
    -- 注册方域范围RP ID；认证必须验证challenge、origin、RP及用户验证要求。 设计场景：将通行密钥限定到对应登记方作用域，认证时由协议库核验，不能跨站点使用凭据。
    "rp_id" character varying(253) NOT NULL,
    -- COSE编码的公开密钥，禁止存私钥、PIN、指纹或面容数据。 设计场景：验证设备签名只需要公钥，设备私钥和生物识别数据留在认证器中，不进入平台数据库。
    "public_key_cose" bytea NOT NULL,
    -- 最近观察的签名计数，原子比较更新；同步通行密钥计数规则由库及风险策略解释。 设计场景：发现可能的凭据复制或异常使用时提供风险证据；同步通行密钥的计数由协议库和策略解释，不能简单一律递增判断。
    "sign_count" bigint DEFAULT 0 NOT NULL,
    -- 登记/认证校验后的凭据可备份标志。 设计场景：识别凭据是否允许备份或跨设备同步，为风险策略提供经协议验证的事实。
    "backup_eligible" boolean DEFAULT false NOT NULL,
    -- 最近校验的已备份标志，仅可备份凭据允许为真。 设计场景：跟踪凭据的备份状态变化，配合可备份标志解释风险，不把已备份视为自动可信设备。
    "backup_state" boolean DEFAULT false NOT NULL,
    -- 可选的认证器型号标识；不等于设备可信授权。 设计场景：识别认证器型号以辅助兼容性和风险排查，不代表唯一设备，也不单独授予可信资格。
    "aaguid" uuid,
    -- 浏览器提示传输方式集合，仅用于交互提示，不作为授权证明。 设计场景：帮助浏览器提示使用 USB、NFC 或其他可用交互方式，传输提示不能作为认证已经完成的证据。
    "transports" character varying(16)[] DEFAULT '{}'::character varying[] NOT NULL,
    -- 用户可辨认的密钥名称，不唯一。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。
    "display_name" character varying(100) NOT NULL,
    -- 本人验证并完成注册的时间。 设计场景：记录本人完成凭据登记的时刻，便于识别陌生新增设备和回溯注册流程。
    "registered_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近成功认证时间。 设计场景：帮助用户识别仍在使用的凭据、设备或票据，支持轮换和清理；不是独立的有效性证明。
    "last_used_at" timestamp with time zone,
    -- 本人或安全恢复流程撤销时间；已撤销凭据保留历史且不可认证。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 并发更新版本，用于计数、状态和名称更新。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    CONSTRAINT "ck_webauthn_backup" CHECK (NOT backup_state OR backup_eligible),
    CONSTRAINT "ck_webauthn_times" CHECK ((last_used_at IS NULL OR last_used_at >= registered_at) AND (revoked_at IS NULL OR revoked_at >= registered_at)),
    CONSTRAINT "ck_webauthn_transports" CHECK (transports <@ ARRAY['usb'::character varying(16), 'nfc'::character varying(16), 'ble'::character varying(16), 'internal'::character varying(16), 'hybrid'::character varying(16)] AND array_position(transports, NULL::character varying) IS NULL),
    CONSTRAINT "fk_webauthn_credential_user" FOREIGN KEY (account_id, rp_id, user_handle) REFERENCES identity.webauthn_user(account_id, rp_id, user_handle),
    CONSTRAINT "uq_webauthn_credential_account" UNIQUE (account_id, id),
    CONSTRAINT "webauthn_credential_account_id_fkey" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "webauthn_credential_credential_id_check" CHECK (octet_length(credential_id) >= 1 AND octet_length(credential_id) <= 1024),
    CONSTRAINT "webauthn_credential_credential_id_key" UNIQUE (credential_id),
    CONSTRAINT "webauthn_credential_display_name_check" CHECK (btrim(display_name::text) <> ''::text),
    CONSTRAINT "webauthn_credential_id_check" CHECK (id > 0),
    CONSTRAINT "webauthn_credential_pkey" PRIMARY KEY (id),
    CONSTRAINT "webauthn_credential_public_key_cose_check" CHECK (octet_length(public_key_cose) > 0),
    CONSTRAINT "webauthn_credential_rp_id_check" CHECK (rp_id::text = lower(btrim(rp_id::text)) AND rp_id::text <> ''::text),
    CONSTRAINT "webauthn_credential_sign_count_check" CHECK (sign_count >= 0),
    CONSTRAINT "webauthn_credential_user_handle_check" CHECK (octet_length(user_handle) >= 1 AND octet_length(user_handle) <= 64),
    CONSTRAINT "webauthn_credential_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE identity.webauthn_credential IS '通行密钥/安全密钥公钥凭据；允许同账号多个设备，私钥及设备生物特征不进入平台；所有协议校验由成熟WebAuthn库完成。';
COMMENT ON COLUMN identity.webauthn_credential."id" IS '应用生成的正数雪花凭据ID，不是浏览器协议credentialId。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.webauthn_credential."account_id" IS '凭据所属全局账号。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.webauthn_credential."credential_id" IS '认证器返回的不透明credentialId字节，全局唯一并原样比较。 设计场景：同一账号可以有多个通行密钥，认证器返回的凭据 ID 用于精确选择公钥，原样比较不进行文本规范化。';
COMMENT ON COLUMN identity.webauthn_credential."user_handle" IS '登记时分配给账号的稳定随机WebAuthn用户句柄，同账号同RP通过复合外键保持一致，不使用邮箱或手机号。 设计场景：邮箱或用户名变化时通行密钥仍能识别同一账号，使用随机不透明句柄避免泄露个人标识。';
COMMENT ON COLUMN identity.webauthn_credential."rp_id" IS '注册方域范围RP ID；认证必须验证challenge、origin、RP及用户验证要求。 设计场景：将通行密钥限定到对应登记方作用域，认证时由协议库核验，不能跨站点使用凭据。';
COMMENT ON COLUMN identity.webauthn_credential."public_key_cose" IS 'COSE编码的公开密钥，禁止存私钥、PIN、指纹或面容数据。 设计场景：验证设备签名只需要公钥，设备私钥和生物识别数据留在认证器中，不进入平台数据库。';
COMMENT ON COLUMN identity.webauthn_credential."sign_count" IS '最近观察的签名计数，原子比较更新；同步通行密钥计数规则由库及风险策略解释。 设计场景：发现可能的凭据复制或异常使用时提供风险证据；同步通行密钥的计数由协议库和策略解释，不能简单一律递增判断。';
COMMENT ON COLUMN identity.webauthn_credential."backup_eligible" IS '登记/认证校验后的凭据可备份标志。 设计场景：识别凭据是否允许备份或跨设备同步，为风险策略提供经协议验证的事实。';
COMMENT ON COLUMN identity.webauthn_credential."backup_state" IS '最近校验的已备份标志，仅可备份凭据允许为真。 设计场景：跟踪凭据的备份状态变化，配合可备份标志解释风险，不把已备份视为自动可信设备。';
COMMENT ON COLUMN identity.webauthn_credential."aaguid" IS '可选的认证器型号标识；不等于设备可信授权。 设计场景：识别认证器型号以辅助兼容性和风险排查，不代表唯一设备，也不单独授予可信资格。';
COMMENT ON COLUMN identity.webauthn_credential."transports" IS '浏览器提示传输方式集合，仅用于交互提示，不作为授权证明。 设计场景：帮助浏览器提示使用 USB、NFC 或其他可用交互方式，传输提示不能作为认证已经完成的证据。';
COMMENT ON COLUMN identity.webauthn_credential."display_name" IS '用户可辨认的密钥名称，不唯一。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。';
COMMENT ON COLUMN identity.webauthn_credential."registered_at" IS '本人验证并完成注册的时间。 设计场景：记录本人完成凭据登记的时刻，便于识别陌生新增设备和回溯注册流程。';
COMMENT ON COLUMN identity.webauthn_credential."last_used_at" IS '最近成功认证时间。 设计场景：帮助用户识别仍在使用的凭据、设备或票据，支持轮换和清理；不是独立的有效性证明。';
COMMENT ON COLUMN identity.webauthn_credential."revoked_at" IS '本人或安全恢复流程撤销时间；已撤销凭据保留历史且不可认证。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN identity.webauthn_credential."version" IS '并发更新版本，用于计数、状态和名称更新。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
CREATE INDEX ix_webauthn_credential_account ON identity.webauthn_credential USING btree (account_id, registered_at);

-- identity.mfa_factor：验证器因子登记和撤销记录；每账号最多一个有效 TOTP 因子，通行密钥单独管理。
CREATE TABLE identity.mfa_factor (
    -- 本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 因子类型；此表仅保存 TOTP，共享秘密与通行密钥公钥分表。 设计场景：本表将共享秘密型 TOTP 因子与通行密钥公钥凭据分开，避免同一字段混存不同安全模型的材料。
    "type" character varying(16) DEFAULT 'TOTP'::character varying NOT NULL,
    -- 对象状态，允许值及字段组合见本表 CHECK 约束。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    -- TOTP 秘密的认证加密信封，包含算法所需 nonce/tag；主密钥在数据库之外，不可使用裸散列替代可解密秘密。 设计场景：TOTP 验证需要可解密的共享秘密，必须认证加密保存并将主密钥放在库外，不能使用不可逆散列替代。
    "secret_ciphertext" bytea NOT NULL,
    -- 数据库之外加密密钥的正整数版本，用于轮换和解密。 设计场景：密钥轮换后按写入时版本选择正确解密材料；不能把新旧密文混用同一把默认密钥。
    "key_version" integer NOT NULL,
    -- 待登记截止时间；激活时在同一原子更新中检查仍未过期。 设计场景：用户开始绑定验证器但未完成确认时限制待登记窗口，过期后不能凭旧登记材料激活。
    "enrollment_expires_at" timestamp with time zone,
    -- 验证完成并启用该对象的时间。 设计场景：区分预登记员工与已经完成本人核验的成员，同步进来的人不会仅因有记录就获得登录资格。
    "activated_at" timestamp with time zone,
    -- 最近一次成功使用的 TOTP 时间步；激活时必须记录登记确认已消费的时间步，后续仅接受更大时间步，并以条件更新阻止并发重放。 设计场景：同一 TOTP 动态码在有效时间内也只能成功消费一次，原子比较时间步阻止并发重放。
    "last_used_step" bigint,
    -- 撤销时间；普通撤销需在受控事务内保护管理员 MFA 和最后一个有效管理员。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 乐观锁版本，变更事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_mfa_factor_activation" CHECK (activated_at IS NULL OR activated_at >= created_at AND (enrollment_expires_at IS NULL OR activated_at < enrollment_expires_at)),
    CONSTRAINT "ck_mfa_factor_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_mfa_factor_revoked" CHECK (revoked_at IS NULL OR revoked_at >= created_at AND (activated_at IS NULL OR revoked_at >= activated_at)),
    CONSTRAINT "ck_mfa_factor_secret" CHECK (octet_length(secret_ciphertext) > 0 AND key_version > 0),
    CONSTRAINT "ck_mfa_factor_state" CHECK (status::text = 'PENDING'::text AND enrollment_expires_at IS NOT NULL AND enrollment_expires_at > created_at AND activated_at IS NULL AND last_used_step IS NULL AND revoked_at IS NULL OR status::text = 'ACTIVE'::text AND activated_at IS NOT NULL AND last_used_step IS NOT NULL AND revoked_at IS NULL OR status::text = 'REVOKED'::text AND revoked_at IS NOT NULL),
    CONSTRAINT "ck_mfa_factor_status" CHECK (status::text = ANY (ARRAY['PENDING'::character varying, 'ACTIVE'::character varying, 'REVOKED'::character varying]::text[])),
    CONSTRAINT "ck_mfa_factor_step" CHECK (last_used_step IS NULL OR last_used_step >= 0 AND activated_at IS NOT NULL),
    CONSTRAINT "ck_mfa_factor_type" CHECK (type::text = 'TOTP'::text),
    CONSTRAINT "ck_mfa_factor_updated" CHECK (updated_at >= created_at),
    CONSTRAINT "ck_mfa_factor_version" CHECK (version >= 0),
    CONSTRAINT "fk_mfa_factor_account" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "mfa_factor_pkey" PRIMARY KEY (id),
    CONSTRAINT "uq_mfa_factor_account_id" UNIQUE (account_id, id)
);
COMMENT ON TABLE identity.mfa_factor IS '验证器因子登记和撤销记录；每账号最多一个有效 TOTP 因子，通行密钥单独管理。';
COMMENT ON COLUMN identity.mfa_factor."id" IS '本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.mfa_factor."account_id" IS '关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.mfa_factor."type" IS '因子类型；此表仅保存 TOTP，共享秘密与通行密钥公钥分表。 设计场景：本表将共享秘密型 TOTP 因子与通行密钥公钥凭据分开，避免同一字段混存不同安全模型的材料。';
COMMENT ON COLUMN identity.mfa_factor."status" IS '对象状态，允许值及字段组合见本表 CHECK 约束。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN identity.mfa_factor."secret_ciphertext" IS 'TOTP 秘密的认证加密信封，包含算法所需 nonce/tag；主密钥在数据库之外，不可使用裸散列替代可解密秘密。 设计场景：TOTP 验证需要可解密的共享秘密，必须认证加密保存并将主密钥放在库外，不能使用不可逆散列替代。';
COMMENT ON COLUMN identity.mfa_factor."key_version" IS '数据库之外加密密钥的正整数版本，用于轮换和解密。 设计场景：密钥轮换后按写入时版本选择正确解密材料；不能把新旧密文混用同一把默认密钥。';
COMMENT ON COLUMN identity.mfa_factor."enrollment_expires_at" IS '待登记截止时间；激活时在同一原子更新中检查仍未过期。 设计场景：用户开始绑定验证器但未完成确认时限制待登记窗口，过期后不能凭旧登记材料激活。';
COMMENT ON COLUMN identity.mfa_factor."activated_at" IS '验证完成并启用该对象的时间。 设计场景：区分预登记员工与已经完成本人核验的成员，同步进来的人不会仅因有记录就获得登录资格。';
COMMENT ON COLUMN identity.mfa_factor."last_used_step" IS '最近一次成功使用的 TOTP 时间步；激活时必须记录登记确认已消费的时间步，后续仅接受更大时间步，并以条件更新阻止并发重放。 设计场景：同一 TOTP 动态码在有效时间内也只能成功消费一次，原子比较时间步阻止并发重放。';
COMMENT ON COLUMN identity.mfa_factor."revoked_at" IS '撤销时间；普通撤销需在受控事务内保护管理员 MFA 和最后一个有效管理员。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN identity.mfa_factor."version" IS '乐观锁版本，变更事务递增。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN identity.mfa_factor."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.mfa_factor."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_mfa_factor_account_status ON identity.mfa_factor USING btree (account_id, status);
CREATE INDEX ix_mfa_factor_pending_expiry ON identity.mfa_factor USING btree (enrollment_expires_at) WHERE ((status)::text = 'PENDING'::text);
CREATE UNIQUE INDEX uq_mfa_factor_active ON identity.mfa_factor USING btree (account_id, type) WHERE ((status)::text = 'ACTIVE'::text);

-- identity.authentication_evidence：已核验认证证据；按方法、近期性和撤销版本判断目标策略，恢复码不是独立主登录入口。
CREATE TABLE identity.authentication_evidence (
    -- 应用生成的正数雪花证据ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 经过证明的账号，与流程/会话/因子通过复合外键保持一致。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 产生证据的认证尝试，可与升格后的会话同时关联。 设计场景：一次性挑战或认证证据只能用于其所属认证过程，避免把重置密码验证码拿去完成其他登录步骤。
    "attempt_id" bigint,
    -- 该证据适用的中央会话；半认证阶段可空，不能以有证据替代正式会话。 设计场景：将记录关联到它所属的会话，校验时不能跨会话借用认证证据或服务端凭据；具体会话类型由所在表决定。
    "session_id" bigint,
    -- 实际完成的方法；外部扫码默认不等于MFA，供应商声明需按受信配置验证。 设计场景：记录实际使用的证明方式，敏感操作按可信验证结果判断，而非接受前端自报方式。
    "method" character varying(16) NOT NULL,
    -- TOTP证明对应的本账号因子，其他方法为空。 设计场景：加强验证证据指向实际使用的本账号 TOTP 因子，因子撤销后不能继续借用旧证明满足新要求。
    "factor_id" bigint,
    -- PASSKEY证明对应的本账号公钥凭据，其他方法为空。 设计场景：认证证据关联实际校验的公钥凭据，便于判断凭据撤销及追溯设备使用。
    "passkey_id" bigint,
    -- EXTERNAL证明对应的外部绑定；后续来源有效性由成员映射与策略检查。 设计场景：企业来源员工必须关联经验证的登录身份，离职后禁用相应入口而不误伤其他独立登录方式。
    "external_identity_id" bigint,
    -- 真实完成该认证步骤的时间，不能用刷新时间替换。 设计场景：敏感操作要求近期认证时采用真实验证时间，刷新访问令牌不能把旧认证伪装成刚刚验证。
    "authenticated_at" timestamp with time zone NOT NULL,
    -- 完成步骤时账号撤销版本快照，必须与当前账号比较。 设计场景：保存完成这一步认证时的版本，敏感操作复用证据前检测账号是否已经被改密或禁用，不能给旧证据补写新版本。
    "auth_epoch" bigint NOT NULL,
    -- 协议已验证的用户验证事实；仅由服务端可信验证器写入。 设计场景：区分仅持有设备与认证器已完成用户验证，应用不能相信前端自称已通过生物识别。
    "user_verified" boolean DEFAULT false NOT NULL,
    -- 经验证的抗钓鱼事实，本模型仅已完成用户验证的PASSKEY可标真。 设计场景：目标策略要求抗钓鱼验证时检查真实证据，本模型只接受符合条件的通行密钥用户验证。
    "phishing_resistant" boolean DEFAULT false NOT NULL,
    -- 证据自身有效期；目标安全策略可能要求更短的近期认证窗口。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone,
    -- 证据写入时间，不代替authenticated_at。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "authentication_evidence_account_id_fkey" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "authentication_evidence_auth_epoch_check" CHECK (auth_epoch >= 0),
    CONSTRAINT "authentication_evidence_id_check" CHECK (id > 0),
    CONSTRAINT "authentication_evidence_method_check" CHECK (method::text = ANY (ARRAY['PASSWORD'::character varying, 'SMS'::character varying, 'EXTERNAL'::character varying, 'TOTP'::character varying, 'PASSKEY'::character varying, 'RECOVERY_CODE'::character varying]::text[])),
    CONSTRAINT "authentication_evidence_pkey" PRIMARY KEY (id),
    CONSTRAINT "ck_auth_evidence_expiry" CHECK (expires_at IS NULL OR expires_at > authenticated_at),
    CONSTRAINT "ck_auth_evidence_material" CHECK (method::text = 'TOTP'::text AND factor_id IS NOT NULL AND passkey_id IS NULL AND external_identity_id IS NULL OR method::text = 'PASSKEY'::text AND passkey_id IS NOT NULL AND factor_id IS NULL AND external_identity_id IS NULL OR method::text = 'EXTERNAL'::text AND external_identity_id IS NOT NULL AND factor_id IS NULL AND passkey_id IS NULL OR (method::text = ANY (ARRAY['PASSWORD'::character varying, 'SMS'::character varying, 'RECOVERY_CODE'::character varying]::text[])) AND factor_id IS NULL AND passkey_id IS NULL AND external_identity_id IS NULL),
    CONSTRAINT "ck_auth_evidence_owner" CHECK (attempt_id IS NOT NULL OR session_id IS NOT NULL),
    CONSTRAINT "ck_auth_evidence_phishing" CHECK (NOT phishing_resistant OR method::text = 'PASSKEY'::text AND user_verified),
    CONSTRAINT "fk_auth_evidence_attempt" FOREIGN KEY (account_id, attempt_id) REFERENCES identity.authentication_attempt(account_id, id),
    CONSTRAINT "fk_auth_evidence_external" FOREIGN KEY (external_identity_id, account_id) REFERENCES identity.external_identity(id, account_id),
    CONSTRAINT "fk_auth_evidence_passkey" FOREIGN KEY (account_id, passkey_id) REFERENCES identity.webauthn_credential(account_id, id),
    CONSTRAINT "fk_auth_evidence_session" FOREIGN KEY (account_id, session_id) REFERENCES identity.auth_session(account_id, id),
    CONSTRAINT "fk_auth_evidence_totp" FOREIGN KEY (account_id, factor_id) REFERENCES identity.mfa_factor(account_id, id)
);
COMMENT ON TABLE identity.authentication_evidence IS '已核验认证证据；按方法、近期性和撤销版本判断目标策略，恢复码不是独立主登录入口。';
COMMENT ON COLUMN identity.authentication_evidence."id" IS '应用生成的正数雪花证据ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.authentication_evidence."account_id" IS '经过证明的账号，与流程/会话/因子通过复合外键保持一致。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.authentication_evidence."attempt_id" IS '产生证据的认证尝试，可与升格后的会话同时关联。 设计场景：一次性挑战或认证证据只能用于其所属认证过程，避免把重置密码验证码拿去完成其他登录步骤。';
COMMENT ON COLUMN identity.authentication_evidence."session_id" IS '该证据适用的中央会话；半认证阶段可空，不能以有证据替代正式会话。 设计场景：将记录关联到它所属的会话，校验时不能跨会话借用认证证据或服务端凭据；具体会话类型由所在表决定。';
COMMENT ON COLUMN identity.authentication_evidence."method" IS '实际完成的方法；外部扫码默认不等于MFA，供应商声明需按受信配置验证。 设计场景：记录实际使用的证明方式，敏感操作按可信验证结果判断，而非接受前端自报方式。';
COMMENT ON COLUMN identity.authentication_evidence."factor_id" IS 'TOTP证明对应的本账号因子，其他方法为空。 设计场景：加强验证证据指向实际使用的本账号 TOTP 因子，因子撤销后不能继续借用旧证明满足新要求。';
COMMENT ON COLUMN identity.authentication_evidence."passkey_id" IS 'PASSKEY证明对应的本账号公钥凭据，其他方法为空。 设计场景：认证证据关联实际校验的公钥凭据，便于判断凭据撤销及追溯设备使用。';
COMMENT ON COLUMN identity.authentication_evidence."external_identity_id" IS 'EXTERNAL证明对应的外部绑定；后续来源有效性由成员映射与策略检查。 设计场景：企业来源员工必须关联经验证的登录身份，离职后禁用相应入口而不误伤其他独立登录方式。';
COMMENT ON COLUMN identity.authentication_evidence."authenticated_at" IS '真实完成该认证步骤的时间，不能用刷新时间替换。 设计场景：敏感操作要求近期认证时采用真实验证时间，刷新访问令牌不能把旧认证伪装成刚刚验证。';
COMMENT ON COLUMN identity.authentication_evidence."auth_epoch" IS '完成步骤时账号撤销版本快照，必须与当前账号比较。 设计场景：保存完成这一步认证时的版本，敏感操作复用证据前检测账号是否已经被改密或禁用，不能给旧证据补写新版本。';
COMMENT ON COLUMN identity.authentication_evidence."user_verified" IS '协议已验证的用户验证事实；仅由服务端可信验证器写入。 设计场景：区分仅持有设备与认证器已完成用户验证，应用不能相信前端自称已通过生物识别。';
COMMENT ON COLUMN identity.authentication_evidence."phishing_resistant" IS '经验证的抗钓鱼事实，本模型仅已完成用户验证的PASSKEY可标真。 设计场景：目标策略要求抗钓鱼验证时检查真实证据，本模型只接受符合条件的通行密钥用户验证。';
COMMENT ON COLUMN identity.authentication_evidence."expires_at" IS '证据自身有效期；目标安全策略可能要求更短的近期认证窗口。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN identity.authentication_evidence."created_at" IS '证据写入时间，不代替authenticated_at。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_auth_evidence_account_time ON identity.authentication_evidence USING btree (account_id, authenticated_at DESC);
CREATE INDEX ix_auth_evidence_attempt ON identity.authentication_evidence USING btree (attempt_id) WHERE (attempt_id IS NOT NULL);
CREATE INDEX ix_auth_evidence_external ON identity.authentication_evidence USING btree (external_identity_id) WHERE (external_identity_id IS NOT NULL);
CREATE INDEX ix_auth_evidence_factor ON identity.authentication_evidence USING btree (factor_id) WHERE (factor_id IS NOT NULL);
CREATE INDEX ix_auth_evidence_passkey ON identity.authentication_evidence USING btree (passkey_id) WHERE (passkey_id IS NOT NULL);
CREATE INDEX ix_auth_evidence_session ON identity.authentication_evidence USING btree (session_id) WHERE (session_id IS NOT NULL);

-- identity.external_connection_key：上游协议密钥/证书版本引用；支持新旧验证材料重叠，密钥本体在受控秘密存储；应用校验用途和有效期。
CREATE TABLE identity.external_connection_key (
    -- 应用生成的正数雪花材料记录ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属上游连接，与版本通过复合外键绑定。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。
    "connection_id" bigint NOT NULL,
    -- 该密钥/证书适用的上游配置快照。 设计场景：同一连接换配置或换钥后仍能定位材料属于哪份发布快照，避免跨版本混用证书。
    "connection_version_id" bigint NOT NULL,
    -- 版本内材料标识，例如kid或管理员生成的轮换标签，不作为认证凭据。 设计场景：多把上游验签材料同时有效时精确定位对应项，不能仅凭收到的 kid 信任未登记公钥。
    "key_identifier" character varying(200) NOT NULL,
    -- CLIENT_AUTH客户端认证、VERIFY_SIGNATURE验证上游签名、DECRYPTION解密上游消息、TLS_CLIENT双向TLS。 设计场景：上游验签、请求签名和客户端认证材料按用途隔离，收到外部 kid 也只能选择当前连接获准材料。
    "purpose" character varying(24) NOT NULL,
    -- 秘密管理器或受保护证书库的版本化引用，禁止存私钥、共享秘密明文。 设计场景：让配置引用受保护的特定版本材料，换钥时能保留验证窗口，而无需在业务表复制明文私钥。
    "material_ref" text NOT NULL,
    -- 可选的公开证书/公钥指纹，用于核对及展示，不代替签名校验。 设计场景：管理员核对导入或轮换的证书、公钥是否为预期材料，避免只凭名称选错密钥。
    "fingerprint" character varying(128),
    -- PENDING待启用、ACTIVE使用中、GRACE仅过渡验证、REVOKED撤销；GRACE不能用于新的客户端签名。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。
    "status" character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    -- 材料最早可用时刻。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。
    "valid_from" timestamp with time zone NOT NULL,
    -- 材料到期时刻；无固定到期的秘密可空，轮换仍受策略管理。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。
    "valid_until" timestamp with time zone,
    -- 材料撤销时刻，撤销后不得再验签或认证。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 材料引用登记时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_external_connection_key_fingerprint" CHECK (fingerprint IS NULL OR btrim(fingerprint::text) <> ''::text),
    CONSTRAINT "ck_external_connection_key_state" CHECK ((status::text = 'REVOKED'::text) = (revoked_at IS NOT NULL)),
    CONSTRAINT "ck_external_connection_key_times" CHECK ((valid_until IS NULL OR valid_until > valid_from) AND (revoked_at IS NULL OR revoked_at >= created_at)),
    CONSTRAINT "external_connection_key_id_check" CHECK (id > 0),
    CONSTRAINT "external_connection_key_key_identifier_check" CHECK (btrim(key_identifier::text) <> ''::text),
    CONSTRAINT "external_connection_key_material_ref_check" CHECK (btrim(material_ref) <> ''::text),
    CONSTRAINT "external_connection_key_pkey" PRIMARY KEY (id),
    CONSTRAINT "external_connection_key_purpose_check" CHECK (purpose::text = ANY (ARRAY['CLIENT_AUTH'::character varying, 'VERIFY_SIGNATURE'::character varying, 'DECRYPTION'::character varying, 'TLS_CLIENT'::character varying]::text[])),
    CONSTRAINT "external_connection_key_status_check" CHECK (status::text = ANY (ARRAY['PENDING'::character varying, 'ACTIVE'::character varying, 'GRACE'::character varying, 'REVOKED'::character varying]::text[])),
    CONSTRAINT "fk_external_connection_key_version" FOREIGN KEY (connection_id, connection_version_id) REFERENCES identity.external_connection_version(connection_id, id),
    CONSTRAINT "uq_external_connection_key_version" UNIQUE (connection_version_id, purpose, key_identifier)
);
COMMENT ON TABLE identity.external_connection_key IS '上游协议密钥/证书版本引用；支持新旧验证材料重叠，密钥本体在受控秘密存储；应用校验用途和有效期。';
COMMENT ON COLUMN identity.external_connection_key."id" IS '应用生成的正数雪花材料记录ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.external_connection_key."connection_id" IS '所属上游连接，与版本通过复合外键绑定。 设计场景：将配置、身份或任务限定到明确连接，来源或目标相同字符串必须在连接作用域内解释，不能跨连接复用映射。';
COMMENT ON COLUMN identity.external_connection_key."connection_version_id" IS '该密钥/证书适用的上游配置快照。 设计场景：同一连接换配置或换钥后仍能定位材料属于哪份发布快照，避免跨版本混用证书。';
COMMENT ON COLUMN identity.external_connection_key."key_identifier" IS '版本内材料标识，例如kid或管理员生成的轮换标签，不作为认证凭据。 设计场景：多把上游验签材料同时有效时精确定位对应项，不能仅凭收到的 kid 信任未登记公钥。';
COMMENT ON COLUMN identity.external_connection_key."purpose" IS 'CLIENT_AUTH客户端认证、VERIFY_SIGNATURE验证上游签名、DECRYPTION解密上游消息、TLS_CLIENT双向TLS。 设计场景：上游验签、请求签名和客户端认证材料按用途隔离，收到外部 kid 也只能选择当前连接获准材料。';
COMMENT ON COLUMN identity.external_connection_key."material_ref" IS '秘密管理器或受保护证书库的版本化引用，禁止存私钥、共享秘密明文。 设计场景：让配置引用受保护的特定版本材料，换钥时能保留验证窗口，而无需在业务表复制明文私钥。';
COMMENT ON COLUMN identity.external_connection_key."fingerprint" IS '可选的公开证书/公钥指纹，用于核对及展示，不代替签名校验。 设计场景：管理员核对导入或轮换的证书、公钥是否为预期材料，避免只凭名称选错密钥。';
COMMENT ON COLUMN identity.external_connection_key."status" IS 'PENDING待启用、ACTIVE使用中、GRACE仅过渡验证、REVOKED撤销；GRACE不能用于新的客户端签名。 设计场景：区分记录当前所处生命周期阶段；用例按状态决定能否继续操作，具体允许值和字段组合见本表约束。';
COMMENT ON COLUMN identity.external_connection_key."valid_from" IS '材料最早可用时刻。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。';
COMMENT ON COLUMN identity.external_connection_key."valid_until" IS '材料到期时刻；无固定到期的秘密可空，轮换仍受策略管理。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。';
COMMENT ON COLUMN identity.external_connection_key."revoked_at" IS '材料撤销时刻，撤销后不得再验签或认证。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN identity.external_connection_key."created_at" IS '材料引用登记时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
CREATE INDEX ix_external_connection_key_connection ON identity.external_connection_key USING btree (connection_id, connection_version_id);

-- identity.username_reservation：用户名永久占用登记；旧用户名不再登录但仍归原账号，系统保留名不能绑定；不得以注销为由回收给他人。
CREATE TABLE identity.username_reservation (
    -- 应用生成的正数雪花占用记录ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 小写ASCII用户名，4～32位字母数字下划线且至少一个字母，全局永久唯一。 设计场景：登录匹配与唯一判断使用同一规范化值，避免大小写或空白产生重复身份；具体规则随标识类型确定。
    "normalized_value" character varying(32) NOT NULL,
    -- 占用账号；系统保留名称为空，账号合并默认不迁移旧名称的占用归属。 设计场景：本人选用的用户名永久归属该账号；系统保留名按约束可没有账号，不因改名或注销回收给其他人。
    "account_id" bigint,
    -- ACCOUNT本人选用的名字；SYSTEM禁止普通用户使用的系统名称。 设计场景：区分用户永久占用与系统保留名，避免注册到管理员等受保护名称或重用他人旧用户名。
    "reservation_kind" character varying(16) NOT NULL,
    -- 首次占用时间；撤销当前登录标识不删除这条登记。 设计场景：保留用户名首次占用事实，改名或注销后仍可解释为什么旧用户名不再分配给其他人。
    "reserved_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_username_reservation_owner" CHECK (reservation_kind::text = 'ACCOUNT'::text AND account_id IS NOT NULL OR reservation_kind::text = 'SYSTEM'::text AND account_id IS NULL),
    CONSTRAINT "ck_username_reservation_value" CHECK (normalized_value::text = lower(normalized_value::text) AND normalized_value::text ~ '^[a-z0-9_]{4,32}$'::text AND normalized_value::text ~ '[a-z]'::text),
    CONSTRAINT "uq_username_reservation_owner" UNIQUE (id, account_id, normalized_value),
    CONSTRAINT "username_reservation_account_id_fkey" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "username_reservation_id_check" CHECK (id > 0),
    CONSTRAINT "username_reservation_normalized_value_key" UNIQUE (normalized_value),
    CONSTRAINT "username_reservation_pkey" PRIMARY KEY (id)
);
COMMENT ON TABLE identity.username_reservation IS '用户名永久占用登记；旧用户名不再登录但仍归原账号，系统保留名不能绑定；不得以注销为由回收给他人。';
COMMENT ON COLUMN identity.username_reservation."id" IS '应用生成的正数雪花占用记录ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.username_reservation."normalized_value" IS '小写ASCII用户名，4～32位字母数字下划线且至少一个字母，全局永久唯一。 设计场景：登录匹配与唯一判断使用同一规范化值，避免大小写或空白产生重复身份；具体规则随标识类型确定。';
COMMENT ON COLUMN identity.username_reservation."account_id" IS '占用账号；系统保留名称为空，账号合并默认不迁移旧名称的占用归属。 设计场景：本人选用的用户名永久归属该账号；系统保留名按约束可没有账号，不因改名或注销回收给其他人。';
COMMENT ON COLUMN identity.username_reservation."reservation_kind" IS 'ACCOUNT本人选用的名字；SYSTEM禁止普通用户使用的系统名称。 设计场景：区分用户永久占用与系统保留名，避免注册到管理员等受保护名称或重用他人旧用户名。';
COMMENT ON COLUMN identity.username_reservation."reserved_at" IS '首次占用时间；撤销当前登录标识不删除这条登记。 设计场景：保留用户名首次占用事实，改名或注销后仍可解释为什么旧用户名不再分配给其他人。';
CREATE INDEX ix_username_reservation_account ON identity.username_reservation USING btree (account_id) WHERE (account_id IS NOT NULL);

-- identity.login_identifier：当前及已撤销的登录标识；邮箱手机须验证，用户名由本人选用；现有两个活跃唯一索引同时限制值归属和每账号每类型数量。
CREATE TABLE identity.login_identifier (
    -- 本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- EMAIL邮箱、PHONE短信手机号、USERNAME本人设置用户名；PHONE不参与密码登录。 设计场景：用户名和邮箱共用账号密码，手机号只走验证码；不同类型采用各自规范化、归属验证及唯一性规则。
    "kind" character varying(16) NOT NULL,
    -- 邮箱整体小写；手机号使用带国家码的E.164形式，完整号码及可发送地区由应用校验；用户名使用小写ASCII。 设计场景：登录匹配与唯一判断使用同一规范化值，避免大小写或空白产生重复身份；具体规则随标识类型确定。
    "normalized_value" character varying(254) NOT NULL,
    -- 展示原文，不能替代 normalized_value 参与身份匹配。 设计场景：界面保留用户原始输入外观，查询匹配和唯一约束仍使用规范化值，避免展示格式影响身份判断。
    "display_value" character varying(254) NOT NULL,
    -- 邮箱/手机号归属验证时间；用户名为空，设置时间用created_at，不伪造验证记录。 设计场景：区分仅声明拥有身份、地址或域名与已经实际完成核验，核验结果是否仍有效由期限与状态共同决定。
    "verified_at" timestamp with time zone,
    -- 为空表示当前绑定；跨所有主登录方式的最后一种解绑保护须锁定账号。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 用户名的永久占用记录；复合外键同时验证账号和值，非用户名必须为空。 设计场景：用户名变更后仍有永久占用记录，防止旧名被他人注册后产生身份混淆。
    "username_reservation_id" bigint,
    CONSTRAINT "ck_login_identifier_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_login_identifier_kind" CHECK (kind::text = ANY (ARRAY['EMAIL'::character varying, 'PHONE'::character varying, 'USERNAME'::character varying]::text[])),
    CONSTRAINT "ck_login_identifier_proof" CHECK (kind::text = 'USERNAME'::text AND username_reservation_id IS NOT NULL AND verified_at IS NULL OR (kind::text = ANY (ARRAY['EMAIL'::character varying, 'PHONE'::character varying]::text[])) AND username_reservation_id IS NULL AND verified_at IS NOT NULL),
    CONSTRAINT "ck_login_identifier_revoked" CHECK (revoked_at IS NULL OR revoked_at >= COALESCE(verified_at, created_at)),
    CONSTRAINT "ck_login_identifier_updated" CHECK (updated_at >= created_at),
    CONSTRAINT "ck_login_identifier_value" CHECK (normalized_value::text <> ''::text AND normalized_value::text = btrim(normalized_value::text) AND btrim(display_value::text) <> ''::text AND (kind::text = 'EMAIL'::text AND normalized_value::text = lower(normalized_value::text) OR kind::text = 'PHONE'::text AND normalized_value::text ~ '^\+[1-9][0-9]{1,14}$'::text OR kind::text = 'USERNAME'::text AND normalized_value::text = lower(normalized_value::text) AND normalized_value::text ~ '^[a-z0-9_]{4,32}$'::text AND normalized_value::text ~ '[a-z]'::text)),
    CONSTRAINT "fk_login_identifier_account" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "fk_login_identifier_username" FOREIGN KEY (username_reservation_id, account_id, normalized_value) REFERENCES identity.username_reservation(id, account_id, normalized_value),
    CONSTRAINT "login_identifier_pkey" PRIMARY KEY (id)
);
COMMENT ON TABLE identity.login_identifier IS '当前及已撤销的登录标识；邮箱手机须验证，用户名由本人选用；现有两个活跃唯一索引同时限制值归属和每账号每类型数量。';
COMMENT ON COLUMN identity.login_identifier."id" IS '本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.login_identifier."account_id" IS '关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.login_identifier."kind" IS 'EMAIL邮箱、PHONE短信手机号、USERNAME本人设置用户名；PHONE不参与密码登录。 设计场景：用户名和邮箱共用账号密码，手机号只走验证码；不同类型采用各自规范化、归属验证及唯一性规则。';
COMMENT ON COLUMN identity.login_identifier."normalized_value" IS '邮箱整体小写；手机号使用带国家码的E.164形式，完整号码及可发送地区由应用校验；用户名使用小写ASCII。 设计场景：登录匹配与唯一判断使用同一规范化值，避免大小写或空白产生重复身份；具体规则随标识类型确定。';
COMMENT ON COLUMN identity.login_identifier."display_value" IS '展示原文，不能替代 normalized_value 参与身份匹配。 设计场景：界面保留用户原始输入外观，查询匹配和唯一约束仍使用规范化值，避免展示格式影响身份判断。';
COMMENT ON COLUMN identity.login_identifier."verified_at" IS '邮箱/手机号归属验证时间；用户名为空，设置时间用created_at，不伪造验证记录。 设计场景：区分仅声明拥有身份、地址或域名与已经实际完成核验，核验结果是否仍有效由期限与状态共同决定。';
COMMENT ON COLUMN identity.login_identifier."revoked_at" IS '为空表示当前绑定；跨所有主登录方式的最后一种解绑保护须锁定账号。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN identity.login_identifier."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.login_identifier."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
COMMENT ON COLUMN identity.login_identifier."username_reservation_id" IS '用户名的永久占用记录；复合外键同时验证账号和值，非用户名必须为空。 设计场景：用户名变更后仍有永久占用记录，防止旧名被他人注册后产生身份混淆。';
CREATE INDEX ix_login_identifier_account ON identity.login_identifier USING btree (account_id, created_at);
CREATE INDEX ix_login_identifier_username_reservation ON identity.login_identifier USING btree (username_reservation_id) WHERE (username_reservation_id IS NOT NULL);
CREATE UNIQUE INDEX uq_login_identifier_active_kind ON identity.login_identifier USING btree (account_id, kind) WHERE (revoked_at IS NULL);
CREATE UNIQUE INDEX uq_login_identifier_active_value ON identity.login_identifier USING btree (kind, normalized_value) WHERE (revoked_at IS NULL);

-- identity.password_credential：账号当前密码凭据；每个账号最多一份，不保存密码历史明文。
CREATE TABLE identity.password_credential (
    -- 关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- PasswordEncoder 完整编码值，包含算法标识、参数与盐；由应用使用 Argon2id/DelegatingPasswordEncoder 生成。 设计场景：校验密码时使用带算法参数和盐的不可逆编码值，升级算法可重新编码，不保存可还原的密码。
    "password_hash" text NOT NULL,
    -- 密码最后设置或变更时间。 设计场景：说明最近改密时间并支持安全审计，改密后的会话撤销仍通过撤销版本和相关用例执行。
    "changed_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 乐观锁版本，更新匹配旧值并递增；换密须同时协调账号 auth_epoch 和会话撤销。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_password_credential_hash" CHECK (btrim(password_hash) <> ''::text),
    CONSTRAINT "ck_password_credential_updated" CHECK (updated_at >= created_at),
    CONSTRAINT "ck_password_credential_version" CHECK (version >= 0),
    CONSTRAINT "fk_password_credential_account" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "password_credential_pkey" PRIMARY KEY (account_id)
);
COMMENT ON TABLE identity.password_credential IS '账号当前密码凭据；每个账号最多一份，不保存密码历史明文。';
COMMENT ON COLUMN identity.password_credential."account_id" IS '关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.password_credential."password_hash" IS 'PasswordEncoder 完整编码值，包含算法标识、参数与盐；由应用使用 Argon2id/DelegatingPasswordEncoder 生成。 设计场景：校验密码时使用带算法参数和盐的不可逆编码值，升级算法可重新编码，不保存可还原的密码。';
COMMENT ON COLUMN identity.password_credential."changed_at" IS '密码最后设置或变更时间。 设计场景：说明最近改密时间并支持安全审计，改密后的会话撤销仍通过撤销版本和相关用例执行。';
COMMENT ON COLUMN identity.password_credential."version" IS '乐观锁版本，更新匹配旧值并递增；换密须同时协调账号 auth_epoch 和会话撤销。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN identity.password_credential."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.password_credential."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';

-- identity.rate_limit_bucket：认证尝试频率计数窗口；供应商发送费用和短信额度由 Delivery 单独管理。
CREATE TABLE identity.rate_limit_bucket (
    -- 服务端按用途、账号/目标/来源组合的桶标识；建议带版本的 HMAC 编码，避免保存原始联系方式。 设计场景：把登录、验证码等用途与账号、目标或来源分桶，防止一种操作的额度被另一种复用或原始联系方式泄露。
    "bucket_key" character varying(256) NOT NULL,
    -- 限流计数窗口开始时间。 设计场景：明确本轮限流计数从何时开始，多个实例按同一时间窗口累计而非各自计数。
    "window_start" timestamp with time zone NOT NULL,
    -- 限流计数窗口截止时间。 设计场景：窗口结束后按规则重置计数，仍需检查独立封禁期限，不能一到窗口边界就解除处罚。
    "window_end" timestamp with time zone NOT NULL,
    -- 事务内原子累加的尝试次数；阈值和封禁策略由受控认证用例决定。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。
    "attempts" bigint DEFAULT 0 NOT NULL,
    -- 可跨计数窗口的封禁截止时间；清理必须同时确认窗口结束且封禁已结束。 设计场景：封禁可跨越多个计数窗口，避免攻击者等窗口刷新后马上继续猜测。
    "blocked_until" timestamp with time zone,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_rate_limit_bucket_attempts" CHECK (attempts >= 0),
    CONSTRAINT "ck_rate_limit_bucket_blocked" CHECK (blocked_until IS NULL OR blocked_until >= window_start),
    CONSTRAINT "ck_rate_limit_bucket_key" CHECK (btrim(bucket_key::text) <> ''::text),
    CONSTRAINT "ck_rate_limit_bucket_updated" CHECK (updated_at >= created_at),
    CONSTRAINT "ck_rate_limit_bucket_window" CHECK (window_end > window_start),
    CONSTRAINT "pk_rate_limit_bucket" PRIMARY KEY (bucket_key, window_start)
);
COMMENT ON TABLE identity.rate_limit_bucket IS '认证尝试频率计数窗口；供应商发送费用和短信额度由 Delivery 单独管理。';
COMMENT ON COLUMN identity.rate_limit_bucket."bucket_key" IS '服务端按用途、账号/目标/来源组合的桶标识；建议带版本的 HMAC 编码，避免保存原始联系方式。 设计场景：把登录、验证码等用途与账号、目标或来源分桶，防止一种操作的额度被另一种复用或原始联系方式泄露。';
COMMENT ON COLUMN identity.rate_limit_bucket."window_start" IS '限流计数窗口开始时间。 设计场景：明确本轮限流计数从何时开始，多个实例按同一时间窗口累计而非各自计数。';
COMMENT ON COLUMN identity.rate_limit_bucket."window_end" IS '限流计数窗口截止时间。 设计场景：窗口结束后按规则重置计数，仍需检查独立封禁期限，不能一到窗口边界就解除处罚。';
COMMENT ON COLUMN identity.rate_limit_bucket."attempts" IS '事务内原子累加的尝试次数；阈值和封禁策略由受控认证用例决定。 设计场景：累计执行尝试次数，为退避、告警和停止自动重试提供依据；一次网络超时不等于远端未执行。';
COMMENT ON COLUMN identity.rate_limit_bucket."blocked_until" IS '可跨计数窗口的封禁截止时间；清理必须同时确认窗口结束且封禁已结束。 设计场景：封禁可跨越多个计数窗口，避免攻击者等窗口刷新后马上继续猜测。';
COMMENT ON COLUMN identity.rate_limit_bucket."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.rate_limit_bucket."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_rate_limit_bucket_window_end ON identity.rate_limit_bucket USING btree (window_end);

-- identity.recovery_code：主认证后的受限 MFA 恢复码；每码独立、只展示一次、原子消费。
CREATE TABLE identity.recovery_code (
    -- 本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 应用生成的恢复码批次雪花 ID；重新生成时在同一事务撤销该账号旧批次。 设计场景：重新生成恢复码时整批撤销旧码，用户可以确认手中哪一组仍有效。
    "batch_id" bigint NOT NULL,
    -- 高熵随机恢复码的 32 字节 SHA-256 摘要；不得保存恢复码明文。 设计场景：恢复码只展示一次并保存高熵摘要，数据库泄露时不能直接取出原码；成功使用后原子消费。
    "code_verifier" bytea NOT NULL,
    -- 仅当 consumed_at 和 revoked_at 均为空时才能原子消费；已消费值不得重置。 设计场景：一次性证明成功使用后立即标记，业务效果与消费同事务完成，防止重复回调再次生效。
    "consumed_at" timestamp with time zone,
    -- 撤销时间；撤销后的记录不能参与认证或授权。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_recovery_code_batch_id_positive" CHECK (batch_id > 0),
    CONSTRAINT "ck_recovery_code_consumed" CHECK (consumed_at IS NULL OR consumed_at >= created_at),
    CONSTRAINT "ck_recovery_code_id_positive" CHECK (id > 0),
    CONSTRAINT "ck_recovery_code_revoked" CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT "ck_recovery_code_updated" CHECK (updated_at >= created_at),
    CONSTRAINT "ck_recovery_code_verifier" CHECK (octet_length(code_verifier) = 32),
    CONSTRAINT "fk_recovery_code_account" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "recovery_code_pkey" PRIMARY KEY (id),
    CONSTRAINT "uq_recovery_code_verifier" UNIQUE (code_verifier)
);
COMMENT ON TABLE identity.recovery_code IS '主认证后的受限 MFA 恢复码；每码独立、只展示一次、原子消费。';
COMMENT ON COLUMN identity.recovery_code."id" IS '本表稳定主键；自有业务对象使用应用生成的正数雪花 ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.recovery_code."account_id" IS '关联的全局平台账号 ID。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.recovery_code."batch_id" IS '应用生成的恢复码批次雪花 ID；重新生成时在同一事务撤销该账号旧批次。 设计场景：重新生成恢复码时整批撤销旧码，用户可以确认手中哪一组仍有效。';
COMMENT ON COLUMN identity.recovery_code."code_verifier" IS '高熵随机恢复码的 32 字节 SHA-256 摘要；不得保存恢复码明文。 设计场景：恢复码只展示一次并保存高熵摘要，数据库泄露时不能直接取出原码；成功使用后原子消费。';
COMMENT ON COLUMN identity.recovery_code."consumed_at" IS '仅当 consumed_at 和 revoked_at 均为空时才能原子消费；已消费值不得重置。 设计场景：一次性证明成功使用后立即标记，业务效果与消费同事务完成，防止重复回调再次生效。';
COMMENT ON COLUMN identity.recovery_code."revoked_at" IS '撤销时间；撤销后的记录不能参与认证或授权。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN identity.recovery_code."created_at" IS '记录创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.recovery_code."updated_at" IS '最后更新时间，由业务事务维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_recovery_code_account_batch ON identity.recovery_code USING btree (account_id, batch_id);

-- identity.risk_event：安全风险决策证据，包含登录前未识别账号事件；属于全局安全域，不因带tenant_id就让企业管理员读取完整个人安全信息。
CREATE TABLE identity.risk_event (
    -- 应用生成的正数雪花风险事件ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 已识别账号；登录前未知身份可空，不根据用户自报ID填写。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint,
    -- 此次决策目标企业，可空；不是对企业的读取授权。 设计场景：为安全调查保留请求目标企业的上下文，风险事件仍属于全局账号安全域，不能自动对该企业管理员公开。
    "tenant_id" bigint,
    -- 关联认证尝试；若账号也非空则复合外键验证同一账号。 设计场景：一次性挑战或认证证据只能用于其所属认证过程，避免把重置密码验证码拿去完成其他登录步骤。
    "attempt_id" bigint,
    -- 关联中央会话；未登录时为空。 设计场景：将记录关联到它所属的会话，校验时不能跨会话借用认证证据或服务端凭据；具体会话类型由所在表决定。
    "session_id" bigint,
    -- 受控风险类型代码，如异地异常或凭据计数异常，不在此记录秘密。 设计场景：以稳定风险分类解释为何要求加强验证或拒绝登录，便于统计和排查误判。
    "risk_code" character varying(64) NOT NULL,
    -- 风险分级，仅为决策证据，不直接授予或撤销业务权限。 设计场景：辅助风险分级和人工处理优先级，最终是否允许操作仍由明确决策与权限规则决定。
    "severity" character varying(16) NOT NULL,
    -- 本次决策：放行、再次认证、加强验证或拒绝，由受控风险引擎产生。 设计场景：保存明确的处理决定供后续执行与追溯；决定本身和实际执行完成分别验证。
    "decision" character varying(24) NOT NULL,
    -- version=1的脱敏信号摘要：规则版本、国家/地区、粗粒度设备类别、命中规则代码；禁止原始凭据、生物特征和完整设备指纹。 设计场景：保留足够解释风险决策的脱敏线索，同时避免收集原始生物特征、完整设备指纹和凭据。
    "signal_summary" jsonb DEFAULT '{"version": 1}'::jsonb NOT NULL,
    -- 关联业务请求ID，便于审计排查。 设计场景：将风险判定追溯到具体登录或敏感请求，排查误拦截时不必记录用户密码和完整设备信息。
    "request_id" character varying(64) NOT NULL,
    -- 风险决策发生时间。 设计场景：记录事实实际发生时间，异步入库和投递延迟时仍可正确追溯先后关系。
    "occurred_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_risk_event_session_owner" CHECK (session_id IS NULL OR account_id IS NOT NULL),
    CONSTRAINT "ck_risk_event_summary" CHECK (jsonb_typeof(signal_summary) = 'object'::text AND signal_summary @> '{"version": 1}'::jsonb),
    CONSTRAINT "fk_risk_event_attempt_account" FOREIGN KEY (account_id, attempt_id) REFERENCES identity.authentication_attempt(account_id, id),
    CONSTRAINT "fk_risk_event_session_account" FOREIGN KEY (account_id, session_id) REFERENCES identity.auth_session(account_id, id),
    CONSTRAINT "risk_event_account_id_fkey" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "risk_event_attempt_id_fkey" FOREIGN KEY (attempt_id) REFERENCES identity.authentication_attempt(id),
    CONSTRAINT "risk_event_decision_check" CHECK (decision::text = ANY (ARRAY['ALLOW'::character varying, 'REAUTHENTICATE'::character varying, 'REQUIRE_MFA'::character varying, 'DENY'::character varying]::text[])),
    CONSTRAINT "risk_event_id_check" CHECK (id > 0),
    CONSTRAINT "risk_event_pkey" PRIMARY KEY (id),
    CONSTRAINT "risk_event_request_id_check" CHECK (btrim(request_id::text) <> ''::text),
    CONSTRAINT "risk_event_risk_code_check" CHECK (btrim(risk_code::text) <> ''::text),
    CONSTRAINT "risk_event_session_id_fkey" FOREIGN KEY (session_id) REFERENCES identity.auth_session(id),
    CONSTRAINT "risk_event_severity_check" CHECK (severity::text = ANY (ARRAY['LOW'::character varying, 'MEDIUM'::character varying, 'HIGH'::character varying, 'CRITICAL'::character varying]::text[])),
    CONSTRAINT "risk_event_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id)
);
COMMENT ON TABLE identity.risk_event IS '安全风险决策证据，包含登录前未识别账号事件；属于全局安全域，不因带tenant_id就让企业管理员读取完整个人安全信息。';
COMMENT ON COLUMN identity.risk_event."id" IS '应用生成的正数雪花风险事件ID。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.risk_event."account_id" IS '已识别账号；登录前未知身份可空，不根据用户自报ID填写。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.risk_event."tenant_id" IS '此次决策目标企业，可空；不是对企业的读取授权。 设计场景：为安全调查保留请求目标企业的上下文，风险事件仍属于全局账号安全域，不能自动对该企业管理员公开。';
COMMENT ON COLUMN identity.risk_event."attempt_id" IS '关联认证尝试；若账号也非空则复合外键验证同一账号。 设计场景：一次性挑战或认证证据只能用于其所属认证过程，避免把重置密码验证码拿去完成其他登录步骤。';
COMMENT ON COLUMN identity.risk_event."session_id" IS '关联中央会话；未登录时为空。 设计场景：将记录关联到它所属的会话，校验时不能跨会话借用认证证据或服务端凭据；具体会话类型由所在表决定。';
COMMENT ON COLUMN identity.risk_event."risk_code" IS '受控风险类型代码，如异地异常或凭据计数异常，不在此记录秘密。 设计场景：以稳定风险分类解释为何要求加强验证或拒绝登录，便于统计和排查误判。';
COMMENT ON COLUMN identity.risk_event."severity" IS '风险分级，仅为决策证据，不直接授予或撤销业务权限。 设计场景：辅助风险分级和人工处理优先级，最终是否允许操作仍由明确决策与权限规则决定。';
COMMENT ON COLUMN identity.risk_event."decision" IS '本次决策：放行、再次认证、加强验证或拒绝，由受控风险引擎产生。 设计场景：保存明确的处理决定供后续执行与追溯；决定本身和实际执行完成分别验证。';
COMMENT ON COLUMN identity.risk_event."signal_summary" IS 'version=1的脱敏信号摘要：规则版本、国家/地区、粗粒度设备类别、命中规则代码；禁止原始凭据、生物特征和完整设备指纹。 设计场景：保留足够解释风险决策的脱敏线索，同时避免收集原始生物特征、完整设备指纹和凭据。';
COMMENT ON COLUMN identity.risk_event."request_id" IS '关联业务请求ID，便于审计排查。 设计场景：将风险判定追溯到具体登录或敏感请求，排查误拦截时不必记录用户密码和完整设备信息。';
COMMENT ON COLUMN identity.risk_event."occurred_at" IS '风险决策发生时间。 设计场景：记录事实实际发生时间，异步入库和投递延迟时仍可正确追溯先后关系。';
CREATE INDEX ix_risk_event_account_time ON identity.risk_event USING btree (account_id, occurred_at DESC) WHERE (account_id IS NOT NULL);
CREATE INDEX ix_risk_event_attempt ON identity.risk_event USING btree (attempt_id) WHERE (attempt_id IS NOT NULL);
CREATE INDEX ix_risk_event_session ON identity.risk_event USING btree (session_id) WHERE (session_id IS NOT NULL);
CREATE INDEX ix_risk_event_tenant_time ON identity.risk_event USING btree (tenant_id, occurred_at DESC) WHERE (tenant_id IS NOT NULL);

-- identity.tenant_security_policy：企业访问安全策略；进入目标租户时与平台最低要求及应用策略叠加，不能降低管理员必需MFA，不改变中央会话的全局当前企业。
CREATE TABLE identity.tenant_security_policy (
    -- 策略所属企业，企业级唯一且由租户RLS隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 可接受的主要登录方式集合；值由服务端去重，用户实际方式仍须可用。 设计场景：同一用户可能有多种登录方式，进入企业或应用时检查实际认证证据属于允许集合。
    "allowed_primary_methods" character varying(16)[] DEFAULT '{PASSWORD,SMS,EXTERNAL,PASSKEY}'::character varying[] NOT NULL,
    -- 是否要求所有普通成员完成加强验证；管理员始终受平台最低MFA规则约束。 设计场景：企业或应用可以要求普通成员也加强验证，管理员必须 MFA 的规则仍独立成立。
    "require_member_mfa" boolean DEFAULT false NOT NULL,
    -- 本企业接受的附加验证方法集合，不能把短信自动当作TOTP。 设计场景：限制哪些加强验证方式能满足当前策略，不能把短信、恢复流程或任意扫码自动认定为合格 MFA。
    "allowed_mfa_methods" character varying(16)[] DEFAULT '{TOTP,PASSKEY}'::character varying[] NOT NULL,
    -- 是否要求抗钓鱼认证证据；为真时必须要求MFA并允许PASSKEY。 设计场景：高敏感应用要求具有抗钓鱼能力的认证证据，不能仅凭做过任何第二步验证就满足。
    "require_phishing_resistance" boolean DEFAULT false NOT NULL,
    -- 敏感动作允许的最近认证窗口秒数，调用时检查实际认证证据。 设计场景：改密、绑因子或访问敏感应用前要求重新认证，避免多年有效的会话直接执行高风险操作。
    "recent_auth_seconds" integer DEFAULT 300 NOT NULL,
    -- 访问本企业允许的最大空闲秒数，与应用要求取更严格值。 设计场景：不同企业或应用可以要求不同空闲期限，进入时按有效的更严格策略计算。
    "idle_timeout_seconds" integer DEFAULT 1800 NOT NULL,
    -- 访问本企业允许的最长认证年龄秒数，刷新不能重置认证起点。 设计场景：限定最长连续使用时长，防止活跃访问或刷新令牌让会话无限延期。
    "absolute_timeout_seconds" integer DEFAULT 28800 NOT NULL,
    -- 本企业允许的并发访问会话数；空表示不另设上限，计数范围由企业访问会话记录确定。 设计场景：控制同一身份允许同时使用的会话数，并发创建会话时需原子检查上限。
    "max_concurrent_sessions" integer,
    -- 超限拒绝新访问或撤销本企业最旧访问；不得顺带撤销其他独立企业资格。 设计场景：达到会话上限时明确是拒绝新登录还是淘汰旧会话，避免不同客户端表现不一致。
    "concurrency_action" character varying(24) DEFAULT 'REJECT_NEW'::character varying NOT NULL,
    -- 本企业可信设备最长秒数，0表示不接受设备信任；不能永久绕过认证。 设计场景：限定设备信任免重复验证的窗口，到期重新核验；可信设备不能绕过企业最新策略。
    "trusted_device_seconds" integer DEFAULT 0 NOT NULL,
    -- version=1及rules数组；规则元素为受控risk_signal、threshold、action(REAUTHENTICATE/REQUIRE_MFA/DENY)，服务端校验完整schema，不放用户授权关系或原始设备指纹。 设计场景：配置可解释的风险判定条件，在异常登录时要求额外验证或拒绝，不接受任意执行代码。
    "risk_rules" jsonb DEFAULT '{"rules": [], "version": 1}'::jsonb NOT NULL,
    -- 策略并发版本；变更后下一次目标访问按最新策略校验。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。
    "version" bigint DEFAULT 0 NOT NULL,
    -- 最近修改管理员账号，受控初始化可空并须审计。 设计场景：记录最后修改者，便于审计和问题定位；提交时仍须核实其当前账号及业务资格。
    "updated_by_account_id" bigint,
    -- 策略创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近修改时间，由应用维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "ck_tenant_security_methods" CHECK (cardinality(allowed_primary_methods) > 0 AND allowed_primary_methods <@ ARRAY['PASSWORD'::character varying(16), 'SMS'::character varying(16), 'EXTERNAL'::character varying(16), 'PASSKEY'::character varying(16)] AND array_position(allowed_primary_methods, NULL::character varying) IS NULL AND cardinality(allowed_mfa_methods) > 0 AND allowed_mfa_methods <@ ARRAY['TOTP'::character varying(16), 'PASSKEY'::character varying(16)] AND array_position(allowed_mfa_methods, NULL::character varying) IS NULL),
    CONSTRAINT "ck_tenant_security_phishing" CHECK (NOT require_phishing_resistance OR ('PASSKEY'::text = ANY (allowed_mfa_methods::text[])) AND require_member_mfa),
    CONSTRAINT "ck_tenant_security_risk" CHECK (jsonb_typeof(risk_rules) = 'object'::text AND risk_rules @> '{"version": 1}'::jsonb AND risk_rules ? 'rules'::text AND jsonb_typeof(risk_rules -> 'rules'::text) = 'array'::text),
    CONSTRAINT "ck_tenant_security_timeouts" CHECK (idle_timeout_seconds <= absolute_timeout_seconds),
    CONSTRAINT "ck_tenant_security_updated" CHECK (updated_at >= created_at),
    CONSTRAINT "tenant_security_policy_absolute_timeout_seconds_check" CHECK (absolute_timeout_seconds > 0),
    CONSTRAINT "tenant_security_policy_concurrency_action_check" CHECK (concurrency_action::text = ANY (ARRAY['REJECT_NEW'::character varying, 'REVOKE_OLDEST'::character varying]::text[])),
    CONSTRAINT "tenant_security_policy_idle_timeout_seconds_check" CHECK (idle_timeout_seconds > 0),
    CONSTRAINT "tenant_security_policy_max_concurrent_sessions_check" CHECK (max_concurrent_sessions > 0),
    CONSTRAINT "tenant_security_policy_pkey" PRIMARY KEY (tenant_id),
    CONSTRAINT "tenant_security_policy_recent_auth_seconds_check" CHECK (recent_auth_seconds > 0),
    CONSTRAINT "tenant_security_policy_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "tenant_security_policy_trusted_device_seconds_check" CHECK (trusted_device_seconds >= 0),
    CONSTRAINT "tenant_security_policy_updated_by_account_id_fkey" FOREIGN KEY (updated_by_account_id) REFERENCES directory.account(id),
    CONSTRAINT "tenant_security_policy_version_check" CHECK (version >= 0)
);
COMMENT ON TABLE identity.tenant_security_policy IS '企业访问安全策略；进入目标租户时与平台最低要求及应用策略叠加，不能降低管理员必需MFA，不改变中央会话的全局当前企业。';
COMMENT ON COLUMN identity.tenant_security_policy."tenant_id" IS '策略所属企业，企业级唯一且由租户RLS隔离。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN identity.tenant_security_policy."allowed_primary_methods" IS '可接受的主要登录方式集合；值由服务端去重，用户实际方式仍须可用。 设计场景：同一用户可能有多种登录方式，进入企业或应用时检查实际认证证据属于允许集合。';
COMMENT ON COLUMN identity.tenant_security_policy."require_member_mfa" IS '是否要求所有普通成员完成加强验证；管理员始终受平台最低MFA规则约束。 设计场景：企业或应用可以要求普通成员也加强验证，管理员必须 MFA 的规则仍独立成立。';
COMMENT ON COLUMN identity.tenant_security_policy."allowed_mfa_methods" IS '本企业接受的附加验证方法集合，不能把短信自动当作TOTP。 设计场景：限制哪些加强验证方式能满足当前策略，不能把短信、恢复流程或任意扫码自动认定为合格 MFA。';
COMMENT ON COLUMN identity.tenant_security_policy."require_phishing_resistance" IS '是否要求抗钓鱼认证证据；为真时必须要求MFA并允许PASSKEY。 设计场景：高敏感应用要求具有抗钓鱼能力的认证证据，不能仅凭做过任何第二步验证就满足。';
COMMENT ON COLUMN identity.tenant_security_policy."recent_auth_seconds" IS '敏感动作允许的最近认证窗口秒数，调用时检查实际认证证据。 设计场景：改密、绑因子或访问敏感应用前要求重新认证，避免多年有效的会话直接执行高风险操作。';
COMMENT ON COLUMN identity.tenant_security_policy."idle_timeout_seconds" IS '访问本企业允许的最大空闲秒数，与应用要求取更严格值。 设计场景：不同企业或应用可以要求不同空闲期限，进入时按有效的更严格策略计算。';
COMMENT ON COLUMN identity.tenant_security_policy."absolute_timeout_seconds" IS '访问本企业允许的最长认证年龄秒数，刷新不能重置认证起点。 设计场景：限定最长连续使用时长，防止活跃访问或刷新令牌让会话无限延期。';
COMMENT ON COLUMN identity.tenant_security_policy."max_concurrent_sessions" IS '本企业允许的并发访问会话数；空表示不另设上限，计数范围由企业访问会话记录确定。 设计场景：控制同一身份允许同时使用的会话数，并发创建会话时需原子检查上限。';
COMMENT ON COLUMN identity.tenant_security_policy."concurrency_action" IS '超限拒绝新访问或撤销本企业最旧访问；不得顺带撤销其他独立企业资格。 设计场景：达到会话上限时明确是拒绝新登录还是淘汰旧会话，避免不同客户端表现不一致。';
COMMENT ON COLUMN identity.tenant_security_policy."trusted_device_seconds" IS '本企业可信设备最长秒数，0表示不接受设备信任；不能永久绕过认证。 设计场景：限定设备信任免重复验证的窗口，到期重新核验；可信设备不能绕过企业最新策略。';
COMMENT ON COLUMN identity.tenant_security_policy."risk_rules" IS 'version=1及rules数组；规则元素为受控risk_signal、threshold、action(REAUTHENTICATE/REQUIRE_MFA/DENY)，服务端校验完整schema，不放用户授权关系或原始设备指纹。 设计场景：配置可解释的风险判定条件，在异常登录时要求额外验证或拒绝，不接受任意执行代码。';
COMMENT ON COLUMN identity.tenant_security_policy."version" IS '策略并发版本；变更后下一次目标访问按最新策略校验。 设计场景：两个管理员同时修改时，通过 WHERE version=旧值 的条件更新识别冲突，避免后提交覆盖先提交。';
COMMENT ON COLUMN identity.tenant_security_policy."updated_by_account_id" IS '最近修改管理员账号，受控初始化可空并须审计。 设计场景：记录最后修改者，便于审计和问题定位；提交时仍须核实其当前账号及业务资格。';
COMMENT ON COLUMN identity.tenant_security_policy."created_at" IS '策略创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN identity.tenant_security_policy."updated_at" IS '最近修改时间，由应用维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_tenant_security_policy_updater ON identity.tenant_security_policy USING btree (updated_by_account_id) WHERE (updated_by_account_id IS NOT NULL);

-- identity.trusted_device：本人登记的可撤销设备信任凭证；全局账号安全对象，不向企业管理员开放个人设备令牌；访问每家企业仍检查策略。
CREATE TABLE identity.trusted_device (
    -- 应用生成的正数雪花设备信任ID，不是设备持有的秘密。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 设备信任所属账号，只有本人安全入口及受控安全流程可管理。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。
    "account_id" bigint NOT NULL,
    -- 可选的信任限制范围；非空只在该企业使用，空也不代表所有企业必须接受。 设计场景：记录设备信任的适用企业范围，空值语义依照全局信任规则；企业管理员不能凭 tenant_id 读取个人设备令牌。
    "tenant_id" bigint,
    -- 高熵设备信任令牌的SHA-256验证值，明文只交客户端安全保存。 设计场景：设备再次出现时验证它持有的高熵信任令牌，库内不保存可直接重放的原令牌。
    "trust_token_verifier" bytea NOT NULL,
    -- 用户可识别的设备名称，不作为真实硬件身份或认证证据。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。
    "display_name" character varying(120) NOT NULL,
    -- 登记时账号撤销版本，换密或冻结后必须失效。 设计场景：设备信任建立时绑定账号版本，发生全局安全撤销后不能继续拿旧设备信任跳过验证。
    "auth_epoch" bigint NOT NULL,
    -- 完成近期加强验证后发起登记的本账号中央会话；登记用例校验实际证据。 设计场景：建立设备信任前必须有本人近期加强认证，不能让普通未验证请求注册可信设备。
    "verified_session_id" bigint NOT NULL,
    -- 本人确认建立信任的时间。 设计场景：让本人知道设备何时被认可，并据此计算最长信任窗口，后续访问不能无限延长原授权。
    "trusted_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 信任凭证自身期限，目标策略可以要求更短期限。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone NOT NULL,
    -- 最近通过该凭证检查的时间，不延长原始信任期限。 设计场景：区分持续使用与长期不活跃记录，为会话空闲判断或设备管理提供依据；不能刷新绝对有效期。
    "last_seen_at" timestamp with time zone,
    -- 主动撤销、丢失或安全处置时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 脱敏撤销原因代码，不存原始请求。 设计场景：向用户和运维解释会话为何退出，例如改密、本人退出或管理员撤销，并为审计提供分类。
    "revoke_reason" character varying(64),
    CONSTRAINT "ck_trusted_device_revoke" CHECK (revoked_at IS NULL AND revoke_reason IS NULL OR revoked_at IS NOT NULL AND revoke_reason IS NOT NULL AND btrim(revoke_reason::text) <> ''::text),
    CONSTRAINT "ck_trusted_device_times" CHECK (expires_at > trusted_at AND (last_seen_at IS NULL OR last_seen_at >= trusted_at) AND (revoked_at IS NULL OR revoked_at >= trusted_at)),
    CONSTRAINT "fk_trusted_device_session" FOREIGN KEY (account_id, verified_session_id) REFERENCES identity.auth_session(account_id, id),
    CONSTRAINT "trusted_device_account_id_fkey" FOREIGN KEY (account_id) REFERENCES directory.account(id),
    CONSTRAINT "trusted_device_auth_epoch_check" CHECK (auth_epoch >= 0),
    CONSTRAINT "trusted_device_display_name_check" CHECK (btrim(display_name::text) <> ''::text),
    CONSTRAINT "trusted_device_id_check" CHECK (id > 0),
    CONSTRAINT "trusted_device_pkey" PRIMARY KEY (id),
    CONSTRAINT "trusted_device_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "trusted_device_trust_token_verifier_check" CHECK (octet_length(trust_token_verifier) = 32),
    CONSTRAINT "trusted_device_trust_token_verifier_key" UNIQUE (trust_token_verifier),
    CONSTRAINT "uq_trusted_device_account_id" UNIQUE (account_id, id)
);
COMMENT ON TABLE identity.trusted_device IS '本人登记的可撤销设备信任凭证；全局账号安全对象，不向企业管理员开放个人设备令牌；访问每家企业仍检查策略。';
COMMENT ON COLUMN identity.trusted_device."id" IS '应用生成的正数雪花设备信任ID，不是设备持有的秘密。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN identity.trusted_device."account_id" IS '设备信任所属账号，只有本人安全入口及受控安全流程可管理。 设计场景：跨企业识别同一个平台账号；企业成员、显示名和登录方式变化时，继续引用稳定账号身份。';
COMMENT ON COLUMN identity.trusted_device."tenant_id" IS '可选的信任限制范围；非空只在该企业使用，空也不代表所有企业必须接受。 设计场景：记录设备信任的适用企业范围，空值语义依照全局信任规则；企业管理员不能凭 tenant_id 读取个人设备令牌。';
COMMENT ON COLUMN identity.trusted_device."trust_token_verifier" IS '高熵设备信任令牌的SHA-256验证值，明文只交客户端安全保存。 设计场景：设备再次出现时验证它持有的高熵信任令牌，库内不保存可直接重放的原令牌。';
COMMENT ON COLUMN identity.trusted_device."display_name" IS '用户可识别的设备名称，不作为真实硬件身份或认证证据。 设计场景：为用户提供易读名称，可能与其他记录重名；不得通过显示名自动关联账号或授予权限。';
COMMENT ON COLUMN identity.trusted_device."auth_epoch" IS '登记时账号撤销版本，换密或冻结后必须失效。 设计场景：设备信任建立时绑定账号版本，发生全局安全撤销后不能继续拿旧设备信任跳过验证。';
COMMENT ON COLUMN identity.trusted_device."verified_session_id" IS '完成近期加强验证后发起登记的本账号中央会话；登记用例校验实际证据。 设计场景：建立设备信任前必须有本人近期加强认证，不能让普通未验证请求注册可信设备。';
COMMENT ON COLUMN identity.trusted_device."trusted_at" IS '本人确认建立信任的时间。 设计场景：让本人知道设备何时被认可，并据此计算最长信任窗口，后续访问不能无限延长原授权。';
COMMENT ON COLUMN identity.trusted_device."expires_at" IS '信任凭证自身期限，目标策略可以要求更短期限。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN identity.trusted_device."last_seen_at" IS '最近通过该凭证检查的时间，不延长原始信任期限。 设计场景：区分持续使用与长期不活跃记录，为会话空闲判断或设备管理提供依据；不能刷新绝对有效期。';
COMMENT ON COLUMN identity.trusted_device."revoked_at" IS '主动撤销、丢失或安全处置时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN identity.trusted_device."revoke_reason" IS '脱敏撤销原因代码，不存原始请求。 设计场景：向用户和运维解释会话为何退出，例如改密、本人退出或管理员撤销，并为审计提供分类。';
CREATE INDEX ix_trusted_device_account ON identity.trusted_device USING btree (account_id, trusted_at DESC);
CREATE INDEX ix_trusted_device_expiry ON identity.trusted_device USING btree (expires_at) WHERE (revoked_at IS NULL);
CREATE INDEX ix_trusted_device_session ON identity.trusted_device USING btree (verified_session_id);
CREATE INDEX ix_trusted_device_tenant ON identity.trusted_device USING btree (tenant_id) WHERE (tenant_id IS NOT NULL);

-- machine.credential：机器凭据的版本化验证材料；原始秘密只在生成时展示，不保存在普通字段中
CREATE TABLE machine.credential (
    CONSTRAINT ck_machine_credential_nonempty CHECK ((issuer IS NULL OR btrim(issuer)<>'') AND (subject IS NULL OR btrim(subject)<>'') AND (audience IS NULL OR btrim(audience)<>'')),
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 机器主体。 设计场景：将机器凭据、授权和委托关联到稳定机器主体，轮换凭据不改变其身份与审计归属。
    "principal_id" bigint NOT NULL,
    -- 公开凭据标识，不是秘密。 设计场景：调用方用公开标识选择要验证的凭据，避免把秘密本体当查询键或写入普通日志。
    "credential_key" character varying(200) NOT NULL,
    -- 凭据版本。 设计场景：记录机器凭据的轮换版本，供调用方和运维区分新旧验证材料，轮换链另由 rotated_from_id 表示。
    "version" integer NOT NULL,
    -- 秘密散列、公钥或外部工作负载联合身份。 设计场景：区分共享秘密、公钥及外部工作负载身份，校验该类型必需字段并选择对应验证器，不接受不同类型材料混用。
    "kind" character varying(24) NOT NULL,
    -- 不可逆编码的高熵秘密验证值。 设计场景：机器持秘密认证时只保存验证材料，数据库读取者不能直接取回原始秘密进行调用。
    "secret_hash" text,
    -- 公钥材料，不允许私钥。 设计场景：使用非对称认证时平台只保存验签所需公钥，机器私钥留在调用方受控环境。
    "public_key" text,
    -- 工作负载身份的可信签发方。 设计场景：验证外部签发者与登记配置一致，防止其他认证中心签发的合法凭证被误用于本连接。
    "issuer" text,
    -- 工作负载准确主体标识。 设计场景：将验证后的外部身份限定在连接命名空间，跨连接同名或同邮箱不能自动合并为同一个人。
    "subject" character varying(512),
    -- 工作负载预期受众。 设计场景：将凭证限定给预期接收方使用，防止为应用 A 签发的结果被应用 B 接受。
    "audience" character varying(512),
    -- 最早有效时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。
    "valid_from" timestamp with time zone NOT NULL,
    -- 强制到期时间。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。
    "valid_until" timestamp with time zone NOT NULL,
    -- 撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。
    "revoked_at" timestamp with time zone,
    -- 被轮换的同机器凭据。 设计场景：追踪同一机器凭据的轮换链，区别新增凭据与替换旧凭据；旧凭据是否失效仍按状态和有效期判断。
    "rotated_from_id" bigint,
    -- 最近成功使用时间。 设计场景：帮助用户识别仍在使用的凭据、设备或票据，支持轮换和清理；不是独立的有效性证明。
    "last_used_at" timestamp with time zone,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "credential_check" CHECK (updated_at >= created_at),
    CONSTRAINT "credential_check1" CHECK (kind::text = 'SECRET_HASH'::text AND secret_hash IS NOT NULL AND num_nonnulls(secret_hash, public_key, issuer, subject, audience) = 1 OR kind::text = 'PUBLIC_KEY'::text AND public_key IS NOT NULL AND num_nonnulls(secret_hash, public_key, issuer, subject, audience) = 1 OR kind::text = 'WORKLOAD_IDENTITY'::text AND secret_hash IS NULL AND public_key IS NULL AND issuer IS NOT NULL AND subject IS NOT NULL AND audience IS NOT NULL),
    CONSTRAINT "credential_check2" CHECK (valid_until > valid_from),
    CONSTRAINT "credential_check3" CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT "credential_check4" CHECK (rotated_from_id IS NULL OR rotated_from_id <> id),
    CONSTRAINT "credential_credential_key_check" CHECK (btrim(credential_key::text) <> ''::text),
    CONSTRAINT "credential_credential_key_version_key" UNIQUE (credential_key, version),
    CONSTRAINT "credential_id_check" CHECK (id > 0),
    CONSTRAINT "credential_kind_check" CHECK (kind::text = ANY (ARRAY['SECRET_HASH'::character varying, 'PUBLIC_KEY'::character varying, 'WORKLOAD_IDENTITY'::character varying]::text[])),
    CONSTRAINT "credential_pkey" PRIMARY KEY (id),
    CONSTRAINT "credential_public_key_check" CHECK (public_key IS NULL OR public_key !~~ '%PRIVATE KEY%'::text),
    CONSTRAINT "credential_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "credential_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "credential_tenant_id_principal_id_fkey" FOREIGN KEY (tenant_id, principal_id) REFERENCES machine.principal(tenant_id, id),
    CONSTRAINT "credential_tenant_id_principal_id_id_key" UNIQUE (tenant_id, principal_id, id),
    CONSTRAINT "credential_tenant_id_principal_id_rotated_from_id_fkey" FOREIGN KEY (tenant_id, principal_id, rotated_from_id) REFERENCES machine.credential(tenant_id, principal_id, id),
    CONSTRAINT "credential_version_check" CHECK (version > 0)
);
COMMENT ON TABLE machine.credential IS '机器凭据的版本化验证材料；原始秘密只在生成时展示，不保存在普通字段中';
COMMENT ON COLUMN machine.credential."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN machine.credential."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN machine.credential."principal_id" IS '机器主体。 设计场景：将机器凭据、授权和委托关联到稳定机器主体，轮换凭据不改变其身份与审计归属。';
COMMENT ON COLUMN machine.credential."credential_key" IS '公开凭据标识，不是秘密。 设计场景：调用方用公开标识选择要验证的凭据，避免把秘密本体当查询键或写入普通日志。';
COMMENT ON COLUMN machine.credential."version" IS '凭据版本。 设计场景：记录机器凭据的轮换版本，供调用方和运维区分新旧验证材料，轮换链另由 rotated_from_id 表示。';
COMMENT ON COLUMN machine.credential."kind" IS '秘密散列、公钥或外部工作负载联合身份。 设计场景：区分共享秘密、公钥及外部工作负载身份，校验该类型必需字段并选择对应验证器，不接受不同类型材料混用。';
COMMENT ON COLUMN machine.credential."secret_hash" IS '不可逆编码的高熵秘密验证值。 设计场景：机器持秘密认证时只保存验证材料，数据库读取者不能直接取回原始秘密进行调用。';
COMMENT ON COLUMN machine.credential."public_key" IS '公钥材料，不允许私钥。 设计场景：使用非对称认证时平台只保存验签所需公钥，机器私钥留在调用方受控环境。';
COMMENT ON COLUMN machine.credential."issuer" IS '工作负载身份的可信签发方。 设计场景：验证外部签发者与登记配置一致，防止其他认证中心签发的合法凭证被误用于本连接。';
COMMENT ON COLUMN machine.credential."subject" IS '工作负载准确主体标识。 设计场景：将验证后的外部身份限定在连接命名空间，跨连接同名或同邮箱不能自动合并为同一个人。';
COMMENT ON COLUMN machine.credential."audience" IS '工作负载预期受众。 设计场景：将凭证限定给预期接收方使用，防止为应用 A 签发的结果被应用 B 接受。';
COMMENT ON COLUMN machine.credential."valid_from" IS '最早有效时间。 设计场景：支持预约生效，例如下周开始的临时授权；到时间之前不能提前获得权限。';
COMMENT ON COLUMN machine.credential."valid_until" IS '强制到期时间。 设计场景：支持临时授权、凭据或策略到期；是否允许长期有效以可空性和本表约束为准。';
COMMENT ON COLUMN machine.credential."revoked_at" IS '撤销时间。 设计场景：保留曾经存在但已失效的事实；撤销后立即阻止继续使用，历史引用和审计仍可追溯。';
COMMENT ON COLUMN machine.credential."rotated_from_id" IS '被轮换的同机器凭据。 设计场景：追踪同一机器凭据的轮换链，区别新增凭据与替换旧凭据；旧凭据是否失效仍按状态和有效期判断。';
COMMENT ON COLUMN machine.credential."last_used_at" IS '最近成功使用时间。 设计场景：帮助用户识别仍在使用的凭据、设备或票据，支持轮换和清理；不是独立的有效性证明。';
COMMENT ON COLUMN machine.credential."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN machine.credential."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_machine_credential_expiry ON machine.credential USING btree (tenant_id, valid_until) WHERE (revoked_at IS NULL);
CREATE INDEX ix_machine_credential_rotation ON machine.credential USING btree (tenant_id, principal_id, rotated_from_id);

-- machine.delegation_scope：用户委托的明确资源范围；始终与用户及机器当前权限求交集
CREATE TABLE machine.delegation_scope (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 用户委托。 设计场景：限定一次用户给机器的任务委托范围，使用时再与机器自身和用户当前权限求交集。
    "delegation_id" bigint NOT NULL,
    -- 明确店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。
    "store_id" bigint,
    -- 明确其他资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。
    "resource_id" bigint,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "delegation_scope_check" CHECK (updated_at >= created_at),
    CONSTRAINT "delegation_scope_check1" CHECK (num_nonnulls(store_id, resource_id) = 1),
    CONSTRAINT "delegation_scope_id_check" CHECK (id > 0),
    CONSTRAINT "delegation_scope_pkey" PRIMARY KEY (id),
    CONSTRAINT "delegation_scope_tenant_id_delegation_id_fkey" FOREIGN KEY (tenant_id, delegation_id) REFERENCES machine.user_delegation(tenant_id, id),
    CONSTRAINT "delegation_scope_tenant_id_delegation_id_store_id_resource__key" UNIQUE NULLS NOT DISTINCT (tenant_id, delegation_id, store_id, resource_id),
    CONSTRAINT "delegation_scope_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "delegation_scope_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "delegation_scope_tenant_id_resource_id_fkey" FOREIGN KEY (tenant_id, resource_id) REFERENCES access.resource(tenant_id, id),
    CONSTRAINT "delegation_scope_tenant_id_store_id_fkey" FOREIGN KEY (tenant_id, store_id) REFERENCES demo.store(tenant_id, id)
);
COMMENT ON TABLE machine.delegation_scope IS '用户委托的明确资源范围；始终与用户及机器当前权限求交集';
COMMENT ON COLUMN machine.delegation_scope."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN machine.delegation_scope."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN machine.delegation_scope."delegation_id" IS '用户委托。 设计场景：限定一次用户给机器的任务委托范围，使用时再与机器自身和用户当前权限求交集。';
COMMENT ON COLUMN machine.delegation_scope."store_id" IS '明确店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。';
COMMENT ON COLUMN machine.delegation_scope."resource_id" IS '明确其他资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。';
COMMENT ON COLUMN machine.delegation_scope."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN machine.delegation_scope."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_machine_delegation_scope_resource ON machine.delegation_scope USING btree (tenant_id, resource_id);
CREATE INDEX ix_machine_delegation_scope_store ON machine.delegation_scope USING btree (tenant_id, store_id);

-- machine.grant_scope：机器明确资源范围；空集合不表示全部
CREATE TABLE machine.grant_scope (
    -- 应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。
    "id" bigint NOT NULL,
    -- 所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。
    "tenant_id" bigint NOT NULL,
    -- 机器授权。 设计场景：资源范围和复核决定归属某一条具体授权，不能将不同授权的动作与范围任意组合。
    "grant_id" bigint NOT NULL,
    -- 明确店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。
    "store_id" bigint,
    -- 明确其他资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。
    "resource_id" bigint,
    -- 创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- 最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "grant_scope_check" CHECK (updated_at >= created_at),
    CONSTRAINT "grant_scope_check1" CHECK (num_nonnulls(store_id, resource_id) = 1),
    CONSTRAINT "grant_scope_id_check" CHECK (id > 0),
    CONSTRAINT "grant_scope_pkey" PRIMARY KEY (id),
    CONSTRAINT "grant_scope_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES directory.tenant(id),
    CONSTRAINT "grant_scope_tenant_id_grant_id_fkey" FOREIGN KEY (tenant_id, grant_id) REFERENCES machine."grant"(tenant_id, id),
    CONSTRAINT "grant_scope_tenant_id_grant_id_store_id_resource_id_key" UNIQUE NULLS NOT DISTINCT (tenant_id, grant_id, store_id, resource_id),
    CONSTRAINT "grant_scope_tenant_id_id_key" UNIQUE (tenant_id, id),
    CONSTRAINT "grant_scope_tenant_id_resource_id_fkey" FOREIGN KEY (tenant_id, resource_id) REFERENCES access.resource(tenant_id, id),
    CONSTRAINT "grant_scope_tenant_id_store_id_fkey" FOREIGN KEY (tenant_id, store_id) REFERENCES demo.store(tenant_id, id)
);
COMMENT ON TABLE machine.grant_scope IS '机器明确资源范围；空集合不表示全部';
COMMENT ON COLUMN machine.grant_scope."id" IS '应用生成的正数雪花主键。 设计场景：为记录提供稳定引用；名称、状态或来源变化后仍用同一 ID 关联历史，避免重命名造成关联丢失。';
COMMENT ON COLUMN machine.grant_scope."tenant_id" IS '所属企业；所有业务访问必须先验证此企业资格。 设计场景：同一账号可能加入多个企业，读写必须限定目标企业；仅有对象 ID 不足以证明拥有该企业的数据访问权。';
COMMENT ON COLUMN machine.grant_scope."grant_id" IS '机器授权。 设计场景：资源范围和复核决定归属某一条具体授权，不能将不同授权的动作与范围任意组合。';
COMMENT ON COLUMN machine.grant_scope."store_id" IS '明确店铺。 设计场景：将权限限定到明确店铺，避免读取动作与其他授权的店铺范围拼接成越权访问。';
COMMENT ON COLUMN machine.grant_scope."resource_id" IS '明确其他资源。 设计场景：引用受控资源目录中的真实对象，授权校验同时检查企业、资源类型和状态。';
COMMENT ON COLUMN machine.grant_scope."created_at" IS '创建时间。 设计场景：用于追溯记录何时建立、按时间检索及制定保留范围；不能用它替代实际业务发生或完成时间。';
COMMENT ON COLUMN machine.grant_scope."updated_at" IS '最近更新时间，由受控写入维护。 设计场景：帮助定位最近一次资料或状态修改；由写入用例维护，不把时间戳当作并发控制版本。';
CREATE INDEX ix_machine_grant_scope_resource ON machine.grant_scope USING btree (tenant_id, resource_id);
CREATE INDEX ix_machine_grant_scope_store ON machine.grant_scope USING btree (tenant_id, store_id);

-- platform_meta.id_node_state：雪花节点持久化时间保留上界；恢复数据库后须执行发号隔离和恢复流程
CREATE TABLE platform_meta.id_node_state (
    -- 雪花发号节点号，0～1023，运行时独占。 设计场景：多实例生成雪花 ID 时独占不同节点号，防止同一毫秒内不同进程产生相同 ID。
    "node_id" smallint NOT NULL,
    -- 已持久化的发号时间保留上界，Unix 毫秒；重启及恢复必须越过旧区间。 设计场景：进程重启、时钟回退或恢复数据库后越过旧发号区间，避免再次发出已经使用过的 ID。
    "reserved_until_ms" bigint NOT NULL,
    CONSTRAINT "id_node_state_node_id_check" CHECK (node_id >= 0 AND node_id <= 1023),
    CONSTRAINT "id_node_state_pkey" PRIMARY KEY (node_id),
    CONSTRAINT "id_node_state_reserved_until_ms_check" CHECK (reserved_until_ms >= 0)
);
COMMENT ON TABLE platform_meta.id_node_state IS '雪花节点持久化时间保留上界；恢复数据库后须执行发号隔离和恢复流程';
COMMENT ON COLUMN platform_meta.id_node_state."node_id" IS '雪花发号节点号，0～1023，运行时独占。 设计场景：多实例生成雪花 ID 时独占不同节点号，防止同一毫秒内不同进程产生相同 ID。';
COMMENT ON COLUMN platform_meta.id_node_state."reserved_until_ms" IS '已持久化的发号时间保留上界，Unix 毫秒；重启及恢复必须越过旧区间。 设计场景：进程重启、时钟回退或恢复数据库后越过旧发号区间，避免再次发出已经使用过的 ID。';

-- protocol.oauth2_authorization：Spring OAuth 授权与令牌存储；敏感字段仅由协议适配器访问。
CREATE TABLE protocol.oauth2_authorization (
    -- 框架持久化记录主键，保留框架字符串格式。 设计场景：框架内部授权记录标识用于恢复和撤销同一授权，不能当作可在浏览器或 API 中使用的访问令牌。
    "id" character varying(100) NOT NULL,
    -- 框架注册客户端主键。 设计场景：关联框架内部客户端记录，与外部 client_id 区分，便于一个业务应用配置多个终端和环境。
    "registered_client_id" character varying(100) NOT NULL,
    -- 框架使用的认证主体名称，不保存企业当前上下文。 设计场景：协议框架关联稳定认证主体，不能把可变的当前企业或显示名塞进主体名称影响授权归属。
    "principal_name" character varying(200) NOT NULL,
    -- 本次 OAuth 授权类型。 设计场景：区分这一条授权来自授权码、客户端凭据等流程，验证和撤销按实际流程处理。
    "authorization_grant_type" character varying(100) NOT NULL,
    -- 本次已授权的接口/身份字段范围。 设计场景：保存本次实际获准的协议范围，不能把客户端允许申请的全部范围默认视为已经授权。
    "authorized_scopes" character varying(1000) DEFAULT NULL::character varying,
    -- 框架受保护的授权上下文序列化内容。 设计场景：框架恢复授权上下文时使用受保护序列化数据，只接受框架适配器写入的可信内容。
    "attributes" text,
    -- 框架保存的协议关联状态；由协议层验证。 设计场景：将授权回调关联到原始请求，拒绝未发起或被替换的登录回调，不能仅因拿到 code 就接受。
    "state" character varying(500) DEFAULT NULL::character varying,
    -- 授权码框架管理的敏感凭据值，禁止日志输出及普通接口读取。 设计场景：用于浏览器带回授权码后，在令牌端点交换令牌，并检查单次使用、客户端与回调关联；敏感值只供协议存储适配器访问，不复制到普通接口或日志。
    "authorization_code_value" text,
    -- 授权码签发时间。 设计场景：记录该协议凭据何时签发，配合失效时间验证其生命周期；用途是浏览器带回授权码后，在令牌端点交换令牌，并检查单次使用、客户端与回调关联。
    "authorization_code_issued_at" timestamp with time zone,
    -- 授权码过期时间。 设计场景：凭据使用时拒绝超过截止的请求，而非等清理任务删除；用途是浏览器带回授权码后，在令牌端点交换令牌，并检查单次使用、客户端与回调关联。
    "authorization_code_expires_at" timestamp with time zone,
    -- 授权码框架序列化的凭据元数据。 设计场景：由所锁定框架保存并恢复该凭据的状态和协议上下文，支持浏览器带回授权码后，在令牌端点交换令牌，并检查单次使用、客户端与回调关联；业务代码不自行改写序列化结构。
    "authorization_code_metadata" text,
    -- 访问令牌框架管理的敏感凭据值，禁止日志输出及普通接口读取。 设计场景：用于调用受保护 API 时证明本次访问许可，并检查有效期、撤销和资源权限；敏感值只供协议存储适配器访问，不复制到普通接口或日志。
    "access_token_value" text,
    -- 访问令牌签发时间。 设计场景：记录该协议凭据何时签发，配合失效时间验证其生命周期；用途是调用受保护 API 时证明本次访问许可，并检查有效期、撤销和资源权限。
    "access_token_issued_at" timestamp with time zone,
    -- 访问令牌过期时间。 设计场景：凭据使用时拒绝超过截止的请求，而非等清理任务删除；用途是调用受保护 API 时证明本次访问许可，并检查有效期、撤销和资源权限。
    "access_token_expires_at" timestamp with time zone,
    -- 访问令牌框架序列化的凭据元数据。 设计场景：由所锁定框架保存并恢复该凭据的状态和协议上下文，支持调用受保护 API 时证明本次访问许可，并检查有效期、撤销和资源权限；业务代码不自行改写序列化结构。
    "access_token_metadata" text,
    -- 访问令牌类型。 设计场景：让协议框架按令牌类型解释使用方式，不把任意字符串或 ID Token 当作访问凭据。
    "access_token_type" character varying(100) DEFAULT NULL::character varying,
    -- 访问令牌包含的协议范围。 设计场景：API 访问限制在本次令牌获准的范围内，同时仍检查账号、成员和业务资源权限。
    "access_token_scopes" character varying(1000) DEFAULT NULL::character varying,
    -- 身份令牌框架管理的敏感凭据值，禁止日志输出及普通接口读取。 设计场景：用于客户端验证登录身份结果；不能替代 Access Token 调用业务 API；敏感值只供协议存储适配器访问，不复制到普通接口或日志。
    "oidc_id_token_value" text,
    -- 身份令牌签发时间。 设计场景：记录该协议凭据何时签发，配合失效时间验证其生命周期；用途是客户端验证登录身份结果；不能替代 Access Token 调用业务 API。
    "oidc_id_token_issued_at" timestamp with time zone,
    -- 身份令牌过期时间。 设计场景：凭据使用时拒绝超过截止的请求，而非等清理任务删除；用途是客户端验证登录身份结果；不能替代 Access Token 调用业务 API。
    "oidc_id_token_expires_at" timestamp with time zone,
    -- 身份令牌框架序列化的凭据元数据。 设计场景：由所锁定框架保存并恢复该凭据的状态和协议上下文，支持客户端验证登录身份结果；不能替代 Access Token 调用业务 API；业务代码不自行改写序列化结构。
    "oidc_id_token_metadata" text,
    -- 刷新令牌框架管理的敏感凭据值，禁止日志输出及普通接口读取。 设计场景：用于在允许刷新令牌的客户端中续领访问令牌，仍检查原授权与撤销状态；敏感值只供协议存储适配器访问，不复制到普通接口或日志。
    "refresh_token_value" text,
    -- 刷新令牌签发时间。 设计场景：记录该协议凭据何时签发，配合失效时间验证其生命周期；用途是在允许刷新令牌的客户端中续领访问令牌，仍检查原授权与撤销状态。
    "refresh_token_issued_at" timestamp with time zone,
    -- 刷新令牌过期时间。 设计场景：凭据使用时拒绝超过截止的请求，而非等清理任务删除；用途是在允许刷新令牌的客户端中续领访问令牌，仍检查原授权与撤销状态。
    "refresh_token_expires_at" timestamp with time zone,
    -- 刷新令牌框架序列化的凭据元数据。 设计场景：由所锁定框架保存并恢复该凭据的状态和协议上下文，支持在允许刷新令牌的客户端中续领访问令牌，仍检查原授权与撤销状态；业务代码不自行改写序列化结构。
    "refresh_token_metadata" text,
    -- 用户码框架管理的敏感凭据值，禁止日志输出及普通接口读取。 设计场景：用于在框架支持且明确启用的设备授权流程中，让用户在另一设备关联待确认请求；敏感值只供协议存储适配器访问，不复制到普通接口或日志。
    "user_code_value" text,
    -- 用户码签发时间。 设计场景：记录该协议凭据何时签发，配合失效时间验证其生命周期；用途是在框架支持且明确启用的设备授权流程中，让用户在另一设备关联待确认请求。
    "user_code_issued_at" timestamp with time zone,
    -- 用户码过期时间。 设计场景：凭据使用时拒绝超过截止的请求，而非等清理任务删除；用途是在框架支持且明确启用的设备授权流程中，让用户在另一设备关联待确认请求。
    "user_code_expires_at" timestamp with time zone,
    -- 用户码框架序列化的凭据元数据。 设计场景：由所锁定框架保存并恢复该凭据的状态和协议上下文，支持在框架支持且明确启用的设备授权流程中，让用户在另一设备关联待确认请求；业务代码不自行改写序列化结构。
    "user_code_metadata" text,
    -- 设备码框架管理的敏感凭据值，禁止日志输出及普通接口读取。 设计场景：用于在框架支持且明确启用的设备授权流程中，让设备查询所关联授权结果；敏感值只供协议存储适配器访问，不复制到普通接口或日志。
    "device_code_value" text,
    -- 设备码签发时间。 设计场景：记录该协议凭据何时签发，配合失效时间验证其生命周期；用途是在框架支持且明确启用的设备授权流程中，让设备查询所关联授权结果。
    "device_code_issued_at" timestamp with time zone,
    -- 设备码过期时间。 设计场景：凭据使用时拒绝超过截止的请求，而非等清理任务删除；用途是在框架支持且明确启用的设备授权流程中，让设备查询所关联授权结果。
    "device_code_expires_at" timestamp with time zone,
    -- 设备码框架序列化的凭据元数据。 设计场景：由所锁定框架保存并恢复该凭据的状态和协议上下文，支持在框架支持且明确启用的设备授权流程中，让设备查询所关联授权结果；业务代码不自行改写序列化结构。
    "device_code_metadata" text,
    CONSTRAINT "oauth2_authorization_pkey" PRIMARY KEY (id)
);
COMMENT ON TABLE protocol.oauth2_authorization IS 'Spring OAuth 授权与令牌存储；敏感字段仅由协议适配器访问。';
COMMENT ON COLUMN protocol.oauth2_authorization."id" IS '框架持久化记录主键，保留框架字符串格式。 设计场景：框架内部授权记录标识用于恢复和撤销同一授权，不能当作可在浏览器或 API 中使用的访问令牌。';
COMMENT ON COLUMN protocol.oauth2_authorization."registered_client_id" IS '框架注册客户端主键。 设计场景：关联框架内部客户端记录，与外部 client_id 区分，便于一个业务应用配置多个终端和环境。';
COMMENT ON COLUMN protocol.oauth2_authorization."principal_name" IS '框架使用的认证主体名称，不保存企业当前上下文。 设计场景：协议框架关联稳定认证主体，不能把可变的当前企业或显示名塞进主体名称影响授权归属。';
COMMENT ON COLUMN protocol.oauth2_authorization."authorization_grant_type" IS '本次 OAuth 授权类型。 设计场景：区分这一条授权来自授权码、客户端凭据等流程，验证和撤销按实际流程处理。';
COMMENT ON COLUMN protocol.oauth2_authorization."authorized_scopes" IS '本次已授权的接口/身份字段范围。 设计场景：保存本次实际获准的协议范围，不能把客户端允许申请的全部范围默认视为已经授权。';
COMMENT ON COLUMN protocol.oauth2_authorization."attributes" IS '框架受保护的授权上下文序列化内容。 设计场景：框架恢复授权上下文时使用受保护序列化数据，只接受框架适配器写入的可信内容。';
COMMENT ON COLUMN protocol.oauth2_authorization."state" IS '框架保存的协议关联状态；由协议层验证。 设计场景：将授权回调关联到原始请求，拒绝未发起或被替换的登录回调，不能仅因拿到 code 就接受。';
COMMENT ON COLUMN protocol.oauth2_authorization."authorization_code_value" IS '授权码框架管理的敏感凭据值，禁止日志输出及普通接口读取。 设计场景：用于浏览器带回授权码后，在令牌端点交换令牌，并检查单次使用、客户端与回调关联；敏感值只供协议存储适配器访问，不复制到普通接口或日志。';
COMMENT ON COLUMN protocol.oauth2_authorization."authorization_code_issued_at" IS '授权码签发时间。 设计场景：记录该协议凭据何时签发，配合失效时间验证其生命周期；用途是浏览器带回授权码后，在令牌端点交换令牌，并检查单次使用、客户端与回调关联。';
COMMENT ON COLUMN protocol.oauth2_authorization."authorization_code_expires_at" IS '授权码过期时间。 设计场景：凭据使用时拒绝超过截止的请求，而非等清理任务删除；用途是浏览器带回授权码后，在令牌端点交换令牌，并检查单次使用、客户端与回调关联。';
COMMENT ON COLUMN protocol.oauth2_authorization."authorization_code_metadata" IS '授权码框架序列化的凭据元数据。 设计场景：由所锁定框架保存并恢复该凭据的状态和协议上下文，支持浏览器带回授权码后，在令牌端点交换令牌，并检查单次使用、客户端与回调关联；业务代码不自行改写序列化结构。';
COMMENT ON COLUMN protocol.oauth2_authorization."access_token_value" IS '访问令牌框架管理的敏感凭据值，禁止日志输出及普通接口读取。 设计场景：用于调用受保护 API 时证明本次访问许可，并检查有效期、撤销和资源权限；敏感值只供协议存储适配器访问，不复制到普通接口或日志。';
COMMENT ON COLUMN protocol.oauth2_authorization."access_token_issued_at" IS '访问令牌签发时间。 设计场景：记录该协议凭据何时签发，配合失效时间验证其生命周期；用途是调用受保护 API 时证明本次访问许可，并检查有效期、撤销和资源权限。';
COMMENT ON COLUMN protocol.oauth2_authorization."access_token_expires_at" IS '访问令牌过期时间。 设计场景：凭据使用时拒绝超过截止的请求，而非等清理任务删除；用途是调用受保护 API 时证明本次访问许可，并检查有效期、撤销和资源权限。';
COMMENT ON COLUMN protocol.oauth2_authorization."access_token_metadata" IS '访问令牌框架序列化的凭据元数据。 设计场景：由所锁定框架保存并恢复该凭据的状态和协议上下文，支持调用受保护 API 时证明本次访问许可，并检查有效期、撤销和资源权限；业务代码不自行改写序列化结构。';
COMMENT ON COLUMN protocol.oauth2_authorization."access_token_type" IS '访问令牌类型。 设计场景：让协议框架按令牌类型解释使用方式，不把任意字符串或 ID Token 当作访问凭据。';
COMMENT ON COLUMN protocol.oauth2_authorization."access_token_scopes" IS '访问令牌包含的协议范围。 设计场景：API 访问限制在本次令牌获准的范围内，同时仍检查账号、成员和业务资源权限。';
COMMENT ON COLUMN protocol.oauth2_authorization."oidc_id_token_value" IS '身份令牌框架管理的敏感凭据值，禁止日志输出及普通接口读取。 设计场景：用于客户端验证登录身份结果；不能替代 Access Token 调用业务 API；敏感值只供协议存储适配器访问，不复制到普通接口或日志。';
COMMENT ON COLUMN protocol.oauth2_authorization."oidc_id_token_issued_at" IS '身份令牌签发时间。 设计场景：记录该协议凭据何时签发，配合失效时间验证其生命周期；用途是客户端验证登录身份结果；不能替代 Access Token 调用业务 API。';
COMMENT ON COLUMN protocol.oauth2_authorization."oidc_id_token_expires_at" IS '身份令牌过期时间。 设计场景：凭据使用时拒绝超过截止的请求，而非等清理任务删除；用途是客户端验证登录身份结果；不能替代 Access Token 调用业务 API。';
COMMENT ON COLUMN protocol.oauth2_authorization."oidc_id_token_metadata" IS '身份令牌框架序列化的凭据元数据。 设计场景：由所锁定框架保存并恢复该凭据的状态和协议上下文，支持客户端验证登录身份结果；不能替代 Access Token 调用业务 API；业务代码不自行改写序列化结构。';
COMMENT ON COLUMN protocol.oauth2_authorization."refresh_token_value" IS '刷新令牌框架管理的敏感凭据值，禁止日志输出及普通接口读取。 设计场景：用于在允许刷新令牌的客户端中续领访问令牌，仍检查原授权与撤销状态；敏感值只供协议存储适配器访问，不复制到普通接口或日志。';
COMMENT ON COLUMN protocol.oauth2_authorization."refresh_token_issued_at" IS '刷新令牌签发时间。 设计场景：记录该协议凭据何时签发，配合失效时间验证其生命周期；用途是在允许刷新令牌的客户端中续领访问令牌，仍检查原授权与撤销状态。';
COMMENT ON COLUMN protocol.oauth2_authorization."refresh_token_expires_at" IS '刷新令牌过期时间。 设计场景：凭据使用时拒绝超过截止的请求，而非等清理任务删除；用途是在允许刷新令牌的客户端中续领访问令牌，仍检查原授权与撤销状态。';
COMMENT ON COLUMN protocol.oauth2_authorization."refresh_token_metadata" IS '刷新令牌框架序列化的凭据元数据。 设计场景：由所锁定框架保存并恢复该凭据的状态和协议上下文，支持在允许刷新令牌的客户端中续领访问令牌，仍检查原授权与撤销状态；业务代码不自行改写序列化结构。';
COMMENT ON COLUMN protocol.oauth2_authorization."user_code_value" IS '用户码框架管理的敏感凭据值，禁止日志输出及普通接口读取。 设计场景：用于在框架支持且明确启用的设备授权流程中，让用户在另一设备关联待确认请求；敏感值只供协议存储适配器访问，不复制到普通接口或日志。';
COMMENT ON COLUMN protocol.oauth2_authorization."user_code_issued_at" IS '用户码签发时间。 设计场景：记录该协议凭据何时签发，配合失效时间验证其生命周期；用途是在框架支持且明确启用的设备授权流程中，让用户在另一设备关联待确认请求。';
COMMENT ON COLUMN protocol.oauth2_authorization."user_code_expires_at" IS '用户码过期时间。 设计场景：凭据使用时拒绝超过截止的请求，而非等清理任务删除；用途是在框架支持且明确启用的设备授权流程中，让用户在另一设备关联待确认请求。';
COMMENT ON COLUMN protocol.oauth2_authorization."user_code_metadata" IS '用户码框架序列化的凭据元数据。 设计场景：由所锁定框架保存并恢复该凭据的状态和协议上下文，支持在框架支持且明确启用的设备授权流程中，让用户在另一设备关联待确认请求；业务代码不自行改写序列化结构。';
COMMENT ON COLUMN protocol.oauth2_authorization."device_code_value" IS '设备码框架管理的敏感凭据值，禁止日志输出及普通接口读取。 设计场景：用于在框架支持且明确启用的设备授权流程中，让设备查询所关联授权结果；敏感值只供协议存储适配器访问，不复制到普通接口或日志。';
COMMENT ON COLUMN protocol.oauth2_authorization."device_code_issued_at" IS '设备码签发时间。 设计场景：记录该协议凭据何时签发，配合失效时间验证其生命周期；用途是在框架支持且明确启用的设备授权流程中，让设备查询所关联授权结果。';
COMMENT ON COLUMN protocol.oauth2_authorization."device_code_expires_at" IS '设备码过期时间。 设计场景：凭据使用时拒绝超过截止的请求，而非等清理任务删除；用途是在框架支持且明确启用的设备授权流程中，让设备查询所关联授权结果。';
COMMENT ON COLUMN protocol.oauth2_authorization."device_code_metadata" IS '设备码框架序列化的凭据元数据。 设计场景：由所锁定框架保存并恢复该凭据的状态和协议上下文，支持在框架支持且明确启用的设备授权流程中，让设备查询所关联授权结果；业务代码不自行改写序列化结构。';
CREATE INDEX ix_oauth_access_token ON protocol.oauth2_authorization USING btree (access_token_value) WHERE (access_token_value IS NOT NULL);
CREATE INDEX ix_oauth_authorization_principal ON protocol.oauth2_authorization USING btree (principal_name);
CREATE INDEX ix_oauth_refresh_token ON protocol.oauth2_authorization USING btree (refresh_token_value) WHERE (refresh_token_value IS NOT NULL);

-- protocol.oauth2_authorization_consent：用户对具体协议客户端的同意记录；不代替企业开通和成员分配。
CREATE TABLE protocol.oauth2_authorization_consent (
    -- 框架注册客户端主键。 设计场景：关联框架内部客户端记录，与外部 client_id 区分，便于一个业务应用配置多个终端和环境。
    "registered_client_id" character varying(100) NOT NULL,
    -- 框架使用的认证主体名称，不保存企业当前上下文。 设计场景：协议框架关联稳定认证主体，不能把可变的当前企业或显示名塞进主体名称影响授权归属。
    "principal_name" character varying(200) NOT NULL,
    -- 用户对该客户端同意的权限项，不代表企业应用分配。 设计场景：保存用户对特定客户端同意释放的范围，不能替代管理员开通应用和成员分配。
    "authorities" character varying(1000) NOT NULL,
    CONSTRAINT "oauth2_authorization_consent_pkey" PRIMARY KEY (registered_client_id, principal_name)
);
COMMENT ON TABLE protocol.oauth2_authorization_consent IS '用户对具体协议客户端的同意记录；不代替企业开通和成员分配。';
COMMENT ON COLUMN protocol.oauth2_authorization_consent."registered_client_id" IS '框架注册客户端主键。 设计场景：关联框架内部客户端记录，与外部 client_id 区分，便于一个业务应用配置多个终端和环境。';
COMMENT ON COLUMN protocol.oauth2_authorization_consent."principal_name" IS '框架使用的认证主体名称，不保存企业当前上下文。 设计场景：协议框架关联稳定认证主体，不能把可变的当前企业或显示名塞进主体名称影响授权归属。';
COMMENT ON COLUMN protocol.oauth2_authorization_consent."authorities" IS '用户对该客户端同意的权限项，不代表企业应用分配。 设计场景：保存用户对特定客户端同意释放的范围，不能替代管理员开通应用和成员分配。';

-- protocol.spring_session：Spring Session JDBC 会话主体。
CREATE TABLE protocol.spring_session (
    -- Spring Session 内部主键。 设计场景：框架内部关联会话属性的稳定主键，与客户端持有的会话标识区分，保持框架存储契约。
    "primary_id" character(36) NOT NULL,
    -- 会话标识；本表语义由所属框架决定。 设计场景：将记录关联到它所属的会话，校验时不能跨会话借用认证证据或服务端凭据；具体会话类型由所在表决定。
    "session_id" character(36) NOT NULL,
    -- 框架会话创建时间，Unix 毫秒。 设计场景：框架按 Unix 毫秒记录会话创建时间，与业务时间字段的单位区分，避免秒与毫秒混用。
    "creation_time" bigint NOT NULL,
    -- 最近访问时间，Unix 毫秒。 设计场景：框架据最近访问时间计算空闲失效，不能将它解释为最近一次输入密码或 MFA 的时间。
    "last_access_time" bigint NOT NULL,
    -- 最长空闲时长，单位秒。 设计场景：以秒设置框架会话空闲上限，和毫秒时间戳一起按框架规则计算，避免单位错误导致过早或过晚退出。
    "max_inactive_interval" integer NOT NULL,
    -- 框架会话过期时刻，Unix 毫秒。 设计场景：框架查询和清理已过期会话时使用的 Unix 毫秒截止，业务中央会话仍有独立撤销检查。
    "expiry_time" bigint NOT NULL,
    -- 框架使用的认证主体名称，不保存企业当前上下文。 设计场景：协议框架关联稳定认证主体，不能把可变的当前企业或显示名塞进主体名称影响授权归属。
    "principal_name" character varying(100),
    CONSTRAINT "spring_session_pk" PRIMARY KEY (primary_id)
);
COMMENT ON TABLE protocol.spring_session IS 'Spring Session JDBC 会话主体。';
COMMENT ON COLUMN protocol.spring_session."primary_id" IS 'Spring Session 内部主键。 设计场景：框架内部关联会话属性的稳定主键，与客户端持有的会话标识区分，保持框架存储契约。';
COMMENT ON COLUMN protocol.spring_session."session_id" IS '会话标识；本表语义由所属框架决定。 设计场景：将记录关联到它所属的会话，校验时不能跨会话借用认证证据或服务端凭据；具体会话类型由所在表决定。';
COMMENT ON COLUMN protocol.spring_session."creation_time" IS '框架会话创建时间，Unix 毫秒。 设计场景：框架按 Unix 毫秒记录会话创建时间，与业务时间字段的单位区分，避免秒与毫秒混用。';
COMMENT ON COLUMN protocol.spring_session."last_access_time" IS '最近访问时间，Unix 毫秒。 设计场景：框架据最近访问时间计算空闲失效，不能将它解释为最近一次输入密码或 MFA 的时间。';
COMMENT ON COLUMN protocol.spring_session."max_inactive_interval" IS '最长空闲时长，单位秒。 设计场景：以秒设置框架会话空闲上限，和毫秒时间戳一起按框架规则计算，避免单位错误导致过早或过晚退出。';
COMMENT ON COLUMN protocol.spring_session."expiry_time" IS '框架会话过期时刻，Unix 毫秒。 设计场景：框架查询和清理已过期会话时使用的 Unix 毫秒截止，业务中央会话仍有独立撤销检查。';
COMMENT ON COLUMN protocol.spring_session."principal_name" IS '框架使用的认证主体名称，不保存企业当前上下文。 设计场景：协议框架关联稳定认证主体，不能把可变的当前企业或显示名塞进主体名称影响授权归属。';
CREATE UNIQUE INDEX spring_session_ix1 ON protocol.spring_session USING btree (session_id);
CREATE INDEX spring_session_ix2 ON protocol.spring_session USING btree (expiry_time);
CREATE INDEX spring_session_ix3 ON protocol.spring_session USING btree (principal_name);

-- protocol.spring_session_attributes：Spring Session JDBC 会话属性。
CREATE TABLE protocol.spring_session_attributes (
    -- 对应 Spring Session 内部主键。 设计场景：把序列化属性关联到确切的框架会话，不能用另一个会话 ID 读取属性。
    "session_primary_id" character(36) NOT NULL,
    -- 框架会话属性名。 设计场景：在同一框架会话内定位具体属性，属性名称来自受控框架约定而非任意业务授权声明。
    "attribute_name" character varying(200) NOT NULL,
    -- 框架序列化属性值，受保护存储；不得允许不可信反序列化输入。 设计场景：框架持久化会话状态供恢复使用，限制读写权限与反序列化来源，不接收外部任意序列化对象。
    "attribute_bytes" bytea NOT NULL,
    CONSTRAINT "spring_session_attributes_fk" FOREIGN KEY (session_primary_id) REFERENCES protocol.spring_session(primary_id) ON DELETE CASCADE,
    CONSTRAINT "spring_session_attributes_pk" PRIMARY KEY (session_primary_id, attribute_name)
);
COMMENT ON TABLE protocol.spring_session_attributes IS 'Spring Session JDBC 会话属性。';
COMMENT ON COLUMN protocol.spring_session_attributes."session_primary_id" IS '对应 Spring Session 内部主键。 设计场景：把序列化属性关联到确切的框架会话，不能用另一个会话 ID 读取属性。';
COMMENT ON COLUMN protocol.spring_session_attributes."attribute_name" IS '框架会话属性名。 设计场景：在同一框架会话内定位具体属性，属性名称来自受控框架约定而非任意业务授权声明。';
COMMENT ON COLUMN protocol.spring_session_attributes."attribute_bytes" IS '框架序列化属性值，受保护存储；不得允许不可信反序列化输入。 设计场景：框架持久化会话状态供恢复使用，限制读写权限与反序列化来源，不接收外部任意序列化对象。';

-- protocol.web_authorized_client：Web BFF 服务端加密凭据与刷新租约。
CREATE TABLE protocol.web_authorized_client (
    -- 会话标识；本表语义由所属框架决定。 设计场景：将记录关联到它所属的会话，校验时不能跨会话借用认证证据或服务端凭据；具体会话类型由所在表决定。
    "session_id" character varying(128) NOT NULL,
    -- 协议客户端公开标识，不是平台账号 ID。 设计场景：同一个浏览器会话可能使用不同协议客户端，按会话和客户端组合查找凭据，避免跨应用使用令牌。
    "client_id" character varying(100) NOT NULL,
    -- 服务端加密的访问/刷新凭据，浏览器不保存明文。 设计场景：BFF 代浏览器保存访问和刷新令牌，浏览器仅持会话 Cookie，凭据在后端受控解密使用。
    "credentials_ciphertext" bytea NOT NULL,
    -- 当前访问凭据截止时间。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。
    "expires_at" timestamp with time zone NOT NULL,
    -- 刷新租约持有者，防止多个进程并发刷新同一凭据。 设计场景：多个标签页或实例同时触发刷新时只有当前租约持有者执行，防止刷新令牌轮换互相覆盖。
    "refresh_owner" character varying(64),
    -- 刷新租约到期时间。 设计场景：刷新进程宕机后允许接管，但旧进程迟到写入仍须检查租约归属，避免覆盖新凭据。
    "refresh_until" timestamp with time zone,
    CONSTRAINT "ck_web_refresh_lease_pair" CHECK ((refresh_owner IS NULL) = (refresh_until IS NULL)),
    CONSTRAINT "web_authorized_client_pkey" PRIMARY KEY (session_id, client_id)
);
COMMENT ON TABLE protocol.web_authorized_client IS 'Web BFF 服务端加密凭据与刷新租约。';
COMMENT ON COLUMN protocol.web_authorized_client."session_id" IS '会话标识；本表语义由所属框架决定。 设计场景：将记录关联到它所属的会话，校验时不能跨会话借用认证证据或服务端凭据；具体会话类型由所在表决定。';
COMMENT ON COLUMN protocol.web_authorized_client."client_id" IS '协议客户端公开标识，不是平台账号 ID。 设计场景：同一个浏览器会话可能使用不同协议客户端，按会话和客户端组合查找凭据，避免跨应用使用令牌。';
COMMENT ON COLUMN protocol.web_authorized_client."credentials_ciphertext" IS '服务端加密的访问/刷新凭据，浏览器不保存明文。 设计场景：BFF 代浏览器保存访问和刷新令牌，浏览器仅持会话 Cookie，凭据在后端受控解密使用。';
COMMENT ON COLUMN protocol.web_authorized_client."expires_at" IS '当前访问凭据截止时间。 设计场景：在每次使用时拒绝已到期记录，避免依赖定时清理是否及时执行；延期或重发遵循对应业务流程。';
COMMENT ON COLUMN protocol.web_authorized_client."refresh_owner" IS '刷新租约持有者，防止多个进程并发刷新同一凭据。 设计场景：多个标签页或实例同时触发刷新时只有当前租约持有者执行，防止刷新令牌轮换互相覆盖。';
COMMENT ON COLUMN protocol.web_authorized_client."refresh_until" IS '刷新租约到期时间。 设计场景：刷新进程宕机后允许接管，但旧进程迟到写入仍须检查租约归属，避免覆盖新凭据。';

-- 循环依赖的外键（全部目标表已在上方完整定义）。
ALTER TABLE identity.external_connection_version ADD CONSTRAINT "external_connection_version_connection_id_fkey" FOREIGN KEY (connection_id) REFERENCES identity.external_connection(id);
ALTER TABLE directory.source_member ADD CONSTRAINT "source_member_tenant_id_member_id_fkey" FOREIGN KEY (tenant_id, member_id) REFERENCES directory.membership(tenant_id, id);
ALTER TABLE access.member_grant ADD CONSTRAINT "fk_member_grant_delegation" FOREIGN KEY (tenant_id, source_delegation_id) REFERENCES access.management_delegation(tenant_id, id);
ALTER TABLE directory.source_department ADD CONSTRAINT "source_department_tenant_id_department_id_fkey" FOREIGN KEY (tenant_id, department_id) REFERENCES directory.department(tenant_id, id);

CREATE FUNCTION access.check_role_inheritance_cycle() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- 企业行锁使同企业并发关系变更串行；连接必须已设置可信租户上下文。
    PERFORM 1 FROM directory.tenant WHERE id=NEW.tenant_id FOR UPDATE;
    IF EXISTS (WITH RECURSIVE ancestors(id) AS (
        SELECT NEW.parent_role_id
        UNION
        SELECT r.parent_role_id FROM access.role_inheritance r JOIN ancestors a ON r.child_role_id=a.id
        WHERE r.tenant_id=NEW.tenant_id
    ) SELECT 1 FROM ancestors WHERE id=NEW.child_role_id) THEN
        RAISE EXCEPTION 'role inheritance cycle' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER role_inheritance_no_cycle BEFORE INSERT OR UPDATE ON access.role_inheritance FOR EACH ROW EXECUTE FUNCTION access.check_role_inheritance_cycle();
CREATE FUNCTION audit.fill_event_actor_type() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $body$
BEGIN
    IF NEW.actor_type IS NULL THEN
        NEW.actor_type := CASE WHEN NEW.actor_machine_id IS NOT NULL THEN 'MACHINE'
                              WHEN NEW.actor_account_id IS NOT NULL THEN 'ACCOUNT' ELSE 'SYSTEM' END;
    END IF;
    RETURN NEW;
END
$body$;
CREATE FUNCTION audit.check_execution_scope() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $body$
DECLARE expected_tenant bigint;
BEGIN
    SELECT tenant_id INTO expected_tenant FROM audit.data_operation WHERE id = NEW.operation_id;
    IF NOT FOUND OR NEW.tenant_id IS DISTINCT FROM expected_tenant THEN
        RAISE EXCEPTION 'data operation execution scope mismatch' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$body$;
CREATE TRIGGER fill_event_actor_type BEFORE INSERT ON audit.event
    FOR EACH ROW EXECUTE FUNCTION audit.fill_event_actor_type();
CREATE TRIGGER check_execution_scope BEFORE INSERT OR UPDATE ON audit.data_operation_execution
    FOR EACH ROW EXECUTE FUNCTION audit.check_execution_scope();
ALTER TABLE access.approval_decision ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.approval_decision FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.approval_decision FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.authorization_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.authorization_request FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.authorization_request FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.delegation_scope ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.delegation_scope FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.delegation_scope FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.grant_resource ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.grant_resource FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.grant_resource FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.grant_store ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.grant_store FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.grant_store FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.invitation_grant ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.invitation_grant FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.invitation_grant FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.invitation_grant_resource ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.invitation_grant_resource FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.invitation_grant_resource FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.invitation_grant_store ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.invitation_grant_store FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.invitation_grant_store FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.management_delegation ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.management_delegation FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.management_delegation FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.member_grant ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.member_grant FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.member_grant FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.policy FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.policy FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.policy_permission ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.policy_permission FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.policy_permission FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.policy_resource ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.policy_resource FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.policy_resource FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.policy_subject ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.policy_subject FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.policy_subject FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.request_scope ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.request_scope FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.request_scope FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.resource ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.resource FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.resource FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.resource_relation ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.resource_relation FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.resource_relation FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.review_campaign ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.review_campaign FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.review_campaign FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.review_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.review_item FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.review_item FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.role ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.role FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.role FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.role_conflict ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.role_conflict FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.role_conflict FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.role_inheritance ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.role_inheritance FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.role_inheritance FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE access.role_permission ENABLE ROW LEVEL SECURITY;
ALTER TABLE access.role_permission FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON access.role_permission FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.access_session ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.access_session FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.access_session FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.aliyun_mapping ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.aliyun_mapping FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.aliyun_mapping FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.app_group ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.app_group FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.app_group FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.assignment ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.assignment FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.assignment FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.attribute_mapping ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.attribute_mapping FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.attribute_mapping FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.connection ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.connection FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.connection FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.connection_key ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.connection_key FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.connection_key FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.favorite ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.favorite FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.favorite FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.identity_group ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.identity_group FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.identity_group FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.launch_ticket ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.launch_ticket FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.launch_ticket FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.preapproval ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.preapproval FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.preapproval FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.provisioned_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.provisioned_object FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.provisioned_object FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.provisioning_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.provisioning_run FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.provisioning_run FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.provisioning_task ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.provisioning_task FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.provisioning_task FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.role_mapping ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.role_mapping FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.role_mapping FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.security_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.security_policy FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.security_policy FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.tenant_application ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.tenant_application FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.tenant_application FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE application.user_identity ENABLE ROW LEVEL SECURITY;
ALTER TABLE application.user_identity FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON application.user_identity FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE audit.data_operation ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.data_operation FORCE ROW LEVEL SECURITY;
CREATE POLICY "personal_data_operation" ON audit.data_operation FOR ALL USING (((tenant_id IS NULL) AND ((operation)::text = 'PERSONAL_EXPORT'::text) AND (requested_by_account_id = (NULLIF(current_setting('app.account_id'::text, true), ''::text))::bigint))) WITH CHECK (((tenant_id IS NULL) AND ((operation)::text = 'PERSONAL_EXPORT'::text) AND (requested_by_account_id = (NULLIF(current_setting('app.account_id'::text, true), ''::text))::bigint)));
CREATE POLICY "tenant_isolation" ON audit.data_operation FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE audit.data_operation_execution ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.data_operation_execution FORCE ROW LEVEL SECURITY;
CREATE POLICY "personal_data_execution" ON audit.data_operation_execution FOR ALL USING (((tenant_id IS NULL) AND (EXISTS ( SELECT 1
   FROM audit.data_operation o
  WHERE ((o.id = data_operation_execution.operation_id) AND (o.tenant_id IS NULL) AND (o.requested_by_account_id = (NULLIF(current_setting('app.account_id'::text, true), ''::text))::bigint)))))) WITH CHECK (((tenant_id IS NULL) AND (EXISTS ( SELECT 1
   FROM audit.data_operation o
  WHERE ((o.id = data_operation_execution.operation_id) AND (o.tenant_id IS NULL) AND (o.requested_by_account_id = (NULLIF(current_setting('app.account_id'::text, true), ''::text))::bigint))))));
CREATE POLICY "tenant_isolation" ON audit.data_operation_execution FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE audit.event ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.event FORCE ROW LEVEL SECURITY;
CREATE POLICY "audit_insert" ON audit.event FOR INSERT WITH CHECK (true);
CREATE POLICY "audit_own_read" ON audit.event FOR SELECT USING (((tenant_id IS NULL) AND (actor_account_id = (NULLIF(current_setting('app.account_id'::text, true), ''::text))::bigint)));
CREATE POLICY "audit_tenant_read" ON audit.event FOR SELECT USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE audit.retention_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.retention_policy FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON audit.retention_policy FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE delivery.domain_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery.domain_event FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON delivery.domain_event FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE delivery.event_delivery ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery.event_delivery FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON delivery.event_delivery FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE delivery.event_delivery_attempt ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery.event_delivery_attempt FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON delivery.event_delivery_attempt FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE delivery.event_subscription ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery.event_subscription FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON delivery.event_subscription FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE delivery.notification ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery.notification FORCE ROW LEVEL SECURITY;
CREATE POLICY "notification_own_insert" ON delivery.notification FOR INSERT WITH CHECK (((tenant_id IS NULL) AND (recipient_account_id = (NULLIF(current_setting('app.account_id'::text, true), ''::text))::bigint)));
CREATE POLICY "notification_own_read" ON delivery.notification FOR SELECT USING (((tenant_id IS NULL) AND (recipient_account_id = (NULLIF(current_setting('app.account_id'::text, true), ''::text))::bigint)));
CREATE POLICY "notification_own_update" ON delivery.notification FOR UPDATE USING (((tenant_id IS NULL) AND (recipient_account_id = (NULLIF(current_setting('app.account_id'::text, true), ''::text))::bigint))) WITH CHECK (((tenant_id IS NULL) AND (recipient_account_id = (NULLIF(current_setting('app.account_id'::text, true), ''::text))::bigint)));
CREATE POLICY "tenant_isolation" ON delivery.notification FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE delivery.subscription_event_type ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery.subscription_event_type FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON delivery.subscription_event_type FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE demo.store ENABLE ROW LEVEL SECURITY;
ALTER TABLE demo.store FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON demo.store FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE demo.store_note ENABLE ROW LEVEL SECURITY;
ALTER TABLE demo.store_note FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON demo.store_note FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.department ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.department FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.department FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.invitation ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.invitation FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.invitation FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.invitation_proof ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.invitation_proof FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.invitation_proof FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.member_activation ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.member_activation FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.member_activation FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.member_department ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.member_department FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.member_department FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.member_department_source ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.member_department_source FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.member_department_source FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.member_external_login ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.member_external_login FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.member_external_login FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.member_field_source ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.member_field_source FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.member_field_source FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.member_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.member_profile FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.member_profile FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.membership FORCE ROW LEVEL SECURITY;
CREATE POLICY "own_membership_select" ON directory.membership FOR SELECT USING ((account_id = (NULLIF(current_setting('app.account_id'::text, true), ''::text))::bigint));
CREATE POLICY "tenant_isolation" ON directory.membership FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.profile_field_definition ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.profile_field_definition FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.profile_field_definition FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.source_department ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.source_department FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.source_department FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.source_member ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.source_member FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.source_member FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.sync_change ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.sync_change FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.sync_change FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.sync_connection ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.sync_connection FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.sync_connection FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.sync_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.sync_event FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.sync_event FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.sync_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.sync_run FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.sync_run FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.team ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.team FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.team FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.team_member ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.team_member FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.team_member FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.tenant_domain ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.tenant_domain FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.tenant_domain FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.tenant_lifecycle_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.tenant_lifecycle_request FORCE ROW LEVEL SECURITY;
CREATE POLICY "lifecycle_requester" ON directory.tenant_lifecycle_request FOR SELECT USING ((requester_account_id = (NULLIF(current_setting('app.account_id'::text, true), ''::text))::bigint));
CREATE POLICY "lifecycle_self_create" ON directory.tenant_lifecycle_request FOR INSERT WITH CHECK (((requester_account_id = (NULLIF(current_setting('app.account_id'::text, true), ''::text))::bigint) AND ((kind)::text = 'CREATE'::text) AND (tenant_id IS NULL) AND ((status)::text = 'REQUESTED'::text) AND (reviewer_account_id IS NULL) AND (reviewed_at IS NULL) AND (completed_at IS NULL)));
CREATE POLICY "lifecycle_tenant" ON directory.tenant_lifecycle_request FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.tenant_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.tenant_settings FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.tenant_settings FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE directory.work_assignment ENABLE ROW LEVEL SECURITY;
ALTER TABLE directory.work_assignment FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON directory.work_assignment FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE identity.tenant_security_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.tenant_security_policy FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON identity.tenant_security_policy FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE machine.credential ENABLE ROW LEVEL SECURITY;
ALTER TABLE machine.credential FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON machine.credential FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE machine.delegation_scope ENABLE ROW LEVEL SECURITY;
ALTER TABLE machine.delegation_scope FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON machine.delegation_scope FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE machine.grant ENABLE ROW LEVEL SECURITY;
ALTER TABLE machine.grant FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON machine.grant FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE machine.grant_scope ENABLE ROW LEVEL SECURITY;
ALTER TABLE machine.grant_scope FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON machine.grant_scope FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE machine.principal ENABLE ROW LEVEL SECURITY;
ALTER TABLE machine.principal FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON machine.principal FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));
ALTER TABLE machine.user_delegation ENABLE ROW LEVEL SECURITY;
ALTER TABLE machine.user_delegation FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON machine.user_delegation FOR ALL USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::bigint));

INSERT INTO access.resource_type(code,name,adapter_key) VALUES ('TENANT','企业','directory.tenant'),('STORE','店铺','demo.store');

INSERT INTO access.permission (code, name, resource_type) VALUES
    ('store.read', '读取店铺', 'STORE'),
    ('store.note.update', '编辑店铺备注', 'STORE'),
    ('tenant.member.manage', '管理企业成员及邀请', 'TENANT'),
    ('tenant.organization.manage', '管理企业部门及团队', 'TENANT'),
    ('tenant.role.manage', '管理企业角色及授权', 'TENANT'),
    ('tenant.audit.read', '查看企业审计', 'TENANT');

GRANT USAGE ON SCHEMA directory,identity,access,application,machine,audit,delivery,protocol,platform_meta,demo TO platform_runtime;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA directory,identity,access,application,machine,delivery,protocol,demo TO platform_runtime;
GRANT SELECT,INSERT,UPDATE ON platform_meta.id_node_state TO platform_runtime;
GRANT SELECT,INSERT,UPDATE,DELETE ON audit.retention_policy,audit.data_operation TO platform_runtime;
GRANT SELECT,INSERT ON audit.event,audit.data_operation_execution,delivery.event_delivery_attempt TO platform_runtime;
REVOKE UPDATE,DELETE ON delivery.event_delivery_attempt,identity.username_reservation,identity.authentication_evidence,access.approval_decision FROM platform_runtime;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA directory,identity,access,application,machine,audit,delivery FROM PUBLIC;
