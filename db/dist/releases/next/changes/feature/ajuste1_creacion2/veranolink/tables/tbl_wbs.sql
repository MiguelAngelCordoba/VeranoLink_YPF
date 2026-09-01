-- liquibase formatted sql
-- changeset VERANOLINK:1787600192720 stripComments:false  logicalFilePath:feature\ajuste1_creacion2\veranolink\tables\tbl_wbs.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/tbl_wbs.sql:null:f01b2636a3a69c05f4864f68bc012ef0d19fd846:create

create table veranolink.tbl_wbs (
    id_fila     number generated always as identity minvalue 1 maxvalue 9999999999999999999999999999 increment by 1 cache 20 noorder nocycle
    nokeep noscale not null enable,
    project_id  number not null enable,
    wbs_id      number not null enable,
    wbs_code    varchar2(60 byte) not null enable,
    wbs_name    varchar2(255 byte),
    wbs_path    varchar2(4000 byte) not null enable,
    type        varchar2(20 byte) default 'WBS' not null enable,
    updatedate  timestamp(6) not null enable,
    action      varchar2(10 byte) not null enable,
    fecha_carga timestamp(6) default systimestamp not null enable
);

alter table veranolink.tbl_wbs
    add constraint ck_tbl_wbs_action
        check ( action in ( 'CREATE', 'UPDATE' ) ) enable;

alter table veranolink.tbl_wbs
    add constraint pk_tbl_wbs primary key ( id_fila )
        using index enable;

