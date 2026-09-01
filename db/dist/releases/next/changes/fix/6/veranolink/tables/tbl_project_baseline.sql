-- liquibase formatted sql
-- changeset VERANOLINK:1788300192234 stripComments:false  logicalFilePath:fix\6\veranolink\tables\tbl_project_baseline.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/tbl_project_baseline.sql:null:3f2a876c4e7b84d06a986650d29dad0e774a8a69:create

create table veranolink.tbl_project_baseline (
    id_fila              number generated always as identity minvalue 1 maxvalue 9999999999999999999999999999 increment by 1 cache 20
    noorder nocycle nokeep noscale not null enable,
    project_id           number not null enable,
    project_baseline_id  number not null enable,
    baseline_name        varchar2(255 byte),
    baseline_type        varchar2(10 byte) not null enable,
    baseline_time        timestamp(6),
    baseline_data_date   timestamp(6),
    baseline_update_date timestamp(6),
    vigente              varchar2(1 byte) default 'Y' not null enable,
    intentos             number default 0 not null enable,
    fecha_primer_consumo timestamp(6),
    fecha_ultimo_consumo timestamp(6),
    fecha_desmarcado     timestamp(6),
    fecha_carga          timestamp(6) default systimestamp not null enable
);

alter table veranolink.tbl_project_baseline
    add constraint ck_tbl_prj_bl_type
        check ( baseline_type in ( 'ORIGINAL', 'CURRENT' ) ) enable;

alter table veranolink.tbl_project_baseline
    add constraint ck_tbl_prj_bl_vigente
        check ( vigente in ( 'Y', 'N' ) ) enable;

alter table veranolink.tbl_project_baseline
    add constraint pk_tbl_project_baseline primary key ( id_fila )
        using index enable;

alter table veranolink.tbl_project_baseline
    add constraint uk_tbl_prj_bl
        unique ( project_id,
                 project_baseline_id,
                 baseline_type )
            using index enable;

