-- liquibase formatted sql
-- changeset VERANOLINK:1788372755480 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\tables\tbl_wbs_baseline.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/tbl_wbs_baseline.sql:null:20918b43b4719de92702f6f78b72bc0f150df14a:create

create table veranolink.tbl_wbs_baseline (
    id_fila             number generated always as identity minvalue 1 maxvalue 9999999999999999999999999999 increment by 1 cache 20 noorder
    nocycle nokeep noscale not null enable,
    project_id          number not null enable,
    project_baseline_id number not null enable,
    id_tbl_wbs          number,
    wbs_id              number not null enable,
    wbs_code            varchar2(60 byte) not null enable,
    wbs_name            varchar2(255 byte),
    wbs_path            varchar2(4000 byte) not null enable,
    type                varchar2(20 byte) default 'WBS' not null enable,
    nivel               number,
    es_hoja_actividad   varchar2(1 byte) default 'N' not null enable,
    updatedate          timestamp(6),
    fecha_carga         timestamp(6) default systimestamp not null enable
);

alter table veranolink.tbl_wbs_baseline
    add constraint ck_tbl_wbs_bl_hoja
        check ( es_hoja_actividad in ( 'Y', 'N' ) ) enable;

alter table veranolink.tbl_wbs_baseline
    add constraint pk_tbl_wbs_baseline primary key ( id_fila )
        using index enable;

alter table veranolink.tbl_wbs_baseline
    add constraint uk_tbl_wbs_bl unique ( project_baseline_id,
                                          wbs_id )
        using index enable;

