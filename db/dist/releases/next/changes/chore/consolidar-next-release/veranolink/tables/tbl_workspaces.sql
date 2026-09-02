-- liquibase formatted sql
-- changeset VERANOLINK:1788372755515 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\tables\tbl_workspaces.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/tbl_workspaces.sql:null:34574be40bde3a8a02b073cd78a30214129ccfc9:create

create table veranolink.tbl_workspaces (
    workspace_id         number not null enable,
    workspace_code       varchar2(60 byte) not null enable,
    workspace_name       varchar2(255 byte),
    is_production        varchar2(1 byte) not null enable,
    fecha_sincronizacion timestamp(6) not null enable
);

alter table veranolink.tbl_workspaces
    add constraint ck_tbl_ws_is_production
        check ( is_production in ( 'Y', 'N' ) ) enable;

alter table veranolink.tbl_workspaces
    add constraint pk_tbl_workspaces primary key ( workspace_id )
        using index enable;

alter table veranolink.tbl_workspaces add constraint uk_tbl_workspaces_code unique ( workspace_code )
    using index enable;

