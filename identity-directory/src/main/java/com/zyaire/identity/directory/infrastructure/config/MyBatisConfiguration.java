package com.zyaire.identity.directory.infrastructure.config;

import org.mybatis.spring.annotation.MapperScan;
import org.apache.ibatis.annotations.Mapper;
import org.springframework.context.annotation.Configuration;

@Configuration(proxyBeanMethods = false)
@MapperScan(basePackages = "com.zyaire.identity.directory.infrastructure.persistence",
            annotationClass = Mapper.class)
public class MyBatisConfiguration {}
