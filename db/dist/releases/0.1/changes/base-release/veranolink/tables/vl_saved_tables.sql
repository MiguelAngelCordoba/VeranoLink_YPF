-- liquibase formatted sql
-- changeset VERANOLINK:1785188156047 stripComments:false  logicalFilePath:base-release\veranolink\tables\vl_saved_tables.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/vl_saved_tables.sql:null:a33bc3ea9eab1891670fecbcac3e3b69bfdd1465:create

create table veranolink.vl_saved_tables (
    vl_id_saved_table number generated always as identity minvalue 1 maxvalue 1000000000000000000000000000 increment by 1 cache 20 noorder
    nocycle nokeep noscale not null enable,
    short_company     varchar2(100 byte),
    table_name        varchar2(2000 byte),
    table_query       clob,
    created_date      timestamp(6) default current_timestamp,
    name_api          varchar2(1000 byte),
    id_user           number,
    request_env       number,
    json_request      varchar2(4000 byte),
    is_sync           char(20 byte),
    api_id            number,
    application       number,
    view_name         varchar2(1000 byte),
    query_create      clob,
    job_name          varchar2(1000 byte)
);

alter table veranolink.vl_saved_tables
    add constraint pk_vl_saved_tables primary key ( vl_id_saved_table )
        using index enable;

