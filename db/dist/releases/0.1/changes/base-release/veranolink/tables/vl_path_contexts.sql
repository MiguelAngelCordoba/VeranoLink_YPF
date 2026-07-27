-- liquibase formatted sql
-- changeset VERANOLINK:1785188155979 stripComments:false  logicalFilePath:base-release\veranolink\tables\vl_path_contexts.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/vl_path_contexts.sql:null:112bebfc343f2b1c041c8faf0558d540dbb2f03a:create

create table veranolink.vl_path_contexts (
    id_vl_path_context      number,
    name                    varchar2(100 char),
    path_context            varchar2(250 char),
    id_vl_call_type         number,
    id_vl_source_collection number,
    path_description        varchar2(1000 char),
    created_date            timestamp(6) default systimestamp,
    json_p                  clob,
    state                   number
);

alter table veranolink.vl_path_contexts
    add constraint pk_vl_path_contexts_id_vl_path primary key ( id_vl_path_context )
        using index enable;

