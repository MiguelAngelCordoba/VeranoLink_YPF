-- liquibase formatted sql
-- changeset VERANOLINK:1788300192198 stripComments:false  logicalFilePath:fix\6\veranolink\tables\log_opc_sequence.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/log_opc_sequence.sql:null:0c7092ff7ee1e41eb35c08597d4b693cd0cf438e:create

create table veranolink.log_opc_sequence (
    id_log              number generated always as identity minvalue 1 maxvalue 9999999999999999999999999999 increment by 1 cache 20 noorder
    nocycle nokeep noscale not null enable,
    project_id          number not null enable,
    contract_number     varchar2(50 byte) not null enable,
    tipo_objeto         varchar2(10 byte) not null enable,
    object_id           number not null enable,
    object_code         varchar2(60 byte),
    object_name         varchar2(255 byte),
    update_sincronizado timestamp(6),
    accion              varchar2(10 byte) not null enable,
    fecha_ejecucion     timestamp(6) not null enable,
    resultado           varchar2(10 byte) not null enable,
    hierarchy_path_id   varchar2(4000 byte),
    project_baseline_id number,
    id_lote             number
);

alter table veranolink.log_opc_sequence
    add constraint ck_log_accion
        check ( accion in ( 'CREATE', 'UPDATE' ) ) enable;

alter table veranolink.log_opc_sequence
    add constraint ck_log_resultado
        check ( resultado in ( 'OK', 'FALLO' ) ) enable;

alter table veranolink.log_opc_sequence
    add constraint ck_log_tipo_objeto
        check ( tipo_objeto in ( 'WBS', 'ACTIVITY' ) ) enable;

alter table veranolink.log_opc_sequence add primary key ( id_log )
    using index enable;

