package com.zyaire.identity.directory.infrastructure.persistence.tenant;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

@Mapper
public interface TenantMapper {
    long nextLearningId();
    int insert(@Param("row") TenantRow row);
    TenantRow findById(@Param("id") long id);
}
