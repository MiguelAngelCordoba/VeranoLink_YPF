-- liquibase formatted sql
-- changeset VERANOLINK:1788300192180 stripComments:false  logicalFilePath:fix\6\veranolink\tables\tbl_activity_baseline.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/tbl_activity_baseline.sql:null:d0a3204b456a3261366e46381f0ab49089533510:create

create table veranolink.tbl_activity_baseline (
    id_fila             number generated always as identity minvalue 1 maxvalue 9999999999999999999999999999 increment by 1 cache 20 noorder
    nocycle nokeep noscale not null enable,
    project_id          number not null enable,
    project_baseline_id number not null enable,
    baseline_type       varchar2(10 byte) not null enable,
    wbs_id              number not null enable,
    activity_id         number not null enable,
    activity_code       varchar2(60 byte),
    activity_name       varchar2(255 byte),
    planned_labor_units number,
    bl_start_date       timestamp(6),
    bl_finish_date      timestamp(6),
    activity_type_opc   varchar2(30 byte),
    type                varchar2(30 byte) default 'Work Package' not null enable,
    origen_carga        varchar2(10 byte) default 'SNAPSHOT' not null enable,
    updatedate          timestamp(6),
    fecha_carga         timestamp(6) default systimestamp not null enable
);

alter table veranolink.tbl_activity_baseline
    add constraint ck_tbl_act_bl_origen
        check ( origen_carga in ( 'SNAPSHOT', 'REINTENTO' ) ) enable;

alter table veranolink.tbl_activity_baseline
    add constraint ck_tbl_act_bl_type
        check ( baseline_type in ( 'ORIGINAL', 'CURRENT' ) ) enable;

alter table veranolink.tbl_activity_baseline
    add constraint pk_tbl_activity_baseline primary key ( id_fila )
        using index enable;

