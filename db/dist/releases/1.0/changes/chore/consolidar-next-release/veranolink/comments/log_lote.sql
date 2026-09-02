-- liquibase formatted sql
-- changeset veranolink:1788372754078 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\comments\log_lote.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/log_lote.sql:null:02de43496bda20b9b25e2a731960d188560a0da5:create

comment on table veranolink.log_lote is
    'Una fila por peticion HTTP enviada a Ecosys. Aisla los CLOB de request/response, que antes se duplicaban en cada fila de LOG_OPC_SEQUENCE.'
    ;

comment on column veranolink.log_lote.resultado is
    'OK = todos exitosos; FALLO = todos fallaron; PARCIAL = al menos uno fallo.';

comment on column veranolink.log_lote.tipo_objeto is
    'WBS, ACTIVITY o MIXTO. En actualizacion WBS y actividades viajan en la misma peticion.';

