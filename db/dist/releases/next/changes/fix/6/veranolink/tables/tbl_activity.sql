-- liquibase formatted sql
-- changeset VERANOLINK:1788300192189 stripComments:false  logicalFilePath:fix\6\veranolink\tables\tbl_activity.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/tbl_activity.sql:null:3b5c103c6868bbd3de2d06d85a92ca01f525fed2:create

create table veranolink.tbl_activity (
    id_fila                   number generated always as identity minvalue 1 maxvalue 9999999999999999999999999999 increment by 1 cache
    20 noorder nocycle nokeep noscale not null enable,
    project_id                number not null enable,
    wbs_id                    number not null enable,
    activity_id               number not null enable,
    activity_code             varchar2(60 byte),
    activity_name             varchar2(255 byte),
    planned_labor_units       number,
    at_completion_labor_units number,
    original_bl_start_date    timestamp(6),
    original_bl_finish_date   timestamp(6),
    current_bl_start_date     timestamp(6),
    current_bl_finish_date    timestamp(6),
    startdate                 timestamp(6),
    finishdate                timestamp(6),
    status                    varchar2(20 byte),
    type                      varchar2(30 byte) not null enable,
    updatedate                timestamp(6) not null enable,
    action                    varchar2(10 byte) not null enable,
    baseline                  varchar2(10 byte)
);

alter table veranolink.tbl_activity
    add constraint ck_tbl_activity_baseline
        check ( baseline in ( 'ORIGINAL', 'CURRENT', 'SIN_LB' ) ) enable;

alter table veranolink.tbl_activity add primary key ( id_fila )
    using index enable;

