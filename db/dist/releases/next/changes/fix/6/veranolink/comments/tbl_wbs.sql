-- liquibase formatted sql
-- changeset veranolink:1788300191244 stripComments:false  logicalFilePath:fix\6\veranolink\comments\tbl_wbs.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/tbl_wbs.sql:null:a9f54c5711a32a4293e2f0111963a2017599574e:create

comment on table veranolink.tbl_wbs is
    'Historico (append-only) de elementos WBS de OPC - cada fila es una version en el tiempo de un WBS_ID, nunca se sobreescribe ni se borra'
    ;

comment on column veranolink.tbl_wbs.action is
    'CREATE si es la primera vez que se ve este WBS_ID en la tabla; UPDATE si ya existia una version anterior';

comment on column veranolink.tbl_wbs.updatedate is
    'updateDate de OPC correspondiente a esta version especifica de la fila - se usa como pivote para el filtro incremental del proximo ciclo'
    ;

comment on column veranolink.tbl_wbs.wbs_id is
    'ID interno OPC de la WBS - se repite en varias filas a lo largo del tiempo (una por cada version/cambio detectado)';

