-- liquibase formatted sql
-- changeset VERANOLINK:1785188156205 stripComments:false  logicalFilePath:base-release\veranolink\tables\vl_ws_types.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/vl_ws_types.sql:null:e3d0d230c3dec2553f2dddfddbec4b058335531b:create

create table veranolink.vl_ws_types (
    id_vl_ws_type number,
    name_ws       varchar2(50 char),
    created_date  timestamp(6) default systimestamp
);

alter table veranolink.vl_ws_types
    add constraint vl_ws_types_pk primary key ( id_vl_ws_type )
        using index enable;

