-- liquibase formatted sql
-- changeset VERANOLINK:1787600192764 stripComments:false  logicalFilePath:feature\ajuste1_creacion2\veranolink\tables\log_opc_sequence.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/log_opc_sequence.sql:null:218f10d4858801ed24a790c862ba091e45fc1418:create

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
    http_status         number,
    mensaje_respuesta   clob,
    payload_enviado     clob,
    hierarchy_path_id   varchar2(4000 byte),
    project_baseline_id number
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

