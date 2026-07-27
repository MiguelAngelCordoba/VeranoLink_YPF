-- liquibase formatted sql
-- changeset VERANOLINK:1785188155999 stripComments:false  logicalFilePath:base-release\veranolink\tables\vl_logs.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/vl_logs.sql:null:f940e6d3c51b9863dee20aba587be3e0b4018d81:create

create table veranolink.vl_logs (
    id_log             number,
    id_vl_path_context number not null enable,
    company_shortname  varchar2(1000 byte) not null enable,
    vl_audit_log       varchar2(1000 byte) not null enable,
    vl_status_code     number not null enable,
    vl_log_description varchar2(2500 byte),
    vl_parameters      clob,
    vl_timestamp       timestamp(6) default current_timestamp,
    vl_method          varchar2(250 byte),
    vl_aplication      varchar2(100 byte),
    vl_size            number,
    vl_parameter       blob,
    vl_mimetype        varchar2(250 byte),
    vl_name_api        varchar2(500 byte)
);

