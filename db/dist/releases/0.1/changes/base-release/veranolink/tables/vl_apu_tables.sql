-- liquibase formatted sql
-- changeset VERANOLINK:1785188155902 stripComments:false  logicalFilePath:base-release\veranolink\tables\vl_apu_tables.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/vl_apu_tables.sql:null:e1ae47e8c65061afb080cb15d5f296f548ca318b:create

create table veranolink.vl_apu_tables (
    id_vl_apu_table       number generated always as identity minvalue 1 maxvalue 9999999999999999999999999999 increment by 1 cache 20
    noorder nocycle nokeep noscale not null enable,
    company_name          varchar2(1000 char),
    api_table_name        varchar2(1000 char),
    api_table_description varchar2(3000 char),
    api_table_query       clob,
    api_endpoint          varchar2(3000 char),
    created_date          timestamp(6) default current_timestamp,
    id_user               number
);

alter table veranolink.vl_apu_tables add primary key ( id_vl_apu_table )
    using index enable;

