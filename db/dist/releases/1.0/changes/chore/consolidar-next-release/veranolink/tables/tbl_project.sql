-- liquibase formatted sql
-- changeset VERANOLINK:1788372755442 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\tables\tbl_project.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/tbl_project.sql:null:250bd8a1609e4494180ca3c9cb268bf59e3e8a80:create

create table veranolink.tbl_project (
    project_id         number not null enable,
    project_code       varchar2(60 byte) not null enable,
    project_name       varchar2(255 byte),
    status             varchar2(20 byte),
    integracion_flag   varchar2(10 byte),
    contract_number    varchar2(50 byte) not null enable,
    fecha_carga        timestamp(6) default systimestamp not null enable,
    estado_integracion varchar2(20 byte) default 'OK' not null enable,
    workspace_code     varchar2(60 byte),
    workspace_id       number
);

alter table veranolink.tbl_project
    add constraint ck_tbl_project_estado
        check ( estado_integracion in ( 'OK', 'DUPLICADO', 'CONTRATO_CAMBIADO' ) ) enable;

alter table veranolink.tbl_project
    add constraint pk_tbl_project primary key ( project_id )
        using index enable;

